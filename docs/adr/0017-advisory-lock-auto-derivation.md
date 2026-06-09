# 0017 — Advisory lock auto-derivation (amends ADR-0004)

**Status:** accepted
**Date:** 2026-05-28
**Accepted at:** commit `277d818` (2026-05-28; squash-merge of agent-manager PR #2)
**Amends:** ADR-0004 (supersedes the "Advisory-lock id mapping" sub-section of the Decision; ADR-0004's "shared SDK library + per-service binary" decision and migration-filename format remain in force)
**Scope:** backend

## Context

ADR-0004 (2026-05) defined the Migrator pattern (paper-board/sdk/migrator + per-service `cmd/migrator/main.go`) and pinned an integer advisory-lock id per service:

- `identity = 1`, `billing = 2`, `agents = 3`, `platform = 4`

The intent of the manual mapping was to let migrations across services run in parallel without serializing on a shared lock id. New services (Phase 4: audit, metering, notifications, onboarding, environments, vaults) would each pick the next free integer.

During the sdk v0.3.0 → v0.4.0 cycle (2026-05-24), two findings invalidated the manual-mapping rationale:

1. **The field was already vestigial at v0.3.0.** `paper-board/sdk` `migrator/runner.go:26` used `cfg.AdvisoryLockID` only as a `slog` attribute on the migrator's structured logger ("lock_id" key). The actual Postgres lock acquisition was handled by the `golang-migrate` `pgx/v5` driver, which derives the lock id internally from `CRC32(database+schema)`. The field was advertised as required (compile + validate) but had no Postgres-side effect.
2. **Schema-per-service already guarantees hash isolation.** ADR-0002 mandates one Postgres schema per service. CRC32 of `<database_name>+<schema_name>` is collision-free in practice across single-digit services (probability of accidental collision across ~20 schemas in a single database is on the order of 1 / 2³². CRC32 is not cryptographic, but for this purpose — partitioning advisory lock ids — it suffices because schema names are unique and authored, not adversarial input).

sdk v0.4.0 acted on these findings: the `migrator.Config.AdvisoryLockID` field was removed (CHANGELOG: **BREAKING — `migrator.Config.AdvisoryLockID` field. Advisory locks are now managed by `golang-migrate` pgx/v5 driver via `CRC32(database+schema)`. Schema-per-service (ADR-0002) guarantees hash isolation across services. Remove the field from your `cmd/migrator/main.go` Config literal.**).

`paper-board/service-template` (the bootstrap scaffold) and `paper-board/agent-manager/CLAUDE.md` Database Rules section both still carry the manual-mapping pattern as of 2026-05-28, despite sdk v0.4.0 having shipped 4 days earlier. New services bootstrapped from the template inherit the stale mapping by default. This ADR ratifies the new state so the template and CLAUDE.md edits in the companion PR are anchored to a written decision.

## Decision

Advisory lock id for the migrator is **driver-derived `CRC32(database+schema)`** via golang-migrate's pgx/v5 driver. No manual integer mapping is maintained.

Specifically:

- **`migrator.Config.AdvisoryLockID`** field is removed from `paper-board/sdk/migrator.Config` as of sdk v0.4.0.
- **No code in any paper-board service** carries an explicit lock-id constant or per-service integer.
- **Schema-per-service (ADR-0002)** is the sole guarantor of lock-id isolation — new schemas (audit, metering, notifications, onboarding, environments, vaults, plus future Phase 5+ services) automatically receive distinct CRC32 hashes because their schema names are distinct.
- **CLAUDE.md** Database Rules section drops the "Advisory lock id: identity=1, billing=2, …" line; the surrounding rules (MIGRATION_DB_URL vs DATABASE_URL split, 6-digit migration filename format, cluster-wide extensions in `public`) remain.
- **service-template** removes the `{{ADVISORY_LOCK_ID}}` placeholder + the `ADVISORY_LOCK_ID` env-var requirement from `init.sh` + the related row in `README.md` placeholders table + the references in `.github/workflows/template-validate.yml`.

This supersedes the "Advisory-lock id mapping" sub-section of ADR-0004 §Decision. ADR-0004's other decisions — shared `paper-board/sdk/migrator` library, per-service `cmd/migrator/main.go` of ~30 lines, Helm `pre-install` / `pre-upgrade` Job hook, 6-digit migration filename padding, subcommands `up [--dry-run] / down N / force VERSION / version / drop` — remain in force.

## Consequences

- **service-template** bootstrap UX simplified: new-service bootstrap no longer requires the `ADVISORY_LOCK_ID=<n>` env var. Usage becomes `SVC=<svc> PORT=<port> ./init.sh`.
- **CLAUDE.md drift removed**: the stale "identity=1, billing=2, agents=3, audit=4, metering=5, notifications=6, onboarding=7, environments=8, vaults=9" line is deleted in the companion PR.
- **No data-plane migration required.** Existing services already migrated against the driver-derived lock id (since v0.3.0 the field was a no-op at the Postgres layer). The change is documentary + code-cleanup; no `schema_migrations` table change, no in-flight migration risk.
- **CRC32 collision risk** is theoretical only. To collide, two services would need schema names whose CRC32 hashes are identical. Schema names are authored by the team and reviewed in ADR-0002 + service-template bootstrap PRs; collision can be detected pre-merge by computing CRC32 of the proposed schema name against existing schemas. **No automated collision check is part of this ADR** — a one-line `cli` tool subcommand can be added later if collisions ever surface.
- **Engineers writing new `cmd/migrator/main.go`** (whether via service-template init.sh or by hand) must NOT add `AdvisoryLockID` to the Config literal. Compile error makes this self-enforcing for sdk v0.4.0+, but the convention bears stating.
- **ADR-0004 amendment marker** is added to ADR-0004's INDEX.md row (Status: `accepted` → `accepted (amended by ADR-0017)`) following the ADR-0014 / ADR-0015 precedent.

## Alternatives considered

- **(a) Keep the manual integer mapping; treat sdk v0.4.0 removal as an sdk bug to revert.** Rejected: the manual mapping was provably vestigial since v0.3.0 (logger attribute only); the v0.4.0 removal aligned code with reality, not the other way around.
- **(b) Add an explicit per-service integer constant in each service's `cmd/migrator/main.go` and continue passing it via a re-introduced sdk field.** Rejected: zero functional benefit (driver still uses CRC32), maintenance cost across 20+ services, drift risk identical to the original problem.
- **(c) Replace CRC32 with SHA-256 truncated to int64 for collision resistance.** Rejected: CRC32 is the golang-migrate pgx/v5 driver's native implementation; replacing it requires a fork of the driver. Cost > benefit when collision probability is already < 1 / 2³² for ~20 services.
- **(d) Amend ADR-0004 in place.** Rejected: paper-board ADR immutability convention (cf. ADR-0014 superseded by ADR-0015 in a new file). ADR-0004 stays as historical record; ADR-0017 amends the lock-id section.

## References

- ADR-0004 — Migrator: shared SDK library + per-service binary (amended by this ADR)
- ADR-0002 — Schema-per-service in single Postgres (provides the hash-isolation guarantee)
- `paper-board/sdk` CHANGELOG v0.4.0 entry — original removal record
- `paper-board/sdk/migrator/migrator.go` (HEAD) — current `Config` struct without `AdvisoryLockID`
- `tasks/2026-05-28-service-template-sdk-bump-plan.md` — companion plan that applies this ADR's decision to service-template + CLAUDE.md
- `paper-board/agent-manager/CLAUDE.md` Database Rules section — the line being deleted in the companion PR
