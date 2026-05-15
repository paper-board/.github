# Testing Standard

Status: **Active**
RFC 2119 keywords (MUST / SHOULD / MAY) are normative.
References: go-service-layout §7 (co-located tests + build tag), database-conventions §7
(testcontainers + TRUNCATE).

This document fixes the four-layer test pyramid, coverage gates, mocking strategy, the
`sdk/testfixture` v1 API, and golden-file usage for every backend service.

---

## 1. Four-layer matrix

### Rule

Every service MUST organise tests into these layers and gate them by build tag where listed.

| Layer            | Location                                            | Build tag                | DB                       | External services        |
|------------------|-----------------------------------------------------|--------------------------|--------------------------|--------------------------|
| **Unit**         | `internal/<pkg>/*_test.go`                          | none                     | no                       | mocked                   |
| **Integration**  | `internal/store/*_integration_test.go` (and any other pkg needing DB) | `//go:build integration` | testcontainers Postgres  | mocked                   |
| **Service E2E**  | `cmd/server/server_e2e_test.go` per service         | `//go:build e2e`         | testcontainers Postgres  | mock LLM, mock identity  |
| **System E2E**   | `paper-board/infra/e2e/` (Tilt + Kind multi-service) | `//go:build e2e`         | real                     | real                     |

### Layer purposes

- **Unit**: pure logic, no I/O, fast (<1s per package). Tests `internal/core` business rules,
  helpers, parsers. Failures point at a specific function.
- **Integration**: store layer with real Postgres; sdk/testfixture spins testcontainer per package
  (db conventions §7). Catches SQL drift, sqlc-generated bindings, transaction edge cases.
- **Service E2E**: full `cmd/server` binary booted in-process; real DB, mocked downstream gRPC
  (identity, billing). Drives via real HTTP requests through chi + middleware chain. Catches
  middleware order regressions, error-envelope shape, SSE bugs, auth ctx flow.
- **System E2E**: multi-service (gateway + identity + agents + billing) over Kind cluster via
  Tilt; real Anthropic optional behind feature flag.

### Makefile targets

```makefile
test:
	go test -race -count=1 ./...

test-integration:
	go test -race -count=1 -tags=integration ./...

test-e2e:
	go test -race -count=1 -tags=e2e ./cmd/server/...

cover:
	go test -race -coverprofile=cover.out ./...
	go tool cover -func=cover.out

cover-check: cover
	@./scripts/cover-check.sh   # gate
```

### Enforcement

- service-template ships all four targets and a stub `_test.go` per layer.
- CI runs `make test` and `make test-integration` on every PR; `make test-e2e` on PRs touching
  `cmd/`, `internal/api/`, or `internal/middleware/`.

---

## 2. Unit test style — table-driven default

### Rule

Tests SHOULD be table-driven when there are 3+ comparable cases. `t.Parallel()` allowed in unit
tests by default; integration tests MUST opt out unless read-only.

### Pattern

```go
func TestParseSlug(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {"valid", "my-agent", "my-agent", false},
        {"empty", "", "", true},
        {"upper", "MyAgent", "", true},
        {"too long", strings.Repeat("a", 65), "", true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := ParseSlug(tt.input)
            if (err != nil) != tt.wantErr {
                t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
            }
            if got != tt.want {
                t.Errorf("got %q, want %q", got, tt.want)
            }
        })
    }
}
```

### Test-package style

Use `package x_test` (external) by default; `package x` (internal) only when testing unexported
helpers. golangci-lint `testpackage` linter enforces this (locked from go-service-layout §7).

### Naming

Test functions: `Test<Type>_<Scenario>` for methods, `Test<Function>_<Scenario>` for free
functions. Subtests use plain prose names (`"valid"`, `"too long"`), not Go-identifier-shaped
strings.

---

## 3. Coverage gates

### Rule

Coverage MUST be measured per-package and gated against this table. CI fails on regression below
the target. Targets are static once a service is mature; ramp-up trajectories during early
development live in the roadmap, not here.

| Package                         | Target |
|---------------------------------|--------|
| `internal/api`                  | 80%    |
| `internal/core`                 | 90%    |
| `internal/store`                | 80%    |
| `internal/<adapter>` (e.g. llm) | 75%    |
| `cmd/`                          | not measured |

### Rationale

- `internal/core` carries domain logic with no external deps; high coverage is cheap and prevents
  silent regressions.
- `internal/api` mostly wires + DTO; 75% is enough.
- `internal/store` SQL is verified by integration tests; coverage there is meaningful.
- Adapters mock external services; over-testing the mock seam wastes effort.
- `cmd/` is wiring; service E2E exercises it.

