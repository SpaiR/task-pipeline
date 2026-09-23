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

# find_ai_dir — discover the pipeline root that holds `.task/`.
#
# Resolution order (first hit wins):
#   1. `git config --local task.root` — the anchor recorded by the capture
#      skills' inline Step 0 setup, accepted only on evidence, as in step 4:
#      the path ALREADY holds a `CLAUDE.md`, and it belongs to THIS repo — its
#      git common dir is ours, or it is exactly `dirname(our common dir)` (a
#      bare repo's container). A stale anchor left by a moved repo (path gone)
#      or a copied one (path is the original repo) is ignored, not trusted.
#      Lives in the repo-local (common) git config, so it is shared by EVERY
#      worktree of the repo: all
#      worktrees resolve the same `.task/` with zero setup — no symlink, no
#      join mode.
#      `--local --get` scopes to the repo config so a stray global `task.root`
#      cannot leak in. This is what lets user-created parallel worktrees of a
#      repo share one `.task/` — no skill spawns worktrees of its own
#      (`roadmap-to-workflow` runs its items in the shared tree, and the
#      reviewer must see and commit into that same tree, so neither sets
#      `isolation`).
#   2. Upward walk from $PWD for a `.task/CLAUDE.md` ancestor — the
#      pre-anchor fallback. Covers a main worktree, a nested worktree, or a
#      `.task` created in a subdir, for repos bootstrapped before the anchor
#      existed. CEILINGED at the highest directory that still belongs to this
#      project — the highest of this checkout's top level, the main worktree
#      root, and the superproject's working tree that is still an ancestor of
#      $PWD. That directory is checked; above it is someone else's project, so
#      the walk cannot claim a neighbouring `.task/`.
#   3. Parent of the git common dir — the main worktree root (normal / nested /
#      sibling worktrees) or the bare repo's container (bare). Catches sibling
#      worktrees and bare repos that the ceilinged walk in (2) misses; reuses
#      the value (2) already computed.
#   4. `$CLAUDE_PROJECT_DIR/.task` when that path ALREADY holds a
#      `CLAUDE.md` — like steps 1-3, this step claims a root only on
#      evidence, never on the variable being set alone. Otherwise the relative
#      `.task`: the historical default, so a call from outside any project
#      still fails cleanly on the setup gate with "CLAUDE.md not found".
#
# AI_DIR is exported as `<root>/.task` with the `.task` component appended
# literally (never `cd`'d into). Only acts when AI_DIR is unset, so a caller
# that pins AI_DIR keeps control. macOS-safe: no `realpath` / `readlink -f`.
find_ai_dir() {
  [[ -n "${AI_DIR:-}" ]] && { export AI_DIR; return 0; }

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
  #        repository itself. Both sides come from `--path-format=absolute`,
  #        which git canonicalises, so they compare as plain strings.
  #    A rejected anchor falls through to the ancestor walk. A submodule anchored
  #    at its superproject fails the identity check too, and the walk — whose
  #    ceiling includes the superproject — finds the same `.task/`.
  if [[ "$have_git" -eq 1 ]]; then
    root=$(git config --local --get task.root 2>/dev/null) || root=""
    [[ -n "$root" && ! -f "$root/.task/CLAUDE.md" ]] && root=""
    if [[ -n "$root" ]]; then
      local own_common="" anchor_common="" anchor_phys=""
      own_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || own_common=""
      [[ -n "$own_common" ]] && common_root=${own_common%/*}
      anchor_common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
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
      top=$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || top=""
      local common
      if [[ -z "$common_root" ]] \
         && common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
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
      if common3=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
         && [[ -n "$common3" ]]; then
        common_root=$(dirname "$common3")
      fi
    fi
    [[ -n "$top3" ]] || top3=$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || top3=""
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
