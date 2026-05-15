# ADR-0012 — Auth Flow (Phase 2)

**Status:** Accepted (2026-05-15)
**Date:** 2026-05-15
**Deciders:** ensar

> **Slot note:** Plan `tasks/2026-05-11-identity-phase-2-plan.md` referenced this as ADR-0011, but slot 0011 was taken by `0011-standards-refresh.md` (2026-05-04). Substance unchanged; ADR shifts to 0012.

## Context

paper-board needed identity-aware authentication on agents. The Phase 1.1 placeholder was `httpmw.AuthStub(zero-UUID)` — single-tenant, no auth, no signal. Phase 2 of the roadmap delivers:

- `paper-board/identity` service (users, orgs, API keys, JWT issuer)
- `paper-board/sdk/auth` middleware (format-detecting `Require()` decorator)
- `paper-board/agents` retrofit (`AuthStub` → `sdk/auth.Require`, tenant-scoped queries)
- `paper-board/service-template@v0.2.0` (identity-aware middleware as Tier 1 byte-match baseline)
- `paper-board/identity` helm chart + `paper-board/infra` sub-chart wiring (OCI cross-repo consume)

## Decision

Full rationale in `tasks/2026-05-10-identity-phase-2.md` § Decisions. Condensed:

- **D1.** API keys = `pbk_<env>_<crockford32>` (Stripe-style). Single `api_keys` table with env enum (`live | test`); argon2id hash + 12-char plaintext prefix index for O(1) lookup.
- **D2.** Auth = per-route `Require(modes...)` decorator on single `Authorization: Bearer` header. Format-detect routes to JWT or APIKey verifier. JWT-only override for sensitive endpoints (org membership mutations).
- **D3.** JWT = RS256, 1h TTL, ±60s clock skew, no refresh token in Phase 2 (re-login flow).
- **D4.** `auth_keys` = 3-state lifecycle (`next | active | retired`) + manual `identity-cli rotate`; KMS + JWKS deferred to Phase 5.
- **D5.** Roles = `owner | member`; at-least-1-owner invariant enforced app-level Phase 2 (DB CHECK Phase 5).
- **D6'.** Pre-launch: **no backfill migration**; `make drop && make migrate up` is the dev reset workflow (memory `paper_board_pre_launch.md`).
- **D7.** Bootstrap = `identity-cli bootstrap` idempotent subcommand; ships in same multi-binary image as server + migrator (3-binary Dockerfile target).
- **D8.** Error matrix — 404 cross-tenant + 403 within-org + 401 unauthenticated + 401 wrong-environment-tier; privacy-first existence hiding.
- **D9.** `service-template@v0.2.0` ships identity-aware `sdkAuth.Require(JWT, APIKey)` as Tier 1 byte-match baseline; downstream services bootstrap with default already in place; allowlist remains empty.

## Implementation outcome

18-task TDD plan in `tasks/2026-05-11-identity-phase-2-plan.md`. Critical path: `1 → 4 → 9 → 11.5 → 12 → 14 → 17`. Closed 2026-05-04 → 2026-05-15.

### Multi-repo coordination patterns established

- **PAT-escape (release-please)** — fine-grained `RELEASE_PLEASE_PAT` secret on sdk/identity/agents unblocks release-please-driven workflows (workflow-token write-clamp circumvention). Sdk PR #3.
- **OCI helm cross-repo dependency** — `helm/identity` published to `ghcr.io/paper-board/helm/identity:<chart-version>` via tag-triggered release.yml; `helm/agent-manager` (paper-board/infra) consumes via `repository: oci://ghcr.io/paper-board/helm` in Chart.yaml. No file:// hacks, no submodules, fully versioned. Identity PR #14, infra PR #1.
- **Per-PR CodeRabbit (CR) loop discipline** — every PR follows 3-channel signal poll (inline / review body / status context) + 1-commit-per-round fix-and-loop (never force-push) + in-thread reply per finding with fix-SHA + code-quality reviewer dispatch post-CR-convergence. Memory `pr_review_loop_workflow.md`.
- **GHCR per-package "Manage Actions access"** grant — newly-published GHCR packages default-private to source repo; cross-repo workflow access requires `https://github.com/orgs/paper-board/packages/<type>/<name>/settings → Manage Actions access → Add Repository`. Bypasses org-level visibility lock when "Setting is disabled by organization administrators". Infra PR #1 troubleshoot.
- **CI permissions clamp** — `default_workflow_permissions: read` at org level forces top-level `permissions:` block on every workflow needing `packages: read` or `packages: write`. Job-level alone insufficient. Memory `paper_board_actions_permissions.md`.
- **Per-schema `{schema}_migrator` PoLP role** — postgres init creates separate migrator role (schema OWNER, full DDL within own schema) + app role (runtime DML only). `ALTER DEFAULT PRIVILEGES FOR ROLE` propagates grants to future migration-created tables. Infra PR #1 closes postgres-superuser-via-migration leak.
- **Template-time `fail` + `regexMatch` validation** crosses repo boundaries — identity chart's `regexMatch "^[0-9A-Fa-f]{64}$"` KEK guard fires inside infra umbrella render. Helm `fail` is contract enforcement.

