---
title: Local dev setup
description: Prerequisites and step-by-step guide to running paperboard services on your laptop.
sidebar:
  order: 2
status: shipped
owner: '@paper-board/docs-maintainers'
updated: '2026-05-24'
---

This guide gets you from a clean laptop to a running local paperboard cluster. We use
[kind](https://kind.sigs.k8s.io/) for the local Kubernetes cluster and Helm for service
deployment. Estimated time: 30–45 minutes on a fast machine.

## Prerequisites

You need the following tools installed before starting. The versions listed are the minimum
tested; newer versions generally work.

| Tool           | Version | Install                                                                               |
| -------------- | ------- | ------------------------------------------------------------------------------------- |
| Go             | 1.22+   | `brew install go`                                                                     |
| Docker Desktop | 4.x+    | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| kind           | 0.22+   | `brew install kind`                                                                   |
| kubectl        | 1.29+   | `brew install kubectl`                                                                |
| Helm           | 3.14+   | `brew install helm`                                                                   |
| gh CLI         | 2.40+   | `brew install gh`                                                                     |
| golangci-lint  | 1.57+   | `brew install golangci-lint`                                                          |
| pre-commit     | 3.x+    | `brew install pre-commit`                                                             |
| yq             | 4.x+    | `brew install yq`                                                                     |

You also need:

- A GitHub account with access to the `paper-board` org (request from your team lead).
- An `ANTHROPIC_API_KEY` for the agents service LLM calls.

## Quickstart

The sequence below brings up a local cluster with the shipped services (agents + identity +
runtime + compute) running against a local Postgres.

```mermaid
sequenceDiagram
  autonumber
  participant Dev as Developer
  participant Kind as kind cluster
  participant PG as Postgres
  participant Svc as Services

  classDef controlPlane fill:#10b981,stroke:#047857,color:#fff
  classDef dataPlane fill:#3b82f6,stroke:#1d4ed8,color:#fff
  classDef sandbox fill:#f97316,stroke:#c2410c,color:#fff
  classDef external fill:#ef4444,stroke:#b91c1c,color:#fff
  classDef persistence fill:#6b7280,stroke:#374151,color:#fff

  Dev->>Kind: kind create cluster --name paperboard
  Dev->>Kind: kubectl apply -f infra/local/namespace.yaml
  Dev->>PG: helm install postgres bitnami/postgresql
  PG-->>Dev: Postgres ready on :5432 (direct) / :6432 (PgBouncer)
  Dev->>Svc: helm install agents-migrator (pre-install Job)
  Svc->>PG: run agents schema migrations
  Dev->>Svc: helm install identity-migrator
  Svc->>PG: run identity schema migrations
  Dev->>Svc: helm install agents-server + identity-server
  Svc-->>Dev: services healthy
  Dev->>Dev: run smoke: curl localhost:8080/healthz
```

### Step 1 — Clone the repos

Authenticate with `gh` first:

```sh
gh auth login
```

Clone the repos you need. For a first-time setup, you need at minimum `infra`, `agents`, and
`identity`:

```sh
gh repo clone paper-board/infra
gh repo clone paper-board/agents
gh repo clone paper-board/identity
gh repo clone paper-board/sdk
gh repo clone paper-board/proto
```

Set `GOPATH`-style access with `GOPRIVATE` so Go pulls private modules without prompting:

```sh
export GOPRIVATE=github.com/paper-board
```

Add this to your shell profile so it persists.

### Step 2 — Create the kind cluster

```sh
kind create cluster --name paperboard --config infra/local/kind-config.yaml
```

The kind config in `infra/local/kind-config.yaml` sets up a single-node cluster with port
forwarding for the services we need locally.

### Step 3 — Start Postgres

We use Bitnami's Postgres Helm chart for local development. The cluster runs two connection
endpoints: port 5432 (direct, for migrations) and port 6432 (PgBouncer in transaction-pool
mode, for service runtime). **Never mix them** — the migrator requires a session-mode
connection for advisory locks, and the app runtime requires PgBouncer for connection
multiplexing.

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql \
  --namespace paper-board \
  --create-namespace \
  -f infra/local/postgres-values.yaml
```

Wait for Postgres to be ready:

```sh
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql \
  -n paper-board --timeout=120s
```

### Step 4 — Run migrations

Each service ships a migrator binary that runs as a Helm `pre-install` / `pre-upgrade` Job.
In local dev you run them explicitly:

```sh
MIGRATION_DB_URL="postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"

helm install agents-migrator infra/helm/agents \
  --namespace paper-board \
  --set migrator.only=true \
  --set migrator.env.MIGRATION_DB_URL="${MIGRATION_DB_URL}"

helm install identity-migrator infra/helm/identity \
  --namespace paper-board \
  --set migrator.only=true \
  --set migrator.env.MIGRATION_DB_URL="${MIGRATION_DB_URL}"
```

The migrator creates the `agents` and `identity` Postgres schemas and applies all migrations.
It uses an advisory lock (agents=3, identity=1) to prevent concurrent runs.

### Step 5 — Start the services

```sh
helm install agents-server infra/helm/agents \
  --namespace paper-board \
  -f infra/local/agents-values.yaml \
  --set env.ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"

helm install identity-server infra/helm/identity \
  --namespace paper-board \
  -f infra/local/identity-values.yaml
```

### Step 6 — Verify

```sh
kubectl get pods -n paper-board
curl http://localhost:8080/healthz
```

Expected output: `{"status":"ok"}`.

## Environment variables reference

Each service reads config exclusively from environment variables (no config files in
production). The critical split:

| Variable            | Port | Purpose                                                  |
| ------------------- | ---- | -------------------------------------------------------- |
| `MIGRATION_DB_URL`  | 5432 | Direct Postgres — used only by the migrator binary       |
| `DATABASE_URL`      | 6432 | PgBouncer transaction pool — used by the service runtime |
| `JWT_SIGNING_KEY`   | —    | HMAC key for JWT signing (identity service)              |
| `ANTHROPIC_API_KEY` | —    | Anthropic API key (agents service, BYO model)            |

For the full env var list per service, see the service's `operations.md` page.

## Pre-commit hooks

Install the hooks once after cloning any paper-board service repo:

```sh
pre-commit install
```

The hooks run `gofmt`, `golangci-lint`, `commitlint`, and `markdownlint` on every commit.
They will reject commits that fail lint. Never use `--no-verify` to bypass them.

## Resetting local state

If your local cluster gets into a bad state, the fastest reset is:

```sh
kind delete cluster --name paperboard
```

Then repeat Steps 2–6. Because we are pre-launch (Phase 1–4), there is no production data
to preserve — breaking schema changes are fine and `make drop && make migrate up` is the
canonical reset answer.

## Next steps

- [First PR](./first-pr.md) — open your first pull request against a paper-board service repo.
- [Service map](../architecture/service-map.md) — port reference and schema ownership per service.
