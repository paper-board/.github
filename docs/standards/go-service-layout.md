# Go Service Layout Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative. Reference: ADR-0001, ADR-0004, ADR-0007.

This document fixes the on-disk shape of every backend service in
`paper-board/{agents, identity, billing, platform, runtime, gateway, compute}`. A reader
familiar with one service MUST be able to navigate any other in five minutes.

---

## 1. Top-level repository layout

Every service repo MUST have this top-level shape:

```text
<service>/
├── cmd/                     # binaries (one subdir per binary)
│   ├── server/main.go       # http/grpc server
│   └── migrator/main.go     # ~30-line wrapper around sdk/migrator
├── internal/                # all non-exported Go packages
│   ├── api/                 # MUST exist — inbound transport (chi router, handlers, SSE)
│   ├── core/                # MUST exist — domain types and use-case functions
│   ├── store/               # MUST exist — pgx persistence
│   ├── <adapter>/           # MAY exist — outbound integration (llm, mailer, stripe, ...)
│   └── gen/<svc>v1/         # MUST exist when the service ships proto/openapi codegen
├── migrations/
│   ├── embed.go             # `//go:embed schema/*.sql`
│   ├── schema/              # transactional migrations (NNNNNN_name.up.sql / .down.sql)
│   ├── concurrent/          # non-transactional (CREATE INDEX CONCURRENTLY)
│   └── .future/             # gitignored draft area
├── helm/<service>/          # per-repo Helm chart (Chart.yaml, values.yaml, templates/)
├── Dockerfile
├── docker-compose.yaml      # local dev only
├── go.mod                   # module path: github.com/paper-board/<service>
└── README.md
```

A service MUST NOT contain a top-level `pkg/` directory. (Section 4.)
A service MUST NOT contain a top-level `tests/` directory. (Section 7.)
A service MUST NOT contain a top-level `gen/` directory; generated code lives in `internal/gen/`. (Section 5.)

---

## 2. `internal/` package set — the pinned three

### Rule

Every service MUST have exactly these three packages, with these responsibilities:

| Package         | Role                                                            | May import                          |
|-----------------|-----------------------------------------------------------------|-------------------------------------|
| `internal/api`  | HTTP/SSE/gRPC transport. Handlers, request DTOs, router setup.  | `internal/core`, `internal/<adapter>` (rare) |
| `internal/core` | Domain types (`Agent`, `Session`, …) and use-case functions.    | `internal/store` (via interface), `internal/<adapter>` (via interface) |
| `internal/store`| pgx-backed persistence. SQL lives here.                         | `internal/core` (for domain types only) |

Outbound adapters MAY live under `internal/<name>/`, one package per integration role.
Each adapter package MUST expose an interface and MUST provide impl variants under sub-packages,
including a `mock/` sub-package alongside every production impl from day 1
(e.g. `internal/llm/{anthropic, mock}` — precedent: `agents/internal/llm/`). The mandatory
`mock/` keeps the adapter-deletion smoke test (§3.3) always-on.

### Rationale

Three roles cover every backend service we know we will build: **inbound transport**, **domain logic**, **outbound integration**, **persistence**. Pinning the names eliminates the cross-service rename
discussions ("is it `handler/` or `api/`? `repo/` or `store/`?"). `core` keeps domain types out of
HTTP handlers and SQL — without it, every service repeats `agents`'s current mistake of putting `Agent`/`Session` structs in `internal/store/store.go` (lines ~30-90 of that file today).

### Rejected alternatives

- **Open-ended package names** — rejected: violates the "five-minute navigation" goal. Drift is the failure mode.
- **`{api, store}` only (no `core`)** — rejected: domain logic leaks into transport or SQL layer; both options 1A-2 and 1A-3 considered, 1A-3 picked because it adds ~150 LOC migration once but pays back across 6 future services.
- **Hexagonal `domain/ + app/ + adapters/{http,db,llm}/`** — rejected: too many layers for current LOC count (~700 in agents); revisit if a service exceeds ~5k LOC.
- **Clean / DDD-lite full naming (`entities/`, `usecases/`, `interfaces/`)** — rejected: unfamiliar to Go newcomers; `core/` is the idiomatic Go shorthand.

### Enforcement

- `go-arch-lint` config at repo root pins import direction:
  - `internal/api` MUST NOT be imported by `internal/store` or any adapter.
  - `internal/core` MUST NOT import `internal/api`, `internal/store`, or any adapter package directly (must go through interfaces it owns).
  - `internal/store` MUST NOT import `internal/api` or any adapter package.
- CI step `make arch-check` runs `go-arch-lint check`.
- `service-template` ships the three dirs with stub files.

---

## 3. The "good package boundary" test

A package boundary is good if **all three** rules hold. Each catches a different class of violation;
single-rule schemes leak.

### 3.1 Import-direction acyclic (structural, CI-enforced)

The repo MUST ship `go-arch-lint.yaml` at root with these directed edges only:

```text
internal/api      → internal/core
internal/api      → internal/<adapter>          (only when transport-level wiring needs it)
internal/store    → internal/core               (for domain types only)
internal/<adapter>→ internal/core               (for domain types only)
cmd/server        → internal/{api,core,store,<adapter>}
cmd/migrator      → migrations, sdk/migrator
```

Any back-edge (e.g. `core → store`, `core → api`) MUST fail `make arch-check`.

### 3.2 Interface ownership (semantic, review-enforced)

When package A consumes package B's behaviour, the interface MUST live in **A** (the consumer),
not in B (the implementer). Concrete impls live in **child sub-packages** of B.

Reference precedent: `agents/internal/llm/llm.go` defines `llm.Client`; `cmd/server/main.go:62-72`
selects `mock.Client` or `anthropic.New(...)` and hands it to `api.New(st, llmClient)`. The interface
sits with the consumer cluster (`api`, `core`); each impl is a child package.

Enforced via:
- golangci-lint `interfacebloat` (cap interface size).
- Code-review checklist line: *"Does the interface live with the consumer? Are impls in child packages?"*

### 3.3 Adapter-deletion smoke (operational, CI-enforced from day 1)

Every service with at least one outbound adapter MUST provide a `make test-mock-only` target. The
target sets `*_PROVIDER=mock` (or equivalent) for every adapter and runs
`go test -tags=integration ./...`. The build fails if any non-mock impl is reached.

This is a smoke test that the swap actually works at runtime — not just at compile time. Because
§2 mandates a `mock/` sub-package alongside every production impl, the smoke test always has
something to swap to and runs continuously rather than activating only after a second impl lands.

### Rationale

Import-direction alone permits domain types to leak through HTTP DTOs (a structural pass with
semantic rot). Interface-ownership alone is review-only and humans miss it. Adapter-deletion alone
is a smoke test, not a structural rule. Combining the three covers structural, semantic, and
runtime classes of boundary violation at low cost: one config file, one review checklist item, one
Make target.

### Rejected alternatives

- **Single rule "swap any sibling adapter"** — rejected: under-specified; doesn't catch domain leaks
  or structural cycles.
- **`go-arch-lint` only** — rejected: misses interface-ownership inversion, which is the most common
  Go-newbie mistake (defining the interface in the impl package).
- **Manual review only** — rejected: drifts. Lint must catch the structural class.

### Enforcement summary

| Sub-rule | Tool                              | Trigger                  |
|----------|-----------------------------------|--------------------------|
| §3.1     | `go-arch-lint check` in CI        | every PR                 |
| §3.2     | `interfacebloat` + review item    | every PR                 |
| §3.3     | `make test-mock-only` in CI       | every PR; required from day 1 (mock sub-package mandated by §2)                   |

---

## 4. `pkg/` directory — forbidden

### Rule

A service repo MUST NOT contain a top-level `pkg/` directory. Reusable code lives in
`paper-board/sdk` (separate repo, MIT-licensed, public Go module).

### Rationale

Module paths are private (`github.com/paper-board/<service>` — proprietary repo). There are no
external Go consumers of any backend service. `pkg/` was originally a marker for "this is OK to
import from outside the module"; we have no outside, so the marker is noise.

### Enforcement

CI grep step:

```sh
test -z "$(find . -type d -name pkg -not -path './internal/*' -prune -print)"
```

Fails the build if any `pkg/` dir exists.

---

## 5. Generated code location

### Rule

Generated code MUST live under `internal/gen/<source>/`, where `<source>` is the schema name:

- Protobuf: `internal/gen/<svc>v1/` (e.g. `internal/gen/agentsv1/` for `paper-board/proto/agents/v1`).
- OpenAPI: `internal/gen/openapi/`.

Top-level `gen/` is forbidden; it implies external import surface.

### Rationale

Generated code is implementation detail, not API surface. `internal/` enforces this at the compiler
level. A `<source>` subdir keeps `buf generate` deterministic and lets us regenerate without
touching hand-written code.

### Enforcement

- `buf.gen.yaml` pins `out: internal/gen/<svc>v1` per service (template artifact in
  `paper-board/proto/` build pipeline).
- Same CI grep as section 4 also rejects top-level `gen/`.

---

## 6. Helm chart location

### Rule

Each service MUST ship its Helm chart at `helm/<service>/` inside its own repo.
Example: `paper-board/agents/helm/agents/` (verified present:
`Chart.yaml`, `values.yaml`, `templates/server-deployment.yaml`,
`templates/server-service.yaml`, `templates/migrator-job.yaml`).

`paper-board/infra` MUST own only cluster-level charts (cert-manager, ingress-nginx, postgres,
observability stack).

### Rationale

Chart values change in lockstep with service code (image tag, env vars, migrator job hook). Putting
the chart in a sibling repo means every value bump is a cross-repo PR — friction without benefit.
ADR-0001 (multi-repo) accepts coupled-but-co-located.

If chart drift across services becomes painful, revisit by extracting a shared
`paper-board-svc-base` chart into `infra/` and depending on it as a Helm subchart.

### Rejected alternatives

- **Centralized in `paper-board/infra/helm/<service>/`** — rejected: cross-repo PR for every
  service-side change; image tag coupling is awkward.
- **Templated via Helmfile / Argo ApplicationSet only** — deferred; does not change per-service
  location of the chart source.

### Enforcement

- Social rule.
- `service-template` ships `helm/<service>/` skeleton.

---

## 7. Tests location

### Rule

Test files MUST be co-located as `_test.go` next to the code they test. There MUST NOT be a
top-level `tests/` directory inside a service repo.

Integration tests (testcontainers-go) MUST be gated by build tag:

```go
//go:build integration
// +build integration

