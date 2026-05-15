# 0003 — Strict ban on cross-schema FK

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0002 (schema-per-service)

## Context

Schema-per-service was chosen (ADR-0002). Inter-table references can be enforced one of two ways: a Postgres FK across schemas, or UUID-by-reference with application-level validation. Cross-schema FKs give referential integrity for free, but they couple deployments and migrations and they make moving a schema to its own database a months-long refactor.

## Decision

**Cross-schema FKs are forbidden.** Inter-service references are UUID columns without `REFERENCES`. Constraint enforcement is application-level. Cross-service consistency uses soft-delete + outbox events from Phase 4+.

**Intra-schema FKs are fine** (e.g. `agents.session_events` → `agents.sessions`).

```sql
-- agents schema
CREATE TABLE agents.sessions (
  id          uuid PRIMARY KEY,
  org_id      uuid NOT NULL,             -- identity.organizations.id; NO FK
  user_id     uuid NOT NULL,             -- identity.users.id; NO FK
  agent_id    uuid NOT NULL REFERENCES agents.agents(id),  -- intra-schema OK
  ...
);
```

## Rejected alternatives

- **Permissive cross-schema FK.** Postgres referential integrity for free, but moving to DB-per-service later means months of refactoring; the `REFERENCES` privilege itself leaks domain information.
- **No FKs at all (intra-schema included).** Overkill — intra-schema invariants belong in Postgres.

## Consequences

**Gain:**
- Migrating a schema to its own database is free.
- Bounded contexts are enforced at the database layer.
- PoLP is complete: no `REFERENCES` privilege required.
- Test isolation is easy (TRUNCATE is schema-bound).

**Risk and mitigation:**
- Orphan rows are possible — soft-delete + emit-event handles this. From Phase 4 the outbox pattern propagates `UserDeleted` so consumers (`agents`, `billing`) cascade-soft-delete sessions/subscriptions.
- No distributed transactions — through Phase 3, cross-schema transactions still work inside the single Postgres; from Phase 4 the outbox decouples writes from publication.
- Bugs surface at runtime instead of insert time — covered by integration tests of cross-service consistency invariants.
- Admin queries that need joins use a read replica and a `superuser` connection.

## Outbox sketch (Phase 4+)

- The service writes its domain row and an outbox row in the same transaction.
- An async dispatcher reads the outbox and publishes to Redis Streams.
- Consumer services apply at-least-once with idempotency keys.
