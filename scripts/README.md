# scripts/

Operational scripts for the `paper-board/.github` repo. Not part of CI — run
manually by engineers or as one-shot bootstrap steps.

______________________________________________________________________

## compare-template.sh

Drift detector for backend service repos against `paper-board/service-template`.
Consumed by `.github/workflows/template-drift.yml`.

Usage: see file header.

______________________________________________________________________

## setup-autolinks.sh

Registers the `PB-` GitHub autolink reference on all 16 bootstrapped
`paper-board/*` repos.

### What it does

Posts `POST /repos/paper-board/{repo}/autolinks` with:

- `key_prefix`: `PB-`
- `url_template`: `https://kovankaya.atlassian.net/browse/PB-<num>`
- `is_alphanumeric`: `false`

After registration, any `PB-NNN` mention in a PR description, commit message, or
issue body renders as a clickable link.

### Dead-link caveat

The target Jira project is **archived** per ADR-0020 (2026-05-29). Links are
decorative — useful for tracing legacy commit messages back to their original
tickets, but the Jira project is no longer active.

### How to run

```bash
./scripts/setup-autolinks.sh
```

Requires `gh` CLI authenticated with org-admin rights on the `paper-board` org.

### Idempotency

Safe to re-run at any time. HTTP 422 (autolink already exists with the same
prefix and URL) is treated as success. Re-run after bootstrapping new repos:

- `e2e` — after S-0001 merges
- `billing` — Phase 6
- `gateway` — Phase 8

Add the new repo name to the `REPOS` list in the script before re-running.
