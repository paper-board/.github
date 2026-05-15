# HTTP API Conventions

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative. References: ADR-0005 (REST public), ADR-0007.

This document fixes the wire shape and middleware contract for every public REST endpoint across
the seven backend services. Internal gRPC is governed by `paper-board/proto` and is out of scope.

---

## 1. Router — `chi/v5` locked

### Rule

All HTTP servers MUST use `github.com/go-chi/chi/v5`. No alternative routers (gorilla/mux, gin,
echo, fiber, stdlib `http.ServeMux`) are permitted.

### Rationale

Already in `agents/internal/api/api.go:29`. `chi` is `net/http`-based, so every Go HTTP middleware
works; same-binary gRPC interop via `cmux` is straightforward; OTel is the boring `otelhttp`.
Express-style alternatives (Fiber/fasthttp) lock us into a custom engine that cannot share a
listener with grpc-go and forces a Fiber-shaped middleware ecosystem.

### Rejected alternatives

- **`fiber/v2`** — Express ergonomics, but fasthttp engine forces two-port REST+gRPC pods, and
  `sdk/httpmw` would be Fiber-specific from day one.
- **`fiber/v3`** — additionally still in beta; breaking changes during the roadmap window are an
  unacceptable risk.
- **`gin`** — large dep tree, opinionated middleware story; no lift over chi for our use case.
- **`net/http` 1.22+ `ServeMux`** — pattern routing exists, but no sub-router groups, no
  `URLParam` helper, no built-in middleware chain composition.

### Enforcement

- `golangci-lint depguard` rule: only `github.com/go-chi/chi/v5` allowed for HTTP routing imports
  inside `internal/api/`.
- service-template wires the canonical chain (§2).

---

## 2. Middleware chain — canonical 9-stage order

### Rule

Every service's `internal/api` MUST register middleware in this exact order:

```
1. RequestID         chi.middleware.RequestID            stamp X-Request-ID early
2. RealIP            chi.middleware.RealIP               resolve X-Forwarded-For BEFORE log
3. OTelTrace         sdk/httpmw.OTel                     extract W3C traceparent, start span
4. Logger            sdk/httpmw.Logger                   slog bound to request_id + trace_id
5. Recoverer         sdk/httpmw.Recoverer                catch panic; structured log payload
6. Timeout           chi.middleware.Timeout              per-route group; default 120s
7. CORS              sdk/httpmw.CORS                     only on /v1; gateway handles once it lands
8. Auth              sdk/httpmw.Auth                     sets ctx auth.* keys
9. RateLimit         sdk/httpmw.RateLimit                per-org token bucket
```

Stages 1-7 are MANDATORY for every service. Stages 8-9 (Auth, RateLimit) MUST be wired once their
sdk packages ship; until then the relevant rules are documented here as `Status: Pending`.

### Order rationale

- ID/IP/trace MUST come before Logger so logs include them.
- Recoverer MUST come after Logger so the panic event is logged with full structured payload.
- Auth MUST come after Recoverer (so a panicking auth check is captured) but before RateLimit
  (rate-limit per-org needs the org from auth context).
- Timeout MUST come before any handler-level work so cancellation propagates correctly.

### Enforcement

- service-template wires the full chain.
- Code review: chain order is checked on every PR touching `internal/api/api.go`.

---

## 3. Middleware location — hybrid

### Rule

- Cross-cutting middleware (Logger, OTel, Recoverer, Auth, RateLimit, CORS, WriteError helper,
  pagination codec) MUST live in `paper-board/sdk/httpmw`.
- Service-specific middleware (e.g. quota check, billing-trial guard) MUST live in
  `internal/middleware/` of that service.

A middleware MUST NOT exist in both places under the same name.

### Rationale

Five of nine canonical stages are identical concept across all services; copying them means each
service rediscovers the right `slog` keys or trace propagation idiom. SDK churn is real but
`sdk/httpmw` is small (~300 LOC target) and stabilises with use. Service-specific middleware is
rare and lives where it belongs.

