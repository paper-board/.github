# Go Coding Conventions

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative.
References: ADR-0008 (commit/license/style), CLAUDE.md (style).

This document fixes dependency injection shape, lint configuration, naming, formatting, complexity
limits, and (especially) the comment policy for every backend service.

---

## 1. Dependency injection — manual constructor, six fixed phases

### Rule

Wiring lives in `cmd/<binary>/main.go`. Manual constructor injection only — no `wire`, no `fx`,
no reflection-driven containers. The phase order is locked.

### Six phases

```go
func main() {
    // 1. Config
    cfg := config.Load()

    // 2. Log + Observability
    logger := pblog.New(os.Stderr, "<svc>", parseLevel(cfg.LogLevel))
    pblog.SetDefault(logger)
    shutdown, err := obs.SetupOTel("<svc>", cfg.ServiceVersion)
    must(err)
    defer shutdown(context.Background())

    // 3. Context
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    // 4. Persistence (pool ownership)
    pool := store.MustConnect(ctx, cfg)
    defer pool.Close()
    st := store.New(pool)

    // 5. Outbound adapters
    llmClient := llmadapter.Build(cfg)
    identityClient := identityadapter.Build(cfg)

    // 6. Domain + transport, then run
    svc := core.NewService(st, llmClient, identityClient)
    handler := api.New(svc, cfg)
    runHTTPServer(ctx, logger, handler, cfg.ServerPort)
}
```

### Rationale

`wire` codegen and `fx` reflection are over-engineering at our scale (≤7 services, each ~5 wires).
Manual construction is grep-able, survives refactors, and stays a junior-readable script. Pinning
phase order eliminates "where do I put this?" reviews.

### Rejected alternatives

- **`google/wire`** — codegen step + magic; failure modes opaque.
- **`uber/fx`** — runtime DI graph; over-spec for ≤5 wires per service.
- **Service-locator pattern** (global registry) — hides dependencies; defeats compile-time safety.

### Enforcement

- `service-template` ships exactly this skeleton with a stub for each phase.
- Code review: PR touching `cmd/server/main.go` MUST follow the 6-phase order.
- `golangci-lint` `funlen` setting allows `main` up to 80 lines (tighten if exceeded).

---

## 2. Comment policy — strict, enforced

### Default

**No comment.** A function with a clear name and small body needs no commentary. The cost of a
comment is non-zero: reviewers must check it stays true, and stale comments lie.

### Allowed comments — exhaustive list

A comment is permitted only if it falls into one of these six categories:

1. **Public-API godoc** on every exported package, type, function, variable, constant. One
   sentence summary, MUST start with the identifier name.
   ```go
   // Wrap annotates a sentinel with context; the sentinel survives errors.Is.
   func Wrap(sentinel error, msg string, kvs ...any) error
   ```

2. **WHY non-obvious**: the reason is not derivable from reading the code.
   ```go
   // pgx prepared-statement cache must be off when DATABASE_URL points at PgBouncer
   // transaction-pool mode (port 6432); statements are evicted between calls otherwise.
   cfg.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
   ```

3. **Invariant** the type relies on but the code can't enforce locally.
   ```go
   // SequenceNumber is monotonic per session_id and gap-free.
   // Enforced by COALESCE((SELECT MAX(...)+1)) in AppendSessionEvent.
   ```

4. **Workaround with citation**: ticket, RFC, or postgres bug number.
   ```go
   // Postgres < 15 returns 0 rows on empty IN list; we filter upstream.
   // https://www.postgresql.org/docs/15/release-15.html
   ```

5. **Trap warning**: code that *looks* wrong but is intentional.
   ```go
   // Intentional: status filter applied after pagination cursor decode,
   // because the cursor encodes pre-filter row position.
   ```

6. **TODO with concrete trigger**: only the tagged form is permitted. Trigger MUST be
   resolvable — an issue number, a date, a named milestone, or a condition (not a phase
   number).
   ```go
   // TODO(#123): replace DefaultOrgID with auth-extracted org.
   // TODO(once-identity-ships): wire JWT verification.
   // TODO(2026-12-01): drop legacy header.
   ```

### Banned comments — exhaustive list

These MUST NOT appear in any service or sdk code:

1. **WHAT comments** that paraphrase the code:
   ```go
   // BAD
   // Increment the counter
   counter++

   // BAD
   // CreateAgent creates an agent in the database and returns it
   func (s *Store) CreateAgent(...) {...}
   ```

2. **Section dividers** decorating files:
   ```go
   // BAD — current `agents/internal/store/store.go` has these; remove in migration
   // ─────────────────────────────────────────────────────────────────────────────
   // Agent
   // ─────────────────────────────────────────────────────────────────────────────
   ```

