#!/usr/bin/env bash
# close.sh — Close the current task. One mode (full close):
#   archive everything including task.md to .task/log/<task-id>/<N>-<slug>/,
#   remove the entire .task/workspace/<task-id>/ subfolder, and remove the
#   active-task pointer — the workspace returns to empty.
#
# Roadmap auto-mark: if task.md carries `Roadmap: <path>` and `Source item:
# #<N> — <title>` lines in the header AND Description is non-empty, flips the
# matching `### - [ ] <N>. ` heading to `### - [x] <N>. ` in the roadmap. Loud
# failure on stale paths or unknown N (silent skip would let the next
# /task:design re-pick the same item).
#
# Usage:
#   close.sh <slug>
#
# Workspace resolution uses _lib/resolve-ws.sh — reads the active-task pointer
# to find the active umbrella's subfolder. The slug positional is NOT a task-id;
# resolve_ws() reads no positionals here.

set -euo pipefail

# --- Parse args ---
# Contract: <slug> is MANDATORY at this layer. close/SKILL.md Step 1 (main
# thread) auto-derives a slug from .task/workspace/<task-id>/summary.md
# (primary) or task.md Description (fallback) and passes it explicitly.
# close.sh is not meant to be user-callable directly — users invoke it via
# /task:ship. /task:auto-roadmap's per-item ship lets the slug be
# auto-derived from summary.md (no explicit slug).
# Full close is the only mode: `close.sh <slug>` closes the task entirely. The
# removed `--full` / `--next` flags are guarded below so a stray occurrence
# fails loud rather than being silently captured as the mandatory <slug>
# positional.
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --full)
      echo "ERROR: --full removed — /task:ship already closes the task (no flag needed)." >&2
      exit 1
      ;;
    --next)
      echo "ERROR: --next removed — /task:ship now always closes the task (subtask-transition mode was dropped)." >&2
      exit 1
      ;;
    *)      ARGS+=("$arg") ;;
  esac
done
SLUG="${ARGS[0]:?Usage: close.sh <slug>}"

# --- Bootstrap: resolve SCRIPT_DIR through symlinks, then load shared preamble ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=../_lib/preamble.sh
source "$SCRIPT_DIR/../_lib/preamble.sh"

require_config_md
# Resolve workspace from the active-task pointer. Note: SLUG was already captured above
# so resolve_ws sees no positional args (it would otherwise treat SLUG as a
# task-id override — that's the exact bug close.sh's old code avoided by
# calling resolve_ws with no args).
source_resolve_ws
TASK_FILE="$WS_DIR/task.md"
# TASK_ID from the active-task pointer IS the lowercase form (the path-side identifier).
# task.md's header may preserve the original case (e.g. `# [DT-1234]`); we
# read that for sanity checks below, but archive paths use the resolver's id.
TASK_ID_LOWER="$TASK_ID"

# --- Precondition: task.md format (validate sibling skill) ---
# task.md may have been moved/removed in an aborted prior close run; the helper
# returns 0 in that case so we fall through to the explicit "$TASK_FILE not
# found" check below for a clearer error.
run_validator task "$TASK_FILE"

# --- Step 1: Read task.md ---
if [[ ! -f "$TASK_FILE" ]]; then
  echo "ERROR: $TASK_FILE not found (resolved from active-task pointer=$TASK_ID)."
  exit 1
fi

# Extract task-id from first line: # [TASK-ID] ... (header form, may be uppercase).
FIRST_LINE=$(head -1 "$TASK_FILE")
# Pattern mirrors validate.sh (`^# \[[^]]+\] .+$`): non-empty task-id,
# space after `]`, non-empty title.
HEADER_TASK_ID=$(echo "$FIRST_LINE" | sed -nE 's/^# \[([^]]+)\] .+$/\1/p')
if [[ -z "$HEADER_TASK_ID" ]]; then
  echo "ERROR: Could not extract task-id from header: $FIRST_LINE"
  exit 1