### Enforcement

- `golangci-lint depguard` blocks duplicate names: `internal/middleware/*.go` MUST NOT export a
  symbol whose name already exists in `sdk/httpmw`.
- `sdk/httpmw` package documentation lists every exported middleware.

---

## 4. Auth boundary

### Rule

Until the gateway terminates auth, each service's `internal/api` MUST mount `sdk/httpmw.Auth`
immediately after Recoverer/Timeout (stage 8 in §2). Once the gateway terminates auth and
forwards trusted `x-user-id`/`x-org-id`/`x-roles` headers, per-service middleware degrades to
header-trust mode.

### Stable contract — `ctx` keys

Regardless of mode, downstream handlers MUST read auth state via these `ctx` keys (defined in
`sdk/httpmw/auth.go`):

| Key                   | Type           | Required mode | Notes                                   |
|-----------------------|----------------|---------------|-----------------------------------------|
| `auth.user_id`        | `uuid.UUID`    | always        | end user; zero UUID for service-to-service |
| `auth.org_id`         | `uuid.UUID`    | always        | tenant; zero UUID forbidden in prod     |
| `auth.roles`          | `[]string`     | always        | RBAC roles                              |
| `auth.api_key_id`     | `*uuid.UUID`   | api-key only  | nil for JWT-bearer requests             |
| `auth.session_id`     | `*uuid.UUID`   | jwt only      | nil for API key requests                |

### Modes

```
AUTH_MODE=jwt              verify Bearer JWT against identity service via gRPC.
AUTH_MODE=api-key          verify ApiKey against identity service via gRPC.
AUTH_MODE=trust-headers    trust gateway-injected x-user-id/x-org-id/x-roles headers.
                           MUST be combined with mTLS or NetworkPolicy default-deny.
```

`AUTH_MODE` is a `Config` field (Topic 3); see Configuration standard.

### Failure response

```json
HTTP/1.1 401 Unauthorized
X-Request-ID: <id>
{"error":{"code":"<service>.unauthorized","message":"Authentication required."}}
```

### Enforcement

- `sdk/httpmw.Auth` (`Status: Pending` until shipped) MUST be the only auth middleware in service
  code; ad-hoc auth middleware is forbidden.
- ADR-0010 records the contract keys; any change to the keys is a SemVer-major bump for sdk.
- Code review: handlers MUST read auth via the typed accessor `httpmw.OrgFrom(ctx)`, not raw
  `ctx.Value`.

---

## 5. Error response envelope

### Rule

Every response with HTTP status ≥ 400 from a public REST endpoint MUST have body:

```json
{
  "error": {
    "code": "<service>.<error_code>",
    "message": "<single-sentence English>",
    "details": { ... }   // optional
  }
}
```

- `code`: lowercase snake_case, prefixed with the service name. Examples: `agents.not_found`,
  `agents.validation_failed`, `identity.unauthorized`, `billing.quota_exceeded`.
- `message`: human-readable English, ASCII, single sentence ending in period. MUST NOT leak
  internal details (stack traces, SQL state, file paths).
- `details`: optional object. For validator/v10-driven 400s, MUST be:
  ```json
  {"fields":[{"name":"slug","reason":"required"},{"name":"model","reason":"oneof"}]}
  ```
- `Content-Type: application/json` MUST be set.
- `X-Request-ID` header (from chi RequestID middleware) MUST be present in every response,
  success or failure.

### Helper

`sdk/httpmw.WriteError(w, status, code, msg, details)` is the only sanctioned way to write an error
body. Direct `json.Encoder` use for error paths is forbidden.

### Code prefix table — per-service

| Service   | Prefix      |
|-----------|-------------|
| agents    | `agents.`   |
| identity  | `identity.` |
| billing   | `billing.`  |
| platform  | `platform.` |
| runtime   | `runtime.`  |
| compute   | `compute.`  |
| gateway   | `gateway.`  |

