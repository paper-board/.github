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
CONTENT_BASE="${DOCS_ROOT}/src/content/docs"
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

  emit_placeholder() {
    local reason="$1"
    log "  ${reason} — emitting placeholder for ${repo_base}"
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
  }

  if ! gh_out=$(gh repo clone "${repo}" "${tmp}" -- --depth=1 --quiet 2>&1); then
    # Repo may not exist yet (planned but not bootstrapped — e.g., platform,
    # billing, gateway, frontend, cli before Phase 4-7 ship them). Emit a
    # placeholder so the docs site sidebar still surfaces the section.
    log "  WARN: clone failed for ${repo}: ${gh_out}"
    emit_placeholder "clone-failed"
    return 0
  fi

  if [[ ! -d "${tmp}/docs" ]]; then
    emit_placeholder "no docs/ folder in ${repo}"
    return 0
  fi

  rm -rf "${target}"
  mkdir -p "${target}"
  cp -R "${tmp}/docs/." "${target}/"
  inject_frontmatter "${target}"
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
    inject_frontmatter "${target}"
  else
    log "  WARN: source not found at ../${source} — skipping"
  fi
}

# Inject minimal Starlight frontmatter into .md files that lack it or lack a
# `title:` key. Title derives from the first `# Heading` line (basename as
# fallback). Files whose existing frontmatter already declares `title:` are
# left untouched; files with frontmatter but no title get the key spliced in
# immediately after the opening `---`.
inject_frontmatter() {
  local dir="$1"
  while IFS= read -r -d '' file; do
    # Derive a title from the first `# Heading` line; basename fallback.
    local title
    title=$(awk '/^# / { sub(/^# /, ""); print; exit }' "${file}")
    if [[ -z "${title}" ]]; then
      title=$(basename "${file}" .md)
    fi
    title="${title//\"/\\\"}"

    local first_line
    IFS= read -r first_line < "${file}" || first_line=""

    local tmp
    tmp=$(mktemp)

    if [[ "${first_line}" == "---" ]]; then
      # File has YAML frontmatter — only inject title if absent.
      if awk '/^---/{ if (++n == 2) exit } n==1 && /^[[:space:]]*title:/ { found=1 } END { exit found ? 0 : 1 }' "${file}"; then
        # title present already — leave file untouched
        rm -f "${tmp}"
        continue
      fi
      # Insert `title: "<title>"` immediately after the opening `---`.
      awk -v t="${title}" '
        NR==1 && /^---/ { print; print "title: \"" t "\""; next }
        { print }
      ' "${file}" > "${tmp}"
    else
      # No frontmatter at all — prepend a minimal block.
      {
        printf -- '---\ntitle: "%s"\n---\n\n' "${title}"
        cat "${file}"
      } > "${tmp}"
    fi
    mv "${tmp}" "${file}"
  done < <(find "${dir}" -type f -name '*.md' -print0)
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
