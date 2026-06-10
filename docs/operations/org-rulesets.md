# Org Rulesets — Operations Runbook

Two org-level rulesets enforce branch protection for `main` across all paper-board repositories.
The canonical state is codified in `scripts/org-rulesets-apply.sh`; that script is the source of
truth for replay, drift detection, and audit.

## Ruleset A — `main-protection-universal` (id 16879319)

Targets every repository (`~ALL`) on the default branch (`~DEFAULT_BRANCH`).

| Field                                            | Value                          |
| ------------------------------------------------ | ------------------------------ |
| `enforcement`                                    | `active`                       |
| `target`                                         | `branch`                       |
| `conditions.ref_name.include`                    | `~DEFAULT_BRANCH`              |
| `conditions.repository_name.include`             | `~ALL`                         |
| `rules.deletion`                                 | enabled                        |
| `rules.non_fast_forward`                         | enabled                        |
| `rules.required_linear_history`                  | enabled                        |
| `pull_request.required_approving_review_count`   | 0                              |
| `pull_request.dismiss_stale_reviews_on_push`     | false                          |
| `pull_request.require_code_owner_review`         | false                          |
| `pull_request.require_last_push_approval`        | false                          |
| `pull_request.required_review_thread_resolution` | true                           |
| `pull_request.allowed_merge_methods`             | `["squash"]`                   |
| `bypass_actors[0].actor_type`                    | `OrganizationAdmin`            |
| `bypass_actors[0].actor_id`                      | `1` (GitHub sentinel for role) |
| `bypass_actors[0].bypass_mode`                   | `pull_request`                 |

The `OrganizationAdmin` bypass grants org admins the ability to merge without a PR review when
needed (e.g. during incident response or bootstrap operations). In the current solo-founder setup
this is functionally "bypass for the founder only". Phase 8 will replace this with a Team-scoped
bypass (`actor_type: "Team"`, `actor_id: <release-team-id>`) when additional engineers are
onboarded. `require_last_push_approval: false` is explicit to prevent the sweep-stall pattern
documented in memory `require_last_push_approval_blocks_sweep`.

## Ruleset B — `main-ci-required` (id 16888787)

Targets all repositories on the default branch **except** the four excluded repos listed below.

| Field                                  | Value                                           |
| -------------------------------------- | ----------------------------------------------- |
| `enforcement`                          | `active`                                        |
| `bypass_actors`                        | `[]` (no bypass)                                |
| `conditions.repository_name.exclude`   | `.github`, `infra`, `service-template`, `proto` |
| `strict_required_status_checks_policy` | `true`                                          |
| Required status checks (6)             | see table below                                 |

| Check context      | Source                                                                   |
| ------------------ | ------------------------------------------------------------------------ |
| `ci / commitlint`  | `paper-board/.github/.github/workflows/go-ci.yml` reusable workflow      |
| `ci / lint`        | same                                                                     |
| `ci / unit`        | same                                                                     |
| `ci / integration` | same                                                                     |
| `ci / pr-title`    | same (added by branch-release-conventions Task 1, go-ci.yml@main)        |
| `CodeRabbit`       | CodeRabbit GitHub App (org-level install; independent of Go CI workflow) |

The four excluded repos (`.github`, `infra`, `service-template`, `proto`) do not invoke
`go-ci.yml`, so the standard 5 CI checks do not fire there. Applying the ruleset to them would
permanently block every PR. See branch-release-conventions design §7.2 for the full rationale.

**Expected near-term drift:** S-0047 may change the required-contexts list (possibly removing
`ci / pr-title` from this ruleset or adding a guard job). When S-0047 lands, update this
script and runbook in the same PR. Cross-ref S-0047 in the PR description.

## Replay procedure

Run from a shell authenticated with org-admin scope:

```bash
cd paper-board/.github
./scripts/org-rulesets-apply.sh           # apply + verify
./scripts/org-rulesets-apply.sh --dry-run # print bodies only, no changes
./scripts/org-rulesets-apply.sh --verify  # skip apply, run smoke check only
```

`--dry-run` is safe to run anywhere — it prints the canonical JSON bodies and exits without
contacting the GitHub API. Use it to diff against a known-good state before applying.

## Drift detection

Run `./scripts/org-rulesets-apply.sh --verify` periodically (no cron; user-initiated). The smoke
block re-fetches both rulesets and asserts key fields via `jq`. Any mismatch prints the field
path, actual value, and expected value, then exits non-zero.

Typical drift sources: manual edits via the GitHub org settings UI, GitHub API contract changes,
or a follow-up Story updating the required-contexts list (e.g. S-0047).

## Required scopes

| Scope       | Why                                    |
| ----------- | -------------------------------------- |
| `admin:org` | Read and write org-level rulesets      |
| `repo`      | Org context required for ruleset calls |

Authenticate via `gh auth login --scopes admin:org,repo` or set `GH_TOKEN` to a fine-grained PAT
with the same scopes. The default `GITHUB_TOKEN` in GitHub Actions **does not** carry `admin:org`
(see memory `paper_board_actions_permissions`) — this script must be run manually.

## Cross-references

- `tasks/2026-05-26-branch-release-conventions-design.md` §7 — canonical Ruleset A + B spec
- `tasks/2026-05-30-s-0019-org-rulesets-update-design.md` — S-0019 design decisions
- Memory `org_ruleset_main_ci_required_pr_title` — Ruleset B's `ci / pr-title` blast-radius
- Memory `required_thread_resolution_merge_gate` — Ruleset A's thread-resolution rule
- Memory `require_last_push_approval_blocks_sweep` — Ruleset A's `require_last_push_approval: false` rationale