package store_test
```

E2E tests (multi-service) live outside any service repo: in `paper-board/infra/e2e/` or a future
`paper-board/e2e` repo.

### Rationale

Go convention: co-located `_test.go` is what `go test ./...` and the coverage tooling expect. A
build tag cleanly separates "unit (fast, no DB)" from "integration (testcontainers)" without
duplicating directory layout. E2E is multi-service by definition, so it belongs in a place that can
reference all of them.

### Enforcement

- golangci-lint enables the `testpackage` linter (force `package x_test`, not `package x`).
- `Makefile` standardises:
  - `make test` → `go test ./...` (unit only).
  - `make test-integration` → `go test -tags=integration ./...`.
- `service-template` ships both targets.

---

## Summary table — per-rule enforcement

| Rule    | Topic                          | Enforcement                                                     |
|---------|--------------------------------|-----------------------------------------------------------------|
| §1      | top-level shape                | service-template + CI grep                                      |
| §2      | `internal/{api,core,store}`    | `go-arch-lint` + service-template                               |
| §4      | no `pkg/`                      | CI grep                                                         |
| §5      | `internal/gen/<src>/`          | `buf.gen.yaml` + CI grep                                        |
| §6      | per-repo `helm/<svc>/`         | service-template + social                                       |
| §7      | co-located tests + build tag   | golangci-lint `testpackage` + Makefile                          |
