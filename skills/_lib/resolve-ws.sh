#!/usr/bin/env bash
# resolve-ws.sh — Resolve the `.task/` pipeline root.
#
# Sourced (NOT exec'd) by callers. Runs `find_ai_dir` at source time and
# exports `AI_DIR` — the discovered `.task` directory. Pure root finder: no
# active-task pointer, no per-task workspace, no TASK_ID_OVERRIDE. In v3 the
# artifact path (`.task/task/<slug>.md`) is the handle — there is no "which
# task is active" resolution anywhere.
#
# Usage (from a sibling script):
#   SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
#   # now $AI_DIR is set

# find_ai_dir — discover the pipeline root that holds `.task/`.
#
# Resolution order (first hit wins):
#   1. `git config --local task.root` — the anchor recorded by the intake
#      skills' inline Step 0 setup. Lives in the repo-local (common) git
#      config, so it is shared by EVERY worktree of the repo: all worktrees
#      resolve the same `.task/` with zero setup — no symlink, no join mode.
#      `--local --get` scopes to the repo config so a stray global `task.root`
#      cannot leak in. This is what lets worktrees spawned by
#      `roadmap-to-workflow` share one `.task/`.
#   2. Upward walk from $PWD for a `.task/config/config.md` ancestor — the
#      pre-anchor fallback. Covers a main worktree, a nested worktree, or a
#      `.task` created in a subdir, for repos bootstrapped before the anchor
#      existed.
#   3. Parent of the git common dir — the main worktree root (normal / nested /
#      sibling worktrees) or the bare repo's container (bare). Catches sibling
#      worktrees and bare repos that the upward walk in (2) misses.
#   4. `$CLAUDE_PROJECT_DIR/.task` when set inside a hook, else the relative
#      `.task` — the historical default, so a call from outside any project
#      still fails cleanly on the config gate with "config.md not found".
#
# AI_DIR is exported as `<root>/.task` with the `.task` component appended
# literally (never `cd`'d into). Only acts when AI_DIR is unset, so a caller
# that pins AI_DIR keeps control. macOS-safe: no `realpath` / `readlink -f`.
find_ai_dir() {
  [[ -n "${AI_DIR:-}" ]] && { export AI_DIR; return 0; }

  local root="" have_git=0
  command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 && have_git=1

  # 1. Anchor recorded by the inline Step 0 setup (shared across all worktrees).
  if [[ "$have_git" -eq 1 ]]; then
    root=$(git config --local --get task.root 2>/dev/null) || root=""
  fi

  # 2. Upward walk for a config.md ancestor (pre-anchor repos).
  if [[ -z "$root" ]]; then
    local dir
    dir=$(pwd)
    while :; do
      if [[ -f "$dir/.task/config/config.md" ]]; then root="$dir"; break; fi
      [[ "$dir" == "/" ]] && break
      dir=${dir%/*}; [[ -z "$dir" ]] && dir=/   # parent, no `dirname` fork
    done
  fi

  # 3. Parent of the git common dir (sibling worktrees / bare repos).
  if [[ -z "$root" && "$have_git" -eq 1 ]]; then
    local common
    if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
       && [[ -n "$common" ]]; then
      root=$(dirname "$common")
    fi
  fi

  # 4. Hook context, then the historical relative default.
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
