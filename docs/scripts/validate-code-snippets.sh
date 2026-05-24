#!/usr/bin/env bash
# validate-code-snippets.sh - Verify source-path comments in markdown code blocks.
#
# Per design §6.4.1: every code block > 3 lines must carry a comment of the form
#   // from paper-board/<repo>/<path>:<from>-<to>
# (or # from ... for yaml/sh/bash, -- from ... for sql)
# The referenced repo/path/line-range must exist.
#
# Exit codes:
#   0 = all snippets valid (or zero snippets found)
#   1 = at least one MISSING_FILE / OUT_OF_RANGE / INVERTED_RANGE
#   2 = script invocation error

set -euo pipefail

ROOT="${1:-.}"
WORKDIR="${WORKDIR:-${HOME}/Projects}"
ISSUES=0

if [[ ! -d "${ROOT}" ]]; then
  printf 'INVOCATION_ERROR: root dir %s not found\n' "${ROOT}" >&2
  exit 2
fi

# Find all markdown files under ROOT (portable: no mapfile/bash 4 required)
MD_COUNT=0

while IFS= read -r md; do
  MD_COUNT=$((MD_COUNT + 1))
  # Extract candidate lines: any line beginning with a comment prefix
  # then "from paper-board/" then "<path>:<from>-<to>"
  # Comment prefixes: // (go/proto), # (yaml/sh/bash), -- (sql)
  while IFS=: read -r lineno content; do
    # Extract the "paper-board/..." portion from the source-path comment.
    # grep already guarantees the line matches (//|#|--) from paper-board/...
    if [[ "${content}" =~ paper-board/([a-z0-9_-]+)/([^:]+):([0-9]+)-([0-9]+)$ ]]; then
      repo="${BASH_REMATCH[1]}"
      path="${BASH_REMATCH[2]}"
      from="${BASH_REMATCH[3]}"
      to="${BASH_REMATCH[4]}"
      source_file="${WORKDIR}/paper-board/${repo}/${path}"

      if [[ ! -f "${source_file}" ]]; then
        printf 'MISSING_FILE: %s:%s — file %s does not exist\n' "${md}" "${lineno}" "paper-board/${repo}/${path}" >&2
        ISSUES=$((ISSUES + 1))
        continue
      fi

      if [[ "${from}" -gt "${to}" ]]; then
        printf 'INVERTED_RANGE: %s:%s — from=%s > to=%s\n' "${md}" "${lineno}" "${from}" "${to}" >&2
        ISSUES=$((ISSUES + 1))
        continue
      fi

      file_lines=$(wc -l < "${source_file}")
      if [[ "${to}" -gt "${file_lines}" ]]; then
        printf 'OUT_OF_RANGE: %s:%s — to=%s exceeds source file length %s\n' "${md}" "${lineno}" "${to}" "${file_lines}" >&2
        ISSUES=$((ISSUES + 1))
        continue
      fi
    fi
  done < <(grep -nE '^\s*(//|#|--)\s*from\s+paper-board/' "${md}" || true)
done < <(find "${ROOT}" -type f -name '*.md')

if [[ "${ISSUES}" -gt 0 ]]; then
  printf 'validate-code-snippets: %d issue(s) found\n' "${ISSUES}" >&2
  exit 1
fi

printf 'validate-code-snippets: clean (%d files scanned)\n' "${MD_COUNT}" >&2
exit 0
