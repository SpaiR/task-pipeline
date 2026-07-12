#!/usr/bin/env bash
# auto-roadmap-context.sh — Gather all context needed by /task:auto-roadmap in one call.
# Usage: auto-roadmap-context.sh [<roadmap-path-or-slug>]
#
# Outputs (to stdout) clearly-delimited sections:
#   - autoroadmap-precondition: ok
#   - config.md
#   - roadmap-resolution: path / mtime
#   - roadmap-progress: counts of [ ] / [x]
#   - items-unchecked: tab-separated `<N>\t<title>` lines (un-checked items only)
#
# Hard-stop preconditions (exit 1 with ERROR ... message on stderr):
#   - .task/config/config.md missing
#   - an active-task pointer exists for this worktree (auto-roadmap refuses
#     mid-flight tasks — resume is the user's manual job)
#   - .task/roadmap/*.lock exists (a run lock from a still-active
#     /task:auto-roadmap run — possibly in another worktree sharing this
#     .task/ — or one left behind by a crashed run)
#
# When arg passed: validate.sh roadmap <arg> is invoked; failure → exit 1.
# When arg omitted: skip roadmap-related sections (caller wizard will pick).

set -euo pipefail

# --- Bootstrap: resolve SCRIPT_DIR through symlinks, then load shared preamble ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=../_lib/preamble.sh
source "$SCRIPT_DIR/../_lib/preamble.sh"
# Roadmap utilities (resolve_roadmap_path, roadmap_mtime, roadmap_progress_counts).
# shellcheck source=../_lib/roadmap.sh
source "$SCRIPT_DIR/../_lib/roadmap.sh"

require_config_md
# auto-roadmap operates on the workspace ROOT (umbrella container), not a single
# umbrella's subfolder — `.task-current` MUST be absent at this stage (the next
# gate enforces that). Distinct from resolve_ws() semantics.
set_workspace_root

# --- Precondition: no active umbrella in this worktree ---
# /task:auto-roadmap is forward-only — an existing active-task pointer means a
# mid-flight umbrella (manual or from a prior failed run) that auto-roadmap must
# not silently overwrite. Resume = user's manual job (/task:ship).
# The pointer lives in git's per-worktree dir (task_current_path), so it is
# naturally scoped to THIS worktree regardless of cwd.
TASK_CURRENT="$(task_current_path)"
if [[ -f "$TASK_CURRENT" ]]; then
  CURRENT=$(head -n 1 "$TASK_CURRENT" | tr -d '[:space:]')
  echo "ERROR: an active-task pointer exists for this worktree (points to '$CURRENT') — auto-roadmap is not for resume." >&2
  echo "  Run /task:ship to close the current task, then rerun /task:auto-roadmap." >&2
  exit 1
fi