### Sub-task outcomes (1-16)

| Task   | Outcome                                                                                                                          |
|--------|----------------------------------------------------------------------------------------------------------------------------------|
| 1      | identity schema 5 tables + 4 inline CHECK + 2 partial unique indexes; migration `000001`.                                        |
| 2      | identity sqlc queries (5 per-table .sql files; 6 integration tests; 76% cover).                                                  |
| 3      | apikey package: `pbk_(live\|test)_<crockford32>` generate + argon2id hash + parse-and-verify.                                    |
| 4      | jwtcore package: RS256 issuer + verifier + 3-state auth_keys + AES-GCM KEK envelope.                                             |
| 5      | proto `identity/v1/auth.proto` + 4 RPCs + AuthContext message; common.v1 package rename.                                         |
| 6      | identity gRPC AuthService impl (4 RPCs) on :50051.                                                                               |
| 7      | identity REST 7 endpoints + local httpmw (sdk/auth deferred to Task 9).                                                          |
| 8      | identity-cli bootstrap subcommand; idempotent tx; 3-binary Dockerfile target.                                                    |
| 9      | sdk/auth package: `Require + RequireRole + Keystore + jwt_verify + apikey_verify + mock`; 94.4% cover.                           |
| 10     | sdk/auth integration tests (8 cases): in-process bufconn + testcontainers Postgres + replica dbAuthServer.                       |
| 11     | sdk v0.3.0 release via PAT-escape pattern.                                                                                       |
| 11.5   | service-template@v0.2.0 ships `sdkAuth.Require(JWT, APIKey)` default; Tier 1 byte-match baseline.                                |
| 12     | agents `AuthStub` → `sdk/auth.Require` swap; Tier 1 byte-match vs template = NO DIFF.                                            |
| 13     | agents cross-tenant 404 via sqlc named-params `@id`+`@org_id`; new `TestE2E_CrossTenant404` regression guard.                    |
| 14     | agents↔identity cross-svc integration: 11 test cases over docker-compose stack (identity gRPC+REST + agents + postgres).         |
| 15     | tenant isolation E2E (list-bleed test); golangci.yml `^test/(integration\|e2e)/` exemption.                                      |
| 16     | identity helm chart v0.2.1 on OCI + infra umbrella OCI consume + per-schema `{schema}_migrator` PoLP role + sequence grants.     |

### Carry-forwards into Phase 5+

- **mTLS** — drop `cfg.Env != "dev"` insecure-gRPC fail-fast guard when cert-manager + mTLS lands per ADR-0005.
- **TLS-everywhere** — remove `Env default:"dev"` silent fallback (T12 carry-forward #4).
- **docker-compose hygiene** — `service_started → service_healthy` + `agents/scripts/postgres-init/00-app-users.sql` mirror per-schema migrator role pattern (compose-side).
- **DB CHECK constraints** — at-least-1-owner invariant DB enforcement (D5 Phase 5).
- **JWT KMS + JWKS** — replace 3-state auth_keys with KMS-managed keys + JWKS public endpoint.
- **RBAC** — extend `owner | member` to fine-grained role matrix (Phase 8+).
- **Refresh token UX** — Phase 5+.
- **External Secrets Operator / Vault** — replace `values-dev.yaml` checked-in dev KEK pattern.
- **Store-level cross-tenant test** — T13-3 belt-and-braces unit test (E2E covers semantically; store-level for defense-in-depth).

## Consequences

**Positive:**
- agents is tenant-isolated; secure-by-default skeleton for Phase 3+ (billing, platform).
- Multi-repo coordination playbook captured (PAT-escape, OCI helm, CR loop, drift-CI).
- No scope creep into Phase 5 KMS / RBAC / mTLS.

**Negative:**
- 16-task implementation; ~3.5 weeks single-engineer (subagent-paralleled).
- No refresh token UX until Phase 5 (re-login required at JWT TTL boundary).
- Pre-launch reset workflow (`make drop && make migrate up`) instead of backfill — switches to forward-only post-launch (Phase 5 cutover gate).

## References

- `tasks/2026-05-10-identity-phase-2.md` (spec; D1-D9 with rejected alternatives)
- `tasks/2026-05-11-identity-phase-2-plan.md` (TDD impl plan; 17 tasks)
- `tasks/2026-05-11-identity-phase-2-progress.md` (execution log; per-PR commit graphs + CR-loop transcripts + commendations)
- `tasks/RESUME-PROMPT.md` (live state pointer)
- ADR-0001 (multi-repo microservices), ADR-0002 (schema-per-service), ADR-0003 (cross-schema FK ban), ADR-0005 (REST+gRPC communication), ADR-0009 (product-first sequencing), ADR-0010 (go-service-architecture), ADR-0011 (standards-refresh)
- Memory: `paper_board_actions_permissions.md`, `pr_review_loop_workflow.md`, `pr_review_reply_etiquette.md`, `prefer_pr_over_direct_push.md`, `paper_board_pre_launch.md`, `service_template_smoke_bugs.md`, `github_actions_secrets_in_if.md`
