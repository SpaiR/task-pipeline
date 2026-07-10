#!/usr/bin/env bash
# resolve-ws.sh — Resolve the workspace subfolder for the current task.
#
# Sourced (NOT exec'd) by callers. Provides a `resolve_ws` function that, on
# success, exports:
#   - TASK_ID: the task identifier (verbatim, lowercase by convention upstream)
#   - WS_DIR:  "$AI_DIR/workspace/$TASK_ID"
#   - AI_DIR:  the discovered `.task` directory (see find_ai_dir below).
#
# Resolution priority (highest to lowest):
#   1. Env $TASK_ID_OVERRIDE  — used by skills that derive task-id from another
#      source (e.g. close.sh parses task.md line 1, where the in-flight umbrella's
#      id is the source of truth, not a possibly-stale .task-current).
#   2. First positional argument ($1) — used by callers that pass the id explicitly.
#   3. Contents of .task-current (a single line: the task-id) at the discovered
#      root — `$(dirname "$AI_DIR")`, NOT cwd; the two coincide only when cwd is
#      already the project root.
#
# On failure: prints to stderr and returns non-zero. Callers MUST handle the
# return code, e.g.: `resolve_ws "$@" || exit 1`.
#
# Usage (from a sibling script):
#   SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
#   resolve_ws "$@" || exit 1
#   # now $TASK_ID and $WS_DIR are set

# find_ai_dir — git-style upward discovery of the pipeline root.
#
# Walks up from $PWD to `/` and sets AI_DIR to the first ancestor's `.task`
# whose `.task/config/config.md` exists. If none is found, falls back to the
# nearest ancestor carrying a `.task-current` pointer, then (belt-and-braces)
# to `$CLAUDE_PROJECT_DIR/.task` when that env var is set inside a hook. Failing
# all three, AI_DIR is left as the relative `.task` — identical to the historical
# default, so a call from outside any project still fails cleanly on the config
# gate with the same "config.md not found" message.
#
# AI_DIR is exported as an ABSOLUTE `<root>/.task` path, but the `.task`
# component is appended literally — never `cd`'d into — so a linked-worktree
# `.task` symlink is preserved and `dirname "$AI_DIR"` still points at the
# worktree root where the local (never-symlinked) `.task-current` lives.
#
# Only acts when AI_DIR is unset, so a caller that pins AI_DIR keeps control.
# macOS-safe: no `realpath` / `readlink -f` — only `cd … && pwd`, `dirname`,
# and string ops.
find_ai_dir() {
  [[ -n "${AI_DIR:-}" ]] && { export AI_DIR; return 0; }

  local dir config_root="" current_root=""
  dir=$(pwd)
  while :; do
    if [[ -z "$config_root" && -f "$dir/.task/config/config.md" ]]; then
      config_root="$dir"
    fi
    if [[ -z "$current_root" && -f "$dir/.task-current" ]]; then
      current_root="$dir"
    fi
    [[ -n "$config_root" ]] && break
    [[ "$dir" == "/" ]] && break
    dir=$(dirname "$dir")
  done

  local root="${config_root:-$current_root}"
  if [[ -z "$root" && -n "${CLAUDE_PROJECT_DIR:-}" \
        && -f "$CLAUDE_PROJECT_DIR/.task/config/config.md" ]]; then
    root="$CLAUDE_PROJECT_DIR"
  fi

  if [[ -n "$root" ]]; then
    AI_DIR="$root/.task"
  else
    AI_DIR=".task"
  fi
  export AI_DIR
}

find_ai_dir

# _linked_worktree_without_task — true when cwd is a *linked* git worktree that
# has no local `.task` (real dir or symlink). Used only on resolver error paths
# to point the user at `/task:bootstrap` join-mode (which links the shared
# `.task/` from the main worktree). Guard order keeps git off the happy path:
# the `! -e "$AI_DIR"` test fails fast in any normally-set-up tree, so the git
# subprocesses run only when `.task` is already absent. `realpath`/`readlink -f`
# are intentionally avoided (not built-in on macOS) — compare `cd … && pwd`.
_linked_worktree_without_task() {
  [[ ! -e "$AI_DIR" ]] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local gd common
  gd=$(git rev-parse --git-dir 2>/dev/null) || return 1
  gd=$(cd "$gd" 2>/dev/null && pwd) || return 1
  common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$common" 2>/dev/null && pwd) || return 1
  [[ "$gd" != "$common" ]]
}

resolve_ws() {
  local source_label="" id=""
  # `.task-current` lives at the project root beside `.task` (never symlinked),
  # so key off the discovered root rather than cwd.
  local task_current
  task_current="$(dirname "$AI_DIR")/.task-current"
  if [[ -n "${TASK_ID_OVERRIDE:-}" ]]; then
    id="$TASK_ID_OVERRIDE"
    source_label='$TASK_ID_OVERRIDE'
  elif [[ $# -gt 0 && -n "${1:-}" ]]; then
    id="$1"
    source_label="positional arg"
  elif [[ -f "$task_current" ]]; then
    id="$(head -n 1 "$task_current" | tr -d '[:space:]')"
    source_label=".task-current"
    if [[ -z "$id" ]]; then
      echo "ERROR: .task-current is empty. Remove it and run /task:design first." >&2
      return 1
    fi
  else
    if _linked_worktree_without_task; then
      echo "ERROR: you're in a linked git worktree without '.task'. Run /task:bootstrap here to link the shared .task/ from the main worktree." >&2
      return 1
    fi
    echo "ERROR: no active task. Run /task:design first (to revive a closed umbrella, restore it manually from .task/log/ — see README)." >&2
    return 1
  fi

  TASK_ID="$id"
  WS_DIR="$AI_DIR/workspace/$TASK_ID"
  if [[ ! -d "$WS_DIR" ]]; then
    if _linked_worktree_without_task; then
      echo "ERROR: you're in a linked git worktree without '.task'. Run /task:bootstrap here to link the shared .task/ from the main worktree." >&2
      return 1
    fi
    echo "ERROR: source '$source_label' points to task-id '$TASK_ID' but '$WS_DIR' does not exist." >&2
    echo "       Restore '$TASK_ID' manually from .task/log/$TASK_ID/ or remove .task-current to recover." >&2
    return 1
  fi
  export TASK_ID WS_DIR AI_DIR
}
