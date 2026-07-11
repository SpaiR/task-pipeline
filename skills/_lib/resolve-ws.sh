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
#      id is the source of truth, not a possibly-stale pointer).
#   2. First positional argument ($1) — used by callers that pass the id explicitly.
#   3. Contents of the active-task pointer (a single line: the task-id), located
#      per-worktree inside the git dir — see `task_current_path` below.
#
# On failure: prints to stderr and returns non-zero. Callers MUST handle the
# return code, e.g.: `resolve_ws "$@" || exit 1`.
#
# Usage (from a sibling script):
#   SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
#   resolve_ws "$@" || exit 1
#   # now $TASK_ID and $WS_DIR are set

# find_ai_dir — discover the pipeline root that holds `.task/`.
#
# Resolution order (first hit wins):
#   1. `git config --local task.root` — the anchor recorded by /task:bootstrap.
#      Lives in the repo-local (common) git config, so it is shared by EVERY
#      worktree of the repo: all worktrees resolve the same `.task/` with zero
#      setup — no symlink, no join-mode. `--local --get` scopes to the repo
#      config so a stray global `task.root` cannot leak in.
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

  # 1. Anchor recorded by /task:bootstrap (shared across all worktrees).
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
      dir=$(dirname "$dir")
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

# task_current_path — the location of the active-task pointer for THIS worktree.
#
# In a git repo the pointer lives inside git's per-worktree dir, resolved via
# `git rev-parse --git-path task-current`: `.git/task-current` in the main
# worktree, `.git/worktrees/<name>/task-current` in a linked worktree. This
# gives per-worktree isolation for free and keeps the pointer out of the
# project tree entirely (no `.git/info/exclude` entry needed — it is inside the
# git dir). `--path-format=absolute` makes it independent of cwd.
#
# Outside a git repo, fall back to the legacy worktree-root location
# `<root>/.task-current` beside `.task`.
task_current_path() {
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    git rev-parse --path-format=absolute --git-path task-current
  else
    printf '%s\n' "$(dirname "$AI_DIR")/.task-current"
  fi
}

# migrate_legacy_pointer — one-time move of a pre-upgrade pointer.
#
# Runs bootstrapped repos forward: a pointer written by an older version lives
# at the worktree-root `<root>/.task-current`; this moves it into the git-dir
# location `task_current_path` reports. Idempotent — no-ops once migrated, when
# the two locations coincide (non-git), or when there is nothing to move.
#
# MUTATING — only the explicit healers call it (preamble's `source_resolve_ws`);
# the read-only direct sourcers (`validate.sh`, `phase-detect.sh`) never do.
# `resolve_ws` reads the legacy location as a read-only fallback instead.
migrate_legacy_pointer() {
  local new legacy
  new="$(task_current_path)"
  legacy="$(dirname "$AI_DIR")/.task-current"
  [[ "$new" != "$legacy" ]] || return 1   # non-git: locations coincide
  [[ -e "$new" ]] && return 1              # already migrated
  [[ -f "$legacy" ]] || return 1           # nothing to migrate
  mv "$legacy" "$new"
  echo "note: migrated active-task pointer into the git dir (was '$legacy')." >&2
  return 0
}

# heal_stale_pointer — clear a *provably-stale* active-task pointer, with a notice.
#
# "Provably stale" (the safety invariant "never discards a valid in-flight task"
# hinges on this): the pointer exists AND (its first line is empty after
# whitespace-strip, OR the resolved `"$AI_DIR/workspace/<id>/"` directory is
# gone). A pointer whose workspace subfolder exists is a valid in-flight task
# (even mid-transition with an empty task.md Description) and is left untouched.
#
# On a stale pointer: `rm -f` it, print exactly ONE informational line to stderr
# (a benign notice — deliberately NOT prefixed `ERROR:`, so tooling that greps
# for error lines does not read it as a failure), and return 0 (healed). On a
# valid pointer (workspace present) or a missing pointer: return non-zero and
# touch nothing.
#
# Keys off the pointer alone — safe even when a caller also passes a
# positional/override id: if the workspace is present the helper no-ops; if
# absent the pointer is stale by definition regardless of the override.
#
# `resolve_ws` itself stays pure and never calls this — only the explicit
# healers (preamble's `source_resolve_ws` wrapper, design's open phase) mutate,
# so the direct sourcers `phase-detect.sh` / `validate.sh` never delete the
# pointer during read-only detection. Not invoked at source time. Resolves the
# pointer path through `task_current_path` (git-dir location), so it runs AFTER
# `migrate_legacy_pointer` has moved any pre-upgrade root pointer into place.
heal_stale_pointer() {
  local pointer id
  pointer="$(task_current_path)"
  [[ -f "$pointer" ]] || return 1                       # nothing to heal
  id="$(head -n 1 "$pointer" | tr -d '[:space:]')"
  if [[ -z "$id" ]]; then
    rm -f "$pointer"
    echo "note: cleared stale active-task pointer (was empty) — no active task now." >&2
    return 0
  fi
  if [[ ! -d "$AI_DIR/workspace/$id" ]]; then
    rm -f "$pointer"
    echo "note: cleared stale active-task pointer (workspace '$id' is gone) — no active task now." >&2
    return 0
  fi
  return 1                                               # valid in-flight task — untouched
}

resolve_ws() {
  local source_label="" id=""
  # The active-task pointer lives in git's per-worktree dir (see
  # task_current_path). A pointer written by a pre-upgrade run still sits at the
  # legacy worktree-root `<root>/.task-current`; read that as a read-only
  # fallback so a read-only caller (validate.sh / phase-detect.sh) resolves an
  # in-flight umbrella even before a mutating skill migrates it.
  local task_current legacy
  task_current="$(task_current_path)"
  legacy="$(dirname "$AI_DIR")/.task-current"
  if [[ ! -f "$task_current" && -f "$legacy" ]]; then
    task_current="$legacy"
  fi
  if [[ -n "${TASK_ID_OVERRIDE:-}" ]]; then
    id="$TASK_ID_OVERRIDE"
    source_label='$TASK_ID_OVERRIDE'
  elif [[ $# -gt 0 && -n "${1:-}" ]]; then
    id="$1"
    source_label="positional arg"
  elif [[ -f "$task_current" ]]; then
    id="$(head -n 1 "$task_current" | tr -d '[:space:]')"
    source_label="active-task pointer"
    if [[ -z "$id" ]]; then
      echo "ERROR: active-task pointer is empty. Run /task:design first (a stale pointer self-heals on the next command)." >&2
      return 1
    fi
  else
    echo "ERROR: no active task. Run /task:design first (to revive a closed umbrella, restore it manually from .task/log/ — see README)." >&2
    return 1
  fi

  TASK_ID="$id"
  WS_DIR="$AI_DIR/workspace/$TASK_ID"
  if [[ ! -d "$WS_DIR" ]]; then
    echo "ERROR: source '$source_label' points to task-id '$TASK_ID' but '$WS_DIR' does not exist." >&2
    echo "       Restore '$TASK_ID' manually from .task/log/$TASK_ID/, or the pointer self-heals on the next command." >&2
    return 1
  fi
  export TASK_ID WS_DIR AI_DIR
}