fi
HEADER_TASK_ID_LOWER=$(echo "$HEADER_TASK_ID" | tr '[:upper:]' '[:lower:]')
if [[ "$HEADER_TASK_ID_LOWER" != "$TASK_ID_LOWER" ]]; then
  echo "ERROR: active-task pointer points to '$TASK_ID_LOWER' but $TASK_FILE line 1 carries task-id '$HEADER_TASK_ID' (lowercased '$HEADER_TASK_ID_LOWER'). Refusing to archive against mismatched ids." >&2
  exit 1
fi
TASK_ID="$HEADER_TASK_ID"  # used for the header display below; LOG path keeps TASK_ID_LOWER

# Full close allows an empty Description (e.g. dropping an umbrella after an
# aborted run). DESC_CONTENT is still computed below — the roadmap auto-mark
# only fires when a subtask actually produced Description content.
DESC_CONTENT=$(awk '
  /^## Description[[:space:]]*$/ { in_desc = 1; next }
  in_desc && /^## / { exit }
  in_desc { print }
' "$TASK_FILE" \
  | tr '\n' ' ' \
  | sed -E 's/<!--[^-]*(-[^-]+)*-->//g' \
  | tr -d '[:space:]')

# --- Step 1.5: Auto-mark roadmap item (roadmap-mode only) ---
# When Description is non-empty (a subtask actually finished) AND the header
# carries both `Roadmap:` and `Source item: #<N> — <title>` lines, flip the
# matching `- [ ]` to `- [x]` in the source roadmap. Loud failure on stale
# roadmap paths or unknown item numbers — silent skip would let the next
# /task:design re-pick the same item.
ROADMAP_MODE=0
ROADMAP_PATH=""
SOURCE_N=""
if [[ -n "$DESC_CONTENT" ]]; then
  ROADMAP_PATH=$(awk '/^---[[:space:]]*$/{exit} /^Roadmap: /{sub(/^Roadmap: /, ""); sub(/[[:space:]]+$/, ""); print; exit}' "$TASK_FILE")
  SOURCE_ITEM_LINE=$(awk '/^---[[:space:]]*$/{exit} /^Source item: #[0-9][0-9]*/{print; exit}' "$TASK_FILE")

  if [[ -n "$ROADMAP_PATH" && -n "$SOURCE_ITEM_LINE" ]]; then
    SOURCE_N=$(echo "$SOURCE_ITEM_LINE" | sed -n 's/^Source item: #\([0-9][0-9]*\).*/\1/p')
    if [[ -z "$SOURCE_N" ]]; then
      echo "ERROR: Could not parse item number from header line: $SOURCE_ITEM_LINE" >&2
      exit 1
    fi

    if [[ ! -f "$ROADMAP_PATH" ]]; then
      echo "ERROR: Roadmap file '$ROADMAP_PATH' not found; cannot auto-mark item #$SOURCE_N. Restore the file, edit task.md to point at the correct path, or remove the Roadmap:/Source item: lines to disable auto-mark." >&2
      exit 1
    fi

    UNCHECKED=$(grep -c "^### - \[ \] ${SOURCE_N}\. " "$ROADMAP_PATH" || true)
    if [[ "$UNCHECKED" -gt 0 ]]; then
      TMPFILE=$(mktemp 2>/dev/null || echo "/tmp/task-close-roadmap-$$.tmp")
      sed "s|^### - \[ \] ${SOURCE_N}\. |### - [x] ${SOURCE_N}. |" "$ROADMAP_PATH" > "$TMPFILE"
      mv "$TMPFILE" "$ROADMAP_PATH"
      echo "Roadmap: marked item #$SOURCE_N as done in $ROADMAP_PATH"
      ROADMAP_MODE=1
    else
      CHECKED=$(grep -cE "^### - \[[x~>-]\] ${SOURCE_N}\. " "$ROADMAP_PATH" || true)
      if [[ "$CHECKED" -gt 0 ]]; then
        echo "Roadmap: item #$SOURCE_N already marked in $ROADMAP_PATH, leaving as-is"
        ROADMAP_MODE=1
      else
        NOCHECK=$(grep -c "^### ${SOURCE_N}\. " "$ROADMAP_PATH" || true)
        if [[ "$NOCHECK" -gt 0 ]]; then
          echo "ERROR: Roadmap item #$SOURCE_N in '$ROADMAP_PATH' has no checkbox prefix; cannot auto-mark. Add '- [ ]' to the heading or remove the Source item: line from task.md to bypass." >&2
          exit 1
        fi
        echo "ERROR: Item #$SOURCE_N not found in roadmap '$ROADMAP_PATH'. Edit task.md (Source item: line) or the roadmap before retrying close." >&2
        exit 1
      fi
    fi
  fi
