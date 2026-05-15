# 0004 — Migrator: shared SDK library + per-service binary

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo), ADR-0002 (schema-per-service)

## Context

Multi-repo + schema-per-service means each service manages its own migrations. Three options for the migrator binary: copy-paste in every service, one central migrator repo, or a shared library that each service consumes through a thin binary. plan/47 already locked golang-migrate + advisory lock + reversible up/down + forward-only-in-prod.

## Decision

`paper-board/sdk/migrator` is a shared Go library. Each service ships a `cmd/migrator/main.go` of about 30 lines (a `Config` struct plus a call to `Run`).

**Advisory-lock id mapping** (allows parallel migrations across services):

- `identity` = 1
- `billing` = 2
- `agents` = 3
- `platform` = 4

**Migration filename format:** 6-digit padding (`000001_*.up.sql`, `000001_*.down.sql`).

**Library API:**

```go
// paper-board/sdk/migrator/migrator.go
type Config struct {
    DBURL          string  // MIGRATION_DB_URL — port 5432 direct, NOT PgBouncer 6432
    Schema         string  // e.g. "identity"
    AdvisoryLockID int
    EmbedFS        embed.FS
    EmbedRoot      string  // e.g. "schema"
}

func Run(ctx context.Context, cfg Config, args []string) error
```

Subcommands (cobra): `up [--dry-run]`, `down N`, `force VERSION`, `version`, `drop` (dev-only; requires `MIGRATOR_ENV=dev`, an explicit `--confirm=drop-<schema>` token matching the target schema name, and a non-prod allowlist check; hard-denied when `MIGRATOR_ENV=production`).

Each service ships a Helm `pre-install` / `pre-upgrade` Job that runs its migrator.

## Rejected alternatives

- **One central `paper-board/migrator` repo.** Breaks the multi-repo D philosophy; one team owns every schema migration.
- **Per-service copy-paste.** Code duplication 7×; bug fixes need 7 PRs; version drift inevitable.
- **Migrator as an initContainer.** Anti-pattern — rolling restarts can leave the schema dirty mid-deploy.
- **Migrator-as-a-service.** Overkill; a single point of failure for every deploy.

## Consequences

**Gain:**
- DRY (the golang-migrate wrapper lives in one place).
- Independent deploy: each service has its own pre-install Job.
- Per-service advisory locks allow parallel migrations.
- SDK SemVer keeps versions coordinated.

**Risk and mitigation:**
- `paper-board/sdk` becomes a Phase 1.0 prerequisite: v0.1.0 must ship before any service migrator can be built.
- A breaking change to the migrator API forces 4 service bumps — Renovate auto-PRs handle the fan-out.
- GOPRIVATE auth is required (org PAT) for CI to fetch the private module.
