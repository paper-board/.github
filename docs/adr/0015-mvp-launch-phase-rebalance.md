# 0015 — MVP launch phase rebalance (amends ADR-0014)

**Status:** accepted
**Date:** 2026-05-21
**Accepted at:** commit `40d21aa` (2026-05-21)
**Amends:** ADR-0014 (phase order; supersedes the table in ADR-0014 §Decision while keeping ADR-0014's "MVP-first" rationale)
**Scope:** system

## Context

ADR-0014 (2026-05-20) re-scoped phases to "MVP-first": runtime + compute Phase 3, billing Phase 8, marketplace Phase 10. That order assumed the standard "build infrastructure first, monetize last" SaaS pattern.

During the Phase 3 brainstorm session (2026-05-21, source: `tasks/2026-05-21-phase-3-brainstorm-notes.md`), three structural decisions invalidated the ADR-0014 phase order:

1. **Revenue model decided** (D14): paper-board's value capture is **compute/runtime markup**, not LLM-token markup. Customer brings their own Anthropic API key (BYO key, M1 model) and pays Anthropic directly for tokens. paper-board bills the customer for compute pod-seconds, tool-call counts, and workspace-minutes.
2. **Phase ordering consequence** (D17): Because billing IS the value-capture mechanism, billing cannot be Phase 8. Metering must be Phase 3 (Day 1, otherwise retroactive measurement is impossible); billing engine must be earlier in the cycle (Phase 5) to enable real cash flow before the 7 phases conclude.
3. **Concrete MVP-0 scope agreed** (D19/D20): 8 hayati özellik defined; satılabilir; lives at end of Phase 4 (not at the end of all 10 phases).

Additional decisions that shape the new order:

- **D15** — eyes-open competitive positioning vs Modal / LangGraph Cloud / AWS Bedrock Agents / Anthropic Claude Cowork / E2B / Cloudflare Workers AI
- **D16** — adopted moat set: (1) MCP-server harness-agnostic compute backend, (2) self-host enterprise tier
- **D11** — strategy S2 (full-stack platform; competing with paperclip + cloud-first + Claude-optimized)
- **D12** — source-available license (specific TBD as `Q-license.1`)
- **D23** — Payment is generic (Stripe / iyzico / PayTR / Param multi-provider abstraction), not Stripe-locked

## Decision

New phase ordering replaces the table in ADR-0014 §Decision:

| Phase  | Service / Theme                                            | MVP tier         | Existing Epic                                       | Notes                                                                                                                                                               |
| ------ | ---------------------------------------------------------- | ---------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0 ✅ | sdk + proto + infra v0.1.0                                 | —                | (closed)                                            | Shipped 2026-05-06 → 2026-05-08                                                                                                                                     |
| 1.1 ✅ | agents minimal runtime                                     | —                | (closed)                                            | Shipped v0.2.3 with early hardening (C2 / C4-A / C4-B / C5 / M6 / OCI)                                                                                              |
| 2 ✅   | identity AuthService                                       | —                | (closed)                                            | Shipped v0.2.2; continuation parked as PB-42                                                                                                                        |
| **3**  | runtime + compute + workspace sandbox + **metering hooks** | (foundation)     | **PB-7**                                            | Multi-tenant gVisor sandbox + per-session workspace + usage events emit. Day 1 metering is non-negotiable                                                           |
| **4**  | platform + **MVP-0 launch**                                | **MVP-0**        | **PB-10**                                           | Audit + onboarding + outbox + dashboard + 1 agent template + BYO API key flow + manuel e-mail fatura. **Satılabilir tek-müşteri ürün**                              |
| **5**  | **Payment + multi-harness MCP + 3 yeni template**          | **MVP-1**        | **PB-11** (was Phase 8 billing)                     | Multi-provider Payment abstraction (Stripe + iyzico + PayTR + Param); compute exposed as MCP server (claude-code + pi + Cursor + Cline kullanır); 4 toplam template |
| **6**  | production hardening + multi-user per org + Türkçe + KVKK  | **MVP-2**        | **PB-12**                                           | mTLS + cosign + partitioning + hash chain; multi-user org; Türkçe UI; KVKK dokümantasyon                                                                            |
| **7**  | gateway centralize + RBAC                                  | **MVP-2**        | **PB-9 + PB-13 birleşik**                           | Centralize auth + routing + role-based access                                                                                                                       |
| **8**  | **source-available + self-host enterprise tier**           | **MVP-3**        | (new Epic needed)                                   | BSL/Elastic License repo public; Helm installer; license key; air-gap docs                                                                                          |
| **9**  | paperclip-equivalent platform katmanı                      | **v1.0 partial** | (new Epic — büyük; muhtemelen 9a/9b/9c alt-bölünür) | Org chart + ticketing + governance + agent reviews + scheduled routines + memory first-class                                                                        |
| **10** | marketplace + pre-built agent teams + agent-to-agent       | **v1.0 full**    | (new Epic)                                          | SEO Team / Engineering Team / Personal Assistant şablonları + cross-org agent-to-agent protocol                                                                     |

**Identity continuation (PB-42)** remains deferred indefinitely. ADR-0014's "Phase 5 (non-blocking)" identity continuation slot is removed from the active roadmap entirely. PB-42 retains its 5 child Stories (PB-45..PB-49) but no fixVersion or sprint scheduling.

**Tracer-bullet philosophy from ADR-0006 retained.** Vertical-slice-per-service implementation pattern unchanged.

## Consequences

- **Metering hooks are Phase 3 scope**, not deferred. compute servisi Day 1'den usage event emit eder (per pod-second, per tool-call, per workspace-minute, per network egress) to an outbox interface; Phase 4 platform consumes the outbox; Phase 5 billing engine reads from platform's aggregated counters.
- **Billing engine moved from Phase 8 to Phase 5.** This pulls the cash-flow milestone forward by 3 phases. Payment provider abstraction is multi-provider from Day 1 (not Stripe-locked) — see D23.
- **MVP-0 satılabilir milestone is now Phase 4 sonu**, not "after all 10 phases". Customer-facing dashboard + 1 agent template + BYO API key + manuel e-mail fatura ile satılabilir.
- **Phase 8 (was billing) → source-available + self-host enterprise tier.** This shifts the second sales gate (enterprise on-prem) from "ileride bir noktada" to a defined milestone.
- **Phase 9 scope is the biggest of the roadmap** (paperclip-equivalent platform). Likely needs further sub-division (9a/9b/9c) when Phase 8 brainstorm starts.
- **gateway + RBAC merged into Phase 7.** ADR-0014's Phase 9 (RBAC full) absorbed into Phase 7 because RBAC without gateway centralization is incoherent.
- **CLAUDE.md Backend Services table** ve Implementation Strategy section ADR-0015 onaylanınca güncellenecek (yeni Phase column değerleri + Implementation Strategy phase listesi).
- **`.claude/jira-config.json` `epic_keys` remapping** gerekli:
  - `phase_3 = PB-7` (R+C + metering, unchanged Epic but scope-widened)
  - `phase_4 = PB-10` (platform + MVP-0 launch, scope-widened)
  - `phase_5 = PB-11` (billing → Payment + multi-harness MCP; eski Phase 8'den buraya çekildi)
  - `phase_6 = PB-12` (hardening + multi-user + Türkçe + KVKK)
  - `phase_7 = PB-9 + PB-13` (gateway + RBAC birleşik; iki Epic'i tek phase'e bağlamak yeni mapping)
  - `phase_8 = new Epic` (source-available + self-host) — Epic create gerekli
  - `phase_9 = new Epic` (paperclip-equivalent) — Epic create gerekli
  - `phase_10 = new Epic` (marketplace + agent teams) — Epic create gerekli
  - PB-42 (identity continuation) `epic_keys` map'inden tamamen çıkarıldı; PB-42 Epic kendisi deferred Backlog tag'iyle korunur ama active phase mapping yok
- **fixVersions** on PB-7..PB-13 still describe pre-ADR-0014 ladder titles in some cases. ADR-0015 ile birlikte rename + reassign post-execute corrective commit'e bırakılır (ADR-0014 §Consequences'ta da aynı pattern).
- **paperclip-equivalent Phase 9 = stratejik risk.** paperclip 41-section README'lik özellik kümesini katlamak gerekiyor; bu phase'in 14-20 hafta süreceği tahmin edildi (`tasks/2026-05-21-phase-3-brainstorm-notes.md` Grill #4). Phase 8 brainstorm'unda 9a/9b/9c sub-phase split'i değerlendirilmeli.
- **Phase 3 brainstorm** Q2.4 / Q2.5 / Q3 / Q4 / Q5 / Q6 sorularını ADR-0015 hedefine göre dar tutmalı (MVP-0 launch'ın altyapısı; extra özellik yok). Bkz. `tasks/2026-05-21-mvp-roadmap-v2.md` §7.

## Alternatives considered

- **(a) Keep ADR-0014 phase order, add metering as separate side-task.** Rejected: metering can't be a side-task; compute service architecture must emit events from Day 1 or retroactive measurement is impossible (lost revenue + customer billing disputes).
- **(b) Push billing to Phase 4 (one earlier than this ADR proposes).** Rejected: Phase 4 already absorbs MVP-0 launch (dashboard + template + BYO key); piling Stripe automation on top makes Phase 4 too wide. Manual e-mail fatura at Phase 4 is acceptable for first 3-5 customers; Phase 5 automates.
- **(c) Phase 8 stays as billing, source-available pushed to Phase 9 or beyond.** Rejected: source-available + self-host enterprise tier is **moat #2** per D16; it's not optional polish, it's a sales gate (on-prem enterprise customers).
- **(d) Drop Phase 9 (paperclip-equivalent) entirely.** Rejected: S2 strategy (D11) explicitly competes with paperclip; without org chart / ticketing / governance the product is not paperclip-equivalent and can't capture S2 positioning.
- **(e) Amend ADR-0014 in place.** Rejected: ADR immutability convention. ADR-0014 stays as historical record; ADR-0015 amends its phase table.

## References

- `tasks/2026-05-21-phase-3-brainstorm-notes.md` — Brainstorm source (decisions D14, D15, D16, D17, D19, D20, D23 etc.)
- `tasks/2026-05-21-mvp-roadmap-v2.md` — MVP definition + 10-phase roadmap detail (this ADR's design source)
- `tasks/2026-05-20-phase-c-rescope-design.md` — ADR-0014's source design (Phase C re-scope)
- ADR-0006 — vertical (tracer-bullet) implementation (still active; only phase order is reset)
- ADR-0009 — product-first sequencing (superseded by ADR-0014, transitively affected by ADR-0015)
- ADR-0014 — MVP-first sequencing (amended by this ADR; phase table here supersedes ADR-0014's table)
- `.claude/jira-config.json` `phase_c_rescope` block — Jira state delta from ADR-0014 (epic_remapping baseline; ADR-0015 adds new remapping on top)
- Confluence: `PB-43` glossary v0 (page id `1900546`), `PB-44` track plan v0 stub (page id `1933313`)
- CLAUDE.md — Backend Services table + Implementation Strategy section (updated when ADR-0015 lands in same commit, per ADR-0014 precedent)