### Implementation

`scripts/cover-check.sh` (shipped by service-template):

```bash
#!/usr/bin/env bash
set -euo pipefail

go test -coverprofile=cover.out ./internal/...
go tool cover -func=cover.out > cover.txt

declare -A targets=(
  ["internal/api"]=50
  ["internal/core"]=70
  ["internal/store"]=60
)

for pkg in "${!targets[@]}"; do
    pct=$(grep -E "^github.com/paper-board/<svc>/${pkg}\b" cover.txt | grep total: | awk '{print $3}' | tr -d %)
    if (( $(echo "$pct < ${targets[$pkg]}" | bc -l) )); then
        echo "FAIL: $pkg coverage $pct% < ${targets[$pkg]}%"; exit 1
    fi
done
```

### Enforcement

- `make cover-check` in CI fails build below target.
- PR template includes "coverage maintained" checklist line.

---

## 4. Mocking strategy — hand-rolled by default

### Rule

Mocks for adapter interfaces (LLM, identity gRPC client, billing client, SMTP, Stripe) MUST be
hand-rolled in `internal/<adapter>/mock/`. Generated mocks (`mockery`) are permitted only for the
sqlc `Querier` interface, which is too large to hand-roll.

### Hand-rolled precedent

`agents/internal/llm/mock/client.go` is the canonical pattern:

```go
// Package mock provides a deterministic LLM client for tests.
package mock

type Client struct {
    ResponseChunks []string
    TokensIn       int
    TokensOut      int
    FailErr        error
}

func (c *Client) Stream(ctx context.Context, model, system string, msgs []llm.Message) (<-chan llm.StreamChunk, error) {
    // ... deterministic chunk emission
}

func FailingClient(err error) *Client { ... }
```

Properties:
- Behaviour is data-driven (struct fields), not call-recording.
- One file per adapter; co-located with the impl variants under `internal/<adapter>/mock/`.
- Used both by service E2E and local docker-compose (when `ANTHROPIC_API_KEY` unset; see
  `cmd/server/main.go:64-72`).

### Generated mocks — sqlc Querier only

`mockery` config in `service-template`:

```yaml
# .mockery.yaml
with-expecter: true
packages:
  github.com/paper-board/<svc>/internal/store/queries:
    interfaces:
      Querier:
        config:
          dir: internal/store/queries/mocks
          outpkg: mocks
```

`make mocks` regenerates; CI verifies with `make mocks-verify`.

### Rejected alternatives

- **`gomock` / `go.uber.org/mock`** — verbose `.EXPECT()` chains; opaque failures.
- **`testify/mock`** — runtime expectation assertions; failures often unclear.

Both are blocked by golangci-lint `depguard` for service code.

### Enforcement

- depguard rules block `gomock`, `go.uber.org/mock`, `testify/mock` outside `internal/store/queries/mocks/`.
- service-template ships hand-rolled mock for the LLM adapter.

---

## 5. `sdk/testfixture` v1 API

### Frozen ship list

```go
// sdk/testfixture/postgres.go
func MustStartPostgres(
    m *testing.M, embedFS embed.FS, schema string, advisoryLock int,
) *pgxpool.Pool
// Boots a postgres testcontainer, applies the service's embedded migrations,
// returns a pool. Cleans up via m.Run() exit.

// sdk/testfixture/db.go
func Truncate(t *testing.T, pool *pgxpool.Pool, schema string)
// TRUNCATE every table in schema with RESTART IDENTITY CASCADE.

func LoadFixtures(t *testing.T, pool *pgxpool.Pool, fixtureName string)
// Loads testdata/<fixtureName>.sql or testdata/<fixtureName>.yaml relative to caller.

// sdk/testfixture/log.go
func MuteLogger(t *testing.T)
// Installs a slog handler emitting only ERROR-level records to t.Log.
// Restored to slog.Default() at t.Cleanup.

type LogCapture struct { ... }
func CaptureLogs(t *testing.T) *LogCapture
// Returns a helper for asserting log lines emitted during the test.
//   c.Contains(t, "agent_id", id.String())
//   c.HasError(t, "validation_failed")

// sdk/testfixture/build.go — generic builder helper
type Opt[T any] func(*T)

func Build[T any](base T, opts ...Opt[T]) T
// Generic builder. base provides defaults; opts override. Usage in service:
//   func Agent(opts ...testfixture.Opt[core.Agent]) *core.Agent { ... }

// sdk/testfixture/golden.go
func AssertGolden(t *testing.T, got []byte, file string)
// Compares got to testdata/golden/<file>. -update rewrites.
```

