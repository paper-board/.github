# 0007 — Repository topology + naming convention

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo)

## Context

Multi-repo was chosen. The GitHub org name, repo naming, module paths, Helm chart location, and image registry naming are all hard to reverse and benefit from a single up-front decision.

## Decision

**GitHub org:** `github.com/paper-board` (hyphenated; `paperboard` was already taken).

**Repo naming:** `paper-board/<repo>` — short names for services (`identity`, `billing`, `agents`, ...).

**Module path = repo path:** `github.com/paper-board/identity`, `github.com/paper-board/sdk`, etc.

**12 repos:**

| Type      | Repos                                                                              |
|-----------|-------------------------------------------------------------------------------------|
| Backend   | gateway, identity, agents, runtime, billing, platform, compute                     |
| Frontend  | frontend                                                                            |
| Supporting| cli, sdk, proto, infra                                                              |

**Helm chart location:** `paper-board/infra` repo, under `infra/helm/agent-manager/`. The umbrella chart plus per-service subcharts live there.

**GHCR image naming:** `ghcr.io/paper-board/<service>-<binary>:<tag>` — for example, `ghcr.io/paper-board/identity-migrator:v0.1.0`, `ghcr.io/paper-board/identity-server:v0.1.0`.

**Brand vs repo:** `paperboard.app` (DNS, mailboxes) and `paper-board` (GitHub org) need not match — the brand is paperboard.app; the repo namespace is paper-board because of the GitHub naming collision.

**Branch protection rules** (org-level template applied to every repo):
- Default branch: `main`.
- Require a PR with at least one review.
- Require status checks (CI lint + test) to pass.
- Require linear history (rebase/squash merge).
- Squash merge enabled; merge commits and rebase merges disabled.
- Auto-merge enabled.

## Rejected alternatives

- **Helm at repo root (`helm/`).** Awkward in multi-repo; the dedicated `infra` repo keeps deployment context cohesive.
- **Module path `github.com/paper-board/agent-manager-<service>`.** Long and redundant.
- **Single repo `github.com/paper-board/agent-manager`.** Incompatible with ADR-0001.

## Consequences

- Module path = repo path matches the Go convention.
- The `infra` repo holds Helm + Terraform + k8s manifests in one place (DDD: deployment context).
- License (ADR-0008): sdk/proto/cli are MIT (open core); backend services are proprietary, in private repos.
