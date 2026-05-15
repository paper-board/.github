# 0010 — Go Service Architecture & Standards

**Status:** accepted
**Date:** 2026-05-01
**Related:** ADR-0001 (multi-repo), ADR-0002 (schema-per-service), ADR-0003 (no cross-schema FK),
ADR-0004 (migrator), ADR-0005 (REST + gRPC), ADR-0006 (vertical), ADR-0007 (repo topology),
ADR-0008 (license / commits / style), ADR-0009 (product-first sequencing).

## Context

Five repos are live (`.github`, `sdk`, `proto`, `infra`, `agents`). The agents minimal demo
passed (3 tables + REST + SSE + Anthropic). Six more services land per the roadmap. Without an
enforceable cross-service standards baseline, the seven services will diverge in folder layout,
middleware order, error shape, naming, and test strategy — exactly what ADR-0001's multi-repo
decision risks.

This ADR locks the standards. The substance lives in nine documents under `paper-board/.github/docs/standards/`,
each with MUST/SHOULD/MAY rules, real `agents`/`sdk` code references, rejected alternatives, and
enforcement hooks (lint rule, CI check, codegen, template artifact, or social).

## Decision

Adopt the standards suite at `paper-board/.github/docs/standards/`. New services bootstrap from
`paper-board/service-template`, which materialises every rule as a starting file.

**Note:** `paper-board/service-template` is currently pending bootstrap (tracked as Task 32 in
`tasks/2026-05-02-adr-0010-gap-analysis.md`). Standards rules referencing the template are
binding once the repo materialises; until then, services derive directly from `agents`
post-retrofit.

### The nine documents

| Doc                                                                   | Topic                                          |
|-----------------------------------------------------------------------|------------------------------------------------|
| `paper-board/.github/docs/standards/go-service-layout.md`            | folder structure; package boundaries           |
| `paper-board/.github/docs/standards/go-coding-conventions.md`        | DI shape, lint, naming, comment policy         |
| `paper-board/.github/docs/standards/http-api-conventions.md`         | chi/v5, middleware chain, error envelope, pagination, JSON convention |
| `paper-board/.github/docs/standards/database-conventions.md`         | pgx/v5, sqlc hybrid, Querier+WithTx, migration format, testcontainers |
| `paper-board/.github/docs/standards/observability.md`                | log keys, OTLP/HTTP, SSE tracing, metrics, redaction |
| `paper-board/.github/docs/standards/testing.md`                      | 4-layer matrix, coverage ramp, hand-rolled mocks, sdk/testfixture v1, golden |
| `paper-board/.github/docs/standards/error-handling.md`               | 8 sentinels, wrap rules, HTTP/gRPC mapping, panic recovery |
| `paper-board/.github/docs/standards/configuration.md`                | sdk/config env-only loader, Secret xor ConfigMap |
| `paper-board/.github/docs/standards/build-release.md`                | Dockerfile, reusable workflows, image tags, Helm chart, SemVer, service-template |

### Locked technology choices (one-line summary; see docs for detail)

- **Folder layout**: `cmd/{server,migrator}` + `internal/{api,core,store,<adapter>}` + `internal/gen/<svc>v1` + `migrations/{schema,concurrent,.future}` + `helm/<svc>` per-repo.
- **Package boundary test**: import-direction (go-arch-lint) + interface-ownership (review) + adapter-deletion smoke (always-on; mandatory `mock/` sub-package per adapter).
- **Configuration**: `sdk/config` env-only loader; per-service `internal/config.Config` with `validator/v10`; Secret xor ConfigMap; precedence env → built-in default; no flags, no files.
- **HTTP**: `chi/v5` only; 9-stage middleware chain; `sdk/httpmw` for cross-cutting + `internal/middleware/` for service-bespoke; per-service auth until the gateway terminates auth, then trust-headers; error envelope `{error: {code: <svc>.<x>, message, details?}}`; cursor pagination default.
- **Database**: `pgx/v5`; sqlc for static + raw pgx for dynamic; single `Store` struct file-per-aggregate; `Querier` interface + `sdk/store.WithTx`; migrations 6-digit + BEGIN/COMMIT + UTC `timestamptz` + `gen_random_uuid()`; testcontainers per-package + TRUNCATE per test.
- **Observability**: pinned canonical log keys (snake_case for logs); OTLP/HTTP exporter; one server span per HTTP request, one per LLM round-trip in SSE, no per-event spans; OTel SDK metrics; no Sentry; INFO default; redaction (regex + key denylist) default-on.
- **Testing**: unit / integration (`//go:build integration`) / service E2E (`//go:build e2e`) / system E2E; table-driven default; coverage gates per package (`internal/core` ≥ 90%); hand-rolled mocks (`mockery` only for sqlc Querier); `sdk/testfixture` v1 API; golden files for SSE/OpenAPI.
- **Errors**: 8 sentinels in `sdk/errors`; two-tier wrapping (leaf anchors sentinel; intermediate `fmt.Errorf("...: %w", err)`); `sdk/httpmw.HandleErr(w, r, svc, err)` central boundary; structured panic recovery; English only initially.
- **Cross-cutting**: stdlib `net/http` + `otelhttp`; `validator/v10`; UUIDv4 for legacy tables / UUIDv7 for new tables; UTC always.
- **Build/CI**: distroless/static runtime; multi-stage golang:1.23-alpine builder; reusable workflows in `paper-board/.github`; coverage ramp gated.
- **Versioning**: SemVer strict for sdk/proto; loose `v0.x.y` for backend pre-stable; image tag triple `git_tag` + `git_sha` + `latest`.
- **Lint**: `golangci-lint v2` with shared baseline; comment policy: 6 allowed forms (godoc, WHY, invariant, workaround citation, trap, trigger-tagged TODO), 7 banned (WHAT, section dividers, caller refs, removed-code markers, AI preambles, parameter restatements, stale).
- **JSON conventions**: wire DTOs camelCase; SQL columns snake_case; Go fields PascalCase; log attributes snake_case. Three-layer naming switch only at boundaries.
- **DI**: manual constructor injection only; six-phase `cmd/server/main.go` skeleton.
- **service-template**: `init.sh` placeholder rename; nightly drift CI in `paper-board/.github` compares template against `paper-board/.github/docs/standards/*.md`.