### Why service-local builders, not sdk-shipped builders

Domain types live in `internal/core/` of each service (go-service-layout §2). `sdk/testfixture`
MUST NOT import service-specific packages — it is a shared library. The pattern:

```go
// agents/internal/testfixture/agents.go
package testfixture

import (
    sdkfx "github.com/paper-board/sdk/testfixture"
    "github.com/paper-board/agents/internal/core"
)

func Agent(opts ...sdkfx.Opt[core.Agent]) *core.Agent {
    base := core.Agent{
        ID: uuid.New(),
        OrgID: DefaultOrgID,
        Name: "test-agent",
        Slug: "test-agent",
        Model: "claude-opus-4-7",
    }
    out := sdkfx.Build(base, opts...)
    return &out
}

// usage in tests:
//   a := testfixture.Agent(WithSlug("foo"), WithModel("claude-haiku-4-5"))
```

`WithX` opts are co-located with the type (`agents.go`).

### Enforcement

- service-template ships `internal/testfixture/` skeleton.

---

## 6. Golden-file testing

### Rule

Golden files MAY be used for outputs that are:

1. Verbose (long), AND
2. Stable shape (a shape regression is a bug, not a feature change), AND
3. Painful to assert field-by-field.

Recommended for: SSE event streams, generated OpenAPI specs, large JSON DTOs from list endpoints.
Forbidden for: pure-function output already covered by table-driven asserts; error sentinels;
short fixed strings.

### Pattern

```go
func TestSSEStream_Basic(t *testing.T) {
    pool := testfixture.MustStartPostgres(...)
    mockLLM := &llmmock.Client{ResponseChunks: []string{"Hello", " world"}, TokensIn: 5, TokensOut: 2}

    h := api.New(store.New(pool), mockLLM)
    req := httptest.NewRequest("POST", "/v1/sessions/.../prompt", body)
    w := httptest.NewRecorder()
    h.ServeHTTP(w, req)

    sdkfx.AssertGolden(t, w.Body.Bytes(), "sse_stream_basic.txt")
}
```

`testdata/golden/sse_stream_basic.txt`:

```
event: text
data: Hello

event: text
data:  world

event: done
data: {"tokens_in":5,"tokens_out":2}

```

### Determinism

Golden tests MUST run deterministically. Stamp UUIDs, timestamps, durations through fixed seeds
or test-time freezing. `agents/internal/llm/mock/client.go` already emits deterministic chunks
when `ResponseChunks` is set.

### `-update` flag protocol

```
go test -tags=integration -update ./internal/api/...
```

Re-writes golden files. Re-write MUST be reviewed in the PR diff. Reviewer checks:

- Does the diff reflect a real, intentional change?
- Or is this an accidental capture of test pollution (random UUID, timestamp drift)?

### Enforcement

- service-template includes one SSE golden test exemplar.

---

## 7. Test data — fixtures + builders

### Where do fixtures live

```
internal/<pkg>/testdata/
├── golden/                    # AssertGolden targets
│   ├── sse_stream_basic.txt
│   └── openapi_v1.json
├── fixtures/                  # LoadFixtures targets
│   ├── seed_agents.sql
│   └── seed_sessions.yaml
└── input/                     # raw inputs (e.g. mock LLM transcripts)
    └── anthropic_response_1.json
```

`testdata/` is Go-special (not built into binary). Sub-folders allow categorisation.

### Builder vs fixture choice

- **Builder** (`testfixture.Agent(opts...)`) when the test needs a *minimal* agent with one field
  varied — most cases.
- **Fixture file** (`LoadFixtures(t, pool, "seed_agents")`) when the test needs a *realistic*
  multi-row state (e.g. 50 agents with mixed deletion timestamps to test list pagination).

---

## 8. Summary

| §   | Rule                                                        | Enforcement                                  |
|-----|-------------------------------------------------------------|----------------------------------------------|
| §1  | 4-layer matrix; build tags `integration`/`e2e`              | service-template Makefile + CI               |
| §2  | Table-driven default; `t.Parallel()` in unit                | review                                       |
| §3  | Coverage gates per package; CI fails on regression          | `make cover-check` script                    |
| §4  | Hand-rolled mocks; mockery only for sqlc Querier            | depguard + service-template                  |
| §5  | `sdk/testfixture` v1 API frozen; service-local builders     | sdk/testfixture                              |
| §6  | Golden files for SSE/OpenAPI/large DTOs; `-update` flag     | sdk + review                                 |
| §7  | `testdata/{golden,fixtures,input}/` layout                  | service-template                             |
