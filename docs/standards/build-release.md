# Build, CI, Release & Service-Template Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative.
References: ADR-0007 (repo topology), ADR-0008 (license / commits / SemVer), CLAUDE.md.

This document fixes the Dockerfile shape, GitHub Actions reusable workflows, image tagging,
SemVer policy, breaking-change handling, and the `paper-board/service-template` repo's
contract for every backend service.

---

## 1. Dockerfile — multi-stage, distroless runtime

### Rule

Every service MUST ship a single root `Dockerfile` matching this shape:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG GO_VERSION=1.23
ARG ALPINE_VERSION=3.20

# ─── builder ─────────────────────────────────────────────────────────────────
FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder
WORKDIR /src
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    apk add --no-cache git
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download -x
COPY . .
ARG TARGET=server
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
        -ldflags='-s -w -X main.version=${VERSION:-dev}' \
        -o /out/${TARGET} ./cmd/${TARGET}

# ─── runtime ─────────────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/${TARGET} /app
USER nonroot
ENTRYPOINT ["/app"]
```

### Constraints

- Builder base: `golang:1.23-alpine3.20` (or current LTS pair).
- Runtime base: `gcr.io/distroless/static-debian12:nonroot`. Alpine runtime is forbidden — busybox
  shell is unnecessary and `:nonroot` ships UID 65532 by default.
- `CGO_ENABLED=0`. Static binary; no glibc dependency in runtime.
- Image size target: **≤ 25 MB** total. Above that, audit Go vendored deps for accidental ML
  libraries / bloat.
- `--mount=type=cache` for module + build caches. BuildKit-only.
- One Dockerfile produces both `server` and `migrator` via `--build-arg TARGET=`.

### Build invocation

```sh
docker buildx build \
  --build-arg TARGET=server \
  --build-arg VERSION=$(git describe --tags) \
  -t ghcr.io/paper-board/agents-server:$(git describe --tags) \
  --cache-from type=registry,ref=ghcr.io/paper-board/agents-server:cache \
  --cache-to type=registry,ref=ghcr.io/paper-board/agents-server:cache,mode=max \
  --push .
