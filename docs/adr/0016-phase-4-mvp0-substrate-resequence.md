# 0016 — Phase 4 backend MVP-0 substrate re-sequence (amends ADR-0015)

**Status:** accepted
**Date:** 2026-05-25
**Amends:** ADR-0015 (phase rebalance; supersedes ADR-0015's Phase 4 scope definition and downstream phase numbering)
**Scope:** system

## Context

ADR-0015 (2026-05-21) established Phase 4 = "platform + MVP-0 launch" with audit + onboarding + outbox + dashboard + 1 agent template + BYO API key flow + manual e-mail invoice. The phase was framed as a MVP-0 salable milestone in a single Epic (PB-10).

During the Phase 4 brainstorm session (2026-05-24 — 2026-05-25, source: `tasks/2026-05-24-phase-4-mvp0-brainstorm-notes.md`), 14 key decisions (D1-D14) invalidated the ADR-0015 Phase 4 scope in three ways:

1. **D4 — Backend-only Phase 4, frontend moved to Phase 5.** The user explicitly chose to defer frontend so backend cross-service integration could be proven end-to-end first; Phase 4 = "substrate (NOT salable)", Phase 5 = "frontend + MVP-0 launch".
2. **D5a — platform service split into 4 single-responsibility services** (audit + metering + notifications + onboarding) instead of one bundled platform service. Industry single-responsibility norm + Phase 7+ HA/scale separation alignment.
3. **D8' — Anthropic Managed Agents alignment.** Adopted Anthropic's Agent + Environment + Session + Vault separation. Two additional services introduced: `environments` (container config + non-sensitive env vars) and `vaults` (encrypted credentials, GCP KMS envelope). BYO Anthropic key now lives in vaults, not identity.

Additional decisions that shape the scope:

- **D6** — outbox pattern + Redis Streams + at-least-once delivery; sdk/outbox + sdk/inbox standardization
- **D9** — onboarding wizard pipeline: hybrid sync core + async email (D9.1); idempotency A+B (D9.2); DLQ + forward-only retry (D9.3); two-layer retry semantics (D9.4); polled status banner UX (D9.5)
- **D10** — metering aggregation: streaming hourly UPSERT + cron daily/monthly + daily reconciler (shadow invoice pattern)
- **D11** — manual invoice tooling DEFERRED to Phase 6 billing (`cli invoice` subtree removed from Phase 4 scope)
- **D12** — Coding Assistant template detail: claude-sonnet-latest + 5 tools (bash + str_replace_editor + view + web_search + web_fetch) + paperboard-branded ~150 word prompt + Python+node coding-baseline env + empty default vault + memory ON
- **D13** — e2e hybrid: testcontainers flows/ + kind cluster/ + `paper-board/e2e` as a separate repo (neutral ownership); LLM mock as default + nightly real Anthropic API smoke
- **D14** — 18 Story / 6 Wave implementation plan (PB-72..PB-89 under PB-10) with explicit Blocks/BlockedBy critical-path edges

## Decision

ADR-0016 supersedes ADR-0015's Phase 4 scope row and downstream phase numbering.

### New phase order (amends ADR-0015 table)

| Phase  | Service / Theme                                                         | MVP tier         | Epic                      | Notes                                                                                                                                                  |
| ------ | ----------------------------------------------------------------------- | ---------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1.0 ✅ | sdk + proto + infra v0.1.0                                              | —                | (closed)                  | Shipped 2026-05-06 → 2026-05-08                                                                                                                        |
| 1.1 ✅ | agents minimal runtime                                                  | —                | (closed)                  | Shipped v0.2.3                                                                                                                                         |
| 2 ✅   | identity AuthService                                                    | —                | (closed)                  | Shipped v0.2.2; continuation parked as PB-42                                                                                                           |
| 3 ✅   | runtime + compute + workspace sandbox + metering hooks                  | (foundation)     | **PB-7** (closed)         | 14 Stories `PB-50..PB-63` merged 2026-05-23. PB-64 GCP isolation smoke = carry-forward parallel lane.                                                  |
| **4**  | **backend MVP-0 substrate + e2e** (NO frontend, NO invoice tooling)     | (foundation)     | **PB-10**                 | 6 new services + cli + e2e separate repo + 4 existing service mods + sdk Phase 4 additions. 18 Story / 6 Wave (PB-72..PB-89). **NOT salable.**         |
| **5**  | **frontend (website + dashboard) + MVP-0 UI ship + founder-self alpha** | **MVP-0**        | (new Epic TBD)            | `paper-board/website` (paperboard.app marketing) + `paper-board/dashboard` (dashboard.paperboard.app app). MVP-0 launch milestone. Founder-self alpha. |
| **6**  | **Payment + multi-harness MCP + 3 new templates + invoice tooling**     | **MVP-1**        | **PB-11** (was Phase 5)   | Multi-provider Payment (Stripe + iyzico + PayTR + Param); compute exposed as MCP; 4 templates total; D11 invoice tooling here.                         |
| **7**  | production hardening + multi-user per org + Turkish + KVKK              | **MVP-2**        | **PB-12** (was Phase 6)   | mTLS + cosign + partitioning + hash chain; multi-user org; Turkish UI; KVKK documentation                                                              |
| **8**  | gateway centralize + RBAC                                               | **MVP-2**        | **PB-9 + PB-13 combined** | Centralize auth + routing + role-based access (was Phase 7 in ADR-0015)                                                                                |
| **9**  | source-available + self-host enterprise tier                            | **MVP-3**        | (new Epic needed)         | BSL/Elastic License repo public; Helm installer; license key; air-gap docs (was Phase 8 in ADR-0015)                                                   |
| **10** | paperclip-equivalent platform layer                                     | **v1.0 partial** | (new Epic)                | Org chart + ticketing + governance + agent reviews + scheduled routines + memory first-class (was Phase 9 in ADR-0015)                                 |
| **11** | marketplace + pre-built agent teams + agent-to-agent                    | **v1.0 full**    | (new Epic)                | SEO Team / Engineering Team / Personal Assistant templates + cross-org a2a (was Phase 10 in ADR-0015)                                                  |

### Phase 4 scope (Epic PB-10)

**New services bootstrap (6 + 1 cli + 1 e2e):**

| Repo                        | Schema          | Advisory lock | Responsibility                                                            |
| --------------------------- | --------------- | ------------- | ------------------------------------------------------------------------- |
| `paper-board/audit`         | `audit`         | 4             | gRPC ingest + query API; centralized event log; 90-day hot retention      |
| `paper-board/metering`      | `metering`      | 5             | Streaming hourly + cron daily/monthly + reconciler; invoice basis         |
| `paper-board/notifications` | `notifications` | 6             | Outbound notification gateway; Phase 4 = e-mail only; outbox cascade      |
| `paper-board/onboarding`    | `onboarding`    | 7             | Cross-service orchestrator + DLQ + status API                             |
| `paper-board/environments`  | `environments`  | 8             | Anthropic-style container config + non-sensitive env vars                 |
| `paper-board/vaults`        | `vaults`        | 9             | Anthropic-style encrypted credentials store; GCP KMS envelope             |
| `paper-board/cli`           | (none)          | —             | ops tooling (`dlq` + `rollup` + `reconcile`); invoice DEFERRED to Phase 6 |
| `paper-board/e2e`           | (none)          | —             | testcontainers flows/ + kind cluster/; neutral ownership (D13)            |

**Existing service modifications:**

- `agents`: session create takes `environment_id` + `vault_ids[]`; Anthropic API key fetched from vaults at session start; outbox emit; "Coding Assistant" template (D12)
- `identity`: outbox emit (user.created, login, logout, key-rotate); BYO key handling removed (moved to vaults per D8')
- `runtime`: outbox emit + environment.config consumer (NetworkPolicy, env_vars inject)
- `compute`: outbox emit + env_vars + vault credential injection; sandbox lifecycle metering emit

**SDK Phase 4 additions (tagged `paper-board/sdk` v0.2.0):**

- `sdk/outbox` (D6) — transactional outbox + Redis Streams publisher
- `sdk/inbox` (D9.2) — consumer-side dedupe (`processed_events`)
- `sdk/errors` (D9.3) — gRPC code → Retryable/Permanent classification
- `sdk/retry` (D9.4) — in-memory backoff + jitter

**Proto Phase 4 additions (tagged `paper-board/proto` v0.4.0):**

- 6 gRPC service contracts (audit, metering, notifications, onboarding, environments, vaults)
- Outbox event schemas (`proto/events/v1`)

### Phase 4 acceptance gate

**Automated e2e cross-service integration test suite green:**

- `e2e/flows/...` ≥ 7 golden path tests on every PR (PB-86/S15)
- `e2e/cluster/...` ≥ 3 cluster tests nightly + manual label trigger (PB-87/S16)
- `e2e/flows/realapi/...` ≥ 2 nightly real-API smoke tests (PB-88/S17)
- PB-64 GCP gVisor isolation smoke green (parallel lane carry-forward)

### Story breakdown — 18 Story / 6 Wave (D14)

PB-72..PB-89 under Epic PB-10; Wave dependency enforced via Blocks/BlockedBy critical-path edges.

| Wave | Stories      | Theme                                                                               |
| ---- | ------------ | ----------------------------------------------------------------------------------- |
| 1    | PB-72, PB-73 | sdk + proto foundations                                                             |
| 2    | PB-74..PB-78 | 5 new service bootstraps (audit, metering, notifications, environments, vaults)     |
| 3    | PB-79..PB-83 | onboarding bootstrap + 4 existing service mods (identity, agents, runtime, compute) |
| 4    | PB-84, PB-85 | cli bootstrap + e2e harness skeleton                                                |
| 5    | PB-86..PB-88 | e2e flows + cluster + nightly real-API smoke                                        |
| 6    | PB-89        | ADR-0016 ratify + PB-10 close                                                       |

### Anthropic Managed Agents alignment (D8')

- **Agent** = the agents service's agent table (model, system_prompt, tools, MCP, skills)
- **Environment** = environments service (container config, packages, networking, env vars)
- **Vault** = vaults service (encrypted credentials)
- **Session** = the agents service's session table + runtime tenant pod

Session create flow: client gRPC → agents → fetch agent + env + vaults → provision runtime pod with merged config → LLM calls use Anthropic key from vault.

Reference: https://platform.claude.com/docs/en/managed-agents/

## Consequences

- **CLAUDE.md updates:** Backend Services table count 10 → 12 (+environments +vaults); Supporting count 6 → 7 (+e2e); total repos 18 → 19. DB users list extended (audit_app, metering_app, notifications_app, onboarding_app, environments_app, vaults_app, billing_app). Advisory lock IDs extended (4-9). Phase 4 narrative + Implementation Strategy section updated; invoice tooling DEFERRED marker added.
- **D11 invoice tooling DEFERRED to Phase 6 billing.** `cli invoice` subtree removed from Phase 4 scope. When the Phase 6 billing service is opened, pricing config + PDF generation + invoice_number sequencing will be added. identity.organizations tax fields (tax_number, billing_address, country) are Phase 6 prerequisites.
- **Skills/MCP integration DEFERRED.** D12.6 arrives with Phase 6 multi-harness; Phase 4 sample agent template has Memory ON but no Skills/MCP.
- **Multi-language template registry (Turkish system prompt) DEFERRED to Phase 7+.** Phase 4 sample agent is English; Turkish UI + KVKK are added in Phase 7.
- **SSE-based onboarding progress DEFERRED to Phase 7+.** Phase 5 frontend `GET /v1/onboarding/status` ETag polling banner for MVP-0 launch; SSE is Phase 7+ polish.
- **`paper-board/e2e` added as a separate repo.** Neutral ownership pattern; symbol of the platform contract. Compatible with ADR-0007 repo topology (supporting layer); license MIT.
- **`.claude/jira-config.json` epic_keys remapping** required:
  - `phase_5` Epic key TBD (new frontend Epic — create after Wave 6)
  - `phase_6 = PB-11` (was Phase 5: Payment + multi-harness; was PB-11 in ADR-0015, scope preserved)
  - `phase_7 = PB-12` (was Phase 6: hardening + multi-user + Turkish + KVKK)
  - `phase_8 = PB-9 + PB-13` (was Phase 7: gateway + RBAC combined)
  - `phase_9` = new Epic (was Phase 8: source-available + self-host)
  - `phase_10` = new Epic (was Phase 9: paperclip-equivalent)
  - `phase_11` = new Epic (was Phase 10: marketplace + a2a)
- **Stale Epic names need renaming after Wave 6:** PB-8 ("Phase 4 — Memory + Artifacts"), PB-9 ("Phase 5 — Gateway"), PB-11 ("Phase 7 — Billing"), PB-12 ("Phase 8 — Full Hardening"), PB-13 ("Phase 9 — RBAC"). These carry ADR-0014-era names; rename is in the PB-89 (S18) closure scope.
- **PB-64 carry-forward** Phase 3 acceptance gate; Phase 4 parallel lane; gates 2nd-tenant onboarding (D2). ADR-0016 does not cover PB-64's GCP runner provisioning detail (PB-64 has its own content); Phase 4 brainstorm only clarifies the PB-64 dependency.
- **Phase 4 ETA:** 22-33 calendar days (founder-self solo). Closure target: **2026-06-25 — 2026-07-05**.
- **Phase 5 frontend** = MVP-0 launch milestone. Tech stack decision (Next.js / SvelteKit / Astro) will be made at the start of Phase 5; out of ADR-0016 scope.
- **Phase 4 end is NOT salable.** ADR-0015 had Phase 4 end as the salable target; ADR-0016 shifts this to end of Phase 5. Founder-self alpha (founder tests without paying) happens at end of Phase 5; first real customer is recommended at end of Phase 6 (when Payment automation is ready).

## Alternatives considered

- **(a) Keep ADR-0015 Phase 4 single-service `platform` bundled with MVP-0 launch + frontend.** Rejected: D4 + D5a + D8' decisions arrived as a single decision package; 6 separate services instead of one preserve single-responsibility; frontend deferral prioritizes cross-service integration and proves substrate soundness with the e2e suite.
- **(b) Phase 4 includes frontend; platform as a single service.** Rejected: D4 user redirect ("Phase 4 backend-only, Phase 5'de frontend'e başlarız. önce backend servislerin end to end çalıştığından emin olmak istiyorum") [user quote, kept in Turkish]. For the single-service alternative, D5a provides the "industry single-responsibility norm" argument and D8' Anthropic alignment provides a separate argument.
- **(c) Adopt Anthropic environment as `is_secret` flag on a single env table instead of a separate vaults service.** Rejected: D8' follows Anthropic's env/vault separation pattern; ACL granularity + KMS audit trail + cross-service consistency (compile-time enforcement via service boundary) are clearly superior to the `is_secret` flag approach.
- **(d) Keep invoice tooling in Phase 4 scope.** Rejected: D11 user redirect ("faturayı şimdilik öteleyelim, mvp'de olmayacak") [user quote, kept in Turkish]. MVP-0 = substrate only; invoicing arrives with Phase 6 Payment automation; ad-hoc SQL + spreadsheet manual founder-self bridges Phase 5-6.
- **(e) Single e2e suite (testcontainers or kind), inside `agent-manager` instead of `paper-board/e2e`.** Rejected: D13 Hybrid decision + separate-repo neutral-ownership pattern (so tests are not mistaken for agents-specific; symbol of the "platform contract"). Also, cluster/ kind tests require PB-64 parity, so the flows/ + cluster/ separation remains stable when the Phase 8 gateway is added.
- **(f) Implement Phase 4 as a single Story.** Rejected: D14 18 Story / 6 Wave breakdown conforms to the atomic + mergeable + demoable Story discipline (Phase 1/3 14-Story sweet-spot pattern + repo race mitigation single-service-single-Story).
- **(g) Amend ADR-0015 in place.** Rejected: ADR immutability convention. ADR-0015 stays as historical record; ADR-0016 amends its Phase 4 row + downstream phase numbering.

## References

- `tasks/2026-05-24-phase-4-mvp0-brainstorm-notes.md` — Brainstorm source (D1-D14 full record)
- `tasks/2026-05-21-mvp-roadmap-v2.md` — MVP definition + 10-phase roadmap detail
- ADR-0001 — Multi-repo microservices (extended by D5a + D8' + D13 with 8 new repos)
- ADR-0002 — Schema-per-service (extended with 6 new schemas)
- ADR-0003 — No cross-schema FK (cross-service consistency now via outbox + inbox patterns from D6 + D9.2)
- ADR-0005 — REST public + gRPC internal (extended with new service contracts)
- ADR-0006 — Vertical (tracer-bullet) implementation (still active; 18 Story / 6 Wave pattern applies)
- ADR-0014 — MVP-first sequencing (amended by ADR-0015, transitively by ADR-0016)
- ADR-0015 — MVP launch phase rebalance (amended by this ADR; Phase 4 row + downstream numbering supersedes)
- `.claude/jira-config.json` — Jira state delta (epic_keys remapping pending Wave 6 closure)
- CLAUDE.md — Backend Services table + Implementation Strategy + DB Rules sections updated to reflect ADR-0016
- Anthropic Managed Agents docs: https://platform.claude.com/docs/en/managed-agents/ (Environment + Vault separation reference model)
- PB-10 (Jira Epic) — Phase 4 backend MVP-0 substrate, 18 child Stories PB-72..PB-89
