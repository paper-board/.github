---
title: CI/CD
description: GitHub Actions reusable workflows, Conventional Commits, release-please, and image publishing for paper-board services.
sidebar:
  order: 1
status: shipped
owner: '@paper-board/docs-maintainers'
updated: '2026-05-24'
---

paper-board CI runs through reusable workflows hosted in `paper-board/.github`. Service repos
consume them via `uses:` — they never inline `go test` or `golangci-lint` directly.

## Workflow inventory

| Workflow file        | Triggered by                                          | Does                                                                                           |
| -------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `go-ci.yml`          | push / pull_request in service repos                  | lint, unit, integration (testcontainers), coverage gate, mocks-verify, sqlc-verify, arch-check |
| `docker-publish.yml` | GitHub Release published                              | buildx multi-arch build + GHCR push; cosign signing (Phase 5)                                  |
| `helm-publish.yml`   | GitHub Release published                              | helm lint + package + push OCI to `ghcr.io/paper-board/helm/<svc>`                             |
| `release-please.yml` | push to main                                          | parse Conventional Commits → open release PR with CHANGELOG + tag bump                         |
| `standards-sync.yml` | nightly 04:00 UTC                                     | diff service-template vs standards docs; open issue on mismatch                                |
| `docs-deploy.yml`    | push to main (paths: docs/\*\*) + repository_dispatch | aggregate + Astro build + Cloudflare Pages deploy                                              |

### Service-repo wrapper

Each service repo carries only a thin wrapper that delegates to the reusable workflow:

```yaml
# from paper-board/agents/.github/workflows/ci.yml:1-10
name: ci
on: [push, pull_request]

jobs:
  ci:
    uses: paper-board/.github/.github/workflows/go-ci.yml@main
    with:
      service: agents
      coverage_threshold: "70"
    secrets: inherit
```

Service repos MUST NOT duplicate lint or test steps outside this wrapper.

## Commit discipline (Conventional Commits)

All commits to any paper-board repo MUST follow [Conventional Commits](https://www.conventionalcommits.org/).
`commitlint` runs as a pre-commit hook (installed by `make hooks`). CI enforces it on PR title
via `go-ci.yml`.

| Type        | Triggers version bump | Example                                  |
| ----------- | --------------------- | ---------------------------------------- |
| `fix:`      | patch                 | `fix(sessions): handle EOF on SSE flush` |
| `feat:`     | minor                 | `feat(agents): add agent clone endpoint` |
| `BREAKING`  | major (footer token)  | `feat!: rename x-org-id header`          |
| `chore:`    | none                  | `chore(deps): bump sdk to v0.2.0`        |
| `docs:`     | none                  | `docs(agents): add API reference`        |
| `refactor:` | none                  | `refactor(store): extract WithTx helper` |

Footer token for breaking changes: `BREAKING CHANGE: <description>` in the commit body.

## release-please flow

```mermaid
sequenceDiagram
  autonumber
  participant Dev as Developer
  participant GH  as GitHub main
  participant RP  as release-please
  participant DR  as Docker registry (GHCR)
  participant HC  as Helm OCI (GHCR)

  Dev->>GH: squash-merge PR (Conventional Commit title)
  GH->>RP: push event
  RP->>GH: open/update release PR (CHANGELOG + version bump)
  Dev->>GH: squash-merge release PR
  GH->>GH: create git tag vX.Y.Z + GitHub Release
  GH->>DR: docker-publish.yml — build + push 3 tags
  GH->>HC: helm-publish.yml — lint + push chart OCI

  classDef controlPlane fill:#10b981,stroke:#047857,color:#fff
  classDef dataPlane fill:#3b82f6,stroke:#1d4ed8,color:#fff
  classDef sandbox fill:#f97316,stroke:#c2410c,color:#fff
  classDef external fill:#ef4444,stroke:#b91c1c,color:#fff
  classDef persistence fill:#6b7280,stroke:#374151,color:#fff

  class Dev dataPlane
  class GH,RP controlPlane
  class DR,HC persistence
```

release-please reads commit history since the last tag, computes the next SemVer, and writes
`CHANGELOG.md`. Squash-merging the release PR publishes the GitHub Release, which triggers image
and chart publishing in parallel.

## Image tagging

Every service image is pushed with three tags on release:

| Tag            | Source                              | Use               |
| -------------- | ----------------------------------- | ----------------- |
| `vX.Y.Z`       | `git describe --tags --exact-match` | prod (immutable)  |
| `sha-<7-char>` | first 7 chars of `HEAD`             | staging / preview |
| `latest`       | main branch HEAD                    | dev only          |

Naming pattern: `ghcr.io/paper-board/<svc>-<binary>:<tag>`.

Examples:

```text
ghcr.io/paper-board/agents-server:v0.3.0
ghcr.io/paper-board/agents-server:sha-7c1d4a2
ghcr.io/paper-board/agents-migrator:v0.3.0
```

`latest` MUST NOT appear in any committed deployment manifest. Helm `appVersion` pins the exact
git tag at release time; chart `version` is an independent SemVer bumped on chart edits.

## Cache strategy

| Layer        | Mechanism                                           | Cache key                       |
| ------------ | --------------------------------------------------- | ------------------------------- |
| Go modules   | `actions/setup-go@v5` with `cache: true`            | hash of `go.sum`                |
| Go build     | `actions/cache@v4` on `GOCACHE`                     | OS + Go version + `go.sum` hash |
| Docker layer | BuildKit registry cache (`--cache-from/--cache-to`) | branch-scoped                   |

## Org-level secrets

| Secret                   | Scope          | Purpose                                              |
| ------------------------ | -------------- | ---------------------------------------------------- |
| `GHCR_TOKEN`             | org, all repos | push to `ghcr.io/paper-board`                        |
| `CLOUDFLARE_API_TOKEN`   | org, `.github` | Cloudflare Pages / Edit                              |
| `CLOUDFLARE_ACCOUNT_ID`  | org, `.github` | Cloudflare account scoping for Wrangler              |
| `DOCS_DISPATCH_PAT`      | org, all repos | `repository_dispatch:write` on `paper-board/.github` |
| `COSIGN_KEY`             | org, planned   | image signing (Phase 5)                              |
| `ANTHROPIC_API_KEY_TEST` | org, optional  | agents E2E layer                                     |

## Breaking-change policy

**Proto:** `buf breaking` runs in CI on PRs touching `proto/<svc>/v*/*.proto`.

**REST:** URL-versioned. `/v1` and `/v2` coexist. Removing `/v1` requires:

1. `Deprecation: <RFC date>` header on `/v1` responses for ≥ 90 days.
2. `Sunset: <removal date>` header pointing at the removal date.
3. Migration note in the service's `CHANGELOG.md`.

## Enforcement checklist (PR author)

- Commit title follows Conventional Commits.
- No inline `go test` / `golangci-lint` added to the service CI wrapper.
- `latest` tag not referenced in Helm `values.yaml` or kustomize overlays.
- Breaking REST change includes `Deprecation` + `Sunset` headers + CHANGELOG note.
