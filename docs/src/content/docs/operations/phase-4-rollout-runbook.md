---
title: Phase 4 rollout runbook
description: Staging deploy guide for the 6 new Phase 4 backend services — environments, vaults, audit, metering, notifications, and onboarding.
sidebar:
  order: 6
status: draft
owner: '@paper-board/docs-maintainers'
updated: '2026-06-10'
---

import { Aside } from '@astrojs/starlight/components';

<Aside type="caution" title="Not yet cluster-validated">
This runbook has been desk-checked against chart values, migrator source, and service configs — but has NOT been executed against a live staging cluster. The first live execution is owed by the phase-4-smoke e2e (S-0045). Fold any deviations back into this document via a follow-up Story after that run.

Until `paper-board/infra` PR [S-0035](https://github.com/paper-board/infra) merges (umbrella chart Phase 4 wiring), use the per-service `helm install oci://…` interim path described in each phase below.

</Aside>

Phase 4 brings six new services online: **environments** and **vaults** (the Anthropic-style config + credential stores), then **audit**, **metering**, **notifications**, and **onboarding**. It also retrofits the four existing services (agents, identity, runtime, compute) with outbox-emit images.

Target rollout window: **≤ 30 minutes** on staging. Estimated breakdown: pre-flight 5 min · migrations 3 min · service deploys 10 min · retrofit 5 min · smoke 7 min.

Related: [Outbox pattern](/architecture/outbox-pattern), [Deployment](/operations/deployment), [ADR-0002](/decisions/0002-schema-per-service), [ADR-0003](/decisions/0003-no-cross-schema-fk), [ADR-0004](/decisions/0004-migrator-shared-library), [ADR-0019](/decisions/0019-standard-healthcheck-pattern).

______________________________________________________________________

## Phase 0 — Pre-flight

Run every check before touching any chart.

### 1. Postgres roles

Each service requires its own `<svc>_app` Postgres user and schema. Verify all six exist:

```bash
psql "$POSTGRES_ADMIN_URL" <<'SQL'
SELECT rolname FROM pg_roles
WHERE rolname IN (
  'audit_app','metering_app','notifications_app',
  'onboarding_app','environments_app','vaults_app'
)
ORDER BY rolname;
SQL
# Expect 6 rows. Missing roles: run init-db.sql or the postgres init-container.
```

### 2. Secrets

Create (or confirm) these Kubernetes Secrets in the `paper-board` namespace **before** any Helm install:

| Secret name                      | Key         | Value                                                                                                                           |
| -------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `audit-migration-db-url`         | `url`       | `postgres://audit_app:<pw>@postgres.paper-board:5432/paper_board?search_path=audit`                                             |
| `audit-app-db-url`               | `url`       | `postgres://audit_app:<pw>@pgbouncer.paper-board:6432/paper_board?search_path=audit`                                            |
| `metering-migration-db-url`      | `url`       | `postgres://metering_app:…@postgres…`                                                                                           |
| `metering-app-db-url`            | `url`       | `postgres://metering_app:…@pgbouncer…`                                                                                          |
| `notifications-migration-db-url` | `url`       | `…notifications_app…`                                                                                                           |
| `notifications-app-db-url`       | `url`       | `…notifications_app…pgbouncer…`                                                                                                 |
| `onboarding-migration-db-url`    | `url`       | `…onboarding_app…`                                                                                                              |
| `onboarding-app-db-url`          | `url`       | `…onboarding_app…pgbouncer…`                                                                                                    |
| `environments-migration-db-url`  | `url`       | `…environments_app…`                                                                                                            |
| `environments-app-db-url`        | `url`       | `…environments_app…pgbouncer…`                                                                                                  |
| `vaults-migration-db-url`        | `url`       | `…vaults_app…`                                                                                                                  |
| `vaults-app-db-url`              | `url`       | `…vaults_app…pgbouncer…`                                                                                                        |
| `vaults-kms-secret`              | `local-kek` | 32-byte hex key (`openssl rand -hex 32`); staging can use a static dev key; production MUST use GCP KMS (`VAULTS_KMS_MODE=gcp`) |

SMTP secrets for notifications (staging can point at a test SMTP relay):

| Secret / env var | Value                                 |
| ---------------- | ------------------------------------- |
| `SMTP_HOST`      | hostname of staging SMTP relay        |
| `SMTP_PORT`      | `587` (or `1025` for local dev relay) |
| `SMTP_USER`      | relay auth user                       |
| `SMTP_PASSWORD`  | relay auth password                   |
| `SMTP_FROM`      | `noreply@paperboard.app`              |

### 3. GHCR image pull

All Phase 4 images are at `ghcr.io/paper-board/<svc>-{server,migrator}:v0.1.0`. Verify the cluster can pull:

```bash
kubectl run img-check --rm -it --restart=Never \
  --image=ghcr.io/paper-board/vaults-migrator:v0.1.0 \
  -- echo "pull OK"
```

If the pull fails with `401 Unauthorized`, confirm the cluster has an `imagePullSecret` bound to the `paper-board` service account pointing at `ghcr.io`.

### 4. Redis

The outbox relay (environments + vaults + notifications) needs Redis. Verify:

```bash
kubectl exec -n paper-board deploy/redis-master -- redis-cli ping
# Expected: PONG
```

### 5. Chart versions

```bash
helm show chart oci://ghcr.io/paper-board/helm/environments --version 0.2.0 2>/dev/null | grep version
helm show chart oci://ghcr.io/paper-board/helm/vaults        --version 0.2.0 2>/dev/null | grep version
helm show chart oci://ghcr.io/paper-board/helm/audit         --version 0.2.0 2>/dev/null | grep version
helm show chart oci://ghcr.io/paper-board/helm/metering      --version 0.2.0 2>/dev/null | grep version
helm show chart oci://ghcr.io/paper-board/helm/notifications --version 0.2.0 2>/dev/null | grep version
helm show chart oci://ghcr.io/paper-board/helm/onboarding    --version 0.2.0 2>/dev/null | grep version
# Note: until S-0035 merges, these charts ship from their own service repos via the per-service helm/ folder.
```

______________________________________________________________________

## Phase 1 — Schema migration

The Helm migrator Job (ADR-0004) runs as a `pre-install`/`pre-upgrade` hook, so `helm install` triggers migrations automatically. The manual `helm install` commands below are the interim path; after S-0035 merges, a single `helm upgrade --install agent-manager` with appropriate `--set` flags runs all migrators in order.

**Order matters for environments and vaults** — other services carry UUID references to `environment_id` and `vault_id` at the application layer (no FK per ADR-0003, but the schemas must exist before services start). Install them first.

```mermaid
sequenceDiagram
    participant Op as Operator
    participant K8s as Kubernetes
    participant PG as Postgres

    Op->>K8s: helm install environments (pre-install hook)
    K8s->>PG: CREATE SCHEMA environments; CREATE TABLE environments.environments …
    K8s-->>Op: migrator Job Complete

    Op->>K8s: helm install vaults (pre-install hook)
    K8s->>PG: CREATE SCHEMA vaults; CREATE TABLE vaults.vaults, credentials, outbox_events …
    K8s-->>Op: migrator Job Complete

    par Parallel batch (no cross-schema FK — ADR-0003)
        Op->>K8s: helm install audit
        K8s->>PG: CREATE SCHEMA audit …
    and
        Op->>K8s: helm install metering
        K8s->>PG: CREATE SCHEMA metering …
    and
        Op->>K8s: helm install notifications
        K8s->>PG: CREATE SCHEMA notifications …
    and
        Op->>K8s: helm install onboarding
        K8s->>PG: CREATE SCHEMA onboarding …
    end

    Op->>K8s: Deploy all 6 services
    Op->>K8s: Rolling restart agents, identity, runtime, compute (outbox images)
    Op->>K8s: Run e2e smoke suite
```

### Run migrations

```bash
NAMESPACE=paper-board
HELM_REPO=oci://ghcr.io/paper-board/helm

# Step 1 — environments first
helm install environments "$HELM_REPO/environments" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --set server.enabled=false \
  --wait --timeout 3m

# Step 2 — vaults second
helm install vaults "$HELM_REPO/vaults" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --set server.enabled=false \
  --set server.kmsMode=local \
  --set server.kmsSecretName=vaults-kms-secret \
  --wait --timeout 3m

# Step 3 — parallel batch; capture PIDs to detect individual failures
helm install audit         "$HELM_REPO/audit"         --namespace "$NAMESPACE" --version 0.2.0 --set server.enabled=false --wait --timeout 3m & PID_AUDIT=$!
helm install metering      "$HELM_REPO/metering"      --namespace "$NAMESPACE" --version 0.2.0 --set server.enabled=false --wait --timeout 3m & PID_METERING=$!
helm install notifications "$HELM_REPO/notifications" --namespace "$NAMESPACE" --version 0.2.0 --set server.enabled=false --wait --timeout 3m & PID_NOTIF=$!
helm install onboarding    "$HELM_REPO/onboarding"    --namespace "$NAMESPACE" --version 0.2.0 --set server.enabled=false --wait --timeout 3m & PID_ONBOARD=$!
FAIL=0
wait "$PID_AUDIT"    || { echo "ERROR: audit migration failed";         FAIL=1; }
wait "$PID_METERING" || { echo "ERROR: metering migration failed";      FAIL=1; }
wait "$PID_NOTIF"    || { echo "ERROR: notifications migration failed"; FAIL=1; }
wait "$PID_ONBOARD"  || { echo "ERROR: onboarding migration failed";   FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "All migrations complete" || { echo "One or more migrations FAILED — do not proceed"; exit 1; }
```

Verify each schema exists:

```bash
psql "$POSTGRES_ADMIN_URL" -c "\dn" | grep -E "audit|metering|notifications|onboarding|environments|vaults"
# Expect 6 schema rows.
```

______________________________________________________________________

## Phase 2 — Service deploy

Enable servers in dependency order. Wait for `/readyz` (ADR-0019) before advancing.

```bash
NAMESPACE=paper-board
HELM_REPO=oci://ghcr.io/paper-board/helm

# environments (gRPC :50056, HTTP :8086)
helm upgrade environments "$HELM_REPO/environments" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --wait --timeout 5m

kubectl rollout status deployment/environments -n "$NAMESPACE"
kubectl exec -n "$NAMESPACE" deploy/environments -- wget -qO- http://localhost:8086/readyz

# vaults (gRPC :50089, HTTP :8089)
helm upgrade vaults "$HELM_REPO/vaults" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --set server.kmsMode=local \
  --set server.kmsSecretName=vaults-kms-secret \
  --wait --timeout 5m

kubectl rollout status deployment/vaults -n "$NAMESPACE"
kubectl exec -n "$NAMESPACE" deploy/vaults -- wget -qO- http://localhost:8089/readyz

# audit (gRPC :50057, HTTP :8084)
# Note: config.go defaults GRPC_PORT to 50054; must override to 50057 to
# avoid collision with compute (:50054). See service-map.md note on audit port.
helm upgrade audit "$HELM_REPO/audit" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --set server.config.grpcPort=50057 \
  --wait --timeout 5m

kubectl rollout status deployment/audit -n "$NAMESPACE"
kubectl exec -n "$NAMESPACE" deploy/audit -- wget -qO- http://localhost:8084/readyz

# metering (gRPC :50055)
helm upgrade metering "$HELM_REPO/metering" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --wait --timeout 5m

kubectl rollout status deployment/metering -n "$NAMESPACE"

# notifications (HTTP :8085)
helm upgrade notifications "$HELM_REPO/notifications" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --wait --timeout 5m

kubectl rollout status deployment/notifications -n "$NAMESPACE"
kubectl exec -n "$NAMESPACE" deploy/notifications -- wget -qO- http://localhost:8085/readyz

# onboarding (HTTP :8089) — depends on identity, vaults, environments, agents all up
helm upgrade onboarding "$HELM_REPO/onboarding" \
  --namespace "$NAMESPACE" \
  --version 0.2.0 \
  --reuse-values \
  --set server.enabled=true \
  --wait --timeout 5m

kubectl rollout status deployment/onboarding -n "$NAMESPACE"
```

______________________________________________________________________

## Phase 3 — Retrofit deploy

Bump agents, identity, runtime, and compute to their outbox-emit-enabled images. These are rolling restarts — existing traffic continues during the rollout.

```bash
NAMESPACE=paper-board
HELM_REPO=oci://ghcr.io/paper-board/helm

# Bump each service to the Phase 4 outbox-emit image tag.
# Replace <outbox-tag> with the tag published by the outbox-emit PR for each service.
for svc in agents identity runtime compute; do
  helm upgrade "$svc" "$HELM_REPO/$svc" \
    --namespace "$NAMESPACE" \
    --reuse-values \
    --set server.image.tag=<outbox-tag> \
    --wait --timeout 5m
  kubectl rollout status deployment/"$svc" -n "$NAMESPACE"
done
```

Verify outbox relay is draining (no stale events after 60 s):

```bash
# Each outbox-enabled service exposes event counts via its /metrics endpoint.
# Verify the outbox_events table is not accumulating:
psql "$POSTGRES_ADMIN_URL" -c \
  "SELECT schemaname, COUNT(*) FROM (
     SELECT 'environments' AS schemaname FROM environments.outbox_events WHERE processed_at IS NULL
     UNION ALL
     SELECT 'vaults' FROM vaults.outbox_events WHERE processed_at IS NULL
   ) t GROUP BY schemaname;"
# Expect 0 unprocessed rows after services have been running > 30 s.
```

______________________________________________________________________

## Phase 4 — Smoke

Run the Phase 4 e2e suite against staging. Until S-0001/S-0002 (e2e flows) are deployed:

```bash
# Manual golden-path smoke — hit each new service health endpoint
NAMESPACE=paper-board
for svc_port in "environments:8086" "vaults:8089" "audit:8084" "notifications:8085" "onboarding:8089"; do
  svc="${svc_port%%:*}"
  port="${svc_port##*:}"
  STATUS=$(kubectl exec -n "$NAMESPACE" deploy/"$svc" -- \
    wget -qO- --server-response http://localhost:"$port"/readyz 2>&1 | grep "HTTP/" | awk '{print $2}')
  echo "$svc /readyz → $STATUS"
  [ "$STATUS" = "200" ] || echo "WARN: $svc not ready"
done

# metering is gRPC-only (no HTTP /readyz); check via tcpSocket:
kubectl exec -n "$NAMESPACE" deploy/metering -- \
  nc -z localhost 50055 && echo "metering gRPC :50055 reachable" || echo "WARN: metering not ready"

# Onboarding flow — trigger a user.created event and verify the onboarding
# processed_events table records it within 10 s:
psql "$POSTGRES_ADMIN_URL" -c \
  "SELECT COUNT(*) FROM onboarding.processed_events WHERE processed_at > NOW() - INTERVAL '60s';"
```

When S-0045 (phase-4-smoke e2e) runs, execute the full suite:

```bash
cd paper-board/e2e
go test ./flows/... -v -run Phase4 -staging-url https://staging.paperboard.app
```

______________________________________________________________________

## Phase 5 — Rollback

### Safe rollbacks (additive-only migrations)

The following down-migrations drop their entire schema. They are **safe to run** only if no data exists in the schema — i.e., on a fresh install that failed before any real traffic.

| Service       | Migration | Down SQL action                     | Safe?                                                        |
| ------------- | --------- | ----------------------------------- | ------------------------------------------------------------ |
| audit         | 000001    | `DROP SCHEMA audit CASCADE`         | Safe if no events written                                    |
| metering      | 000001    | `DROP SCHEMA metering CASCADE`      | Safe if no raw events                                        |
| notifications | 000001    | `DROP SCHEMA notifications CASCADE` | Safe if no send_log rows                                     |
| onboarding    | 000001    | `DROP SCHEMA onboarding CASCADE`    | Safe if no processed_events                                  |
| environments  | 000001    | `DROP SCHEMA environments CASCADE`  | Safe if no environments rows                                 |
| vaults        | 000001    | `DROP SCHEMA vaults CASCADE`        | **NOT safe** if any credentials stored (encrypted data loss) |
| vaults        | 000002    | `DROP TABLE vaults.outbox_events`   | Safe (outbox only; no business data)                         |

**Non-safe down-migration: `vaults` 000001.** If any encrypted credentials have been stored, running `cmd/migrator down 1` for vaults causes **irreversible data loss** — the encrypted `credentials` rows and the `vaults` rows are dropped. Do not run without an explicit data-loss acceptance sign-off.

### Helm rollback

```bash
NAMESPACE=paper-board

# Roll back a service to its previous Helm release revision:
helm rollback <service> 0 --namespace "$NAMESPACE" --wait
# 0 means "previous revision". Use `helm history <service> -n paper-board` to pick a specific revision.

# If the rollback involves schema migration, run migrator down FIRST:
# (only do this on a fresh-install failure with no business data)
kubectl run migrator-down --rm -it --restart=Never \
  --image=ghcr.io/paper-board/<svc>-migrator:v0.1.0 \
  --env="MIGRATION_DB_URL=$MIGRATION_DB_URL" \
  -- /migrator down 1
```

### Retrofit rollback

To revert agents/identity/runtime/compute to the pre-Phase-4 image:

```bash
helm upgrade <svc> oci://ghcr.io/paper-board/helm/<svc> \
  --namespace paper-board \
  --reuse-values \
  --set server.image.tag=<previous-tag> \
  --wait --timeout 5m
```

______________________________________________________________________

## Quick reference — service ports

| Service       | HTTP | gRPC  |
| ------------- | ---- | ----- |
| environments  | 8086 | 50056 |
| vaults        | 8089 | 50089 |
| audit         | 8084 | 50057 |
| metering      | —    | 50055 |
| notifications | 8085 | —     |
| onboarding    | 8089 | —     |

All services except `metering` expose `/healthz` (liveness) and `/readyz` (readiness) per ADR-0019.
`metering` is gRPC-only; its Helm chart uses a `tcpSocket` probe on port 50055 instead.
`vaults` and `onboarding` share the same default port 8089 but run as separate Kubernetes Services with distinct DNS names.
