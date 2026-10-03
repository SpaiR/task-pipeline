#!/usr/bin/env bash
# resolve-ws.sh — Resolve the `.task/` pipeline root.
#
# Sourced (NOT exec'd) by callers. Runs `find_ai_dir` at source time and
# exports `AI_DIR` — the discovered `.task` directory. Pure root finder: no
# active-task pointer, no per-task workspace, no TASK_ID_OVERRIDE. The
# artifact path (`.task/task/<slug>.md`) is the handle — there is no "which
# task is active" resolution anywhere.
#
# Usage (from a sibling script):
#   SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
#   # now $AI_DIR is set

# _git_abs <rev-parse option> — print git's answer as one absolute path.
# `--path-format=absolute` needs git >= 2.31; older git does not reject it but
# echoes it back as a line of output, which would become a multi-line `AI_DIR`.
# So an answer counts only when it is a single line starting with `/`; anything
# else falls back to plain rev-parse, made absolute with `cd … && pwd -P`.
_git_abs() {
  local out
  out=$(git rev-parse --path-format=absolute "$@" 2>/dev/null) || out=""
  if [[ -n "$out" && "$out" != *$'\n'* && "$out" == /* ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  out=$(git rev-parse "$@" 2>/dev/null) || return 1
  [[ -n "$out" && "$out" != *$'\n'* ]] || return 1
  [[ "$out" == /* ]] || out=$(cd "$out" 2>/dev/null && pwd -P) || return 1
  printf '%s\n' "$out"
}

# find_ai_dir — discover the pipeline root that holds `.task/`, in four
# steps, first hit wins: the `task.root` anchor, a ceilinged ancestor walk, the
# parent of the git common dir, then `$CLAUDE_PROJECT_DIR`. The order, the
# evidence each step needs and the why live in docs/contract.md § Root
# resolution; the comments beside each step below only explain the code.
#
# AI_DIR is exported as `<root>/.task` with the `.task` component appended
# literally (never `cd`'d into). A pre-set AI_DIR is kept when it holds a
# CLAUDE.md (step 0 in docs/contract.md § Root resolution). macOS-safe: no
# `realpath` / `readlink -f`.
find_ai_dir() {
  [[ -n "${AI_DIR:-}" && -f "$AI_DIR/CLAUDE.md" ]] && { export AI_DIR; return 0; }

  local root="" have_git=0
  command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 && have_git=1

  # `common_root` is computed by step 1 when an anchor has to be checked, else
  # by step 2 (it is one of the walk's ceiling candidates), and REUSED by the
  # steps after it, so the git fork is paid at most once.
  local common_root=""

  # 1. Anchor recorded by the inline Step 0 setup (shared across all worktrees).
  #    Claimed on EVIDENCE, exactly like step 4: the anchor is an absolute path
  #    baked into `.git/config`, which travels with the repo when it is moved or
  #    copied. Two checks, one per way it goes stale:
  #      - MOVED: the path is gone, so it holds no CLAUDE.md. Trusting it would
  #        report the project unconfigured, and capture setup would regenerate
  #        CLAUDE.md over the real one that moved with the repo.
  #      - COPIED: the path is still there — it is the ORIGINAL repo — so the
  #        CLAUDE.md check passes, and the copy would read and write the
  #        original's artifacts. The anchor must belong to THIS repo: its own git
  #        common dir must be ours (main root, subdir-hosted `.task/`, any linked
  #        worktree, a `--separate-git-dir` checkout), or it must be exactly
  #        `dirname(our common dir)` — the container of a bare repo, which is no
  #        repository itself. Both sides come from `_git_abs`, which
  #        canonicalises (git itself, or `pwd -P` on old git), so they compare as
  #        plain strings.
  #    A rejected anchor falls through to the ancestor walk. A submodule anchored
  #    at its superproject fails the identity check too, and the walk — whose
  #    ceiling includes the superproject — finds the same `.task/`.
  if [[ "$have_git" -eq 1 ]]; then
    root=$(git config --local --get task.root 2>/dev/null) || root=""
    [[ -n "$root" && ! -f "$root/.task/CLAUDE.md" ]] && root=""
    if [[ -n "$root" ]]; then
      local own_common="" anchor_common="" anchor_phys=""
      own_common=$(_git_abs --git-common-dir) || own_common=""
      [[ -n "$own_common" ]] && common_root=${own_common%/*}
      anchor_common=$(cd "$root" 2>/dev/null && _git_abs --git-common-dir) \
        || anchor_common=""
      if [[ -z "$own_common" ]]; then
        root=""                                  # nothing to prove it against
      elif [[ "$anchor_common" != "$own_common" ]]; then
        anchor_phys=$(cd "$root" 2>/dev/null && pwd -P) || anchor_phys=""
        [[ -n "$anchor_phys" && "$anchor_phys" == "$common_root" ]] || root=""
      fi
    fi
  fi

  # 2. Upward walk for a `.task/CLAUDE.md` ancestor (pre-anchor repos),
  #    CEILINGED so it cannot climb out of this project and claim a
  #    NEIGHBOURING one. Unbounded, a checkout with no `.task/` of its own that
  #    sits under a directory which has one resolves to that parent and writes
  #    every artifact into the other project's flat namespace — silently,
  #    because the setup gate finds a CLAUDE.md there and skips setup.
  #
  #    The ceiling is the HIGHEST directory that still belongs to this project.
  #    Three candidates, because a `.task/` legitimately lives at any of them:
  #      - this checkout's own top level;
  #      - the repo's main worktree root, for a linked worktree nested under a
  #        subdir-hosted `.task/` (`.task/` above the worktree, below the root);
  #      - the superproject's working tree, for a submodule whose CONTAINING
  #        project owns the `.task/` — step 3 is no help there, since for a
  #        submodule `dirname(git-common-dir)` points inside `.git/modules`.
  #    Each candidate must lie on $dir's own ancestor chain to bound this walk
  #    at all: a sibling worktree's main root is not above the sibling, so it is
  #    correctly ignored here and supplied by step 3 instead.
  if [[ -z "$root" ]]; then
    local dir ceiling="" cand top="" super="" phys=""
    # The walk itself is LOGICAL (plain `pwd`), as it has always been: entering a
    # project through a symlinked subdir must still find that project's own
    # `.task/`, and a physical walk would leave its chain entirely. `pwd` also
    # keeps answering from bash's cached $PWD when the cwd has been deleted under
    # us (a removed worktree with a shell still inside it), where `pwd -P` fails.
    dir=$(pwd 2>/dev/null) || dir="$PWD"
    phys=$(pwd -P 2>/dev/null) || phys="$dir"

    # The ceiling compares against git's PHYSICAL paths, so it can only be
    # applied when the logical and physical cwd agree. Under a symlinked entry
    # path they do not, and there we walk unbounded — exactly as before the
    # ceiling existed. Resolving too permissively in that corner is strictly
    # better than failing to find a root that is really there.
    if [[ "$have_git" -eq 1 && "$dir" == "$phys" ]]; then
      top=$(_git_abs --show-toplevel) || top=""
      local common
      if [[ -z "$common_root" ]] \
         && common=$(_git_abs --git-common-dir) \
         && [[ -n "$common" ]]; then
        common_root=$(dirname "$common")
      fi
      # One level of superproject covers a submodule of a configured project;
      # deeper nesting falls back to the tighter ceiling, never to a wrong root.
      super=$(git rev-parse --show-superproject-working-tree 2>/dev/null) || super=""

      for cand in "$top" "$common_root" "$super"; do
        [[ -n "$cand" ]] || continue
        [[ "$dir" == "$cand" || "$dir" == "$cand"/* ]] || continue   # on our chain?
        # `common_root` is only the MAIN WORKTREE root when it actually holds a
        # `.git`. With `git init --separate-git-dir=…` it is merely whatever
        # directory the git dir was parked in — often a level above the checkout,
        # which would hand the walk a ceiling ABOVE the project and re-open the
        # neighbouring-`.task/` hole this ceiling exists to close.
        if [[ "$cand" == "$common_root" && ! -e "$cand/.git" ]]; then continue; fi
        [[ -z "$ceiling" || ${#cand} -lt ${#ceiling} ]] && ceiling="$cand"
      done
    fi

    while :; do
      if [[ -f "$dir/.task/CLAUDE.md" ]]; then root="$dir"; break; fi
      [[ -n "$ceiling" && "$dir" == "$ceiling" ]] && break   # empty => unbounded
      [[ "$dir" == "/" ]] && break
      dir=${dir%/*}; [[ -z "$dir" ]] && dir=/   # parent, no `dirname` fork
    done
  fi

  # 3. Parent of the git common dir (sibling worktrees / bare repos) — already
  #    computed as a ceiling candidate above when step 2 ran.
  if [[ -z "$root" && "$have_git" -eq 1 ]]; then
    local top3="${top:-}"      # `local` is function-scoped, but be explicit
    if [[ -z "$common_root" ]]; then
      local common3
      if common3=$(_git_abs --git-common-dir) \
         && [[ -n "$common3" ]]; then
        common_root=$(dirname "$common3")
      fi
    fi
    [[ -n "$top3" ]] || top3=$(_git_abs --show-toplevel) || top3=""
    if [[ -n "$common_root" && -e "$common_root/.git" ]]; then
      # A real main worktree root: normal, nested and sibling worktrees all land
      # here, which is what lets every worktree of a repo share one `.task/`.
      root="$common_root"
    elif [[ -n "$top3" ]]; then
      # `git init --separate-git-dir=…` parks the git dir outside the checkout,
      # so `dirname(git-common-dir)` is just whatever directory holds it — often
      # a level ABOVE the checkout, i.e. a neighbouring project. The checkout's
      # own top level is the honest answer there.
      root="$top3"
    elif [[ -n "$common_root" ]]; then
      root="$common_root"          # bare repo: no working tree, so no top level
    fi
  fi

  # 4. Hook context, then the historical relative default.
  if [[ -z "$root" && -n "${CLAUDE_PROJECT_DIR:-}" \
        && -f "$CLAUDE_PROJECT_DIR/.task/CLAUDE.md" ]]; then
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
