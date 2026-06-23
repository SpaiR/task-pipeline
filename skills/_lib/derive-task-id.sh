#!/usr/bin/env bash
# derive-task-id.sh — Derive the task-id from a roadmap file + item number.
#
# Single source of truth for the algorithm described in skills/design/phases/open.md
# (Mode 2 → Step 2). `/task:design --from` invokes it directly so the same id is
# produced whether the user opens an umbrella manually or via /task:auto-roadmap
# (whose first subagent runs the same /task:design --from path).
#
# Usage:
#   derive-task-id.sh <roadmap-path> <item-N> [extra-context-string]
#
# Priority (highest to lowest):
#   1. Ticket pattern ([A-Z]+-[0-9]+) inside the extra-context-string. Case preserved.
#   2. Ticket pattern inside the item title (heading "### (- \[[ x~>-]\] )?<N>\. (.+)$"). Case preserved.
#   3. Roadmap basename slug (.md stripped, lowercased). If longer than 30 chars,
#      truncated at the last hyphen before position 30.
#
# Output: task-id to stdout, exit 0 on success. The header in task.md preserves
# the original case (e.g. `# [DT-1234] ...`); callers must lowercase the output
# themselves when forming workspace/log paths or .task-current contents.

set -euo pipefail

ROADMAP="${1:-}"
ITEM_N="${2:-}"
EXTRA="${3:-}"

if [[ -z "$ROADMAP" || -z "$ITEM_N" ]]; then
  echo "ERROR: usage: derive-task-id.sh <roadmap-path> <item-N> [extra-context]" >&2
  exit 1
fi
if [[ ! -f "$ROADMAP" ]]; then
  echo "ERROR: roadmap '$ROADMAP' not found." >&2
  exit 1
fi
if ! [[ "$ITEM_N" =~ ^[0-9]+$ ]]; then
  echo "ERROR: item-N must be a positive integer, got '$ITEM_N'." >&2
  exit 1
fi

# Priority 1: ticket inside extra-context-string. Case preserved.
if [[ -n "$EXTRA" ]]; then
  T=$(printf '%s' "$EXTRA" | grep -oE '[A-Z]+-[0-9]+' | head -n 1 || true)
  if [[ -n "$T" ]]; then
    printf '%s\n' "$T"
    exit 0
  fi
fi

# Priority 2: ticket inside the item title for the requested N. Case preserved.
# Matches "### <N>. ..." with or without a leading checkbox like "- [ ]"/"- [x]"/"- [~]"/"- [>]"/"- [-]".
TITLE=$(grep -E "^### (- \[[ x~>-]\] )?${ITEM_N}\. .+$" "$ROADMAP" | head -n 1 || true)
if [[ -n "$TITLE" ]]; then
  TITLE_TEXT=$(printf '%s' "$TITLE" | sed -E "s/^### (- \[[ x~>-]\] )?${ITEM_N}\. //")
  T=$(printf '%s' "$TITLE_TEXT" | grep -oE '[A-Z]+-[0-9]+' | head -n 1 || true)
  if [[ -n "$T" ]]; then
    printf '%s\n' "$T"
    exit 0
  fi
fi

# Priority 3: roadmap basename slug, lowercased, ≤30 chars (truncated at last hyphen).
SLUG=$(basename "$ROADMAP" .md | tr '[:upper:]' '[:lower:]')
if (( ${#SLUG} > 30 )); then
  TRUNC="${SLUG:0:30}"
  if [[ "$TRUNC" == *-* ]]; then
    SLUG="${TRUNC%-*}"
  else
    SLUG="$TRUNC"
  fi
fi
printf '%s\n' "$SLUG"
