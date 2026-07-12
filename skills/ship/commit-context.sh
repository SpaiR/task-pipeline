#!/usr/bin/env bash
# commit-context.sh — Gather all context needed to compose a commit message.
# Usage: commit-context.sh
#
# Outputs (to stdout) clearly-delimited sections:
#   - .task/config/config.md
#   - .task/workspace/<task-id>/summary.md (or fallback to .task/workspace/<task-id>/task.md)
#   - git status
#   - git diff --stat
#   - git log -5 --oneline

set -euo pipefail

# --- Bootstrap: resolve SCRIPT_DIR through symlinks, then load shared preamble ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=../_lib/preamble.sh
source "$SCRIPT_DIR/../_lib/preamble.sh"

require_config_md
source_resolve_ws "$@"
# task.md may not exist yet at /task:ship time in some edge cases; run_validator
# returns 0 when the target file is missing (mirrors the original guard).
run_validator task "$WS_DIR/task.md"

# --- config.md ---
emit_section "config.md"
emit_file "$AI_DIR/config/config.md"
echo

# --- Referenced commit-format docs (e.g. CONTRIBUTING.md) ---
# config.md → "Commit Format" may emit `**Source:** <path.md>` instead of duplicating
# project commit rules. Bundle each referenced doc here so /task:ship applies its
# rules directly and stays in sync without re-running /task:bootstrap.
REF_PATHS=$(awk '/^## Commit Format[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag' "$AI_DIR/config/config.md" 2>/dev/null \
  | { grep -oE '\*\*Source:\*\*[[:space:]]+`?[^[:space:]`]+\.md`?' || true; } \
  | sed -E 's/^\*\*Source:\*\*[[:space:]]+`?([^[:space:]`]+\.md)`?.*/\1/' \
  | awk '!seen[$0]++' || true)
if [[ -n "$REF_PATHS" ]]; then
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    case "$ref" in
      .task/*|/*) continue ;;
    esac
    if [[ -f "$ref" ]]; then
      emit_section "referenced: $ref"
      cat "$ref"
      echo
    fi
  done <<< "$REF_PATHS"
fi

# --- summary.md (primary) or task.md (fallback) ---
SUMMARY="$WS_DIR/summary.md"
if [[ -s "$SUMMARY" ]]; then
  emit_section "summary.md (primary)"
  cat "$SUMMARY"
  echo
else
  emit_section "summary.md"
  if [[ -f "$SUMMARY" ]]; then
    echo "(empty — falling back to task.md)"
  else
    echo "(missing — falling back to task.md)"
  fi
  echo

  emit_section "task.md (fallback)"
  emit_file "$WS_DIR/task.md"
  echo
fi

# --- git context (tolerate empty repo / no commits) ---
emit_section "git status"
git status || true
echo

emit_section "git diff --stat"
git diff --stat || true
echo

emit_section "git log -5 --oneline"
git log -5 --oneline 2>&1 || true
echo
