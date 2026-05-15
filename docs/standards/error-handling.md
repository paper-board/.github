# Error Handling Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative.
References: ADR-0005, http-api-conventions §5 (envelope shape), observability §1 (log keys),
`paper-board/sdk/errors`.

This document fixes the canonical sentinel set, wrapping rules, HTTP/gRPC status mapping, panic
recovery, and logging integration for every backend service.

---

## 1. Canonical sentinel set — locked

### Rule

`sdk/errors` defines the only top-level sentinels services MAY use. No service repository MAY
define its own top-level sentinel. Service-specific *typed* errors are permitted but MUST wrap
one of these sentinels via `errors.Wrap(...)`.

### The 8 sentinels (existing)

```go
// sdk/errors/sentinel.go
var (
    ErrNotFound          = errors.New("not found")
    ErrConflict          = errors.New("conflict")
    ErrUnauthorized      = errors.New("unauthorized")
    ErrPermissionDenied  = errors.New("permission denied")
    ErrInvalidInput      = errors.New("invalid input")
    ErrRateLimited       = errors.New("rate limited")
    ErrInternal          = errors.New("internal error")
    ErrUnavailable       = errors.New("service unavailable")
)
```

8 sentinels = 8 HTTP statuses = 8 gRPC codes; mapping is total. No others permitted.

### Service-specific typed errors

A service MAY define typed structs for callers needing structured detail. These MUST wrap a
sentinel:

```go
// agents/internal/core/errors.go
type SlugTaken struct{ Slug string }

func (e *SlugTaken) Error() string { return fmt.Sprintf("slug taken: %s", e.Slug) }
func (e *SlugTaken) Unwrap() error { return errors.ErrConflict }
```

Caller pattern:

```go
var st *core.SlugTaken
if errors.As(err, &st) {
    // st.Slug available; underlying sentinel still ErrConflict
}
```

### Rejected alternatives

- **Per-service top-level sentinels** (e.g. `agents.ErrSlugTaken`) — fragments `errors.Is`
  portability across the gateway boundary; gRPC FromGRPCStatus loses identity.
- **Single generic error type with severity field** — bypasses the type system; can't dispatch
  on sentinel cleanly.

### Enforcement

- golangci-lint `depguard`: `errors.New` and `fmt.Errorf` (without `%w`) blocked outside `sdk/errors/`
  and `cmd/<binary>/main.go` startup paths.
- Code review: a new typed error MUST have an `Unwrap() error` returning a canonical sentinel.

---

## 2. Wrapping rules — two-tier

### Rule

Errors MUST be wrapped according to layer:

| Layer                      | Style                                              | Anchor sentinel? |
|----------------------------|----------------------------------------------------|------------------|
| Leaf (creates the error)   | `errors.Wrap(sentinel, "msg", "k", v)`             | yes (mandatory)  |
| Intermediate (passes through) | `fmt.Errorf("operation: %w", err)`              | no (sentinel survives via `%w`) |
| Public boundary (HTTP/gRPC) | no further wrap; call `httpmw.HandleErr` or `errors.ToGRPCStatus` | no |

### Leaf example

```go
// internal/store/agents.go
func (s *Store) GetAgent(ctx context.Context, q queries.Querier, id uuid.UUID) (*core.Agent, error) {
    row, err := q.GetAgent(ctx, id)
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, errors.Wrap(errors.ErrNotFound, "agent", "id", id)
        }
        return nil, errors.Wrap(errors.ErrInternal, "select agent", "id", id)
    }
    return toCoreAgent(row), nil
}
```

### Intermediate example

```go
// internal/core/agent_service.go
func (s *Service) CreateAgent(ctx context.Context, name, slug, model string) (*Agent, error) {
    a, err := s.store.CreateAgent(ctx, q, ...)
    if err != nil {
        return nil, fmt.Errorf("agent service: create: %w", err)
    }
    return a, nil
}
```

### Boundary example

```go
// internal/api/agents.go
func (s *Server) createAgent(w http.ResponseWriter, r *http.Request) {
    a, err := s.svc.CreateAgent(r.Context(), req.Name, req.Slug, req.Model)
    if err != nil {
        httpmw.HandleErr(w, r, "agents", err)
        return
    }
    httpmw.WriteJSON(w, http.StatusCreated, a)
}
```

