# 0002 — Schema-per-service in single Postgres

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo)

## Context

Multi-repo was chosen (ADR-0001). The DB topology question follows: shared schema vs schema-per-service vs DB-per-service vs cluster-per-service. For multi-repo to be meaningful, each service must own its data; otherwise seven repos writing to the same tables is a network-distributed monolith.

## Decision

A single Postgres cluster, with one schema per service:

| Schema     | Service    | Tables (Phase target)            | DB user        |
|------------|------------|----------------------------------|----------------|
| `identity` | identity   | 14                               | `identity_app` |
| `billing`  | billing    | 14                               | `billing_app`  |
| `agents`   | agents     | 3 (Phase 1.1) → 9 (Phase 5)      | `agents_app`   |
| `platform` | platform   | 14                               | `platform_app` |

`compute`, `gateway`, `runtime` are stateless — no schema.

Each service connects with its own DB user; PoLP applies. The user has USAGE only on its own schema and ALL PRIVILEGES on its own tables. Access to other schemas is denied at runtime by Postgres.

`pgcrypto`, `citext`, and `vector` (pgvector) extensions live in `public` and are cluster-wide.

## Rejected alternatives

- **Single schema.** Defeats the multi-repo decision; PoLP is violated; bounded-context discipline reduces to code review.
- **DB-per-service.** Requires saga + outbox from day one; cross-DB joins are not native; YAGNI for Phase 1.
- **Cluster-per-service.** 7× operational cost (RDS, backups, monitoring) without scale justification.

## Consequences

**Gain:**
- Postgres-level boundary: unauthorized cross-schema access fails at runtime.
- One RDS instance — cheap.
- Cross-schema joins still possible for ad-hoc analytics via a `superuser` (e.g. read replica).
- Migrating a schema to its own DB later is a one-day operation: `pg_dump --schema=billing | pg_restore`.

**Risk and mitigation:**
- Developer temptation to write `SELECT * FROM identity.users` in agents code — Postgres rejects it because `agents_app` has no permission on `identity.*`.
- plan/03 assumed a single schema; reorganizing tables across schemas is a one-day mechanical task.
- Connection pools fan out to seven users — PgBouncer config must mirror that.
