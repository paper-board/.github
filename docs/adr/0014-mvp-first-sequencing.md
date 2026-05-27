# 0014 — MVP-first sequencing (supersedes ADR-0009)

**Status:** accepted
**Date:** 2026-05-20
**Supersedes:** ADR-0009 (product-first sequencing — phase order only; tracer-bullet philosophy from ADR-0006 retained)
**Scope:** system

## Context

ADR-0009 set a product-first phase order in 2026-04-30: agents → identity → billing → platform → hardening → runtime+compute → gateway → RBAC → marketplace. The plan was followed through 2026-05-17 for Phase 1.0 (sdk + proto + infra v0.1.0), Phase 1.1 (agents v0.2.3), and Phase 2 (identity v0.2.2 + early hardening: refresh tokens, idempotency middleware, NetworkPolicy egress, bootstrap Helm Job, JWT key rotation, OCI Helm chart publish).

Two divergences from ADR-0009 occurred without being captured in any decision record until now:

1. **Early hardening on `agents` + `identity`.** Items nominally belonging to Phase 5 (production hardening) shipped during Phase 2 because both services were demoable / live and required production-shaped concerns immediately. The PR-level `C / M / N / T` track marker system (`C2 / C3 / C4-A / C4-B / C5 / C6`, `M6`, `n11 / n13`, `T14`) coordinated this work in PR titles, but no master plan document exists for these tracks; user will dictate v0 in `PB-44` Confluence page.
2. **Product priority shift.** User priority moved from "monetization-soon" to "MVP-first": a demoable multi-tenant agent with sandbox execution must precede billing/Stripe wiring. Identity continuation (Org / Key / MFA / Idempotency public services) is deferred indefinitely under `PB-42`.

`tasks/2026-05-20-actual-state-survey.md` (Path D investigation) verified the actual GitHub state (`identity v0.2.2`, `agents v0.2.3`, `sdk v0.4.0`, `proto v0.2.1`) and confirmed that Phase 0–2 are shipped on `paper-board` main branches. CLAUDE.md Backend Services table ✅ markers and PR-track labels are the ground-truth indicators.

## Decision

New phase ordering (replaces the table in ADR-0009 §Decision):

| Phase                      | Service                                  | Existing Epic | Notes                                                                                    |
| -------------------------- | ---------------------------------------- | ------------- | ---------------------------------------------------------------------------------------- |
| 1.0 ✅                     | sdk + proto + infra v0.1.0               | (closed)      | Shipped 2026-05-06 → 2026-05-08                                                          |
| 1.1 ✅                     | agents minimal runtime                   | (closed)      | Shipped v0.2.3 with early hardening (C2 / C4-A / C4-B / C5 / M6 / OCI)                   |
| 2 ✅                       | identity AuthService                     | (closed)      | Shipped v0.2.2; continuation parked as PB-42                                             |
| **3 (new)**                | runtime + compute                        | **PB-7**      | Multi-tenant data plane + gVisor sandbox MVP. First MVP focus.                           |
| **4 (new)**                | platform                                 | **PB-10**     | Audit + onboarding + notifications + outbox + exports                                    |
| **5 (new) — non-blocking** | identity continuation — deferred backlog | **PB-42**     | Org / Key / MFA / Idempotency public services. Does **not** gate Phase 6.                |
| **6 (new)**                | production hardening cluster-wide        | **PB-12**     | mTLS + cosign + partitioning + DNS + hash chain; absorbs PB-9 light-hardening slice      |
| **7 (new)**                | gateway                                  | **PB-9**      | Centralize auth + routing; gateway slice narrowed from PB-9 original mix                 |
| **8 (new)**                | billing                                  | **PB-11**     | Subscriptions, pricing, metering, Stripe, marketplace catalog. Deferred under MVP-first. |
| **9 (new)**                | RBAC full                                | **PB-13**     |                                                                                          |
| **10 (new)**               | marketplace + advanced features          | (no Epic yet) | Create when prioritized                                                                  |