### Wrap-message style rules

- Lowercase prefix; no trailing punctuation.
- Format: `<package>: <operation>: %w` (e.g. `"agent service: create: %w"`).
- MUST NOT include user-supplied unsanitized strings (slug, email) — leakage to log lines.
- MUST NOT include credentials, tokens, or DB URLs.

### Leaves missing sentinel

A leaf returning an unanchored error (e.g. forgotten `errors.Wrap`) MUST be treated as
`ErrInternal` at the public boundary. `httpmw.HandleErr` returns `500` and logs at ERROR with
`error.kind = "unanchored"` so the regression is visible in Loki.

### Enforcement

- golangci-lint `wrapcheck` linter (configured to exempt `sdk/errors` and boundary handlers).
- Code review checklist line.

---

## 3. HTTP status mapping — `sdk/errors.ToHTTPStatus` + `sdk/httpmw.HandleErr`

### Rule

`sdk/errors` MUST expose `ToHTTPStatus(err) (status int, suffix string)` mirroring the existing
`ToGRPCStatus`:

```go
// sdk/errors/http.go
func ToHTTPStatus(err error) (int, string) {
    switch {
    case errors.Is(err, ErrNotFound):         return 404, "not_found"
    case errors.Is(err, ErrConflict):         return 409, "conflict"
    case errors.Is(err, ErrUnauthorized):     return 401, "unauthorized"
    case errors.Is(err, ErrPermissionDenied): return 403, "permission_denied"
    case errors.Is(err, ErrInvalidInput):     return 400, "validation_failed"
    case errors.Is(err, ErrRateLimited):      return 429, "rate_limited"
    case errors.Is(err, ErrUnavailable):      return 503, "unavailable"
    default:                                  return 500, "internal"
    }
}
```

### `sdk/httpmw.HandleErr` contract

```go
// sdk/httpmw/error.go
func HandleErr(w http.ResponseWriter, r *http.Request, service string, err error)
// 1. status, suffix := errors.ToHTTPStatus(err)
// 2. code := service + "." + suffix
// 3. log:
//    - 5xx → ERROR with error, error.kind, request_id, trace_id, route
//    - 4xx → INFO  (or DEBUG for noisy 401/404 — tunable when needed)
// 4. details := nil; if err is *validator.ValidationErrors, build details.fields[]
// 5. WriteError(w, status, code, message, details)
```

`message` MUST be derived from the sentinel's English text or, for 4xx, a sanitized version of
the wrapped message. MUST NOT echo internal error text for 5xx (leak).

### Validator integration

When `errors.Is(err, ErrInvalidInput)` AND the underlying error is a `validator.ValidationErrors`,
`HandleErr` populates `details`:

```json
{"error":{"code":"agents.validation_failed","message":"Request did not validate.","details":{"fields":[{"name":"slug","reason":"required"}]}}}
```

### Enforcement

- service-template uses `HandleErr` exclusively; ad-hoc `writeJSONError` helpers MUST NOT appear
  in service code.

---

## 4. Code namespacing (cross-reference http-api-conventions §5)

`code` field on the wire MUST be `<service>.<suffix>` where suffix comes from `ToHTTPStatus`.

| Service prefix |
|----------------|
| `agents.`      |
| `identity.`    |
| `billing.`     |
| `platform.`    |
| `runtime.`     |
| `compute.`     |
| `gateway.`     |

`HandleErr` enforces the prefix; passing an unknown service string is a programmer error and
panics in development (`MIGRATOR_ENV=dev`).

### Custom suffixes

A service MAY emit suffixes beyond the canonical 8 (e.g. `agents.quota_exceeded`,
`identity.mfa_required`) when a finer distinction matters for the client. Custom suffixes MUST
still anchor to a sentinel:

```go
// agents-side
err := errors.Wrap(errors.ErrPermissionDenied, "quota exceeded", "limit", limit)
// HandleErr would normally emit "agents.permission_denied"
// Override via httpmw.HandleErrCode(w, r, "agents.quota_exceeded", err)
```

