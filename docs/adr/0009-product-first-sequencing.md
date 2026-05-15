# 0009 — Product-first sequencing (supersedes ADR-0006 phase order)

**Status:** accepted
**Date:** 2026-04-30
**Supersedes:** ADR-0006 (phase order only; tracer-bullet philosophy retained)

## Context

ADR-0006 set vertical (tracer-bullet) implementation in foundation-first order: identity → billing → agents → platform. plan/00 D2 ("RBAC at foundation") drove this — auth/RBAC before product features.

Solo dev pivoted: minimal first, defer non-blocking foundation work, demoable agent in Phase 1, retrofit auth/billing/audit on real product.

## Decision

Phase 1 starts with **`paper-board/agents`** as the tracer bullet (not identity).

**New phase order:**

| Phase | Service                     | Scope                                              |
|-------|-----------------------------|----------------------------------------------------|
| 1     | agents                      | Minimal runtime: 3 tables, REST + SSE, 1 LLM provider, no auth |
| 2     | identity                    | Auth (API keys + JWT signing); retrofit agents middleware |
| 3     | billing                     | Subscriptions + usage metering; agents emit usage  |
| 4     | platform                    | Audit log + memory + artifacts                     |
| 5     | (production hardening)      | DNS, TLS, partitioning, hash-chain, cosign, prod cluster |
| 6     | runtime + compute           | Multi-tenant data plane split from agents          |
| 7     | gateway                     | Centralize auth + routing                          |
| 8+    | RBAC + marketplace + advanced |                                                  |

Phase 1.0 prep (sdk + proto + infra) order unchanged from ADR-0006.

## Rejected alternatives

- **Foundation-first (ADR-0006 original)** — defers demoable product 4-6 weeks; foundation over-engineered before product feedback.
- **Big-bang all-services** — solo dev cannot maintain 4 services in flight simultaneously.
- **Agents-first WITHOUT multi-repo** — would defeat ADR-0001; multi-repo cost paid, sequencing only changes.

## Consequences

**Gain:**
- Demoable agent in 2-3 weeks (vs 4-6 weeks foundation-first).
- Real product feedback shapes auth/billing/audit design (vs upfront speculation).
- Phase 1 acceptance simple: `curl POST /v1/sessions/:id/prompt` returns SSE.
- Parallel deferral of plan/00 ops items (DNS, mailbox, Stripe, Postmark, Vanta, Statuspage, prod K8s) — minimal Phase 0.

**Risk accepted:**
- Auth retrofit refactor on existing endpoints (Phase 2).
- No multi-tenancy in Phase 1 (single hardcoded `org_id` placeholder).
- plan/00 D2 ("RBAC at foundation") violated — RBAC deferred to Phase 8.
- Phase 1 minimal schema → Phase 5 partitioning is migration work (acceptable: data is dev-only Phase 1-4).

**Mitigation:**
- Phase 1 endpoints minimal (~6); retrofit blast radius small.
- Phase 5 schema retrofit while data volume is dev-only (truncate-and-recreate acceptable).
- Catalog tables (`roles`, `role_permissions`) added in Phase 5 even if assignments deferred to Phase 8 — minimizes Phase 8 schema change.

## Tracer-bullet philosophy retained (ADR-0006)

Each service still implemented end-to-end before next. Phase 1 = agents end-to-end (migrator + schema + server + LLM + Helm + smoke), then Phase 2 = identity end-to-end. The vertical-vs-horizontal slicing principle is the same; only the **service order** changes.

## Reference

- Roadmap: `tasks/2026-04-30-backend-roadmap.md`
- Archived foundation-first plan: `tasks/archive/2026-04-30-backend-phase-1-foundation-first.archive.md`
