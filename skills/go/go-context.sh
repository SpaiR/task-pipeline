#!/usr/bin/env bash
# go-context.sh — Hard-stop preconditions for `/task:go --auto` (the autonomous,
# N=1 mini-auto-roadmap mode). Mirrors auto-roadmap-context.sh gates 1-3 without
# the roadmap resolution — `/task:go --auto` opens an ad-hoc task from raw input,
# it does not read a roadmap file.
#
# Hard-stop preconditions (exit 1 with ERROR ... on stderr):
#   - .task/config/config.md missing
#   - .task-current exists at the worktree root (a task is in flight; --auto is a
#     fresh-start mode — resume interactively with /task:go instead)
#   - .task/workspace/*/auto.lock exists (an autonomous run — this worktree's or
#     another sharing this .task/ — already owns an umbrella; cross-worktree mutex
#     shared with /task:auto-roadmap)
#
# On success: prints `go-precondition: ok` to stdout.

set -euo pipefail

# --- Bootstrap: resolve SCRIPT_DIR through symlinks, then load shared preamble ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=../_lib/preamble.sh
source "$SCRIPT_DIR/../_lib/preamble.sh"

require_config_md
# --auto operates on the workspace ROOT (no umbrella yet) — `.task-current` MUST
# be absent (next gate enforces that). Same posture as auto-roadmap-context.sh;
# distinct from resolve_ws() semantics.
set_workspace_root

# --- Precondition: no active umbrella in this worktree ---
# --auto is fresh-start only. An existing .task-current means a mid-flight
# umbrella (manual or from a prior run) that --auto must not silently overwrite;
# resume is the interactive /task:go's job. `.task-current` sits at the project
# root beside `.task` (never symlinked); resolve it off the discovered root, not
# cwd, so a drifted shell still sees it.
TASK_CURRENT="$(dirname "$AI_DIR")/.task-current"
if [[ -f "$TASK_CURRENT" ]]; then
  CURRENT=$(head -n 1 "$TASK_CURRENT" | tr -d '[:space:]')
  echo "ERROR: .task-current exists at the worktree root (points to '$CURRENT') — /task:go --auto is a fresh-start mode, not resume." >&2
  echo "  Run /task:go (interactive) to resume the task in flight," >&2
  echo "  or /task:ship (default) / /task:ship --full to close it. Then rerun /task:go --auto." >&2
  exit 1
fi

# --- Precondition: no stale/active auto.lock anywhere in the workspace ---
# A per-umbrella auto.lock present means an autonomous run (this worktree's, or
# another worktree sharing this .task/) currently owns an umbrella, or a prior
# run was aborted. Either way, refuse until the user cleans up. Shared mutex with
# /task:auto-roadmap (its Step 0 gate 3 scans the same glob).
STALE_LOCKS=()
if [[ -d "$WS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && STALE_LOCKS+=("$f")
  done < <(find "$WS_DIR" -mindepth 2 -maxdepth 2 -type f -name auto.lock 2>/dev/null)
fi
if (( ${#STALE_LOCKS[@]} > 0 )); then
  echo "ERROR: an autonomous run already owns an umbrella (auto.lock present):" >&2
  for l in "${STALE_LOCKS[@]}"; do echo "  $l" >&2; done
  echo "  Another /task:go --auto or /task:auto-roadmap run is active or was aborted." >&2
  echo "  If no run is active, resume it with /task:go, or run /task:ship --full to clean up. Then rerun." >&2
  exit 1
fi

echo "go-precondition: ok"