The override helper exists for this case. Custom codes are documented in the service's OpenAPI
spec error catalogue.

---

## 5. Panic recovery

### Rule

`sdk/httpmw.Recoverer` (Topic 4B stage 5) replaces chi's default `middleware.Recoverer`. On
panic it MUST:

1. `recover()` and capture the panic value.
2. `runtime.Stack(buf, false)` for the goroutine stack.
3. Log at ERROR via `sdk/log.Pkg(r.Context())` with attributes:
   - `panic` (interface{}, formatted with `%v`)
   - `stack` (string, capped at 16 KB)
   - `route` (chi route pattern)
   - `method` (HTTP method)
   - canonical context keys (`request_id`, `trace_id`, `org_id`, ...)
4. Write `{error: {code: "<service>.internal", message: "Internal server error."}}` HTTP 500
   via `WriteError`. MUST NOT include the panic message in the response body.
5. Increment counter `http.server.panics_total{route}` (Topic 6 §4).

### gRPC equivalent

`sdk/grpcmw.Recoverer` interceptor MUST be installed on every gRPC server. Identical log shape;
status code `codes.Internal` with generic message.

### Enforcement

- service-template wires `sdk/httpmw.Recoverer`.
- chi's `middleware.Recoverer` is depguard-blocked in `internal/api/`.

---

## 6. Internationalization (i18n)

### Rule

English only initially. The `message` field is treated as debug copy; clients SHOULD localize
off the `code` field.

### Pre-baked plan (when demand arises)

- `sdk/httpmw.Translate(code, lang) string` helper looks up `<code>` in a per-locale catalogue.
- Catalogue lives in `sdk/httpmw/locales/{en,tr,...}.yaml`.
- Handlers ignore i18n; only `HandleErr` consults `Accept-Language` header.
- Custom codes documented in OpenAPI catalogue auto-generate stub catalogue entries.

No code changes outside `sdk/httpmw` when i18n lands; the `code` field is the stable contract.

---

## 7. Logging integration — `error.kind` + `error`

### Rule

Every error log line emitted by `HandleErr`, gRPC interceptor, Recoverer, or service code MUST
include:

| Key            | Value                                           |
|----------------|-------------------------------------------------|
| `error`        | full error string (after wrap chain)            |
| `error.kind`   | sentinel name (`ErrNotFound`, `ErrConflict`, ...) or `"unanchored"` for leaves missing sentinel, or `"panic"` for recovered panics |

`error.kind` is the Loki-filterable axis: `{service="agents", error.kind="ErrConflict"}` shows
all conflict errors regardless of route. Critical for incident triage.

### Helper

```go
// sdk/log/error.go
func ErrorAttrs(err error) []slog.Attr {
    return []slog.Attr{
        slog.String("error", err.Error()),
        slog.String("error.kind", sentinelName(err)),
    }
}
```

`sentinelName(err)` walks the `Unwrap` chain matching against the 8 sentinels; returns
`"unanchored"` if none match.

### Enforcement

- `HandleErr` and Recoverer use `sdk/log.ErrorAttrs` internally; service code MAY use it for
  ad-hoc error logs.

---

## 8. Summary

| §   | Rule                                                              | Enforcement                                  |
|-----|-------------------------------------------------------------------|----------------------------------------------|
| §1  | 8 sentinels in `sdk/errors`; service typed errors MUST wrap them  | depguard on `errors.New`/`fmt.Errorf` no-`%w`|
| §2  | Two-tier wrapping (leaf anchors; intermediate `: %w`; boundary handles) | `wrapcheck` linter + review            |
| §3  | `ToHTTPStatus` + `HandleErr(w, r, svc, err)` central helper        | sdk/errors + sdk/httpmw                      |
| §4  | `code` = `<service>.<suffix>`; custom suffixes via override helper | `HandleErr` enforces                         |
| §5  | `sdk/httpmw.Recoverer` overrides chi default; structured log + 500 envelope | depguard on chi.Recoverer        |
| §6  | English only initially; clients localize off `code`                | social                                       |
| §7  | Every error log line: `error` + `error.kind`                      | `sdk/log.ErrorAttrs` helper                  |
