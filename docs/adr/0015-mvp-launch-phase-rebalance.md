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
3. **Concrete MVP-0 scope agreed** (D19/D20): 8 critical features defined; salable; lives at end of Phase 4 (not at the end of all 10 phases).

Additional decisions that shape the new order:

- **D15** — eyes-open competitive positioning vs Modal / LangGraph Cloud / AWS Bedrock Agents / Anthropic Claude Cowork / E2B / Cloudflare Workers AI
- **D16** — adopted moat set: (1) MCP-server harness-agnostic compute backend, (2) self-host enterprise tier
- **D11** — strategy S2 (full-stack platform; competing with paperclip + cloud-first + Claude-optimized)
- **D12** — source-available license (specific TBD as `Q-license.1`)
- **D23** — Payment is generic (Stripe / iyzico / PayTR / Param multi-provider abstraction), not Stripe-locked

## Decision

New phase ordering replaces the table in ADR-0014 §Decision:

| Phase  | Service / Theme                                            | MVP tier         | Existing Epic                             | Notes                                                                                                                                                      |
| ------ | ---------------------------------------------------------- | ---------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0 ✅ | sdk + proto + infra v0.1.0                                 | —                | (closed)                                  | Shipped 2026-05-06 → 2026-05-08                                                                                                                            |
| 1.1 ✅ | agents minimal runtime                                     | —                | (closed)                                  | Shipped v0.2.3 with early hardening (C2 / C4-A / C4-B / C5 / M6 / OCI)                                                                                     |
| 2 ✅   | identity AuthService                                       | —                | (closed)                                  | Shipped v0.2.2; continuation parked as PB-42                                                                                                               |
| **3**  | runtime + compute + workspace sandbox + **metering hooks** | (foundation)     | **PB-7**                                  | Multi-tenant gVisor sandbox + per-session workspace + usage events emit. Day 1 metering is non-negotiable                                                  |
| **4**  | platform + **MVP-0 launch**                                | **MVP-0**        | **PB-10**                                 | Audit + onboarding + outbox + dashboard + 1 agent template + BYO API key flow + manual e-mail invoice. **Salable single-customer product**                 |
| **5**  | **Payment + multi-harness MCP + 3 new templates**          | **MVP-1**        | **PB-11** (was Phase 8 billing)           | Multi-provider Payment abstraction (Stripe + iyzico + PayTR + Param); compute exposed as MCP server (claude-code + pi + Cursor + Cline); 4 templates total |
| **6**  | production hardening + multi-user per org + Turkish + KVKK | **MVP-2**        | **PB-12**                                 | mTLS + cosign + partitioning + hash chain; multi-user org; Turkish UI; KVKK documentation                                                                  |
| **7**  | gateway centralize + RBAC                                  | **MVP-2**        | **PB-9 + PB-13 combined**                 | Centralize auth + routing + role-based access                                                                                                              |
| **8**  | **source-available + self-host enterprise tier**           | **MVP-3**        | (new Epic needed)                         | BSL/Elastic License repo public; Helm installer; license key; air-gap docs                                                                                 |
| **9**  | paperclip-equivalent platform layer                        | **v1.0 partial** | (new Epic — large; likely 9a/9b/9c split) | Org chart + ticketing + governance + agent reviews + scheduled routines + memory first-class                                                               |
| **10** | marketplace + pre-built agent teams + agent-to-agent       | **v1.0 full**    | (new Epic)                                | SEO Team / Engineering Team / Personal Assistant templates + cross-org agent-to-agent protocol                                                             |

**Identity continuation (PB-42)** remains deferred indefinitely. ADR-0014's "Phase 5 (non-blocking)" identity continuation slot is removed from the active roadmap entirely. PB-42 retains its 5 child Stories (PB-45..PB-49) but no fixVersion or sprint scheduling.

**Tracer-bullet philosophy from ADR-0006 retained.** Vertical-slice-per-service implementation pattern unchanged.

## Consequences

- **Metering hooks are Phase 3 scope**, not deferred. The compute service emits usage events from Day 1 (per pod-second, per tool-call, per workspace-minute, per network egress) to an outbox interface; Phase 4 platform consumes the outbox; Phase 5 billing engine reads from platform's aggregated counters.
- **Billing engine moved from Phase 8 to Phase 5.** This pulls the cash-flow milestone forward by 3 phases. Payment provider abstraction is multi-provider from Day 1 (not Stripe-locked) — see D23.
- **MVP-0 salable milestone is now end of Phase 4**, not "after all 10 phases". Customer-facing dashboard + 1 agent template + BYO API key + manual e-mail invoice = salable.
- **Phase 8 (was billing) → source-available + self-host enterprise tier.** This shifts the second sales gate (enterprise on-prem) from "at some future point" to a defined milestone.
- **Phase 9 scope is the biggest of the roadmap** (paperclip-equivalent platform). Likely needs further sub-division (9a/9b/9c) when Phase 8 brainstorm starts.
- **gateway + RBAC merged into Phase 7.** ADR-0014's Phase 9 (RBAC full) absorbed into Phase 7 because RBAC without gateway centralization is incoherent.
- **CLAUDE.md Backend Services table** and Implementation Strategy section will be updated when ADR-0015 is ratified (new Phase column values + Implementation Strategy phase list).
- **`.claude/jira-config.json` `epic_keys` remapping** required:
  - `phase_3 = PB-7` (R+C + metering, unchanged Epic but scope-widened)
  - `phase_4 = PB-10` (platform + MVP-0 launch, scope-widened)
  - `phase_5 = PB-11` (billing → Payment + multi-harness MCP; pulled forward from old Phase 8)
  - `phase_6 = PB-12` (hardening + multi-user + Turkish + KVKK)
  - `phase_7 = PB-9 + PB-13` (gateway + RBAC combined; linking two Epics to one phase is a new mapping)
  - `phase_8 = new Epic` (source-available + self-host) — Epic create required
  - `phase_9 = new Epic` (paperclip-equivalent) — Epic create required
  - `phase_10 = new Epic` (marketplace + agent teams) — Epic create required
  - PB-42 (identity continuation) removed from `epic_keys` map entirely; PB-42 Epic itself is retained with deferred Backlog tag but has no active phase mapping
- **fixVersions** on PB-7..PB-13 still describe pre-ADR-0014 ladder titles in some cases. Rename + reassign will be left to a post-execute corrective commit alongside ADR-0015 ratification (same pattern as ADR-0014 §Consequences).
- **paperclip-equivalent Phase 9 = strategic risk.** Folding in the full paperclip 41-section README feature set is required; this phase was estimated at 14-20 weeks (`tasks/2026-05-21-phase-3-brainstorm-notes.md` Grill #4). A 9a/9b/9c sub-phase split should be evaluated during the Phase 8 brainstorm.
- **Phase 3 brainstorm** questions Q2.4 / Q2.5 / Q3 / Q4 / Q5 / Q6 should be kept narrow relative to the ADR-0015 target (MVP-0 launch infrastructure; no extra features). See `tasks/2026-05-21-mvp-roadmap-v2.md` §7.

## Alternatives considered

- **(a) Keep ADR-0014 phase order, add metering as separate side-task.** Rejected: metering can't be a side-task; compute service architecture must emit events from Day 1 or retroactive measurement is impossible (lost revenue + customer billing disputes).
- **(b) Push billing to Phase 4 (one earlier than this ADR proposes).** Rejected: Phase 4 already absorbs MVP-0 launch (dashboard + template + BYO key); piling Stripe automation on top makes Phase 4 too wide. Manual e-mail invoice at Phase 4 is acceptable for first 3-5 customers; Phase 5 automates.
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
