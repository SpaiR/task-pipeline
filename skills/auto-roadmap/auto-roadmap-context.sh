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
#   - .task-current exists at the worktree root (auto-roadmap refuses mid-flight
#     umbrellas — resume is the user's manual job)
#   - .task/workspace/*/auto.lock exists (stale per-umbrella sentinel
#     from a previously failed /task:auto-roadmap run, or an active run owned
#     by another worktree sharing this .task/)
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
# /task:auto-roadmap is forward-only — an existing .task-current means a
# mid-flight umbrella (manual or from a prior failed run) that auto-roadmap must
# not silently overwrite. Resume = user's manual job (/task:ship --full).
if [[ -f .task-current ]]; then
  CURRENT=$(head -n 1 .task-current | tr -d '[:space:]')
  echo "ERROR: .task-current exists at the worktree root (points to '$CURRENT') — auto-roadmap is not for resume." >&2
  echo "  Either run /task:ship (default) to transition the current subtask," >&2
  echo "  or /task:ship --full to drop the umbrella entirely. Then rerun /task:auto-roadmap." >&2
  exit 1
fi

# --- Precondition: no stale auto.lock anywhere in the workspace ---
# A per-umbrella auto.lock present means a prior /task:auto-roadmap run
# failed and left the sentinel behind, OR another worktree (sharing this .task/)
# currently owns an autopilot run on that umbrella. Either way, this worktree
# must not start a new run until the user cleans up.
STALE_LOCKS=()
if [[ -d "$WS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && STALE_LOCKS+=("$f")
  done < <(find "$WS_DIR" -mindepth 2 -maxdepth 2 -type f -name auto.lock 2>/dev/null)
fi
if (( ${#STALE_LOCKS[@]} > 0 )); then
  echo "ERROR: stale auto.lock present in the workspace:" >&2
  for l in "${STALE_LOCKS[@]}"; do echo "  $l" >&2; done
  echo "  A prior /task:auto-roadmap run was aborted (or another worktree owns it)." >&2
  echo "  If you are sure no run is active, run /task:ship --full to clean up the corresponding umbrella, or remove the sentinel manually." >&2
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
# WARN-on-legacy stays silent; validate.sh (invoked above) already surfaces it.
ROADMAP_PATH=$(resolve_roadmap_path "$ROADMAP_ARG")
if [[ -z "$ROADMAP_PATH" ]]; then
  echo "ERROR: roadmap '$ROADMAP_ARG' not found (looked at $ROADMAP_ARG, $AI_DIR/roadmap/$ROADMAP_ARG(.md), $AI_DIR/todo/$ROADMAP_ARG(.md))." >&2
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