```

### Rejected alternatives

- **Alpine runtime** — adds busybox, apk metadata; 5-7 MB overhead; no shell needed in production.
- **Ubuntu / Debian slim** — too large; glibc not needed for static Go.
- **Single-stage `FROM golang:...` runtime** — ships ~900 MB of toolchain in production.
- **Custom scratch image** — distroless gives non-root + ca-certificates + tzdata for free.

### Enforcement

- service-template ships this Dockerfile.
- CI step `make docker-size-check`: fails build if final image > 25 MB.

---

## 2. CI — reusable workflows in `paper-board/.github`

### Rule

`paper-board/.github` repo hosts reusable GitHub Actions workflows under
`.github/workflows/`. Every service repo MUST consume them via `uses:`; service repos MUST NOT
duplicate the substance of these workflows.

### Workflow inventory

| File                                         | Purpose                                                                |
|----------------------------------------------|------------------------------------------------------------------------|
| `.github/workflows/go-ci.yml`                | lint, unit test, integration test (testcontainers), coverage gate, mocks-verify, sqlc-verify, arch-check |
| `.github/workflows/docker-publish.yml`       | buildx multi-arch build + push to GHCR; cosign signing (planned)        |
| `.github/workflows/helm-publish.yml`         | helm lint + package + push OCI to GHCR `ghcr.io/paper-board/helm/<svc>` |
| `.github/workflows/release-please.yml`       | release-please runs Conventional Commits → tag + changelog              |
| `.github/workflows/standards-sync.yml`       | nightly drift check (service-template vs `agent-manager/docs/standards/*.md`) |

### Service-repo wrapper

```yaml
# paper-board/agents/.github/workflows/ci.yml
name: ci
on: [push, pull_request]

jobs:
  ci:
    uses: paper-board/.github/.github/workflows/go-ci.yml@main
    with:
      service: agents
      coverage_threshold: "70"
    secrets: inherit
```

Secrets the workflows expect (set at the org level, inherited):

- `GHCR_TOKEN` — push to GHCR.
- `COSIGN_KEY` (planned) — image signing.
- `ANTHROPIC_API_KEY_TEST` (optional) — used by service E2E layer.

### Cache strategy

- Go module cache: `actions/setup-go@v5` with `cache: true` (sums of `go.sum`).
- Go build cache: `actions/cache@v4` keyed on OS + Go version + `go.sum` hash.
- Docker layer cache: BuildKit registry cache (see §1 build invocation). Cache scope per branch.
- Test cache: `GOCACHE=/tmp/gocache` preserved across `go test` calls within a job.

### Enforcement

- service-template ships only the wrapper file.
- CI workflow MUST NOT contain inline `go test` / `golangci-lint` invocations (everything via the
  reusable workflow).

---

## 3. SemVer + release policy

### 3.1 sdk + proto — strict SemVer (locked by ADR-0008)

`paper-board/sdk` and `paper-board/proto` MUST follow strict SemVer.

- `MAJOR` bump on any breaking API change, even pre-1.0.
- pre-1.0 (`v0.x.y`) period currently active; bumps to `v1.0.0` when API stabilises.

### 3.2 Backend services — looser pre-1.0

Backend services (agents, identity, billing, platform, runtime, gateway, compute) MAY ship
breaking changes within `v0.x.y` while pre-stable. Once a service has external consumers
depending on its REST + gRPC contracts (typically: when the gateway routes traffic to it, or
the public CLI wraps it), it MUST follow strict SemVer.

Components consumer-facing from inception (gateway, runtime, compute) MUST follow strict SemVer
from their first release.

The per-service stabilization timeline is a roadmap concern; see `tasks/`.

### 3.3 Conventional Commits + release-please

Locked from ADR-0008. `release-please.yml` (§2 inventory) reads commit history, computes the
next SemVer, opens a release PR with `CHANGELOG.md` + tag bump. Squash-merge of the release PR
publishes the GitHub Release, which triggers `docker-publish.yml` and `helm-publish.yml`.

### 3.4 Breaking-change policy

- **Proto** (when proto stabilizes): `buf breaking` runs in CI on PRs touching `proto/<svc>/v*/*.proto`.
  Breaking changes without a major bump (and a documented migration) fail the build.
- **REST** (every service): URL-versioned. New `/v2` ships in parallel with `/v1`. `/v1`
  deprecation requires:
  - `Deprecation: Tue, 01 Jan 2027 00:00:00 GMT` header on `/v1` responses for ≥ 90 days before
    removal.
  - `Sunset: ...` header pointing at the removal date.
  - PR adding `/v2` MUST include a migration note in the service's `CHANGELOG.md`.
  - 90-day window enforced socially; no automated CI gate.

### 3.5 i18n / wire stability — pre-baked

The `code` field of error envelopes (`<service>.<suffix>`) is the stable contract; `message` text
is debug copy. Changing `code` is a breaking change. Adding a new code is non-breaking.

---

## 4. Image + Helm chart tagging

### 4.1 Image tag triple

Every service image MUST be pushed with three tags:

| Tag form           | Source                              | Use                                               |
|--------------------|-------------------------------------|----------------------------------------------------|
| `<git_tag>`        | `git describe --tags --exact-match` | **prod** (immutable, audit-friendly)               |
| `sha-<git_sha>`    | first 7 chars of `git rev-parse HEAD` | **staging** / preview deploys                    |
| `latest`           | main branch HEAD                    | **dev only** (docker-compose, kind smoke tests)    |

Naming convention (ADR-0007 + CLAUDE.md): `ghcr.io/paper-board/<svc>-<binary>:<tag>`. Examples:

```text
ghcr.io/paper-board/agents-server:v0.1.0
ghcr.io/paper-board/agents-server:sha-7c1d4a2
ghcr.io/paper-board/agents-server:latest
ghcr.io/paper-board/agents-migrator:v0.1.0
```

`latest` MUST NOT be referenced from any deployment manifest committed to the repo. `latest`
exists only for ad-hoc pulls.

### 4.2 Helm chart `appVersion` + `version`

Helm chart fields MUST follow:

- `appVersion` = exact `<git_tag>` of the service image at release time. Updated by
  release-please.
- `version` = chart SemVer; bumps when chart-internal changes occur (template fix, value rename),
  independent of `appVersion`. Each chart change MUST bump `version` (else Helm caches stale).

```yaml
# helm/agents/Chart.yaml
apiVersion: v2
name: agents
version: 0.2.1            # chart SemVer; bumped per chart edit
appVersion: v0.1.0        # service image tag this chart was tested against
description: paper-board agents service
```

### 4.3 SBOM (planned)

`docker-publish.yml` will generate a Syft SBOM and attach it via cosign attestation to the
published image once this capability lands. The capability is added at the workflow level once;
service repos consume it transparently. Until then, services may ship without an SBOM.

---

## 5. `paper-board/service-template`

### Purpose

`paper-board/service-template` is the canonical example of a compliant service. New services
clone it and rename. The template is the **executable specification** of the eight standards
documents under `docs/standards/`.

### Placeholder set

| Placeholder            | Replaced with                                   | Example          |
|------------------------|-------------------------------------------------|------------------|
| `{{SERVICE_NAME}}`     | lowercase service name                          | `identity`       |
| `{{SERVICE_PREFIX}}`   | error-code prefix (`<svc>.`)                    | `identity.`      |
| `{{ADVISORY_LOCK_ID}}` | per-service id (CLAUDE.md mapping)              | `1`              |
| `{{SCHEMA}}`           | Postgres schema name                            | `identity`       |
| `{{MODULE_PATH}}`      | Go module path                                  | `github.com/paper-board/identity` |

### `init.sh` contract

```sh
#!/usr/bin/env bash
# init.sh — bootstrap a new service from the template.
# Usage:  ./init.sh <service_name> <advisory_lock_id>

