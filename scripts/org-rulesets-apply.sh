#!/usr/bin/env bash
# org-rulesets-apply.sh — Apply canonical org-level branch-protection state for paper-board.
#
# What this script does:
#   1. PUT Ruleset A (id 16879319, main-protection-universal) with the canonical body
#      from tasks/2026-05-30-s-0019-org-rulesets-update-design.md §7.1.
#   2. Upsert Ruleset B (main-ci-required) — lookup by name → PUT if found, POST if not.
#   3. Smoke-verify both rulesets match the expected state.
#
# Idempotency contract:
#   Running this script N times produces the same server state and exit code.
#   PUT with a complete body is idempotent per GitHub's REST contract.
#   POST for Ruleset B is reachable only when the org has been wiped; safe to re-run.
#
# Required GitHub scopes:
#   admin:org  (read/write org rulesets)
#   repo       (org context — needed for some ruleset endpoints)
#
# Authentication:
#   gh auth login --scopes admin:org,repo
#   OR a fine-grained PAT stored as the GH_TOKEN env var.
#
# Usage:
#   ./scripts/org-rulesets-apply.sh              # apply + verify
#   ./scripts/org-rulesets-apply.sh --dry-run    # print request bodies, no sends
#   ./scripts/org-rulesets-apply.sh --verify     # skip apply, run smoke only
#
# Source references:
#   tasks/2026-05-30-s-0019-org-rulesets-update-design.md §7 (decisions)
#   tasks/2026-05-26-branch-release-conventions-design.md §7.1 + §7.2 (canonical spec)
#   Story S-0019 plan: tasks/plans/S-0019-org-rulesets-update-plan.md
#
# IMPORTANT: This script requires org-admin OAuth and CANNOT be run by CI/CD.
#   See docs/operations/org-rulesets.md for the full runbook.

set -euo pipefail

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
MODE="apply"
case "${1:-}" in
  --dry-run) MODE="dry" ;;
  --verify)  MODE="verify" ;;
  "")        MODE="apply" ;;
  *)
    echo "Usage: $0 [--dry-run|--verify]" >&2
    exit 64
    ;;
esac

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq / apt-get install jq)" >&2; exit 1; }

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh auth status failed. Run: gh auth login --scopes admin:org,repo" >&2
  exit 1
fi

LOGIN=$(gh api user --jq .login 2>/dev/null)
if [ -z "$LOGIN" ]; then
  echo "ERROR: gh api user returned empty login. Token may be expired." >&2
  exit 1
fi
echo "Authenticated as: ${LOGIN}"

# ---------------------------------------------------------------------------
# Ruleset A body (design §7.1, S-0019-org-rulesets-update-design §7 D9)
# actor_id=1 is the GitHub-defined sentinel for OrganizationAdmin role.
# ---------------------------------------------------------------------------
RULESET_A_BODY=$(cat <<'JSON'
{
  "name": "main-protection-universal",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 1,
      "actor_type": "OrganizationAdmin",
      "bypass_mode": "pull_request"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    },
    "repository_name": {
      "include": ["~ALL"],
      "exclude": [],
      "protected": false
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    }
  ]
}
JSON
)

# ---------------------------------------------------------------------------
# Ruleset B body (design §7.2)
# bypass_actors is explicit empty array — no bypass on CI-required checks.
# Excluded repos: .github, infra, service-template, proto (no go-ci.yml).
# ---------------------------------------------------------------------------
RULESET_B_BODY=$(cat <<'JSON'
{
  "name": "main-ci-required",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    },
    "repository_name": {
      "include": ["~ALL"],
      "exclude": [".github", "infra", "service-template", "proto"],
      "protected": false
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci / commitlint" },
          { "context": "ci / lint" },
          { "context": "ci / unit" },
          { "context": "ci / integration" },
          { "context": "ci / pr-title" },
          { "context": "CodeRabbit" }
        ]
      }
    }
  ]
}
JSON
)

# ---------------------------------------------------------------------------
# Validate JSON bodies (always, even in dry-run — catches heredoc errors)
# ---------------------------------------------------------------------------
if ! echo "$RULESET_A_BODY" | jq empty 2>/dev/null; then
  echo "ERROR: Ruleset A body is not valid JSON. This is a script bug." >&2
  exit 1
fi
if ! echo "$RULESET_B_BODY" | jq empty 2>/dev/null; then
  echo "ERROR: Ruleset B body is not valid JSON. This is a script bug." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Dry-run mode: print bodies and exit
# ---------------------------------------------------------------------------
if [ "$MODE" = "dry" ]; then
  echo "=== DRY RUN: Ruleset A (PUT /orgs/paper-board/rulesets/16879319) ==="
  echo "$RULESET_A_BODY" | jq .
  echo ""
  echo "=== DRY RUN: Ruleset B (upsert by name 'main-ci-required') ==="
  echo "$RULESET_B_BODY" | jq .
  echo ""
  echo "Dry run complete. No changes sent to GitHub."
  exit 0
fi

