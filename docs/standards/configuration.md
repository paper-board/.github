# Configuration Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative. References: ADR-0004, CLAUDE.md DB rules.

This document fixes how every backend service in `paper-board/{agents, identity, billing, platform,
runtime, gateway, compute}` reads, validates, and exposes runtime configuration.

---

## 1. Loader — `sdk/config` thin helper, env-only

### Rule

Every service MUST load configuration through the `paper-board/sdk/config` package. The loader
reads from environment variables only; flags and config files MUST NOT influence runtime behaviour.
The package binds env vars onto a service-defined `Config` struct via reflection over struct tags
and runs `validator/v10` on the bound struct before returning.

### Sketch — `sdk/config` API

```go
// sdk/config/config.go
package config

// Bind reads env vars onto cfg using `env:"…"` and `default:"…"` tags,
// then runs validator/v10 against `validate:"…"` tags.
// Returns wrapped error including all missing/invalid fields at once.
func Bind(cfg any) error

// MustBind panics with an actionable message if Bind fails.
// Used by cmd/<binary>/main.go where there is no recovery path.
func MustBind(cfg any)
```

### Rejected alternatives

- **`spf13/viper`** — heavy (~30 transitive deps), magical multi-source merge we do not use.
- **`knadh/koanf`** — closer to our needs but still over-featured for env-only deployment.
- **Inline `os.Getenv` per binary** — drifts; no precedence; help-text hidden across `main.go`
  files. The whole topic exists to retire this.

### Enforcement

- golangci-lint `forbidigo` rule: `os.Getenv` and `os.LookupEnv` MUST NOT appear outside
  `internal/config/` and `cmd/<binary>/main.go` (the latter only for trivial bootstrap before
  `config.MustBind`).
- `service-template` ships `internal/config/config.go` skeleton + ConfigMap manifest.

---

## 2. `Config` struct location

### Rule

Each service MUST define exactly one struct, `internal/config.Config`, populated by
`sdk/config.MustBind`. Both `cmd/server/main.go` and `cmd/migrator/main.go` MUST consume the
same struct — no duplicate env reads in the migrator binary.

### Example — target shape for `agents` (post-migration)

```go
// internal/config/config.go
package config

import (
    "time"

    sdkconfig "github.com/paper-board/sdk/config"
)

type Config struct {
    // --- Secrets (mounted from K8s Secret) ----------------------------------
    DatabaseURL    string `env:"DATABASE_URL"      validate:"required,url"`
    MigrationDBURL string `env:"MIGRATION_DB_URL"  validate:"required,url"`
    AnthropicKey   string `env:"ANTHROPIC_API_KEY"`

    // --- Non-secret config (mounted from K8s ConfigMap) ---------------------
    ServerPort   int           `env:"SERVER_PORT"     default:"8080"  validate:"gt=0"`
    LogLevel     string        `env:"LOG_LEVEL"       default:"info"  validate:"oneof=debug info warn error"`
    OTLPEndpoint string        `env:"OTEL_EXPORTER_OTLP_ENDPOINT" default:"" `
    DBPoolMax    int           `env:"DB_POOL_MAX"     default:"10"    validate:"gte=1,lte=100"`
    DBPoolMin    int           `env:"DB_POOL_MIN"     default:"2"     validate:"gte=0"`
    DBPoolMaxAge time.Duration `env:"DB_POOL_MAX_AGE" default:"1h"`
}

func Load() Config {
    var c Config
    sdkconfig.MustBind(&c)
    return c
}
```

### Enforcement

- service-template ships this skeleton (with service-specific fields).
- Code-review checklist: `cmd/server/main.go` and `cmd/migrator/main.go` MUST both consume
  `config.Load()`; no `os.Getenv` outside `internal/config`.

---

## 3. Validation — `go-playground/validator/v10`

### Rule

`Config` fields MUST be tagged with `validate:"…"`. `sdk/config.Bind` runs `validator/v10` after
binding and returns a single wrapped error listing every failure. Fields MUST validate at startup
(fail-fast). Validation MUST NOT happen lazily on first use.

