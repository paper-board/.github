# 0001 — Multi-repo microservices architecture

**Status:** accepted
**Date:** 2026-04-30

## Context

The original backend design (plan/14) assumed a single Go monorepo with multiple `cmd/` binaries. That is the fastest setup for a solo dev or a small team. We chose Strategy D from the grilling session — multi-repo microservices — to bake in repo-level ownership boundaries, independent deploy cadence, and an open-source extraction path before the team grows.

## Decision

12 GitHub repositories under the `paper-board` org.

**Backend services (7):** `gateway`, `identity`, `agents`, `runtime`, `billing`, `platform`, `compute`.

**Supporting (5):** `cli` (agentctl), `frontend` (Next.js), `sdk` (Go shared library), `proto` (gRPC + OpenAPI), `infra` (Helm + Terraform + k8s).

## Rejected alternatives

- **Monorepo with multiple cmd binaries (plan/14).** Loses Conway alignment and repo-level boundary discipline. Five years on, a 200k LoC single repo.
- **Strategy 1 (2-3 services).** Defeats the value of multi-repo; the control-plane becomes a monolith-in-disguise.
- **Strategy 3 (12-18 fine-grained services).** Dead on arrival for a solo dev — saga + service mesh required from day one.

## Consequences

**Accepted risk:**
- Solo-dev ops cost is 12× (CI, GHCR images, Helm subcharts, Renovate per repo).
- Shared-code governance: `sdk` + `proto` SemVer discipline. A breaking change in `sdk` requires bumping every consumer service.
- Cross-repo refactors are expensive (e.g. adding a JWT claim → 6+ coordinated PRs).
- GOPRIVATE auth in every CI run — default is ephemeral credentials (GitHub OIDC token or short-lived installation token); PATs/SSH keys are documented exception flows requiring limited scope, rotation policy, and justification.
- Local dev is more complex (`go work` + Tilt + Kind, or per-repo dev workflow).

**Mitigation:**
- `paper-board/service-template` repo (Phase 5) — bootstrap a new service in minutes.
- `sdk` SemVer: major = breaking, minor = additive, patch = fix.
- `proto` versioning carried in package name (`identity.v1`, `identity.v2`) — supports parallel versions.
- Shared Renovate config across the org coordinates auto-bumps.
