# 0008 — License, Code of Conduct, commit convention

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo), ADR-0007 (repo topology)

## Context

Twelve repos need a license, a Code of Conduct, a commit convention, a branch strategy, a release versioning policy, and PR/issue templates. These choices shape contributor onboarding and the open-core strategy.

## Decision

### License — hybrid

Open ecosystem enablers are permissive; commercial code is closed:

| Repos                                                       | License             |
|-------------------------------------------------------------|---------------------|
| `paper-board/sdk`, `paper-board/proto`, `paper-board/cli`   | MIT                 |
| `paper-board/gateway`, `identity`, `agents`, `runtime`, `billing`, `platform`, `compute`, `frontend`, `infra` | Proprietary (private repos) |

Rationale: SDK + protocol + CLI form the integration ecosystem (developers can integrate and contribute). Backend services are commercial.

### Code of Conduct

**Contributor Covenant v2.1**, hosted in `paper-board/.github` and referenced by every public repo.

### Commit message convention

**Conventional Commits.** Format: `<type>(<scope>): <subject>`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Enforcement: a shared `commitlint` config in `paper-board/.github/commitlint.config.js`, plus a Husky `commit-msg` hook and a GitHub Actions check that fails PRs with non-conforming commits.

Auto-changelog: `release-please` GitHub Action generates `CHANGELOG.md` on each tag.

### Branch strategy

**Trunk-based development:**
- `main` is the only long-lived branch.
- Feature branches are short-lived (under one week).
- Squash merge to `main`.
- Releases are tags from `main` (`v0.1.0`, `v1.2.3`).

### Release versioning

**SemVer 2.0** (major.minor.patch).

- `paper-board/sdk` and `paper-board/proto` are strict — every additive change is a minor bump.
- Backend services are looser through Phase 4 (rapid iteration); strictness applies from Phase 5.
- Pre-release tags use `-rc.N` (e.g. `v0.1.0-rc.1`).

### PR and Issue templates

Shared in `paper-board/.github`:

- `PULL_REQUEST_TEMPLATE.md` — Summary, Test plan, ADR/CONTEXT impact.
- `ISSUE_TEMPLATE/bug_report.md`
- `ISSUE_TEMPLATE/feature_request.md`
- `ISSUE_TEMPLATE/architecture_decision.md` (an ADR proposal triggers a discussion before the ADR is committed).

## Rejected alternatives

- **Single license (MIT or Apache).** Would expose backend trade secrets.
- **AGPLv3.** Copyleft on a SaaS scares enterprise customers.
- **Free-form commit messages.** No auto-changelog possible.
- **GitFlow.** Overhead for a solo dev.

## Consequences

**Gain:**
- Open-core strategy is feasible (sdk/proto/cli OSS; backend closed).
- Auto-changelog and release notes come for free.
- The PR template asks about ADR/CONTEXT impact, enforcing documentation discipline.

**Action items:**
- Open `paper-board/.github` repo.
- Commit LICENSE templates per repo.
- Set up commitlint config + Husky.
- Add the `release-please` GHA workflow.

**Open question:**
- The SECURITY.md vulnerability disclosure email is `security@paperboard.app` — DNS is set up in Phase 5 of the active roadmap, so until then disclosures may bounce. Noted as accepted risk.
