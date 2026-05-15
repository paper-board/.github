# Observability Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative.
References: ADR-0005 (auth propagation, x-trace-id metadata), `paper-board/sdk/log`,
`paper-board/sdk/obs`.

This document fixes structured logging keys, OpenTelemetry exporter shape, trace propagation
across SSE, metrics emission, log levels, and sensitive-data redaction for every backend service.

---

## 1. Structured logging keys — pinned canonical set

### Rule

Every log line MUST be JSON via `sdk/log` and MUST use these canonical keys when the underlying
value is available. A service MUST NOT redefine a canonical key with different semantics.

| Key            | Type     | Source                                  | Required when                       |
|----------------|----------|-----------------------------------------|--------------------------------------|
| `service`      | string   | `sdk/log.New(w, service, level)`        | always                              |
| `request_id`   | string   | `chi.middleware.RequestID`              | inside HTTP handler                  |
| `trace_id`     | string   | OTel span context                       | OTel active                          |
| `span_id`      | string   | OTel span context                       | OTel active                          |
| `org_id`       | uuid     | auth ctx (`auth.org_id`)                | auth middleware ran                  |
| `user_id`      | uuid     | auth ctx (`auth.user_id`)               | auth ran in jwt mode                 |
| `api_key_id`   | uuid     | auth ctx (`auth.api_key_id`)            | auth ran in api-key mode             |
| `session_id`   | uuid     | per-request domain context              | request bound to a session          |
| `agent_id`     | uuid     | per-request domain context              | request bound to an agent           |
| `event_type`   | string   | structured emitter key                  | session_event lifecycle logs        |
| `error`        | string   | `slog.Any("error", err)`                | warn/error log                      |
| `error.kind`   | string   | sentinel name (error-handling.md §2)    | sentinel-typed errors               |
| `duration_ms`  | int      | timing                                  | request-scoped final log            |

Service-specific keys MUST be prefixed with the service name (e.g. `billing.invoice_id`,
`identity.api_key_scope`) to prevent semantic collision when logs cross services in Loki/Grafana.

### Helpers

`sdk/log/pkg.go` provides `log.Pkg(ctx)` which extracts canonical keys from context. The package
exposes context-binding helpers:

```go
func WithSpan(ctx context.Context, span trace.Span) context.Context  // sets trace_id + span_id
func WithSession(ctx context.Context, id uuid.UUID) context.Context
func WithAgent(ctx context.Context, id uuid.UUID) context.Context
```

`Pkg(ctx)` extracts every canonical key bound via these helpers.

### Enforcement

- Code review checklist: log lines MUST NOT redefine canonical keys.
- golangci-lint custom analyzer checks `slog` key strings against canonical list.
- service-template's example handler shows `log.Pkg(ctx).Info("...", "agent_id", id)`.

---

## 2. OpenTelemetry — OTLP/HTTP exporter

### Rule

Every service MUST initialize OTel via `sdk/obs.SetupOTel(serviceName, version)`. Exporter MUST
be **OTLP/HTTP** (not OTLP/gRPC) for traces and metrics.

### Endpoint configuration (see configuration.md)

| Env var                         | Type   | Default | Purpose                                              |
|---------------------------------|--------|---------|------------------------------------------------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT`   | string | `""`    | Full URL e.g. `http://otel-collector.observability:4318`. Empty disables export. |
| `OTEL_SERVICE_VERSION`          | string | `dev`   | semver or git sha                                    |
| `OTEL_TRACES_SAMPLER_ARG`       | float  | `1.0`   | Head sampling fraction. Tightened on high-volume routes when scale demands. |
| `OTEL_RESOURCE_ATTRIBUTES`      | string | `""`    | Extra resource attrs (e.g. `deployment.environment=staging`). |

