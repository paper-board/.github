# 0018 — Idempotency v2 replay semantics

**Status:** accepted
**Date:** 2026-05-28
**Accepted at:** commit `277d818` (2026-05-28; squash-merge of agent-manager PR #2)
**Scope:** backend

## Context

`paper-board/sdk/idempotency` ships an HTTP middleware that lets services handle retried client requests safely. The middleware computes a hash of the incoming request (key, method, path, body), stores the response on first execution, and replays the stored response for any subsequent request carrying the same `Idempotency-Key` header. Stripe's idempotency-key contract (`Idempotency-Key` header, 24-hour window, 200/4xx/5xx replay parity) is the design reference.

The package shipped initially in sdk v0.2.0 with a single-value response-header store (`map[string]string`) and a hash that included `Method + Path + Body + Idempotency-Key`. During the sdk v0.3.0 → v0.4.0 cycle (2026-05-24), three findings surfaced in identity-service production-shape integration testing:

1. **`Set-Cookie` and other multi-value headers were truncated on replay.** When a handler set two `Set-Cookie` headers (session + CSRF), the single-value `map[string]string` kept only the last one. On replay, the client received a partial cookie set and the session was broken. Pre-v0.4.0 production identity records are dev/staging-only — no live customers had been bitten, but the latent risk on first production traffic was high.
2. **Two requests differing only in `?query=...` parameters collided on the same idempotency key.** The hash input was `Method + Path + Body + Key`; `RawQuery` was excluded. A REST list endpoint paginated by `?page=2` vs `?page=3` would, if the client (incorrectly) reused an Idempotency-Key, replay the page-2 response for the page-3 request. This is a contract violation (different requests get different idempotency rows).
3. **Handlers returning without `WriteHeader` or `Write`** (implicit-200 path in Go's `net/http`) were persisted with HTTP status `0`. On replay, the middleware wrote status `0` to the response, which the Go stdlib serialized as an empty status line. Real-world handlers that finished without writing a body (e.g., a DELETE returning no body) hit this path.

sdk v0.4.0 changed the contract to address all three findings. Because the changes affect the semantics of stored records (not just the API surface), this ADR ratifies the new contract so consumer services (Phase 4 onboarding; Phase 8 gateway) implementing idempotency stores or replay handling are bound to the v0.4.0+ semantics. `paper-board/service-template`'s current `internal/middleware/middleware.go` does NOT use `sdk/idempotency` (verified 2026-05-28); this ADR therefore documents the contract before adoption, not as a remedial measure.

## Decision

The `paper-board/sdk/idempotency` middleware behaviour is fixed to the v0.4.0 contract:

1. **`idempotency.Record.ResponseHeaders` type is `map[string][]string`**, not `map[string]string`. Repeated headers (canonical example: `Set-Cookie`) survive replay. The replay handler writes each value of each key as a separate header line, matching Go stdlib `http.Header.Add` semantics.
2. **The request hash input is `Method + Path + RawQuery + Body + Idempotency-Key`.** Requests that differ in query-string get distinct idempotency rows. Clients reusing an Idempotency-Key across different `?query=` values get a `409 Conflict` per Stripe's parity rules (different request shape for the same key).
3. **Handlers that return without `WriteHeader` or `Write` are persisted as `200 OK` and replayed as `200 OK`.** This matches Go's `net/http` implicit-200 behaviour (`http.ResponseWriter.Write` defers a `WriteHeader(200)` if status was never set). Status `0` is never persisted.

## Consequences

- **Store implementations** (Postgres, in-memory test store, Redis-backed future store) MUST serialize the multi-value header form. The reference implementation (`sdk/idempotency/store_memory.go`) uses `map[string][]string` natively; SQL-backed stores JSON-encode the map.
- **Pre-v0.4.0 records.** Identity is the only consumer of `sdk/idempotency` in paper-board as of 2026-05-28, running on dev/staging only. No production records exist. **No migration is required**; the dev/staging idempotency tables are routinely truncated as part of `make smoke` resets. Should a future service ship `sdk/idempotency` on top of pre-v0.4.0 records, that service's first deploy MUST run a one-time backfill (re-encoding `string` → `[]string{ value }` for existing rows) before serving traffic.
- **HTTP API contract change for clients.** Same `Idempotency-Key` + same `Method+Path+Body` but DIFFERENT `?query=...` now returns `409 Conflict` (previously: silent replay of mismatched response). API consumers MUST treat `409 Conflict` on idempotency endpoints as "your client reused the key across different request shapes; pick a new key". This is documented in service-level API references; gateway-bound consumers may need a client-library update.
- **Phase 4 onboarding service** is the first new consumer expected to ship `sdk/idempotency` (onboarding's `POST /orgs` endpoint needs idempotent semantics so the orchestrator retries don't double-create orgs). onboarding's ADR-0018-compliance is a PR review check, not an automated gate.
- **Phase 8 gateway centralization** will adopt `sdk/idempotency` as the cross-service `Idempotency-Key` enforcement point. By then, this ADR provides the binding contract.
- **Documentation**: `docs/idempotency-quickstart.md` in service-template (Follow-up PR FP-2; see `tasks/2026-05-28-service-template-sdk-bump-plan.md` §8) MUST cite this ADR.

## Alternatives considered

- **(a) Keep single-value `map[string]string` headers; document `Set-Cookie` as unsupported.** Rejected: forcing every consumer service to special-case `Set-Cookie` in custom middleware defeats the purpose of a shared idempotency package. Multi-value is the only correct contract.
- **(b) Include `RawQuery` only for `GET` and `DELETE`, exclude for `POST`/`PUT` (where the body usually carries the canonical request shape).** Rejected: opaque method-aware behaviour adds a foot-gun. The simpler rule (always hash `RawQuery`) is easier to reason about; the cost is one extra `&` character in the hash input for most POSTs that omit query strings.
- **(c) Persist status `0` faithfully (don't coerce to 200) and let the replay write `0` on the wire.** Rejected: violates Go stdlib `net/http` contract. Clients receiving status `0` cannot interpret it; serializers may emit a malformed status line. Coercing matches the original behaviour the handler would have produced on first execution.
- **(d) Defer the entire ADR to the first consumer service's PR.** Rejected: the contract is sdk-library-level, not service-level. Deferring would leave gateway / onboarding engineers to re-derive the rationale from the sdk CHANGELOG entry; this ADR consolidates the reasoning at the level it applies to.

## References

- `paper-board/sdk` CHANGELOG v0.4.0 entry — original BREAKING change record
- `paper-board/sdk/idempotency/*.go` (HEAD) — current implementation matching this ADR's decision
- Stripe API documentation — Idempotency-Key contract (https://stripe.com/docs/api/idempotent_requests) — design reference for `409 Conflict` on shape mismatch
- `tasks/2026-05-28-service-template-sdk-bump-plan.md` §4.2 — companion plan section that triggered this ADR
- ADR-0008 — Conventions (license + commit + branch), where service-level API conventions reside
