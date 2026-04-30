# Contributing to paper-board

Welcome! paper-board is multi-repo. This guide covers cross-repo conventions; per-repo specifics are in each repo's README.

## Local Development

### Prerequisites

- Go 1.26+
- Docker + Docker Compose
- kubectl + Helm 3.13+
- Kind 0.22+ (for multi-service local cluster)
- buf (for proto repos)
- golangci-lint
- pre-commit

### GOPRIVATE Setup

paper-board private modules require auth:

```bash
# ~/.netrc
machine github.com
  login <your-github-username>
  password <github-pat-read-packages-repo>

# ~/.zshrc
export GOPRIVATE=github.com/paper-board/*
```

### Multi-Service Workspace (Phase 1.1+)

Use `go work` for cross-repo development:

```bash
mkdir -p ~/Projects/paper-board && cd ~/Projects/paper-board

# Clone all backend repos
for r in sdk proto identity billing agents platform infra; do
  git clone git@github.com:paper-board/$r.git
done

# Initialize workspace
go work init ./sdk ./identity ./billing ./agents ./platform

# Now changes in sdk are immediately visible in identity (no go.mod replace needed in CI)
```

For local cluster + hot reload, see `paper-board/dev-tools` (Phase 1.5).

## Branch Strategy — Trunk-Based

- `main` only
- Feature branches short-lived (<1 week)
- Squash merge to `main`
- Tag releases from `main`: `v0.1.0`, `v1.2.3`

No `develop`, no `release/*`, no GitFlow.

## Commit Messages — Conventional Commits

Format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

**Examples:**
- `feat(migrator): add advisory lock per-service`
- `fix(identity): handle dirty state in down migration`
- `docs(adr): add ADR-0009 for outbox pattern`

`commitlint` enforces this in CI. PRs with non-conforming commits fail.

## Pull Request Process

1. Open PR against `main`
2. Fill out PR template (Summary, Test plan, ADR/CONTEXT impact)
3. Wait for CI green (lint + test + build)
4. Request review (1+ approval required)
5. Squash merge

**Auto-merge:** Enabled — PR merges automatically once approved + CI green.

## Release Process

```bash
# After merge to main
git tag v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

`release-please` GHA generates CHANGELOG.md + GitHub Release.

For Docker images: `release.yaml` workflow builds + pushes + cosign signs + SBOM attaches.

## Per-Repo Bootstrap Checklist

When opening a new paper-board/<repo>:

- [ ] LICENSE (MIT for sdk/proto/cli; private for backend)
- [ ] README.md (purpose, dev setup, deploy)
- [ ] .gitignore
- [ ] .dockerignore (if applicable)
- [ ] .editorconfig
- [ ] .pre-commit-config.yaml
- [ ] CODEOWNERS
- [ ] go.mod (`module github.com/paper-board/<repo>`, `go 1.26`)
- [ ] .github/workflows/ci.yaml
- [ ] .github/workflows/release.yaml
- [ ] commitlint.config.js (extends shared)
- [ ] Branch protection rule applied (Settings → Branches)

Templates: see `paper-board/.github/templates/` (or `agent-manager/templates/per-repo/`).

## Code Style

- **Go:** `gofmt`, `goimports`, `golangci-lint` (config: `paper-board/.github/golangci.yaml`)
- **TS:** ESLint + Prettier (config: shared)
- **No emojis in code or commit messages** (unless explicitly user-facing UI)
- **All comments and documentation in English** (paper-board internal style)

## Testing

- Unit: `go test -race -count=1 ./...` (per-repo)
- Integration: testcontainers-go (postgres, redis, minio)
- E2E: Phase 5+ (chaos-mesh + nightly)
- Coverage gate: 75% on `internal/`, 95% on `internal/api/transformers/`

## ADR Process

Architectural decisions go in:
- System-wide: `docs/adr/` (root)
- Per-context: `project/<context>/docs/adr/`

Format: see [ADR-FORMAT.md](https://github.com/paper-board/.github/blob/main/ADR-FORMAT.md).

When proposing breaking changes, file an ADR proposal issue first.

## Questions

- General: GitHub Discussions
- Bugs: GitHub Issues (use bug_report template)
- Security: security@paperboard.app
- Conduct: conduct@paperboard.app
