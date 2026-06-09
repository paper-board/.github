#!/usr/bin/env bash
# setup-autolinks.sh — Register PB- GitHub autolink references on all 16
# bootstrapped paper-board repos.
#
# Purpose: PR descriptions, commit messages, and issue bodies that mention
# PB-NNN will render as clickable links to the archived Jira project.
#
# Dead-link caveat: The target Jira project (kovankaya.atlassian.net/browse/PB-)
# is archived per ADR-0020 (2026-05-29). The autolinks are purely decorative for
# legacy commit-message archaeology — the URL resolves syntactically but the
# project itself is no longer active.
#
# Re-run guidance: This script is idempotent. Re-run after bootstrapping new
# repos (e2e, billing, gateway). HTTP 422 from an existing autolink with the
# same prefix/URL is treated as success.
#
# Usage:
#   ./scripts/setup-autolinks.sh
#
# Requirements:
#   - gh CLI authenticated with org-admin rights on paper-board
#
# Exit codes:
#   0 — all repos registered (or already existed)
#   1 — at least one unexpected error

set -uo pipefail

JIRA_HOST="kovankaya.atlassian.net"
KEY_PREFIX="PB-"
URL_TEMPLATE="https://${JIRA_HOST}/browse/PB-<num>"

REPOS="agents identity runtime compute audit metering notifications onboarding environments vaults sdk proto infra cli .github service-template"

created=0
existing=0
failed=0

for repo in $REPOS; do
    err_output=$(gh api \
        -X POST \
        "/repos/paper-board/${repo}/autolinks" \
        -f key_prefix="${KEY_PREFIX}" \
        -f url_template="${URL_TEMPLATE}" \
        -F is_alphanumeric=false \
        2>&1) && rc=0 || rc=$?

    if [ "$rc" -eq 0 ]; then
        echo "  created   paper-board/${repo}"
        created=$((created + 1))
    elif echo "$err_output" | grep -q '"status":422\|HTTP 422\|already_exists\|Validation Failed'; then
        echo "  existing  paper-board/${repo}"
        existing=$((existing + 1))
    else
        echo "  ERROR     paper-board/${repo}: ${err_output}"
        failed=$((failed + 1))
    fi
done

echo ""
echo "Summary: created=${created} existing=${existing} failed=${failed}"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