Empty `OTEL_EXPORTER_OTLP_ENDPOINT` MUST result in a no-op exporter (so local docker-compose
doesn't fail on missing collector). It MUST NOT crash the service.

### Implementation contract (sdk/obs)

```go
// sdk/obs/otel.go
type Shutdown func(context.Context) error

// SetupOTel returns a tracer provider with batch span processor exporting to
// OTLP/HTTP, a meter provider exporting metrics to the same endpoint, and a
// W3C TraceContext propagator. If OTEL_EXPORTER_OTLP_ENDPOINT is empty, all
// providers are no-op (writes nothing, no error).
func SetupOTel(serviceName, version string) (Shutdown, error)
```

### Rejected alternatives

- **OTLP/gRPC** — needs HTTP/2 path through ingress; sdk/go.mod already pulls `otlptracehttp`,
  not the gRPC variant; switching later is a one-import change inside `sdk/obs`.
- **Jaeger / Zipkin direct exporters** — proprietary protocols; OTel Collector is the universal
  destination and translates downstream.

### Enforcement

- service-template wires `defer shutdown(ctx)` in `cmd/server/main.go`.
- Helm `values.yaml` ships `otelExporterOtlpEndpoint` ConfigMap entry pointing at the in-cluster
  collector.

---

## 3. Trace propagation — HTTP, gRPC, and SSE

### 3.1 HTTP (inbound)

`sdk/httpmw.OTel` (http-api-conventions.md §2 stage 3) MUST extract `traceparent` and `tracestate` headers using
the W3C TraceContext propagator and start the server span. Span name `<METHOD> <route_pattern>`
(e.g. `POST /v1/sessions/{id}/prompt`).

### 3.2 HTTP (outbound)

Outbound HTTP clients MUST be wrapped in `otelhttp.NewTransport`. The pattern, applied in service
constructors:

```go
httpClient := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
    Timeout:   30 * time.Second,
}
```

LLM clients (`agents/internal/llm/anthropic`), Stripe, and any other external HTTP MUST use this
pattern. Direct `http.DefaultClient` MUST NOT be used in production code paths.

### 3.3 gRPC (inbound + outbound)

gRPC servers MUST install `otelgrpc.NewServerHandler()` (statshandler API). Clients use
`otelgrpc.NewClientHandler()`. ADR-0005 already requires `x-trace-id` in metadata; the OTel
handler populates this automatically from the parent context.

### 3.4 SSE — special handling

#### Rule

- **Inbound**: handled by `sdk/httpmw.OTel` (same as non-SSE). One server span covers the entire
  HTTP response lifecycle. Name: `POST /v1/sessions/{id}/prompt`.
- **Outbound LLM call**: `r.Context()` MUST be passed to `llm.Stream(ctx, ...)`. The Anthropic
  client uses `otelhttp.NewTransport`, so each Anthropic round-trip becomes a child span
  automatically.
- **Per-SSE-event spans**: NO. One server span + one per LLM round-trip is the unit. Per-event
  spans flood Grafana for high-token streams (~100 events).
- **Persisting trace ids in events**: SSE-emitting services MUST persist `trace_id` on every
  event row (e.g. `session_events.trace_id text`), populated from the active span. Enables
  cross-system event ↔ trace correlation in audit views.

#### Rationale

W3C TraceContext is the only propagator the OTel SDK ships out-of-box; consistent with non-SSE
endpoints. Per-chunk spans are noise; per-LLM-call spans are the unit users actually look at.

### Enforcement

- Code review: outbound HTTP clients without `otelhttp.NewTransport` are rejected.
- service-template wires both server + client tracing in its example.

---

## 4. Metrics — OTel SDK in code, Collector exposes Prometheus

### Rule

Services MUST emit metrics via the OpenTelemetry SDK (`go.opentelemetry.io/otel/metric`). Services
MUST NOT expose a `/metrics` endpoint. The OTel Collector receives OTLP metrics and exposes
Prometheus-compatible scrape targets to whatever Grafana/Mimir/Cortex stack `paper-board/infra`
runs.

### Standard metric names (initial set)

| Metric                              | Type      | Labels                          | Emit from           |
|-------------------------------------|-----------|---------------------------------|----------------------|
| `http.server.request.duration`      | histogram | route, method, status_class     | `sdk/httpmw.Logger`  |
| `http.server.requests.in_flight`    | gauge     | route                           | `sdk/httpmw.Logger`  |
| `db.client.query.duration`          | histogram | operation (select/insert/...), table | `sdk/store` query hooks |
| `agents.llm.tokens_in`              | counter   | model                           | agents service       |
| `agents.llm.tokens_out`             | counter   | model                           | agents service       |
| `agents.llm.stream.duration`        | histogram | model, status                   | agents service       |

Service-specific metrics MUST be prefixed `<service>.` (e.g. `agents.`, `billing.`,
`identity.`). Cardinality constraints:

- Metric labels MUST NOT carry user-identifying values (`user_id`, `org_id`) — use exemplars
  instead.
- Route labels MUST use the chi route *pattern* (`/v1/sessions/{id}`), never the actual path.

### Rejected alternatives

- **Direct Prometheus client_golang** — duplicates OTel SDK in code; double accounting.
- **Per-service `/metrics` endpoint** — every service needs Prometheus scrape annotations,
  ServiceMonitor, RBAC. Pushing to Collector centralises this.

### Enforcement

- `sdk/httpmw.Logger` and `sdk/store` query hooks emit canonical histograms.
- service-template includes one custom counter example.

---

## 5. Sentry / error tracking

### Rule

Sentry (or equivalent crash-reporter) MUST NOT be added to services. Defer to a future revisit
once error triage becomes a bottleneck.

### Rationale

OTel + structured logs already capture every error with full ctx. Sentry adds subscription cost
plus a Go SDK dep across all 7 services for incremental UX (better stacktrace UI, dedup). At
solo→team-of-3 scale we read errors in Loki+Grafana directly. When demand arises, integration
would be a `slog.Handler` wrapper in `sdk/log` mirroring `slog.LevelError` records to Sentry.

---

## 6. Log level — INFO default, env override

### Rule

- Default: `INFO`.
- `LOG_LEVEL` env var (configuration.md) overrides: `debug | info | warn | error`. Validated
  via `validator/v10` `oneof=debug info warn error`.
- `DEBUG` MUST NOT be the default in any deployed environment (dev/staging/prod). Local
  docker-compose MAY set `LOG_LEVEL=debug`.
- `WARN` and `ERROR` MUST emit a `slog.Source` (file:line) attribute via
  `slog.HandlerOptions{AddSource: true}` for that level only.

### Test logging

`go test` runs MUST NOT print INFO/DEBUG noise. `sdk/testfixture.MuteLogger(t)` installs a logger
emitting only `ERROR` to `os.Stderr`. CLI tests can opt in to verbose with `go test -v`.

### Migrator binary

`migrator up` log lines are operationally useful; default INFO is correct. `MIGRATOR_LOG_LEVEL`
env MAY override.

### Enforcement

- `LOG_LEVEL` field in every service's `Config` struct (locked from Configuration §2 example).
- service-template wires `pblog.New(os.Stderr, "<service>", parseLevel(cfg.LogLevel))`.

---

## 7. Sensitive-data redaction

### Redaction rules

`sdk/log/redact.go` ships a `slog.Handler` wrapper. The wrapper MUST scan attribute string
values and redact these patterns:

| Pattern (regex)                                                | Replace with               | Reason                          |
|-----------------------------------------------------------------|----------------------------|----------------------------------|
| `sk-[A-Za-z0-9_-]{20,}`                                         | `sk-***`                   | Anthropic / OpenAI keys          |
| `Bearer [A-Za-z0-9._-]{20,}`                                    | `Bearer ***`               | JWTs                             |
| `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`                | `***@***`                  | emails (PII)                    |
| `\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}`                            | `**** **** **** ****`      | credit-card-shaped               |
| `postgres://[^:]+:[^@]+@`                                       | `postgres://***:***@`      | DB URLs                          |
| `Authorization: [^\s]+`                                          | `Authorization: ***`       | header dumps                     |

### Per-key denylist

Attribute keys named exactly `password`, `secret`, `api_key`, `token`, `authorization`,
`x_api_key`, `cookie` MUST have their value replaced with `***`, regardless of value content.

### Trade-offs

Regex-based redaction is **leaky**: false negatives on novel formats; false positives on innocent
strings matching the pattern (e.g. a base64 payload looking JWT-ish). This is a **defense layer,
not a guarantee**. The primary control remains: never `slog.Info("...", "password", req.Pwd)` in
the first place.

### Enforcement

- Redaction is default-on in `sdk/log.New`.
- Code review checklist line: "No raw struct dumps with secret fields in logs."
- `forbidigo` rule: attribute keys matching `password|secret|api_key|token|authorization` flagged
  unless paired with the redacting handler.

### Compliance note

When audit logs are persisted (e.g. `platform.audit_events`), the same redaction rules apply on
write — audit logs are not exempt. PII handling for the actual *body* of audit events is out of
scope here; covered in the platform service spec.

---

## 8. Summary

| §   | Rule                                                                | Enforcement                                  |
|-----|---------------------------------------------------------------------|----------------------------------------------|
| §1  | Pinned canonical log keys; `<service>.` prefix for service-specific | sdk/log + review                             |
| §2  | OTLP/HTTP exporter; single endpoint env var                         | sdk/obs                                      |
| §3  | W3C TraceContext via sdk/httpmw.OTel + otelhttp.NewTransport        | sdk/httpmw + review                          |
| §4  | OTel SDK in code; Collector exposes Prometheus; no `/metrics`       | sdk/httpmw + sdk/store hooks                 |
| §5  | No Sentry                                                           | social                                       |
| §6  | INFO default; `LOG_LEVEL` env; tests muted to ERROR                 | Config validate + sdk/testfixture            |
| §7  | Redaction (regex + key denylist) default-on                         | sdk/log                                      |
