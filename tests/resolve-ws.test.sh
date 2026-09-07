#!/usr/bin/env bash
# Contract under test: skills/_lib/resolve-ws.sh — the `.task/` root finder.
# Resolution order is `task.root` on evidence → ceilinged ancestor walk →
# parent of the git common dir → $CLAUDE_PROJECT_DIR on evidence → `.task`.
source "$(dirname "$0")/lib.sh"

RESOLVE="$T_REPO_ROOT/skills/_lib/resolve-ws.sh"

# Source resolve-ws.sh in a fresh shell whose cwd is <dir>, print the AI_DIR it
# exports. A fresh process each time because sourcing is a one-shot: find_ai_dir
# no-ops once AI_DIR is set.
resolve_in() {
  (cd "$1" && env -u AI_DIR -u CLAUDE_PROJECT_DIR \
    bash -c 'source "$0"; printf "%s" "$AI_DIR"' "$RESOLVE")
}

config_at() { mkdir -p "$1/.task" && printf '# task-pipeline\n' >"$1/.task/CLAUDE.md"; }

t_case "task.root anchor wins over the ancestor walk when it holds a config"
repo=$(make_repo --config)
mkdir -p "$repo/inner/sub" "$repo/sub"
config_at "$repo/inner"
git -C "$repo" config --local task.root "$repo/inner"
# Both the repo root and `inner` hold a config, so only the anchor can explain
# the answer — the walk from `$repo/sub` would find the repo root's.
assert_eq "$repo/inner/.task" "$(resolve_in "$repo/sub")" "anchored root"

t_case "stale task.root falls through to the ancestor walk"
repo=$(make_repo --config)
mkdir -p "$repo/sub/deeper"
git -C "$repo" config --local task.root "$repo-vanished"
assert_eq "$repo/.task" "$(resolve_in "$repo/sub/deeper")" "walked root"

t_case "the walk stops at this project and never claims a neighbour's .task"
parent=$(t_tmpdir)
config_at "$parent"
mkdir -p "$parent/child"
git -C "$parent/child" init -q
mkdir -p "$parent/child/sub"
# The ceiling stops the walk at the child checkout, so the neighbouring
# `$parent/.task` is out of reach; resolution step 3 then answers with the
# checkout's own root.
assert_eq "$parent/child/.task" "$(resolve_in "$parent/child/sub")" "own root, not parent's"

t_case "a linked worktree resolves the main worktree's .task"
repo=$(make_repo --config)
printf 'seed\n' >"$repo/seed.txt"
git -C "$repo" add seed.txt >/dev/null 2>&1
git -C "$repo" commit -q -m "seed" >/dev/null 2>&1
wt=$(t_tmpdir)
git -C "$repo" worktree add -q "$wt/linked" >/dev/null 2>&1
assert_eq "$repo/.task" "$(resolve_in "$wt/linked")" "main worktree root"

t_case "outside any git repo the historical relative default is used"
plain=$(t_tmpdir)
assert_eq ".task" "$(resolve_in "$plain")" "relative fallback"

t_summary