# ---------------------------------------------------------------------------
# Apply mode: PUT Ruleset A
# ---------------------------------------------------------------------------
if [ "$MODE" = "apply" ]; then
  echo "Applying Ruleset A (id 16879319, main-protection-universal)..."
  echo "$RULESET_A_BODY" | gh api -X PUT orgs/paper-board/rulesets/16879319 --input - > /dev/null
  echo "Ruleset A applied."

  echo "Locating Ruleset B (main-ci-required)..."
  RULESET_B_ID=$(gh api orgs/paper-board/rulesets --jq '.[] | select(.name=="main-ci-required") | .id')

  if [ -n "$RULESET_B_ID" ]; then
    echo "Ruleset B found (id ${RULESET_B_ID}). Applying PUT..."
    echo "$RULESET_B_BODY" | gh api -X PUT "orgs/paper-board/rulesets/${RULESET_B_ID}" --input - > /dev/null
    echo "Ruleset B applied."
  else
    echo "Ruleset B not found. Creating via POST..."
    RULESET_B_ID=$(echo "$RULESET_B_BODY" | gh api -X POST orgs/paper-board/rulesets --input - --jq .id)
    echo "Ruleset B created (id ${RULESET_B_ID})."
  fi
fi

# ---------------------------------------------------------------------------
# Smoke verification (apply mode runs this automatically; --verify mode entry)
# ---------------------------------------------------------------------------
echo "Running smoke verification..."

# Fetch current state
ACTUAL_A=$(gh api orgs/paper-board/rulesets/16879319 2>/dev/null)
if [ -z "$ACTUAL_A" ]; then
  echo "ERROR: Could not fetch Ruleset A (id 16879319)." >&2
  exit 1
fi

if [ "$MODE" = "verify" ]; then
  RULESET_B_ID=$(gh api orgs/paper-board/rulesets --jq '.[] | select(.name=="main-ci-required") | .id')
fi

if [ -z "$RULESET_B_ID" ]; then
  echo "ERROR: Ruleset B (main-ci-required) not found during verification." >&2
  exit 1
fi
ACTUAL_B=$(gh api "orgs/paper-board/rulesets/${RULESET_B_ID}" 2>/dev/null)
if [ -z "$ACTUAL_B" ]; then
  echo "ERROR: Could not fetch Ruleset B (id ${RULESET_B_ID})." >&2
  exit 1
fi

FAIL=0

# Verify Ruleset A fields
check_field() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" != "$expected" ]; then
    echo "MISMATCH [$label]: actual='${actual}' expected='${expected}'" >&2
    FAIL=1
  fi
}

check_field "A.name"       "$(echo "$ACTUAL_A" | jq -r .name)"       "main-protection-universal"
check_field "A.enforcement" "$(echo "$ACTUAL_A" | jq -r .enforcement)" "active"
check_field "A.target"     "$(echo "$ACTUAL_A" | jq -r .target)"     "branch"

# Verify Ruleset A has required_review_thread_resolution=true
A_THREAD_RES=$(echo "$ACTUAL_A" | jq -r '.rules[] | select(.type=="pull_request") | .parameters.required_review_thread_resolution')
check_field "A.required_review_thread_resolution" "$A_THREAD_RES" "true"

# Verify Ruleset A require_last_push_approval=false
A_LAST_PUSH=$(echo "$ACTUAL_A" | jq -r '.rules[] | select(.type=="pull_request") | .parameters.require_last_push_approval')
check_field "A.require_last_push_approval" "$A_LAST_PUSH" "false"

# Verify Ruleset A allowed_merge_methods=["squash"]
A_MERGE=$(echo "$ACTUAL_A" | jq -r '.rules[] | select(.type=="pull_request") | .parameters.allowed_merge_methods | @json')
check_field "A.allowed_merge_methods" "$A_MERGE" '["squash"]'

# Verify Ruleset B
check_field "B.name"       "$(echo "$ACTUAL_B" | jq -r .name)"       "main-ci-required"
check_field "B.enforcement" "$(echo "$ACTUAL_B" | jq -r .enforcement)" "active"

# Verify Ruleset B has all 6 required check contexts
B_CHECKS=$(echo "$ACTUAL_B" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' | LC_ALL=C sort)
EXPECTED_CHECKS=$(printf 'CodeRabbit\nci / commitlint\nci / integration\nci / lint\nci / pr-title\nci / unit' | LC_ALL=C sort)
if [ "$B_CHECKS" != "$EXPECTED_CHECKS" ]; then
  echo "MISMATCH [B.required_status_checks]:" >&2
  echo "  actual:   $(echo "$B_CHECKS" | tr '\n' ',' | sed 's/,$//')" >&2
  echo "  expected: $(echo "$EXPECTED_CHECKS" | tr '\n' ',' | sed 's/,$//')" >&2
  FAIL=1
fi

# Verify Ruleset B strict policy
B_STRICT=$(echo "$ACTUAL_B" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy')
check_field "B.strict_required_status_checks_policy" "$B_STRICT" "true"

# Verify Ruleset B excluded repos (sort for stable comparison)
B_EXCLUDE_SORTED=$(echo "$ACTUAL_B" | jq -r '.conditions.repository_name.exclude | sort | @json')
check_field "B.repository_name.exclude" "$B_EXCLUDE_SORTED" '[".github","infra","proto","service-template"]'

if [ "$FAIL" -ne 0 ]; then
  echo "Smoke verification FAILED. See mismatches above." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Smoke verification PASSED ==="
echo "Ruleset A: id 16879319 (main-protection-universal)"
echo "Ruleset B: id ${RULESET_B_ID} (main-ci-required)"
echo "Required status checks:"
echo "  ci / commitlint"
echo "  ci / lint"
echo "  ci / unit"
echo "  ci / integration"
echo "  ci / pr-title"
echo "  CodeRabbit"
