#!/usr/bin/env bash
# validate-frontmatter.sh - Verify every Markdown page carries required frontmatter.
#
# Per design §6.7. Required fields: title, description, sidebar.order, status, owner, updated.
# status enum: shipped | draft | placeholder | deprecated.
# owner: must start with "@".
# updated: ISO date (YYYY-MM-DD).
#
# Exit codes:
#   0 = all pages valid
#   1 = at least one validation failure
#   2 = invocation error / yq missing

set -euo pipefail

ROOT="${1:-.}"
ISSUES=0
SCANNED=0
VALID_STATUS=("shipped" "draft" "placeholder" "deprecated")

if ! command -v yq >/dev/null 2>&1; then
  printf 'INVOCATION_ERROR: yq not installed. brew install yq\n' >&2
  exit 2
fi

if [[ ! -d "${ROOT}" ]]; then
  printf 'INVOCATION_ERROR: root dir %s not found\n' "${ROOT}" >&2
  exit 2
fi

valid_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

valid_status() {
  local s="$1"
  for v in "${VALID_STATUS[@]}"; do
    [[ "${v}" == "${s}" ]] && return 0
  done
  return 1
}

report() {
  printf '%s: %s — %s\n' "$1" "$2" "$3" >&2
  ISSUES=$((ISSUES + 1))
}

while IFS= read -r md; do
  SCANNED=$((SCANNED + 1))

  # Extract frontmatter (between two --- lines at top of file)
  fm=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f==2{exit}' "${md}")

  if [[ -z "${fm}" ]]; then
    report "MISSING_FRONTMATTER" "${md}" "no YAML frontmatter block found"
    continue
  fi

  # Required field checks
  title=$(printf '%s' "${fm}" | yq '.title' 2>/dev/null || printf '')
  [[ -z "${title}" || "${title}" == "null" ]] && report "MISSING_TITLE" "${md}" "title field required"

  description=$(printf '%s' "${fm}" | yq '.description' 2>/dev/null || printf '')
  [[ -z "${description}" || "${description}" == "null" ]] && report "MISSING_DESCRIPTION" "${md}" "description field required"

  order=$(printf '%s' "${fm}" | yq '.sidebar.order' 2>/dev/null || printf '')
  [[ -z "${order}" || "${order}" == "null" ]] && report "MISSING_SIDEBAR_ORDER" "${md}" "sidebar.order field required (int)"

  status=$(printf '%s' "${fm}" | yq '.status' 2>/dev/null || printf '')
  if [[ -z "${status}" || "${status}" == "null" ]]; then
    report "MISSING_STATUS" "${md}" "status field required"
  elif ! valid_status "${status}"; then
    report "INVALID_STATUS" "${md}" "status='${status}' not in (shipped|draft|placeholder|deprecated)"
  fi

  owner=$(printf '%s' "${fm}" | yq '.owner' 2>/dev/null || printf '')
  if [[ -z "${owner}" || "${owner}" == "null" ]]; then
    report "MISSING_OWNER" "${md}" "owner field required (e.g. @paper-board/docs-maintainers)"
  elif [[ ! "${owner}" =~ ^@ ]]; then
    report "INVALID_OWNER" "${md}" "owner must start with '@'"
  fi

  updated=$(printf '%s' "${fm}" | yq '.updated' 2>/dev/null || printf '')
  if [[ -z "${updated}" || "${updated}" == "null" ]]; then
    report "MISSING_UPDATED" "${md}" "updated field required (ISO date)"
  elif ! valid_date "${updated}"; then
    report "INVALID_UPDATED" "${md}" "updated='${updated}' not in YYYY-MM-DD format"
  fi
done < <(find "${ROOT}" -type f -name '*.md')

if [[ "${ISSUES}" -gt 0 ]]; then
  printf 'validate-frontmatter: %d issue(s) found in %d file(s)\n' "${ISSUES}" "${SCANNED}" >&2
  exit 1
fi

printf 'validate-frontmatter: clean (%d files scanned)\n' "${SCANNED}" >&2
exit 0