The same library MUST be reused for HTTP request DTO validation (Topic 10F), so adding `validator/v10`
as a sdk/service dep is paid for twice over.

### Rejected alternatives

- **Hand-rolled `if cfg.X == 0 { return err }`** — repetitive, easy to forget a field, no error
  aggregation.
- **`go-ozzo/ozzo-validation`** — uneven adoption; tag-based form is less ergonomic than
  validator/v10.

### Enforcement

- `validator/v10` is a transitive dep of `sdk/config`.
- service-template wires `validate:"…"` on every required field.
- A new field added without a tag is allowed only when the value is genuinely optional and
  unconstrained.

---

## 4. Secrets vs ConfigMap separation

### Rule

Every `Config` field MUST be classified as **Secret** xor **ConfigMap** xor **built-in-default**.
The classification MUST be reflected in Helm:

- **Secret** values: mounted via `valueFrom.secretKeyRef`, one secret object per logical credential.
  Examples: `DATABASE_URL`, `MIGRATION_DB_URL`, `ANTHROPIC_API_KEY`, JWT signing key, Stripe webhook
  secret.
- **ConfigMap** values: mounted via `envFrom.configMapRef`, one ConfigMap per service.
  Examples: `LOG_LEVEL`, `SERVER_PORT`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `DB_POOL_MAX`, feature flags.
- **Built-in defaults**: live in `default:"…"` struct tags; never in Helm.

A single env var MUST NOT be sourced from both a Secret and a ConfigMap. Mixing makes audit logs
ambiguous about whether a credential was rotated or a feature flag was toggled.

### Rationale

K8s separates Secret and ConfigMap so that read access can be scoped differently (RBAC, audit,
encryption-at-rest). If we bypass that distinction (e.g. by stuffing `LOG_LEVEL` into the
service's app-db-url Secret), we forfeit the benefit and create surprising operations.

### Enforcement

- Helm chart linter (custom CI step): scan `templates/server-deployment.yaml`; assert each env var
  comes from at most one source kind.
- Code-review checklist line: "Is this a credential? → Secret. Is this a tunable? → ConfigMap."

---

## 5. Default precedence — env > built-in default

### Rule

The loader MUST resolve each field in this order:

1. Environment variable (whatever set it: K8s Secret, K8s ConfigMap, docker-compose, shell).
2. `default:"…"` struct tag.

Required fields (`validate:"required"`) MUST fail loading if both env and default are unset.

Flags and config files MUST NOT participate in precedence. Service binaries MAY accept positional or
flag args via `cobra` for one-shot operations (e.g. `migrator down 1`), but those flags MUST NOT
override `Config` fields.

### Rationale

Two-level precedence is the simplest scheme satisfying 12-factor. Adding flags or files multiplies
"where did this value come from" debugging without solving a problem in k8s deploy. `agents`'s
existing 3-env-var model already conforms.

### Enforcement

- `sdk/config.Bind` implementation contract: only env + default tags consulted; covered by sdk
  unit tests.

---

## 6. Hardcoded literals — what should move to Config

### Rule

A literal in source code MUST be moved into `Config` when it satisfies any of:

- Differs across environments (dev / staging / prod).
- Differs across deployments of the same env (replica count, pool size).
- Is a credential or external endpoint.
- Has been edited more than once across the service's history.

A literal MAY remain hardcoded when it is a protocol constant (HTTP status code, JSON field name)
or an algorithmic constant (hash size, retry-count proven unchanged).

---

## 7. Summary

| §   | Rule                                                              | Enforcement                                  |
|-----|-------------------------------------------------------------------|----------------------------------------------|
| §1  | Use `sdk/config` env-only loader                                  | sdk dep + `forbidigo` lint on `os.Getenv`    |
| §2  | One `internal/config.Config` struct, shared across binaries        | service-template + review checklist          |
| §3  | `validator/v10` tags; fail-fast at startup                         | sdk/config wraps validator                   |
| §4  | Secret xor ConfigMap per env var                                   | Helm CI linter + review checklist            |
| §5  | Precedence: env → built-in default; no flags, no files             | sdk/config contract + tests                  |
| §6  | Promote env-varying literals to Config                             | review checklist                             |