### Enforcement

- `sdk/httpmw.WriteError` is a hard dependency for `internal/api`.
- golangci-lint forbids `w.WriteHeader` + `json.Encoder` combo in `internal/api/` (`forbidigo` rule).
- A code-review checklist line: "All error codes prefixed with `<service>.`?"
- Topic 8 (Error handling) defines the sentinel-to-code mapping; this document locks the wire shape only.

---

## 6. Pagination — cursor default, offset for admin

### Rule

List endpoints MUST default to **cursor pagination** when the underlying table can exceed
~10k rows or where stable pagination matters across concurrent inserts/deletes. Offset MAY be
used only for admin/debug endpoints with naturally bounded result sets (≤500 rows).

### Cursor wire shape

Request:
```
GET /v1/agents?after=<base64>&limit=20
```

- `after`: opaque base64 cursor; absent ⇒ start of list.
- `limit`: integer, default 20, max 100. Out-of-range MUST 400 with `<service>.invalid_limit`.

Response:
```json
{
  "items": [ ... ],
  "next": "<base64 cursor>" | null
}
```

`next` is `null` when no more rows. Clients MUST NOT parse cursor contents.

### Cursor payload (internal)

The opaque payload SHOULD encode `(sort_field_value, primary_key_id)` to disambiguate ties on
non-unique sort fields:

```go
type Cursor struct {
    Sort string    `json:"s"`  // e.g. "created_at"
    Val  string    `json:"v"`  // RFC3339 timestamp or other serialised value
    ID   uuid.UUID `json:"i"`  // tie-breaker
}
```

Encoded with `json.Marshal` then `base64.URLEncoding.EncodeToString`. SDK provides
`pagination.Encode` / `pagination.Decode`.

### SQL pattern (Topic 5 cross-reference)

```sql
SELECT ...
FROM agents.sessions
WHERE org_id = $1
  AND (created_at, id) < ($2, $3)        -- $2,$3 = decoded cursor; descending order
ORDER BY created_at DESC, id DESC
LIMIT $4
```

For ascending cursors, swap operators. Topic 5 (Database) elaborates.

### Offset wire shape (admin only)

```
GET /admin/users?page=1&size=20
{"items":[...], "page":1, "size":20, "total":347}
```

`total` is included only when feasible; large-table list endpoints MUST omit it.

### Rejected alternatives

- **Offset everywhere** — page drift on inserts; `agents.session_events` is append-heavy and
  would corrupt pagination on every new event.
- **Google AIP-158 page tokens with strict naming (`page_token`, `page_size`)** — wire shape
  compatible, but we keep our `after`/`limit`/`next` names as they're more concise and already
  precedented across our internal habits.

### Enforcement

- `sdk/httpmw/pagination` provides `Encode`/`Decode`/`SQLClause` helpers.
- service-template includes one paginated example endpoint.
- Code review: any new list endpoint over a table without a hard size cap MUST use cursor.

---

## 7. JSON conventions (cross-reference, locked here)

### Rule

- Wire-JSON field naming: **camelCase**. Go field names stay PascalCase; SQL column names stay
  snake_case (database-conventions §8). Conversion happens at the JSON tag boundary.
  ```go
  type Agent struct {
      ID           uuid.UUID `json:"id"`
      OrgID        uuid.UUID `json:"orgId"`
      Name         string    `json:"name"`
      SystemPrompt string    `json:"systemPrompt,omitempty"`
      CreatedAt    time.Time `json:"createdAt"`
      UpdatedAt    time.Time `json:"updatedAt"`
  }
  ```
- Optional fields use `,omitempty`.
- Timestamps are RFC3339 UTC: `"2026-05-01T14:30:00Z"`. Storage is UTC always (Topic 10B).
- UUIDs are canonical lowercase hyphenated form.
- Enum values on the wire are lowercase snake_case strings, even though field names are camelCase
  (e.g. `"eventType": "user_message"`). The *value* matches the SQL CHECK-constraint literal so
  there is one shape end-to-end inside storage; the *field name* matches frontend convention.
