# 0006 — Vertical (tracer-bullet) implementation

**Status:** accepted; phase order superseded by ADR-0009
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo), ADR-0004 (migrator)

## Context

plan/00 wrote Phase 1 in horizontal order: 1.1 migrator → 1.2 helm → 1.3 first migration → 1.13 round-trip test. That order made sense for a single repo, but multi-repo + schema-per-service made each service a vertical slice in its own right.

## Decision

**Vertical implementation:** finish a service end-to-end (migrator + schema + Helm + CI + smoke) before starting the next. Phase 1.0 (sdk + proto + infra) is the parallel prerequisite.

The original phase order in this ADR (identity → billing → agents → platform) is **superseded by ADR-0009**, which keeps the vertical philosophy but starts with `agents` instead of `identity` to put a demoable product in front first.

## Rejected alternatives

- **Horizontal (plan/00 default).** End-to-end verification slips to the end of Phase 1; risk discovery is delayed; the SDK feedback loop is loose; multi-repo D loses its rhythm.
- **Hybrid (Phase 1.0 horizontal + Phase 1.1+ vertical).** In practice identical to vertical because Phase 1.0 is small.

## Consequences

**Gain (vertical philosophy, retained):**
- A tracer bullet validates end-to-end at the close of the first service (CI, GHCR, Helm hook, GOPRIVATE, buf codegen — every infrastructure landmine surfaces early).
- Pattern discovery in service N → straight copy for services N+1..M (2-3× faster).
- Tight SDK feedback loop: v0.1.0 → v0.2.0 evolves with each service's learnings.
- High value of stopping mid-Phase: the first service is production-ready on its own.
- Mental load is one domain at a time.

**Risk:**
- Pattern repetition 4× — drift handled by `paper-board/service-template` (Phase 5).
- plan/00 numbering is invalidated. The new plan file is canonical.

**Phase 1 estimate (solo dev, full-time):** 2-3 weeks for the first service, 3-7 days for each subsequent service. See ADR-0009 + the active roadmap for the concrete order.
