# Template-drift allowlist

Companion document to `.github/workflows/template-drift.yml` and
`scripts/compare-template.sh`. Describes the comparator's two-tier model
and per-service exemptions.

## How drift CI works

Each night `template-drift.yml` clones `paper-board/service-template@main`
into `rendered/`, runs its `init.sh` with the matrix entry's `SVC`,
`ADVISORY_LOCK_ID`, `PORT`, then applies any per-service post-render
overrides (currently just the `enable-e2e: true` flip for services with an
E2E suite). The rendered tree is then diffed against the service repo by
`scripts/compare-template.sh`, which classifies every monitored path:

| Tier | Semantics              | Comparator behavior                                   |
|------|------------------------|-------------------------------------------------------|
| 1    | exact content match    | Byte-diff vs rendered template; mismatch = drift      |
| 2    | presence-only          | Path must exist in service; content may diverge       |
| 3    | implicit (everything else) | Unchecked; services own their domain code        |

`compare-template.sh` exits non-zero on any tier-1 or tier-2 violation.
The workflow then opens (or appends to an open) issue titled
`drift: <service> diverges from service-template` in `paper-board/.github`.

## Tier 1 — exact match

These files are pure-skeleton in the template; no service should ever need
to edit them away from the rendered baseline. If you find yourself wanting
to diverge, propose a template change instead.

- `internal/middleware/middleware.go`
- `migrations/embed.go`
- `Dockerfile`
- `.github/workflows/release.yml`
- `.github/workflows/ci.yml` (after `enable-e2e` flip)

## Tier 2 — presence-only

Service-specific content lives behind these paths; the comparator only
checks existence. The list mirrors `service-template`'s post-init layout.

- `Makefile`
- `.golangci.yml`
- `docker-compose.yaml`
- `sqlc.yaml`
- `cmd/migrator/main.go`
- `cmd/server/main.go`
- `internal/api/api.go`
- `internal/core` (directory)
- `internal/config/config.go`
- `internal/store/store.go`
- `scripts/cover-check.sh`
- `helm/<svc>/Chart.yaml`
- `helm/<svc>/values.yaml`
- `helm/<svc>/templates/{_helpers.tpl,migrator-job.yaml,server-deployment.yaml,server-service.yaml,server-configmap.yaml}`
- `migrations/schema/000001_*.up.sql` (glob; descriptive suffix is service-local)
- `migrations/schema/000001_*.down.sql`

## Per-service post-render overrides

Adjustments applied to the rendered template **before** diffing. These
are intentional service-level decisions, not drift.

| Service  | Override                                         |
|----------|--------------------------------------------------|
| agents   | `enable-e2e: true` in `.github/workflows/ci.yml` |
| identity | (none — straight rendered template)              |

Add new entries to the matrix in `template-drift.yml` and document the
override here.

## Known divergences (open drift)

Tracked as GitHub issues; resolution updates this section.

| Service | Path                          | Drift                                                                     | Tracked         |
|---------|-------------------------------|---------------------------------------------------------------------------|-----------------|
| agents  | `.github/workflows/release.yml` | Missing the cosign+SBOM WARNING comment block (added to template post-Task 31) | issue (auto-filed by drift CI on first run) |

When a drift item is intentionally permanent, move it into a new
**"Permanent exemptions"** table below and update `compare-template.sh`
to skip it.

## How to add a new service

1. Open the service repo by cloning `service-template` and running
   `init.sh SVC=<svc> ADVISORY_LOCK_ID=<n> PORT=<p>` (see template `README.md`).
2. Append a matrix entry to `template-drift.yml`:
   ```yaml
   - service: <svc>
     advisory_lock_id: <n>
     port: <p>
     enable_e2e: <true|false>
   ```
3. If the service ships any post-render override beyond `enable-e2e`, add
   the corresponding `sed` line to the workflow's "Apply per-service
   overrides" step and document it under "Per-service post-render overrides".

## How to update the comparator

Tier-1/Tier-2 changes go in `scripts/compare-template.sh`. After editing,
run locally against any service:

```sh
# 1. render template
cp -r ~/Projects/paper-board/service-template /tmp/rendered
cd /tmp/rendered && rm -rf .git
SVC=agents ADVISORY_LOCK_ID=3 PORT=8080 ./init.sh
sed -i.bak 's|enable-e2e: false|enable-e2e: true|' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak

# 2. compare
~/Projects/paper-board/.github/scripts/compare-template.sh \
  --template /tmp/rendered \
  --service ~/Projects/paper-board/agents \
  --service-name agents
```

Drift output is human-readable markdown, suitable for direct paste into a
GitHub issue.