## Rejected alternatives

- **Hexagonal / Clean / DDD-lite full naming** (`domain/`, `usecases/`, `entities/`) — over-spec for current LOC; revisit at ~5k LOC per service.
- **Fiber v2/v3 web framework** — fasthttp engine forces two-port REST+gRPC pods (no `cmux`-style listener share); v3 still beta during our roadmap window. See go-coding-conventions §3 depguard rule.
- **`wire` / `fx` DI** — over-engineering at ≤5 wires per service; manual is grep-able.
- **`viper` / `koanf`** for config — env-only k8s deploys don't use multi-source merge or hot reload.
- **GORM / ent / bun ORM** — locks query plans behind framework AST; unacceptable for partitioned tables and pgvector similarity.
- **`gomock` / `testify/mock`** — verbose, opaque failures; hand-rolled wins at our adapter count.
- **Per-service top-level error sentinels** — fragments `errors.Is` portability across the gateway boundary.
- **All-snake_case wire JSON** — initially locked, reversed for frontend ergonomics; logs stay snake_case so Loki/Grafana/OTel conventions hold.
- **Per-service Helm chart in `infra` repo** — cross-repo PR per value bump; chart stays in service repo.
- **Sentry / external error tracking** — OTel + structured logs already capture; revisit if error triage becomes a bottleneck.

## Consequences

### Gain

- Reader of one service navigates any other in five minutes.
- Code review focuses on logic, not folder structure.
- Adding service N (n ≥ 2) is `service-template` clone + rename, not a re-decision.
- Lint + CI catch structural regressions; doc text isn't the only line of defence.
- Cross-service log/trace correlation works because keys + IDs are pinned.

### Cost

- `agents` migration to standard ~3-4 days total (extract `core`, sqlc adoption, `internal/middleware` chain, JSON tag flip, comment cleanup). Tracked in `tasks/2026-04-30-backend-roadmap.md`.
- `service-template` repo blocks identity scaffolding.
- Some lint rules are aspirational (custom analyzers); social enforcement covers gap.

### Migration order

1. **agents retrofit**: extract `core`, sqlc adoption, `internal/middleware` chain via `sdk/httpmw`, JSON tag flip to camelCase, comment cleanup, coverage gates met.
2. **service-template**: scaffolds new services from agents-post-retrofit shape.
3. **identity**: clones service-template; first service to ship without retrofit cost.

## Compliance

- A service repo is "compliant" when `make lint`, `make arch-check`, `make sqlc-verify`, `make mocks-verify`, `make cover-check`, `make helm-lint` all pass.
- `paper-board/.github` nightly job diffs `service-template/` against `paper-board/.github/docs/standards/*.md`; failure pings #engineering.
- This ADR supersedes nothing. Future architectural changes get their own ADR (0011+); the nine standards docs are amended in place when needed and referenced from the change ADR.

## Unresolved

- **i18n** (error-handling §6): English-only initially; pre-baked plan documented.
- **Sentry / crash-reporter** (observability §5): deferred until error triage becomes a
  bottleneck.
- **System E2E** harness (`paper-board/infra/e2e/`): Tilt + Kind; lands when multi-service
  testing demand justifies the harness cost.
- **mTLS** between services: ADR-0005 defers; NetworkPolicy default-deny holds until then.
- **`pkg/` of cross-cutting Go helpers** (e.g. service-shared business logic that doesn't belong in `sdk`): not yet needed; revisit if domain-shared types emerge across services.
- **`sdk/grpcmw`** (gRPC middleware mirror of `sdk/httpmw`): introduced once internal gRPC traffic begins; out of scope for this ADR.