3. **Caller / task references** that rot:
   ```go
   // BAD
   // Used by the streamPrompt handler in api.go
   // Added for issue #42, ticket BLR-1234
   // Per request from billing team 2026-04-15
   ```

4. **Removed-code marker comments**:
   ```go
   // BAD
   // (formerly: validateOrgID — moved to identity service)
   ```

5. **AI-style preamble** with numbered bullets restating the function body:
   ```go
   // BAD
   // This function:
   //   1. Validates input
   //   2. Persists to DB
   //   3. Emits event
   // Returns the created agent or an error.
   func CreateAgent(...) {...}
   ```

6. **Parameter / return restatement** that adds nothing the signature doesn't already say:
   ```go
   // BAD
   // ctx: the context
   // id: the agent UUID
   // Returns: pointer to agent, error if not found
   func GetAgent(ctx context.Context, id uuid.UUID) (*Agent, error)
   ```

7. **Out-of-date comments**: if the comment lies, delete it; do not keep "outdated but historical."

### Length rules

- Inline WHY/invariant/trap comment: **≤ 1 line, ≤ 100 chars**, or up to 2-3 short lines if a
  citation URL needs its own line.
- godoc on exported symbol: **one sentence summary**, optionally followed by 1-2 clarifying lines.
- Multi-paragraph comments allowed **only** in `doc.go` for package-level documentation.
- Plain `// TODO` (no trigger tag) MUST be rejected by review.

### Enforcement

- `revive` `package-comments` + `exported` rules require godoc on exported symbols.
- Custom golangci-lint analyzer flags banned patterns: section dividers (`// ──`), plain
  `// TODO`, multi-line `// 1.` / `// 2.` lists in non-package docs.
- Code-review checklist line: *"Did you add a comment? Is it godoc, WHY, invariant, trap,
  workaround, or trigger-tagged TODO? Else delete."*
- AI-pair-programming guidance (CLAUDE.md addition): when generating Go code, default no
  comments; prompt before adding.

---

## 3. golangci-lint v2 configuration — shared

### Rule

Each service repo MUST ship a root-level `.golangci.yml` referencing the shared baseline at
`paper-board/.github/golangci.yml`. golangci-lint v2.x is the locked major version.

### Shared baseline (paper-board/.github/golangci.yml)

```yaml
version: "2"

run:
  timeout: 5m

linters:
  default: none
  enable:
    - errcheck
    - govet
    - staticcheck         # absorbs unused, unconvert
    - revive
    - gocyclo
    - depguard
    - forbidigo
    - wrapcheck
    - bodyclose
    - testpackage
    - gosec
    - misspell
    - unparam
    - sqlclosecheck
    - ineffassign
    - exhaustive
  settings:
    gocyclo:
      min-complexity: 15
    revive:
      rules:
        - { name: exported, severity: error }
        - { name: package-comments, severity: error }
        - { name: unused-parameter, disabled: true }
    gosec:
      excludes:
        - G104   # already covered by errcheck
    depguard:
      rules:
        no-http-routers-in-store:
          list-mode: lax
          files: ["**/internal/store/**/*.go"]
          deny:
            - { pkg: "github.com/go-chi/chi", desc: "use of HTTP routers in store layer banned" }
        no-fiber:
          list-mode: lax
          files: ["**/*.go"]
          deny:
            - { pkg: "github.com/gofiber/fiber", desc: "chi/v5 only (http-api §1)" }
        no-database-sql:
          list-mode: lax
          files: ["**/internal/store/**/*.go"]
          deny:
            - { pkg: "database/sql", desc: "pgx/v5 only (db §1)" }
            - { pkg: "github.com/lib/pq", desc: "pgx/v5 only (db §1)" }
            - { pkg: "github.com/jmoiron/sqlx", desc: "pgx/v5 only (db §1)" }
        no-mock-frameworks:
          list-mode: lax
          files: ["**/*.go"]
          deny:
            - { pkg: "github.com/golang/mock", desc: "hand-rolled mocks (testing §4)" }
            - { pkg: "go.uber.org/mock", desc: "hand-rolled mocks (testing §4)" }
            - { pkg: "github.com/stretchr/testify/mock", desc: "hand-rolled mocks (testing §4)" }
        no-direct-getenv:
          list-mode: lax
          files:
            - "!**/internal/config/**"
            - "!**/cmd/**/main.go"
          deny:
            - { pkg: "os", desc: "use sdk/config; os.Getenv allowed only in internal/config and cmd/*/main.go" }
    forbidigo:
      forbid:
        - { pattern: '^os\.Getenv$', msg: "use sdk/config (config §1)" }
        - { pattern: '^os\.LookupEnv$', msg: "use sdk/config (config §1)" }
        - { pattern: '^errors\.New$', msg: "wrap an sdk/errors sentinel (error-handling §2)" }
        - { pattern: '^http\.DefaultClient$', msg: "use sdk/httpclient.Default (cross-cutting §10C)" }

formatters:
  enable:
    - gofmt
    - goimports
  settings:
    goimports:
      local-prefixes:
        - github.com/paper-board

issues:
  max-same-issues: 0
  max-issues-per-linter: 0
```