set -euo pipefail
SVC=$1
LOCK=$2
SCHEMA=${3:-$SVC}

# 1. validate lock id is unused (script reads paper-board/.github/lock-ids.txt)
# 2. atomic find/replace across all template files
# 3. rename helm/{{SERVICE_NAME}} → helm/$SVC
# 4. git init + first commit on `main`
# 5. print next-step checklist (push, configure CI secrets, deploy to dev)
```

`init.sh` MUST be idempotent — re-running it on the same template directory MUST be a no-op.

### Bootstrap content

```text
service-template/
├── cmd/
│   ├── server/main.go              # six-phase wiring (coding §1)
│   └── migrator/main.go            # ~30-line sdk/migrator wrapper
├── internal/
│   ├── api/
│   │   ├── api.go                  # chi router + middleware chain
│   │   └── healthz.go              # /healthz + /readyz
│   ├── core/                       # domain types stub
│   ├── store/
│   │   ├── store.go                # pool ownership + WithTx
│   │   ├── queries/                # sqlc-generated stubs
│   │   └── example_aggregate.go    # template aggregate
│   ├── middleware/                 # service-bespoke middleware (empty placeholder)
│   ├── config/config.go            # Config struct + sdk/config.MustBind
│   └── testfixture/                # service-local builders
├── migrations/
│   ├── embed.go
│   ├── schema/000001_init.up.sql   # creates {{SCHEMA}} schema
│   ├── concurrent/.gitkeep
│   └── .future/.gitkeep
├── helm/{{SERVICE_NAME}}/
├── Dockerfile
├── docker-compose.yaml
├── Makefile                         # 7 standardised targets (test, test-integration, test-e2e, cover, cover-check, lint, helm-lint, smoke)
├── go.mod
├── .golangci.yml                    # extends paper-board/.github/golangci.yml
├── .mockery.yaml
├── sqlc.yaml
├── go-arch-lint.yml
├── README.md
├── CHANGELOG.md                     # release-please manages
└── init.sh
```

### Drift CI — staying in sync with standards docs

The hardest failure mode: standards docs say one thing, template ships another, services drift
to whichever they cloned.

Mitigations (in `paper-board/.github/.github/workflows/standards-sync.yml`):

1. **Nightly diff job** runs against the `agent-manager` repo (this repo). It diffs key sections
   of `docs/standards/*.md` (e.g. golangci.yml example, six-phase main.go skeleton, Dockerfile)
   against the corresponding template files and posts an issue on mismatch.
2. **PR-time check on standards docs**: a PR in this repo touching `docs/standards/*.md` MUST
   include either a checklist line confirming `service-template` was updated, or the same PR
   updates a sentinel file in service-template (cross-repo via `gh` CLI).
3. **CODEOWNERS**: `docs/standards/*.md` and `service-template/` share owners; review of one
   triggers awareness of the other.
4. **Major decisions = ADR**: standards docs reference ADR numbers; ADRs reference standards docs.
   Drift is a documentation bug, not a silent code bug.

---

## 6. Summary

| §    | Rule                                                              | Enforcement                                  |
|------|-------------------------------------------------------------------|----------------------------------------------|
| §1   | Multi-stage Dockerfile; distroless/static runtime; ≤ 25 MB        | service-template + `docker-size-check` CI    |
| §2   | Reusable workflows in `paper-board/.github`; service-repo wrappers | service-template wrapper-only                |
| §3.1 | sdk + proto strict SemVer (ADR-0008)                              | release-please + buf breaking                |
| §3.2 | Backend services loose `v0.x.y` pre-stable; strict once consumer-facing | per-service CHANGELOG + release-please       |
| §3.4 | REST `/v1` deprecation: 90-day Deprecation/Sunset header window   | social + service-template example            |
| §4.1 | Image tag triple `<git_tag>` + `sha-<sha>` + `latest`              | `docker-publish.yml`                         |
| §4.2 | Helm `appVersion` = git_tag; `version` independent SemVer          | release-please                               |
| §4.3 | SBOM via Syft + cosign (planned)                                   | `docker-publish.yml`                         |
| §5   | service-template; init.sh idempotent                               | `paper-board/service-template` repo          |
| §5   | Drift CI nightly diff template vs `docs/standards/*.md`            | `standards-sync.yml`                         |