fi

# --- Step 2: Determine N ---
LOG_DIR="$AI_DIR/log/$TASK_ID_LOWER"
mkdir -p "$LOG_DIR"

MAX_N=-1
for dir in "$LOG_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  BASENAME=$(basename "$dir")
  NUM=$(echo "$BASENAME" | sed -n 's/^\([0-9]*\)-.*/\1/p')
  # Force base-10: a folder like 08-slug / 09-slug would otherwise be parsed as
  # an invalid octal literal by (( )) and abort under set -e.
  if [[ -n "$NUM" ]] && (( 10#$NUM > MAX_N )); then
    MAX_N=$((10#$NUM))
  fi
done
N=$(( MAX_N + 1 ))

# --- Step 3: Create subfolder and move files ---
SUBFOLDER="$LOG_DIR/${N}-${SLUG}"
mkdir -p "$SUBFOLDER"

# All pipeline artifacts archived, including task.md.
# NOTE: orchestrator artifacts (auto-error.log) are intentionally NOT archived
# here. They belong to the /task:auto-roadmap run, not the task. The full close
# removes them together with the whole subfolder below — the manual
# `/task:ship` is the documented way to clean up after a failed run.
[[ -f "$WS_DIR/plan.md" ]] && cp "$WS_DIR/plan.md" "$SUBFOLDER/plan.md"
[[ -f "$WS_DIR/audit.md" ]] && cp "$WS_DIR/audit.md" "$SUBFOLDER/audit.md"
[[ -f "$WS_DIR/summary.md" ]] && cp "$WS_DIR/summary.md" "$SUBFOLDER/summary.md"
cp "$TASK_FILE" "$SUBFOLDER/task.md"

# --- Step 4: Clean up active slot ---
# Drop the entire umbrella subfolder and the per-worktree pointer. This also
# sweeps any orchestrator state (auto-error.log) that survived a failed
# /task:auto-roadmap run.
rm -rf "$WS_DIR"
# The active-task pointer lives in git's per-worktree dir (task_current_path);
# resolve it there so a drifted cwd doesn't leave it behind.
rm -f "$(task_current_path)"

# --- Report ---
echo "OK"
echo "Archived to: $SUBFOLDER/"
ARCHIVED=""
for f in task.md plan.md audit.md summary.md; do
  if [[ -f "$SUBFOLDER/$f" ]]; then
    ARCHIVED="${ARCHIVED:+$ARCHIVED, }$f"
  fi
done
echo "Files archived: $ARCHIVED"

echo "Workspace subfolder '$WS_DIR' and the active-task pointer removed."
if [[ "$ROADMAP_MODE" -eq 1 ]]; then
  ROADMAP_SLUG=$(basename "$ROADMAP_PATH" .md)
  echo "Next: /task:design --from $ROADMAP_SLUG for the next roadmap item, or /task:design to start something new."
else
  echo "Next: /task:design to start a new task (to revive this one, restore it manually from .task/log/)."
fi