Identity continuation under `PB-42` stays deferred indefinitely; activation requires explicit user direction (chat statement or Jira comment containing "activate" or equivalent). No time-based trigger. Phase 6 hardening big-bang does **not** depend on Phase 5 (new) completion.

Tracer-bullet philosophy from ADR-0006 retained. Phase order is reset; vertical-slice-per-service implementation pattern unchanged.

## Consequences

- Stripe wiring deferred ~5 phases from ADR-0009 (was Phase 3; now Phase 8).
- `paper-board/runtime` and `paper-board/compute` repos require new bootstrap (no existing scaffold; bootstraps follow `paper-board/service-template`).
- Identity continuation backlog (`PB-42` + child Stories `PB-45..PB-49`) holds 5 Stories indefinitely; no fixVersion / sprint scheduling.
- CLAUDE.md Backend Services table updated (Phase column re-numbered for runtime / compute / billing); Implementation Strategy section cites ADR-0014.
- `epic_keys` remapping in `.claude/jira-config.json`: `phase_3 = PB-7` (R+C, unchanged), `phase_4 = PB-10` (platform, widened from Audit+Notifications), `phase_5 = PB-42` (NEW), `phase_6 = PB-12` (hardening big-bang, absorbs PB-9 light-HW), `phase_7 = PB-9` (gateway slice), `phase_8 = PB-11` (billing), `phase_9 = PB-13` (RBAC). PB-8 (Memory+Artifacts) removed from active map pending Phase 4 platform brainstorm disposition.
- Existing PR-level `C / M / N / T` track marker system remains the implementation-level coordination tool; track plan v0 to be documented in `PB-44` Confluence page (page id `1933313`); dictation pending — Phase 3 brainstorm opener fills it.
- The 2026-05-19 brainstorm Jira ladder (which seeded PB-7..PB-13 Epic titles) was already MVP-anticipating in many slots (R+C at Phase 3, billing at Phase 7) — this ADR formalizes that intent rather than overturning it. See `tasks/2026-05-20-phase-c-rescope-design.md` §17 for the mapping-correction discovery story.
- fixVersions on PB-7..PB-13 (`v0.3.0..v1.0.0`) still describe 2026-05-19 ladder phase titles in some cases (e.g., `v0.5.0` "Phase 5 — Gateway + Light Hardening"). Updating fixVersion names + assignments to match new mapping is **out of scope for this commit**; deferred to a post-execute corrective commit.

## Alternatives considered

- **(a) Phase 5 hardening big-bang first.** Rejected: runtime + compute MVP is the bigger product unblock; investor-facing "secure isolation works" claim depends on Phase 3 (new), not on cluster-wide hardening of services that don't yet exist.
- **(b) Identity continuation in active Phase 3+.** Rejected: blocks MVP and adds scope. Single-org admin-side bootstrap via the existing identity CLI is enough for runtime + compute MVP; self-service org creation can wait under `PB-42`.
- **(c) ADR-0009 in-place amendment.** Rejected: violates ADR immutability convention. ADR-0009 stays as historical record marked superseded; ADR-0014 replaces it.

## References

- `tasks/2026-05-20-phase-c-rescope-design.md` — Phase C re-scope design doc (this ADR's source design)
- `tasks/2026-05-20-actual-state-survey.md` — Path D investigation that triggered the re-scope
- ADR-0006 — vertical (tracer-bullet) implementation (still active; only the phase order is reset)
- ADR-0009 — product-first sequencing (now superseded)
- `.claude/jira-config.json` `phase_c_rescope` block — Jira state delta (epic_remapping, new_artifacts, deferred_dispositions)
- Confluence: `PB-43` glossary v0 (page id `1900546`), `PB-44` track plan v0 stub (page id `1933313`)
- CLAUDE.md — Backend Services table + Implementation Strategy section (updated in the same commit)
