# paper-board/.github

Org-wide community files + reusable CI building blocks for the
[paper-board](https://github.com/paper-board) microservice fleet.

## Community files

| File                          | Purpose                                                |
|-------------------------------|--------------------------------------------------------|
| `profile/README.md`           | Org landing page (rendered at github.com/paper-board)  |
| `CODE_OF_CONDUCT.md`          | Contributor Covenant v2.1 (ADR-0008)                   |
| `CONTRIBUTING.md`             | Contribution guide                                     |
| `SECURITY.md`                 | Security policy + disclosure                           |
| `PULL_REQUEST_TEMPLATE.md`    | PR template (default)                                  |
| `ISSUE_TEMPLATE/`             | Bug, feature, ADR templates                            |
| `commitlint.config.js`        | Conventional Commits ruleset (ADR-0008)                |
| `renovate.json`               | Renovate auto-bump (modules + GitHub Actions)          |

## Shared lint baseline

[`golangci.yml`](./golangci.yml) — golangci-lint v2 baseline for every Go repo.
Service repos extend it with a thin per-repo `.golangci.yml`:

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

Spec: `agent-manager/docs/standards/go-coding-conventions.md` §3.

## Reusable workflows

`workflow-templates/` hosts reusable GitHub Actions consumed by service repos via `uses:`.

| File                                          | Purpose                                                       |
|-----------------------------------------------|---------------------------------------------------------------|
| `workflow-templates/go-ci.yaml`               | Lint + test + build + commitlint for Go modules               |
| `workflow-templates/release-image.yaml`       | Multi-arch Docker build + GHCR push (cosign + Syft Phase 5+)  |
| `workflow-templates/release-please.yaml`      | Conventional Commits → release PR + tag + CHANGELOG           |

### Wiring example

```yaml
# <service>/.github/workflows/ci.yaml
name: CI
on: [push, pull_request]
jobs:
  ci:
    uses: paper-board/.github/.github/workflow-templates/go-ci.yaml@main
    with: { go-version: "1.26", coverage-threshold: 60 }
    secrets: { GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }} }
```

```yaml
# <service>/.github/workflows/release-please.yaml
name: release-please
on:
  push:
    branches: [main]
jobs:
  release-please:
    uses: paper-board/.github/.github/workflow-templates/release-please.yaml@main
    with:
      release-type: go
    secrets: inherit
```

## References

- ADR-0007 — repo topology
- ADR-0008 — license + commits + SemVer
- `agent-manager/docs/standards/build-release.md`
- `agent-manager/docs/standards/go-coding-conventions.md`
