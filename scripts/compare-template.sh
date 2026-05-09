#!/usr/bin/env bash
# compare-template.sh — drift detector consumed by .github/workflows/template-drift.yml.
#
# Compares a backend service repo against an init.sh-rendered copy of
# paper-board/service-template@main. Two tiers:
#   Tier 1 — exact content match (drift = required-fix)
#   Tier 2 — presence-only (deletion = drift; content may diverge)
# Files outside both tiers are unchecked (services own their domain code).
#
# Allowed per-service deltas live in template-drift-allowlist.md (declarative
# documentation; this script does not yet read it programmatically).
#
# Usage:
#   compare-template.sh --template <rendered_dir> --service <repo_dir> --service-name <name>
#
# Exit codes:
#   0 — no drift
#   1 — drift detected
#   2 — usage error

set -euo pipefail

TEMPLATE_DIR=
SERVICE_DIR=
SERVICE_NAME=

while [ $# -gt 0 ]; do
  case "$1" in
    --template)     TEMPLATE_DIR="$2"; shift 2 ;;
    --service)      SERVICE_DIR="$2"; shift 2 ;;
    --service-name) SERVICE_NAME="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "✗ unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${TEMPLATE_DIR}" ] || [ -z "${SERVICE_DIR}" ] || [ -z "${SERVICE_NAME}" ]; then
  echo "✗ --template, --service, --service-name all required" >&2
  exit 2
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "✗ template dir not found: $TEMPLATE_DIR" >&2
  exit 2
fi
if [ ! -d "$SERVICE_DIR" ]; then
  echo "✗ service dir not found: $SERVICE_DIR" >&2
  exit 2
fi

drift_count=0

# Tier 1 — files that must match the rendered template byte-for-byte.
TIER1=(
  "internal/middleware/middleware.go"
  "migrations/embed.go"
  "Dockerfile"
  ".github/workflows/release.yml"
  ".github/workflows/ci.yml"
)

echo "## Tier 1 (exact match)"
for f in "${TIER1[@]}"; do
  if [ ! -f "$SERVICE_DIR/$f" ]; then
    echo "MISSING: $f"
    drift_count=$((drift_count + 1))
    continue
  fi
  if ! diff -q "$TEMPLATE_DIR/$f" "$SERVICE_DIR/$f" >/dev/null 2>&1; then
    echo "DIVERGED: $f"
    echo '```diff'
    diff -u "$TEMPLATE_DIR/$f" "$SERVICE_DIR/$f" || true
    echo '```'
    drift_count=$((drift_count + 1))
  else
    echo "OK: $f"
  fi
done

# Tier 2 — paths that must exist in the service. Content may diverge.
TIER2=(
  "Makefile"
  ".golangci.yml"
  "docker-compose.yaml"
  "sqlc.yaml"
  "cmd/migrator/main.go"
  "cmd/server/main.go"
  "internal/api/api.go"
  "internal/core"
  "internal/config/config.go"
  "internal/store/store.go"
  "scripts/cover-check.sh"
  "helm/${SERVICE_NAME}/Chart.yaml"
  "helm/${SERVICE_NAME}/values.yaml"
  "helm/${SERVICE_NAME}/templates/_helpers.tpl"
  "helm/${SERVICE_NAME}/templates/migrator-job.yaml"
  "helm/${SERVICE_NAME}/templates/server-deployment.yaml"
  "helm/${SERVICE_NAME}/templates/server-service.yaml"
  "helm/${SERVICE_NAME}/templates/server-configmap.yaml"
)

echo
echo "## Tier 2 (presence)"
for p in "${TIER2[@]}"; do
  if [ ! -e "$SERVICE_DIR/$p" ]; then
    echo "MISSING: $p"
    drift_count=$((drift_count + 1))
  else
    echo "OK: $p"
  fi
done

# Migration version 1 must exist; descriptive name suffix is service-local
# (e.g. agents uses 000001_minimal, template's init.sh ships 000001_init).
# Glob match keeps both conventions valid.
for direction in up down; do
  # shellcheck disable=SC2086
  if ! ls $SERVICE_DIR/migrations/schema/000001_*.${direction}.sql >/dev/null 2>&1; then
    echo "MISSING: migrations/schema/000001_*.${direction}.sql"
    drift_count=$((drift_count + 1))
  else
    echo "OK: migrations/schema/000001_*.${direction}.sql"
  fi
done

echo
if [ "$drift_count" -eq 0 ]; then
  echo "✓ no drift detected for $SERVICE_NAME"
  exit 0
fi

echo "✗ $drift_count drift item(s) detected for $SERVICE_NAME"
exit 1