# --- Precondition: no run lock under .task/roadmap/ ---
# A `.task/roadmap/<slug>.lock` present means a /task:auto-roadmap run is
# currently active (possibly in another worktree sharing this .task/), OR a run
# crashed and left the lock behind. Either way, this worktree must not start a
# new run until the user cleans up. (The driver removes its own lock on clean
# finish and on every handled failure — a lingering lock is a crash.)
STALE_LOCKS=()
if [[ -d "$AI_DIR/roadmap" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && STALE_LOCKS+=("$f")
  done < <(find "$AI_DIR/roadmap" -mindepth 1 -maxdepth 1 -type f -name '*.lock' 2>/dev/null)
fi
if (( ${#STALE_LOCKS[@]} > 0 )); then
  echo "ERROR: a /task:auto-roadmap run lock is present:" >&2
  for l in "${STALE_LOCKS[@]}"; do echo "  $l" >&2; done
  echo "  A run is active (possibly in another worktree), or a prior run crashed." >&2
  echo "  If you are sure no run is active, remove the lock file(s) above and rerun." >&2
  exit 1
fi

# --- autoroadmap-precondition marker ---
# Emitted unconditionally on success so the SKILL can grep for `autoroadmap-precondition: ok`
# without parsing stderr. On precondition failure we already exit 1 above
# (the section never prints), so any non-zero exit propagates loudly to the SKILL.
emit_section "autoroadmap-precondition"
echo "ok"
echo

# --- config.md ---
emit_section "config.md"
emit_file "$AI_DIR/config/config.md"
echo

# Sibling validate.sh path (SCRIPT_DIR is set by the bootstrap above).
VALIDATOR="$SCRIPT_DIR/../validate/validate.sh"

# --- Optional: roadmap argument ---
ROADMAP_ARG="${1:-}"
if [[ -z "$ROADMAP_ARG" ]]; then
  emit_section "roadmap-resolution"
  echo "(no roadmap argument — wizard upstream will list .task/roadmap/*.md)"
  echo

  emit_section "roadmaps-available"
  if [[ -d "$AI_DIR/roadmap" ]]; then
    found=0
    for f in "$AI_DIR/roadmap"/*.md; do
      [[ -f "$f" ]] || continue
      # Skip sidecars — spec/refine files live here but are not roadmaps
      # (no `### - [ ] N.` headings). Mirrors validate.sh's `all` carve-out.
      case "$f" in *.refine.md|*.spec.md) continue ;; esac
      found=1
      slug=$(basename "$f" .md)
      if [[ -x "$VALIDATOR" ]] && ! bash "$VALIDATOR" roadmap "$f" >/dev/null 2>&1; then
        echo "$slug	[malformed — run \`bash $VALIDATOR roadmap $slug\` to inspect]	$f"
        continue
      fi
      counts=$(roadmap_progress_counts "$f")
      total=$(echo "$counts"  | awk -F': ' '/^total: /  {print $2}')
      done_n=$(echo "$counts" | awk -F': ' '/^done: /   {print $2}')
      echo "$slug	$done_n/$total	$f"
    done
    if [[ "$found" == "0" ]]; then
      echo "(no roadmap files in $AI_DIR/roadmap/ — run /task:roadmap to create one)"
    fi
  else
    echo "(no $AI_DIR/roadmap/ directory — run /task:roadmap to create one)"
  fi
  echo
  exit 0
fi

# --- Validate roadmap ---
if [[ -x "$VALIDATOR" ]]; then
  bash "$VALIDATOR" roadmap "$ROADMAP_ARG" >&2 || exit 1
fi

# --- Resolve roadmap path (shared with validate.sh) ---
ROADMAP_PATH=$(resolve_roadmap_path "$ROADMAP_ARG")
if [[ -z "$ROADMAP_PATH" ]]; then
  echo "ERROR: roadmap '$ROADMAP_ARG' not found (looked at $ROADMAP_ARG, $AI_DIR/roadmap/$ROADMAP_ARG(.md))." >&2
  exit 1
fi

# Roadmap mtime — captured for race-detection in the orchestrator's main-thread loop.
ROADMAP_MTIME=$(roadmap_mtime "$ROADMAP_PATH")

emit_section "roadmap-resolution"
echo "path: $ROADMAP_PATH"
echo "roadmap_mtime: $ROADMAP_MTIME"
echo

# --- Progress counts (delegated to _lib/roadmap.sh) ---
PROGRESS=$(roadmap_progress_counts "$ROADMAP_PATH")
UNCHECKED=$(echo "$PROGRESS" | awk -F': ' '/^unchecked: / {print $2}')

emit_section "roadmap-progress"
echo "$PROGRESS"
echo

# --- Un-checked items list (tab-separated `<N>\t<title>`) ---
emit_section "items-unchecked"
if [[ "$UNCHECKED" -gt 0 ]]; then
  grep -E '^### - \[ \] [0-9]+\. ' "$ROADMAP_PATH" \
    | sed -E 's/^### - \[ \] ([0-9]+)\. (.+)$/\1	\2/'
else
  echo "(none — all roadmap items are [x] or no items)"
fi
echo