### Per-service `.golangci.yml`

```yaml
version: "2"
include:
  - "https://raw.githubusercontent.com/paper-board/.github/main/golangci.yml"
linters:
  settings:
    forbidigo:
      forbid:
        # service-specific exceptions go here
```

### Notes on v2 differences from v1

- `version: "2"` required at top.
- `formatters` is a separate section from `linters` — `gofmt`, `goimports`, `gci` moved.
- `unused`, `unconvert` rolled into `staticcheck`.
- Many linter `enable-all`/`disable-all` flags replaced by `default: none|fast|all|standard`.
- `depguard` config schema simplified (rule names → `list-mode` + `files` + `deny`).

### Enforcement

- service-template ships per-service `.golangci.yml` with `include:` reference.
- CI step `make lint` runs `golangci-lint run --config=.golangci.yml ./...`.

---

## 4. Naming + formatting

### 4.1 Identifier conventions

| Identifier            | Convention                              | Example                           |
|-----------------------|-----------------------------------------|------------------------------------|
| Go package            | lowercase, single word, no underscores  | `store`, `httpmw`, `agentrepo`     |
| Go exported type      | PascalCase                              | `Agent`, `Session`                 |
| Go exported func/var  | PascalCase                              | `MustConnect`, `DefaultOrgID`      |
| Go unexported         | camelCase                               | `writeJSON`, `parseLevel`          |
| Acronyms              | all-caps in identifiers (Go style)       | `OrgID`, `URL`, `APIKeyID`         |
| File name             | snake_case `_test.go` for tests         | `agent_service.go`, `agents_test.go` |
| Wire JSON field       | lowerCamel (http-api §7)                 | `orgId`, `createdAt`               |
| Log attribute key     | snake_case (observability §1)            | `org_id`, `request_id`             |
| SQL column            | snake_case (db §5)                       | `org_id`, `created_at`             |
| Migration filename    | `NNNNNN_<snake_case>.up.sql` (db §5)     | `000001_minimal.up.sql`            |

### 4.2 Import grouping

`goimports -local github.com/paper-board` produces three groups separated by blank lines:

```go
import (
    "context"
    "fmt"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/paper-board/agents/internal/core"
    "github.com/paper-board/sdk/log"
)
```

### 4.3 File-organization order

Within a Go file, declarations SHOULD appear in this order:

1. Package documentation (`// Package x ...`).
2. `import (...)`.
3. Constants (`const`).
4. Variables (`var`).
5. Type declarations.
6. Constructor (`New`, `MustConnect`).
7. Methods on the constructed type.
8. Free functions.
9. Helper / unexported functions.

`go fmt` does not enforce this; reviewers do.

---

## 5. Complexity + size limits

### 5.1 Cyclomatic complexity

`gocyclo` threshold **15**. Violations refactor into helper functions or table-driven dispatch.

### 5.2 Function length

`funlen` 80 lines including signature and braces. Exceptions:

- `cmd/<binary>/main.go::main` — phase-ordered wiring, allowed up to 80 lines (effectively the
  cap is the phase count).
- Generated code (sqlc, mockery) — exempt.

### 5.3 File length

Soft target: ≤ 400 lines per file. Above that, split — typically per-aggregate, per-handler, or
per-concern. Hard fail: 800 lines.

`agents/internal/store/store.go` is 224 today; splitting it into `agents.go`, `sessions.go`,
`events.go` (db §3) sets the precedent.

---

## 5b. Time — UTC always, injectable clock

### Rule

- All timestamps MUST be UTC at storage and on the wire. Migrations use `timestamptz` (db §5);
  Go code uses `time.Now().UTC()` whenever a "now" is needed for persistence or comparison.
- Plain `time.Now()` (without `.UTC()`) MAY be used only for elapsed-time measurement (`time.Since`,
  metric histograms) where the value never crosses an API/SQL boundary.
