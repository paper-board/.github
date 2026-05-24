#!/usr/bin/env bash
# aggregate-docs.sh - Multi-repo docs aggregator for paperboard.
#
# Clones the `docs/` folder of each paper-board repo (per docs/scripts/repos.txt)
# and copies it into content/docs/services/<repo-basename>/.
#
# Auth: uses $GITHUB_TOKEN if set, else falls back to `gh` CLI auth.
# Idempotent: removes target dirs before copy.
# Skips repos that don't have a docs/ folder.
# Modes: default (real fetch), --dry-run (list operations only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_FILE="${SCRIPT_DIR}/repos.txt"
CONTENT_BASE="${DOCS_ROOT}/content/docs"
TMP_BASE="$(mktemp -d -t paperboard-aggregate-XXXXXX)"
trap 'rm -rf "${TMP_BASE}"' EXIT

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

log() { printf '[aggregate-docs] %s\n' "$*" >&2; }

fetch_repo() {
  local repo="$1"
  local repo_base="${repo##*/}"
  local target="${CONTENT_BASE}/services/${repo_base}"
  local tmp="${TMP_BASE}/${repo_base}"

  log "fetch ${repo} -> services/${repo_base}/"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "  (dry-run, skipping)"
    return 0
  fi

  if ! gh_out=$(gh repo clone "${repo}" "${tmp}" -- --depth=1 --quiet 2>&1); then
    log "  WARN: clone failed for ${repo}: ${gh_out} — skipping"
    return 0
  fi

  if [[ ! -d "${tmp}/docs" ]]; then
    log "  no docs/ folder in ${repo} — emitting placeholder"
    rm -rf "${target}"
    mkdir -p "${target}"
    cat > "${target}/index.md" <<EOF
---
title: ${repo_base}
description: Placeholder for ${repo_base}. Content lands when the service ships.
sidebar:
  order: 99
status: placeholder
owner: "@paper-board/docs-maintainers"
updated: $(date -u +%Y-%m-%d)
---

This service has not shipped yet. Documentation lands when the service is built. See the [roadmap](../../decisions/0015-mvp-launch-phase-rebalance.md) for the schedule.
EOF
    return 0
  fi

  rm -rf "${target}"
  mkdir -p "${target}"
  cp -R "${tmp}/docs/." "${target}/"
}

fetch_mirror() {
  local source="$1"  # paper-board/.github path (relative to repo root)
  local target_dir="$2"  # under content/docs/

  log "mirror ${source} -> ${target_dir}/"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "  (dry-run, skipping)"
    return 0
  fi

  local target="${CONTENT_BASE}/${target_dir}"
  rm -rf "${target}"
  mkdir -p "${target}"

  # When running in the .github repo itself, source files are local.
  if [[ -d "${DOCS_ROOT}/../${source}" ]]; then
    cp -R "${DOCS_ROOT}/../${source}/." "${target}/"
  else
    log "  WARN: source not found at ../${source} — skipping"
  fi
}

main() {
  log "starting aggregation (dry-run=${DRY_RUN})"

  # Phase 1: fetch per-service docs
  while IFS= read -r repo; do
    [[ -z "${repo}" || "${repo}" =~ ^# ]] && continue
    fetch_repo "${repo}"
  done < "${REPOS_FILE}"

  # Phase 2: mirror cross-cutting (standards + adr) from same .github repo
  fetch_mirror "docs/standards" "standards"
  fetch_mirror "docs/adr" "decisions"

  log "aggregation complete"
}

main "$@"
