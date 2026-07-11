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
#   - roadmap progress (verdict: transition|full-close)

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

# --- roadmap progress (authoritative close-vs-next verdict) ---
# Emit a parser-stable `verdict:` line so /task:ship proposes close-vs-next
# without re-deriving roadmap counting in the model. Priority order:
#   1. Empty `## Description` body → full-close (umbrella drop; --next would
#      even error on empty Description).
#   2. Roadmap umbrella (Roadmap: + Source item: #N headers) with the roadmap
#      file present → transition when any unchecked item other than the current
#      #N remains (i.e. work remains after it under in-order processing),
#      else full-close.
#   3. Manual umbrella (no roadmap header / file), non-empty Description →
#      full-close (item-AC tie-break; the confirmation gate keeps it safe).
emit_section "roadmap progress"
TASK_FILE="$WS_DIR/task.md"

# Description-empty detection (same awk-extract-then-strip as close.sh).
DESC_CONTENT=""
if [[ -f "$TASK_FILE" ]]; then
  DESC_CONTENT=$(awk '
    /^## Description[[:space:]]*$/ { in_desc = 1; next }
    in_desc && /^## / { exit }
    in_desc { print }
  ' "$TASK_FILE" \
    | tr '\n' ' ' \
    | sed -E 's/<!--[^-]*(-[^-]+)*-->//g' \
    | tr -d '[:space:]')
fi

if [[ -z "$DESC_CONTENT" ]]; then
  echo "roadmap: n/a (empty Description — umbrella drop)"
  echo "verdict: full-close"
else
  # Header lines (above the first ---), reusing close.sh Step 1.5 patterns.
  ROADMAP_PATH=$(awk '/^---[[:space:]]*$/{exit} /^Roadmap: /{sub(/^Roadmap: /, ""); sub(/[[:space:]]+$/, ""); print; exit}' "$TASK_FILE")
  SOURCE_ITEM_LINE=$(awk '/^---[[:space:]]*$/{exit} /^Source item: #[0-9][0-9]*/{print; exit}' "$TASK_FILE")
  SOURCE_N=$(echo "$SOURCE_ITEM_LINE" | sed -n 's/^Source item: #\([0-9][0-9]*\).*/\1/p')

  if [[ -n "$ROADMAP_PATH" && -f "$ROADMAP_PATH" && -n "$SOURCE_N" ]]; then
    # shellcheck source=../_lib/roadmap.sh
    source "$SCRIPT_DIR/../_lib/roadmap.sh"
    UNCHECKED=$(roadmap_progress_counts "$ROADMAP_PATH" | awk '/^unchecked: /{print $2}')
    UNCHECKED=${UNCHECKED:-0}
    CURRENT_UNCHECKED=$(grep -c "^### - \[ \] ${SOURCE_N}\. " "$ROADMAP_PATH" || true)
    CURRENT_UNCHECKED=${CURRENT_UNCHECKED:-0}
    REMAINING=$(( 10#$UNCHECKED - 10#$CURRENT_UNCHECKED ))
    echo "roadmap: $ROADMAP_PATH"
    echo "current item: #$SOURCE_N"
    echo "remaining after this item: $REMAINING"
    if (( REMAINING > 0 )); then
      echo "verdict: transition"
    else
      echo "verdict: full-close"
    fi
  else
    echo "roadmap: none (manual umbrella)"
    echo "verdict: full-close"
  fi
fi
echo
