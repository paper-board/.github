# 0019 — Standard healthcheck pattern

**Status:** accepted
**Date:** 2026-05-28
**Accepted at:** commit `277d818` (2026-05-28; squash-merge of agent-manager PR #2)
**Scope:** backend

## Context

Kubernetes deploys for paper-board services use liveness and readiness probes (Helm `livenessProbe` + `readinessProbe`) to drive pod lifecycle decisions. Before sdk v0.4.0, each service rolled its own `/healthz` and `/readyz` HTTP handlers:

- `paper-board/agents` had a single `/healthz` returning `200 OK` if the process was up. No DB-connectivity check.
- `paper-board/identity` returned `200 OK` from `/healthz` and `200 OK` from `/readyz`, both unconditional. Readiness did not actually verify the `pgxpool` connection.
- No service emitted structured probe-failure diagnostics; on failure the pod restarted with no log trail explaining why.

The inconsistency surfaced during the Phase 3 runtime + compute deploy work (2026-05-22, source: `tasks/2026-05-21-phase-3-runtime-compute-design.md`): rolling-deploy of `runtime` pods occasionally got stuck because `/readyz` returned `200 OK` while the pod's Postgres connection pool was still mid-warmup — k8s sent traffic that immediately failed at the DB layer. The fix was a per-service custom readiness check, but reviewers flagged the pattern: every service repeating the same "ping DB, register dependencies" code is exactly the boilerplate sdk should absorb.

sdk v0.4.0 added `paper-board/sdk/healthcheck` (CHANGELOG: **healthcheck + idempotency + advisory drop**) with:

- `healthcheck.Checker` interface (`Name() string`, `Check(ctx) error`)
- `healthcheck.Registry` (a list of checkers + an HTTP handler)
- `healthcheck/db.go` — default DB-pool checker (executes `SELECT 1` against the configured `pgxpool.Pool`)
- HTTP endpoints: `/healthz` (liveness — process up, no checks run) + `/readyz` (readiness — all registered checkers pass)

Phase 4 services (audit, metering, notifications, onboarding, environments, vaults) bootstrap during the same window as this ADR. Without a binding decision, each Phase 4 engineer is free to roll their own pattern, recreating the inconsistency. This ADR fixes the pattern before Phase 4 PRs land.

## Decision

`paper-board/sdk/healthcheck` is the **standard healthcheck pattern** for all paper-board backend services. The contract:

- **`/healthz`**: liveness signal. Returns `200 OK` if the HTTP server is accepting requests. No registered checkers are run; the endpoint is intentionally cheap (sub-millisecond) because k8s liveness probes fire every 10s on every pod. Failure of `/healthz` causes the pod to be restarted.
- **`/readyz`**: readiness signal. Runs all `Checker`s registered on the `Registry`. Returns `200 OK` if every checker returns nil; returns `503 Service Unavailable` with a JSON body listing failing checkers (name + error message) otherwise. Failure of `/readyz` causes the pod to be removed from the Service's endpoint list but NOT restarted.
- **Default checker**: `healthcheck/db.go` — registered by every service that uses a Postgres connection pool. Executes `SELECT 1` with a 2-second timeout against the configured `pgxpool.Pool`.
- **Custom checkers**: services with additional dependencies (Redis, downstream gRPC, external HTTP) register additional `Checker`s on boot. Each checker MUST be idempotent and bounded (< 2s per checker; the `/readyz` handler enforces a 5s overall deadline).

**MUST trigger**: Phase 4 services (`audit`, `metering`, `notifications`, `onboarding`, `environments`, `vaults`) MUST adopt `sdk/healthcheck` in their first PR (the service-bootstrap PR). The cmd/server `main.go` MUST construct a `healthcheck.Registry`, register at minimum the DB checker (since all six Phase 4 services use Postgres), and mount `/healthz` + `/readyz` on the HTTP router.

**Enforcement actor**: PR-review-time gate. The reviewer (human + CR + engineer subagent) rejects any Phase 4 service PR whose `cmd/server/main.go` does not register `sdk/healthcheck.Registry` and expose `/healthz` + `/readyz`. **No automated CI gate** is part of this ADR — automated enforcement (a grep in `template-validate.yml` or a separate `healthcheck-presence` CI job) is out of scope; if review friction proves unsustainable, a future ADR may automate it.

**Opt-out mechanism**: A service that genuinely does not need this pattern (current candidates: `gateway` as a stateless proxy, `frontend` repos as static-asset hosts) MAY opt out by publishing an **amendment ADR** explicitly referencing this ADR and stating the opt-out rationale. Examples of acceptable forms: "ADR-0020 — gateway opt-out of ADR-0019 (stateless proxy; readiness derived from upstream service /readyz)". **Comment-only, commit-message hand-wave, or silent omission is NOT acceptable.** Gateway and frontend are NOT pre-approved opt-outs by this ADR; if they need to skip, an amendment is required.

**Ordering pin for opt-out**: the amendment ADR MUST merge BEFORE the opt-out service's bootstrap PR opens (same ratify-before-implement rule as paper-board's general ADR practice; see `tasks/2026-05-28-service-template-sdk-bump-plan.md` §5 step 8). Co-merging the amendment + the service PR in a single squash is not allowed.

