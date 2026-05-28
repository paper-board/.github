# 0016 — Phase 4 backend MVP-0 substrate re-sequence (amends ADR-0015)

**Status:** accepted
**Date:** 2026-05-25
**Amends:** ADR-0015 (phase rebalance; supersedes ADR-0015's Phase 4 scope definition and downstream phase numbering)
**Scope:** system

## Context

ADR-0015 (2026-05-21) established Phase 4 = "platform + MVP-0 launch" with audit + onboarding + outbox + dashboard + 1 agent template + BYO API key flow + manual e-mail fatura. The phase was framed as MVP-0 satılabilir milestone in a single Epic (PB-10).

During the Phase 4 brainstorm session (2026-05-24 — 2026-05-25, source: `tasks/2026-05-24-phase-4-mvp0-brainstorm-notes.md`), 14 ana karar (D1-D14) invalidated the ADR-0015 Phase 4 scope in three ways:

1. **D4 — Backend-only Phase 4, frontend moved to Phase 5.** The user explicitly chose to defer frontend so backend cross-service integration could be proven end-to-end first; Phase 4 = "substrate (NOT salable)", Phase 5 = "frontend + MVP-0 launch".
2. **D5a — platform service split into 4 single-responsibility services** (audit + metering + notifications + onboarding) instead of one bundled platform service. Industry single-responsibility norm + Phase 7+ HA/scale separation alignment.
3. **D8' — Anthropic Managed Agents alignment.** Adopted Anthropic's Agent + Environment + Session + Vault separation. Two additional services introduced: `environments` (container config + non-sensitive env vars) and `vaults` (encrypted credentials, GCP KMS envelope). BYO Anthropic key now lives in vaults, not identity.

Additional decisions that shape the scope:

- **D6** — outbox pattern + Redis Streams + at-least-once delivery; sdk/outbox + sdk/inbox standardization
- **D9** — onboarding wizard pipeline: hybrid sync core + async email (D9.1); idempotency A+B (D9.2); DLQ + forward-only retry (D9.3); two-layer retry semantics (D9.4); polled status banner UX (D9.5)
- **D10** — metering aggregation: streaming hourly UPSERT + cron daily/monthly + daily reconciler (shadow invoice pattern)
- **D11** — manual invoice tooling DEFERRED to Phase 6 billing (`cli invoice` subtree removed from Phase 4 scope)
- **D12** — Coding Assistant template detail: claude-sonnet-latest + 5 tools (bash + str_replace_editor + view + web_search + web_fetch) + paperboard-branded ~150 word prompt + Python+node coding-baseline env + empty default vault + memory ON
- **D13** — e2e hybrid: testcontainers flows/ + kind cluster/ + `paper-board/e2e` ayrı repo (neutral ownership); LLM mock as default + nightly real Anthropic API smoke
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
| **4**  | **backend MVP-0 substrate + e2e** (NO frontend, NO invoice tooling)     | (foundation)     | **PB-10**                 | 6 new services + cli + e2e ayrı repo + 4 mevcut servis mod + sdk Phase 4 additions. 18 Story / 6 Wave (PB-72..PB-89). **NOT salable.**                 |
| **5**  | **frontend (website + dashboard) + MVP-0 UI ship + founder-self alpha** | **MVP-0**        | (new Epic TBD)            | `paper-board/website` (paperboard.app marketing) + `paper-board/dashboard` (dashboard.paperboard.app app). MVP-0 launch milestone. Founder-self alpha. |
| **6**  | **Payment + multi-harness MCP + 3 yeni template + invoice tooling**     | **MVP-1**        | **PB-11** (was Phase 5)   | Multi-provider Payment (Stripe + iyzico + PayTR + Param); compute exposed as MCP; 4 toplam template; D11 invoice tooling burada.                       |
| **7**  | production hardening + multi-user per org + Türkçe + KVKK               | **MVP-2**        | **PB-12** (was Phase 6)   | mTLS + cosign + partitioning + hash chain; multi-user org; Türkçe UI; KVKK dokümantasyon                                                               |
| **8**  | gateway centralize + RBAC                                               | **MVP-2**        | **PB-9 + PB-13 birleşik** | Centralize auth + routing + role-based access (was Phase 7 in ADR-0015)                                                                                |
| **9**  | source-available + self-host enterprise tier                            | **MVP-3**        | (new Epic needed)         | BSL/Elastic License repo public; Helm installer; license key; air-gap docs (was Phase 8 in ADR-0015)                                                   |
| **10** | paperclip-equivalent platform katmanı                                   | **v1.0 partial** | (new Epic)                | Org chart + ticketing + governance + agent reviews + scheduled routines + memory first-class (was Phase 9 in ADR-0015)                                 |
| **11** | marketplace + pre-built agent teams + agent-to-agent                    | **v1.0 full**    | (new Epic)                | SEO Team / Engineering Team / Personal Assistant şablonları + cross-org a2a (was Phase 10 in ADR-0015)                                                 |

### Phase 4 scope (Epic PB-10)

**New services bootstrap (6 + 1 cli + 1 e2e):**

| Repo                        | Schema          | Advisory lock <sup>†</sup> | Sorumluluk                                                                |
| --------------------------- | --------------- | -------------------------- | ------------------------------------------------------------------------- |
| `paper-board/audit`         | `audit`         | 4                          | gRPC ingest + query API; centralized event log; 90-day hot retention      |
| `paper-board/metering`      | `metering`      | 5                          | Streaming hourly + cron daily/monthly + reconciler; invoice basis         |
| `paper-board/notifications` | `notifications` | 6                          | Outbound notification gateway; Phase 4 = e-mail only; outbox cascade      |
| `paper-board/onboarding`    | `onboarding`    | 7                          | Cross-service orchestrator + DLQ + status API                             |
| `paper-board/environments`  | `environments`  | 8                          | Anthropic-style container config + non-sensitive env vars                 |
| `paper-board/vaults`        | `vaults`        | 9                          | Anthropic-style encrypted credentials store; GCP KMS envelope             |
| `paper-board/cli`           | (none)          | —                          | ops tooling (`dlq` + `rollup` + `reconcile`); invoice DEFERRED to Phase 6 |
| `paper-board/e2e`           | (none)          | —                          | testcontainers flows/ + kind cluster/; neutral ownership (D13)            |

<sup>†</sup> **Historical note:** the Advisory-lock column values shown here (4–9) reflect the manual numbering planned at ADR-0016 authoring time. After this ADR was drafted, verification of `paper-board/sdk/migrator/migrator.go` confirmed that locks are auto-derived via `CRC32(database+schema)` (golang-migrate pgx/v5 driver) — schema-per-service guarantees collision isolation, so the manual IDs above are not used at runtime. The numbers are retained in this ADR row solely as a record of the original planning intent. The deployed [Service map](../src/content/docs/architecture/service-map.md) drops the column.

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

**Otomatik e2e cross-service integration test suite green:**

- `e2e/flows/...` ≥ 7 golden path tests on every PR (PB-86/S15)
- `e2e/cluster/...` ≥ 3 cluster tests nightly + manuel label trigger (PB-87/S16)
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

- **Agent** = agents servisinin agent tablosu (model, system_prompt, tools, MCP, skills)
- **Environment** = environments servisi (container config, packages, networking, env vars)
- **Vault** = vaults servisi (encrypted credentials)
- **Session** = agents servisinin session tablosu + runtime tenant pod

Session create flow: client gRPC → agents → fetch agent + env + vaults → provision runtime pod with merged config → LLM calls use Anthropic key from vault.

Reference: https://platform.claude.com/docs/en/managed-agents/

## Consequences

- **CLAUDE.md updates:** Backend Services table count 10 → 12 (+environments +vaults); Supporting count 6 → 7 (+e2e); total repos 18 → 19. DB users list extended (audit_app, metering_app, notifications_app, onboarding_app, environments_app, vaults_app, billing_app). Advisory lock IDs extended (4-9). Phase 4 narrative + Implementation Strategy section updated; invoice tooling DEFERRED marker added.
- **D11 invoice tooling DEFERRED to Phase 6 billing.** `cli invoice` subtree removed from Phase 4 scope. Phase 6 billing servisi açılırken pricing config + PDF generation + invoice_number sequencing eklenir. identity.organizations tax fields (tax_number, billing_address, country) Phase 6 prerequisite.
- **Skills/MCP integration DEFERRED.** D12.6 Phase 6 multi-harness ile birlikte gelir; Phase 4 sample agent template'inde Memory ON ama Skills/MCP yok.
- **Multi-language template registry (Turkish system prompt) DEFERRED to Phase 7+.** Phase 4 sample agent İngilizce; Türkçe UI + KVKK Phase 7'de eklenir.
- **SSE-based onboarding progress DEFERRED to Phase 7+.** Phase 5 frontend `GET /v1/onboarding/status` ETag polling banner ile MVP-0 launch; SSE Phase 7+ polish.
- **`paper-board/e2e` ayrı repo eklendi.** Neutral ownership pattern; platform sözleşmesi simgesi. ADR-0007 repo topology'ye uyumlu (supporting layer); license MIT.
- **`.claude/jira-config.json` epic_keys remapping** gerekli:
  - `phase_5` Epic key TBD (new frontend Epic — Wave 6 sonrasında create)
  - `phase_6 = PB-11` (was Phase 5: Payment + multi-harness; ADR-0015'te PB-11 idi, scope korunur)
  - `phase_7 = PB-12` (was Phase 6: hardening + multi-user + Türkçe + KVKK)
  - `phase_8 = PB-9 + PB-13` (was Phase 7: gateway + RBAC birleşik)
  - `phase_9` = new Epic (was Phase 8: source-available + self-host)
  - `phase_10` = new Epic (was Phase 9: paperclip-equivalent)
  - `phase_11` = new Epic (was Phase 10: marketplace + a2a)
- **Stale Epic names need renaming after Wave 6:** PB-8 ("Phase 4 — Memory + Artifacts"), PB-9 ("Phase 5 — Gateway"), PB-11 ("Phase 7 — Billing"), PB-12 ("Phase 8 — Full Hardening"), PB-13 ("Phase 9 — RBAC"). Bunlar ADR-0014 era isimleri taşıyor; rename PB-89 (S18) closure scope'unda.
- **PB-64 carry-forward** Phase 3 acceptance gate; Phase 4 paralel lane; gates 2nd-tenant onboarding (D2). ADR-0016 PB-64'ün GCP runner provisioning detayını kapsamaz (PB-64 kendi içeriği var); Phase 4 brainstorm sadece PB-64 dependency'sini açıklar.
- **Phase 4 ETA:** 22-33 calendar days (founder-self solo). Closure target: **2026-06-25 — 2026-07-05**.
- **Phase 5 frontend** = MVP-0 launch milestone. Tech stack decision (Next.js / SvelteKit / Astro) Phase 5'in başında yapılır; ADR-0016 scope dışı.
- **Phase 4 sonu satılabilir DEĞİL.** ADR-0015'te Phase 4 sonu satılabilir hedefiydi; ADR-0016 bunu Phase 5 sonuna kaydırır. Founder-self alpha (founder kendi para ödemeden test eder) Phase 5 sonunda gerçekleşir; ilk gerçek customer Phase 6 sonu (Payment automation hazır) önerilir.

## Alternatives considered

- **(a) Keep ADR-0015 Phase 4 single-service `platform` bundled with MVP-0 launch + frontend.** Rejected: D4 + D5a + D8' kararları tek karar paketinde geldi; tek servis yerine 6 ayrı servis single-responsibility'i koruyor; frontend deferral cross-service integration'ı önceleyerek e2e suite ile substrate sağlamlığını kanıtlar.
- **(b) Phase 4'te frontend de var; platform tek servis.** Rejected: D4 user redirect ("Phase 4 backend-only, Phase 5'de frontend'e başlarız. önce backend servislerin end to end çalıştığından emin olmak istiyorum"). Tek servis için D5a'da "industry single-responsibility norm" + D8' Anthropic alignment iki ayrı argüman var.
- **(c) Adopt Anthropic environment as `is_secret` flag on tek env tablosu yerine ayrı vaults servisi.** Rejected: D8' Anthropic'in env/vault separation pattern'ini takip eder; ACL granularity + KMS audit trail + cross-service consistency (compile-time enforcement via service boundary) `is_secret` flag yaklaşımından net üstün.
- **(d) Invoice tooling Phase 4 kapsamında kalsın.** Rejected: D11 sonrası user redirect ("faturayı şimdilik öteleyelim, mvp'de olmayacak"). MVP-0 = sadece substrate; faturalama Phase 6 Payment automation ile birlikte gelir; Phase 5-6 köprüsünde ad-hoc SQL + spreadsheet manual founder-self.
- **(e) Tek e2e suite (testcontainers veya kind), `paper-board/e2e` yerine `agent-manager` içinde.** Rejected: D13 Hybrid kararı + ayrı repo neutral-ownership pattern (testler agents-özel sanılmasın; "platform sözleşmesi" simgesi). Ayrıca cluster/ kind testleri PB-64 paritesi gerektirdiğinden flows/ + cluster/ separation Phase 8 gateway eklendiğinde de stable kalır.
- **(f) Tek Story olarak Phase 4'ü implemente et.** Rejected: D14 18 Story / 6 Wave breakdown atomic + mergeable + demoable Story disiplinine uyar (Phase 1/3 14 Story sweet spot pattern + repo race mitigation single-service-single-Story).
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
