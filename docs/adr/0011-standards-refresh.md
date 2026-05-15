# 0011 — Standards Refresh: Decouple Phase Roadmap from Timeless Rules

**Status:** accepted
**Date:** 2026-05-03
**Related:** ADR-0010 (standards suite), ADR-0006 (vertical implementation), ADR-0008 (license / commits / style).

## Context

ADR-0010 introduced the nine standards docs under `docs/standards/`. Each doc was drafted while
the sdk was being designed; rules were interleaved with version commitments
("ships v0.1.1 (Phase 1.5)"), per-service drift notes ("Migration cost in `agents`"), and phase
gates ("Phase 5+ tunable"). Once `paper-board/sdk` shipped v0.2.0, the docs began to lie: many
"Phase 1.5 deliverable" rules referenced packages that already existed, and engineers reading
the docs would skip features they could already use. The genre-mix decayed every release.

## Decision

Standards docs document **timeless rules**. The refresh strips:

- SemVer version tags ("ships v0.X.Y").
- Phase gates ("Phase 1.5", "Phase 5+ tunable").
- Per-service drift notes ("Current state in `agents`", "Migration cost in `agents`").
- Doc-level "Last update" / "Phase X.Y+" status suffix.

When a rule references an API not yet shipped (today only `sdk/ids`), the rule is annotated
`Status: Pending`. All other rules are `Active` once the doc lists them.

Phase-gated content lives elsewhere:

- `tasks/2026-04-30-backend-roadmap.md` — when each service ships, which Phase 5+ items exist.
- `tasks/2026-05-02-adr-0010-gap-analysis.md` — per-service migration tasks and intermediate
  coverage gates.
- `paper-board/sdk/CHANGELOG.md` — sdk version sequencing.

Two consequential rule changes landed in the same refresh:

1. **`go-service-layout.md` §3.3 escalation:** the adapter-deletion smoke test was conditional
   ("when ≥2 impls"); now mandatory. Every adapter MUST ship a `mock/` sub-package alongside
   production impls so the smoke test runs from day 1.
2. **`database-conventions.md` §8b mixing rules:** UUID version follows the **entity** that owns
   it, not the **table** that stores it. Reference columns inherit the source's version. App-side
   generation is canonical regardless of Postgres `uuidv7()` support; the prior "until PG18+"
   caveat is dropped.

## Rejected alternatives

- **Keep version tags but move them to a single appendix per doc** — preserves the genre-mixing
  problem; appendix decays at the same rate as inline tags.
- **Strip without `Status: Pending` flag** — silently lies when a rule references an unshipped
  API; reader cannot tell what is enforceable today.
- **Per-rule status flags everywhere** — only one rule (`sdk/ids` UUIDv7 generation) is genuinely
  pending; flagging dozens of `Active` rules adds noise.

## Consequences

**Gain:** Standards docs become enforceable today; engineers no longer skip rules that already
apply. Cross-doc references stop decaying with every sdk release. The `mock/` sub-package
mandate makes §3.3's smoke test always-on, catching adapter-leak regressions earlier rather than
on the day a second impl is added.

**Cost:** ~115 edits across 10 files in this single refresh. Coverage ramp values are no longer
per-phase in the standards (only mature targets); per-phase intermediate values live in
`tasks/2026-05-02-adr-0010-gap-analysis.md`. The SemVer per-service mode×phase mapping table
was dropped — prose rule remains; per-service stabilization timeline lives in roadmap.

## Compliance

- Standards docs MUST NOT acquire phase numbers, SemVer tags, or per-service drift notes again.
  Rule additions referencing time-bound content link to the roadmap or gap-analysis files.
- New rules referencing unshipped APIs are annotated `Status: Pending`; tag is dropped when the
  API ships.
- Every adapter MUST ship a `mock/` sub-package; CI's `make test-mock-only` runs from day 1.