- Acronyms in field names follow Go style on the Go side (`OrgID`, `URL`) and lowerCamel on the
  wire (`orgId`, `url`). When the acronym starts the field, it's lowercased: `id` (not `iD`).

### Log JSON is exempt

Structured-log JSON keys (Topic 6 §1) stay snake_case (`request_id`, `trace_id`, `org_id`).
Loki/Grafana ecosystems and OTel semantic conventions assume snake_case attribute identifiers;
keeping logs separate from wire DTOs decouples frontend ergonomics from operator ergonomics.

### Enforcement

- Code review.
- service-template uses camelCase in all DTO struct tags; snake_case retained only on log
  attribute keys.
- golangci-lint custom rule flags `json:"<has_underscore>"` outside `internal/store/queries/`
  (sqlc-generated row types are exempt — they map SQL columns).

---

## 8. Versioning — URL path

### Rule

All versioned endpoints MUST be mounted under `/v1`. Breaking changes ship under `/v2` and serve
in parallel for a deprecation window; deprecation governance lives in a separate ADR.

### Enforcement

- service-template registers `r.Route("/v1", ...)` and rejects un-prefixed handlers in lint review.

---

## 9. Health endpoints

### Rule

Every service MUST expose:
- `GET /healthz` — liveness; 200 if process can serve. No DB check.
- `GET /readyz` — readiness; 200 only if DB and dependent services are reachable. Returns 503 + JSON envelope on failure.

Both endpoints MUST be unauthenticated and MUST NOT participate in rate limiting.

### Enforcement

- service-template ships both. Helm `livenessProbe`/`readinessProbe` references them.

---

## 9b. Idempotency — `Idempotency-Key` header

### Rule

POST / PUT / PATCH endpoints under `/v1` that mutate state MUST honour an `Idempotency-Key`
header. The middleware lives in `sdk/httpmw.Idempotency(store)` (`Status: Pending` until
shipped) and is mounted on the relevant routes only (not on safe GETs).

### Wire shape

```
POST /v1/agents
Idempotency-Key: 7c1d-4a23-...   (caller-generated, opaque to server, ≤ 128 ASCII bytes)
```

- Same key + same request body within the TTL window MUST yield byte-identical replay of the
  original response (status, body, headers).
- Same key + different body MUST return `409` with `code: "<service>.idempotency_conflict"`.
- Missing header on a mutating endpoint is permitted; future tightening MAY require it on every
  mutating `/v1/*` endpoint.

### Storage

Idempotency keys live in `identity.idempotency_keys` (CLAUDE.md identity service responsibility),
keyed by `(org_id, key)`. TTL: 24h default, configurable. Each row stores response status, body
hash, and a content-addressable replay payload.

### Enforcement

- service-template wires `sdk/httpmw.Idempotency` on canonical mutating endpoints once the sdk
  package ships.

---

## 10. Summary

| §   | Rule                                                              | Enforcement                                  |
|-----|-------------------------------------------------------------------|----------------------------------------------|
| §1  | chi/v5 only                                                       | depguard                                     |
| §2  | 9-stage middleware order                                          | service-template + sdk/httpmw                |
| §3  | sdk/httpmw cross-cutting; internal/middleware bespoke             | depguard duplicate-name check                |
| §4  | Auth boundary; stable ctx keys                                    | sdk/httpmw.Auth + typed accessors            |
| §5  | `{error: {code: <service>.<x>, message, details?}}`               | sdk/httpmw.WriteError; forbidigo on encoder  |
| §6  | Cursor default; offset admin-only                                 | sdk/httpmw/pagination + review               |
| §7  | snake_case JSON, RFC3339 UTC                                      | review                                       |
| §8  | `/v1` URL versioning                                              | service-template                             |
| §9  | `/healthz` + `/readyz` mandatory                                  | service-template + Helm probes               |