## Consequences

- **Helm chart `_helpers.tpl` and `server-deployment.yaml`** in service-template currently target `/healthz` and `/readyz` (verified 2026-05-28) — the existing chart shape is already aligned with this ADR. No chart changes required.
- **`paper-board/agents`** (Phase 1.1 ✅) currently runs the old single-`/healthz` pattern. Retrofit to `sdk/healthcheck` is in-scope for FP-1/2/3-class follow-up work (NOT in this ADR's PR; see `tasks/2026-05-28-service-template-sdk-bump-plan.md` §8). Until retrofit lands, agents pre-dates this ADR and is grandfathered.
- **`paper-board/identity`** (Phase 2 ✅) same retrofit footprint as agents. Grandfathered until follow-up PR.
- **`paper-board/runtime`** + **`paper-board/compute`** (Phase 3 ✅, shipped 2026-05-23) — current state should be inspected; if they already use `sdk/healthcheck` (added during Phase 3 work after sdk v0.4.0 shipped), great. If not, retrofit lands in the same follow-up PR as agents/identity.
- **service-template** ships `sdk/healthcheck` integration as part of FP-3 (`docs/healthcheck-quickstart.md` + boot-wiring example in template). The sdk-bump PR (`tasks/2026-05-28-service-template-sdk-bump-plan.md`) bumps the sdk version but does NOT add the boot wiring to template — that's FP-3 scope.
- **Documentation**: `docs/healthcheck-quickstart.md` in service-template (FP-3) MUST cite this ADR; the quickstart covers how to register the default DB checker, how to add a custom checker, and how to wire Helm `livenessProbe`/`readinessProbe` against `/healthz`/`/readyz`.
- **Grandfathered services exit grandfathering** when their retrofit PR merges. The retrofit PR's commit message MUST reference ADR-0019.

## Alternatives considered

- **(a) Single `/healthz` endpoint covering both liveness and readiness.** Rejected: Kubernetes documents the two as semantically distinct (liveness restarts the pod; readiness withdraws traffic). Conflating them either causes unnecessary pod restarts on transient downstream failures (if `/healthz` runs deep checks) or causes traffic to a not-ready pod (if `/readyz` is too shallow).
- **(b) gRPC `grpc.health.v1.Health` instead of HTTP.** Rejected: paper-board's observability tooling — Grafana, kube-prometheus, k8s native probes — has tighter integration with HTTP probes than with gRPC health. paper-board services already expose HTTP for REST traffic (ADR-0005); requiring a second protocol surface for healthchecks adds infrastructure burden without comparable benefit.
- **(c) Defer the ADR; let Phase 4 services choose their own pattern.** Rejected: the Phase 3 readiness-race incident already proved the cost of inconsistency. Phase 4 brings six new services online; binding them to a single pattern at bootstrap is cheaper than retrofit later.
- **(d) Mandate `sdk/healthcheck` without an opt-out mechanism.** Rejected: gateway and (future) frontend repos have plausible reasons to opt out (no Postgres pool, no downstream-dependency check semantics). A blanket mandate would force these services to implement no-op checkers, polluting the registry. The amendment-ADR opt-out provides a documented escape valve without weakening the default.

## References

- ADR-0005 — REST public + gRPC internal communication (HTTP-side observability rationale)
- `paper-board/sdk/healthcheck/*.go` (HEAD) — implementation
- `paper-board/sdk` CHANGELOG v0.4.0 entry — package introduction
- `tasks/2026-05-21-phase-3-runtime-compute-design.md` — context for the readiness-race incident that motivated standardization
- `tasks/2026-05-28-service-template-sdk-bump-plan.md` §4.3 — companion plan section that triggered this ADR
- Kubernetes documentation — liveness and readiness probe semantics (https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