- Tests requiring time control MUST use `sdk/clock.Now()`, an injectable clock that returns a
  frozen value when `clock.Set(t)` is called from a `_test.go`. Production code calls
  `clock.Now()` instead of `time.Now().UTC()`.

### Sketch — `sdk/clock`

```go
// sdk/clock/clock.go
package clock

var nowFunc = func() time.Time { return time.Now().UTC() }

func Now() time.Time { return nowFunc() }

// Set replaces the clock for the duration of a test. Restore via t.Cleanup.
func Set(t *testing.T, fixed time.Time) {
    prev := nowFunc
    nowFunc = func() time.Time { return fixed }
    t.Cleanup(func() { nowFunc = prev })
}
```

### Enforcement

- golangci-lint `forbidigo` rule:
  `^time\.Now\(\)$` flagged outside `sdk/clock` and metric-emitter call sites.
- Code review: any `time.Now()` not followed by `.UTC()` MUST justify the elapsed-time exception.

---

## 5c. Outbound HTTP client — `sdk/httpclient.Default`

### Rule

Outbound HTTP calls MUST use the factory `sdk/httpclient.Default(name)` rather than
`http.DefaultClient` or hand-rolled `&http.Client{}`. The factory wires:

- `otelhttp.NewTransport(http.DefaultTransport)` — observability §3 trace propagation.
- 30s per-request timeout (`http.Client.Timeout = 30s`).
- Configurable per-call timeout via `ctx` deadlines (LLM streams use 5min ctx deadlines).
- `cenkalti/backoff/v4` retry wrapper for 5xx + connection errors (3 attempts, exponential).
- A `name` label that becomes the metric `http.client.request.duration{client=<name>}` axis.

### Sketch

```go
// sdk/httpclient/client.go
func Default(name string) *http.Client {
    return &http.Client{
        Transport: otelhttp.NewTransport(
            retry.NewTransport(http.DefaultTransport, retry.Config{
                MaxAttempts: 3,
                BaseBackoff: 200 * time.Millisecond,
            }),
            otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
                return fmt.Sprintf("HTTP %s %s", r.Method, name)
            }),
        ),
        Timeout: 30 * time.Second,
    }
}
```

### Adapter usage

```go
// agents/internal/llm/anthropic/client.go
type Client struct {
    http *http.Client
    key  string
}

func New(key string) *Client {
    return &Client{http: httpclient.Default("anthropic"), key: key}
}
```

### Enforcement

- golangci-lint `forbidigo`: `^http\.DefaultClient$` blocked everywhere; `^&http\.Client\{`
  blocked outside `sdk/httpclient/`.

---

## 6. Logging + error idioms (cross-reference)

- Always use `pblog.Pkg(ctx)` not `slog.Default()` directly (observability §1).
- Always wrap leaf errors with `errors.Wrap(sentinel, ...)` or pass-through with
  `fmt.Errorf("...: %w", err)` (error-handling §2).
- Boundary handlers call `httpmw.HandleErr(w, r, "<svc>", err)` (error-handling §3); never
  hand-write `w.WriteHeader(400)` + `json.Encode`.

---

## 7. Test-only conventions (cross-reference)

- Test packages MUST be `<pkg>_test` external (`testpackage` linter); internal `<pkg>` only when
  testing unexported helpers (testing §2).
- Table-driven default for 3+ comparable cases (testing §2).
- `t.Parallel()` allowed in unit tests; opt-out in integration unless read-only (testing §1).

---

## 8. Commit messages

Locked by ADR-0008: Conventional Commits + commitlint + release-please.

```text
<type>(<scope>): <subject>

[body]

[footer]
```

`<type>` ∈ `feat | fix | refactor | docs | test | chore | build | ci | perf`.
`<scope>` is the affected component (e.g. `agents`, `sdk/config`, `helm`).

---

## 9. Summary

| §   | Rule                                                                | Enforcement                              |
|-----|---------------------------------------------------------------------|-------------------------------------------|
| §1  | Manual constructor DI; six-phase `cmd/server/main.go` skeleton      | service-template + review                 |
| §2  | Comment policy: 6 allowed forms, 7 banned; godoc one-sentence rule  | revive + custom analyzer                  |
| §3  | golangci-lint v2; shared `paper-board/.github/golangci.yml`         | CI `make lint`                            |
| §4  | Identifier + import + file-org conventions                          | goimports + `go fmt` + review             |
| §5  | gocyclo 15; funlen 80; soft file 400 / hard 800                     | golangci-lint + review                    |
| §8  | Conventional Commits (ADR-0008)                                     | commitlint + release-please               |
