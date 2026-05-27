# 0013 — agent-manager coord repo layout

**Status:** accepted
**Date:** 2026-05-17
**Related:** ADR-0001 (multi-repo), ADR-0007 (repo topology), ADR-0008 (license + commits), ADR-0011 (standards refresh)
**Scope:** system

## Context

The `agent-manager` coord repo (this repo) accumulated four kinds of clutter since the multi-repo refactor (ADR-0001) and the product-first re-sequencing (ADR-0009): a frozen `plan/` design-doc tree, stale templates predating the live `paper-board/<svc>` repos, one-shot prompt drafts, and a split 12-ADR registry across `docs/adr/` and `project/backend/docs/adr/`. The `project/` directory also wrapped a single live folder plus an empty `project/frontend/`. The 2026-05-17 reorg (`tasks/2026-05-17-repo-reorg-{design,plan}.md`) executed the cleanup in three PRs. This ADR locks the resulting conventions so the layout does not drift back.

## Decision

The coord repo top-level is exactly four directories:

- `.claude/` — agent configuration; canonical.
- `docs/` — canonical reference content: ADRs, glossaries, agents docs, diagrams, research.
- `tasks/` — active plans, specs, progress logs, handoffs, and `tasks/archive/` for superseded items.
- `legacy/` — frozen, pre-reorg content kept for git-archaeology only. Read-only by convention; never linked from canonical docs except via `legacy/README.md`'s `## Pointer to active content` block.

Plus the top-level files: `CLAUDE.md`, `AGENTS.md`, `CONTEXT-MAP.md`, `.gitignore`.

Conventions:

1. **ADR registry is single-folder.** All ADRs live in `docs/adr/`. Each ADR has a `**Scope:** system | backend` frontmatter line immediately after the last `**Key:**` metadata line and before `## Context`. Allowed values are exactly `system` (cross-cutting / org-level) and `backend` (backend-only). `docs/adr/INDEX.md` is the registry table (ADR, Title, Scope, Status).
2. **Backend glossary is `docs/backend-context.md`.** Anchors `#identity`, `#billing`, `#agents`, `#runtime`, `#platform`, `#compute`, `#gateway` are stable; renaming the file or its H3 headings requires an ADR.
3. **Research content lives at `docs/research/`.** Reference-quality, non-canonical; does not lock decisions.
4. **Legacy content stays under `legacy/`.** Cross-reference rewrites in the canonical tree (everything outside `legacy/`, `tasks/archive/`, `.claude/plugins/`, `.git/`) must not point into `legacy/`.
5. **Active tasks/ files at root.** `HANDOFF-*.md`, `RESUME-PROMPT.md`, and any `YYYY-MM-DD-handoff.md` are live working files; date-stamped plans/specs/progress follow `YYYY-MM-DD-{slug}-{design,plan,spec,progress}.md`.

## Rejected alternatives

- **Two-folder ADR split (system in `docs/adr/`, backend in `project/backend/docs/adr/`).** Locating "ADR-0003" requires scanning two folders; numbering already shares a single sequence. Single-folder + `Scope:` line resolves the same intent.
- **Delete `plan/` / `templates/` / `prompts/` outright.** Loses git-archaeology; reorg chose archive-into-`legacy/` to preserve blame history with `git mv`.
- **Top-level `analysis/` retained.** Reference-quality but ungrouped; `docs/research/` puts it under the canonical umbrella.
- **`project/` retained as wrapper.** Adds nesting depth with no value once `frontend/` is empty and `backend/` collapses to a single `CONTEXT.md`.

## Consequences

- A reader landing on the repo can tell within seconds what is live (`docs/`, `tasks/`), what is reference (`docs/research/`), and what is fossil (`legacy/`).
- Future docs additions follow the four-directory rule; introducing a fifth top-level directory requires an ADR amendment.
- Cross-ref tooling (`rg`) can use a stable exclude list: `-g '!legacy/**' -g '!tasks/archive/**' -g '!.claude/plugins/**' -g '!.git/**'`.
- Adding a new ADR requires assigning `Scope:` (`system` or `backend`) and updating `docs/adr/INDEX.md`.

## References

- `tasks/2026-05-17-repo-reorg-design.md` — design + two rounds of `spec-self-review`.
- `tasks/2026-05-17-repo-reorg-plan.md` — 3-PR implementation plan.
- Reorg commits on `main`:
  - `07af3b7` — PR-1: archive `plan/`, `prompts/`, `templates/` to `legacy/`.
  - `af6e4af` — PR-2: consolidate 12 ADRs into `docs/adr/` with `**Scope:**` lines + `INDEX.md`; flatten `project/`; `analysis/` → `docs/research/`.
  - `0a1109e` — PR-3: rewrite cross-references in canonical files (`CLAUDE.md`, `CONTEXT-MAP.md`, `AGENTS.md`, `.claude/`, `tasks/*`).
