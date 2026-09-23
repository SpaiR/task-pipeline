#!/usr/bin/env bash
# Contract under test: skills/_lib/resolve-ws.sh — the `.task/` root finder.
# Resolution order is `task.root` on evidence (holds a CLAUDE.md, belongs to
# this repo) → ceilinged ancestor walk →
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

t_case "a copied repo ignores the anchor that still names the original"
base=$(t_tmpdir)
git -C "$base" init -q main
git -C "$base/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m seed
config_at "$base/main"
git -C "$base/main" config --local task.root "$base/main"
cp -R "$base/main" "$base/copy"
mkdir -p "$base/copy/sub"
# The copied `.git/config` still names `main`, which still holds a CLAUDE.md —
# the evidence check alone would pass. Only the repo-identity check rejects it.
assert_eq "$base/copy/.task" "$(resolve_in "$base/copy/sub")" "copy's own root"
assert_eq "$base/main/.task" "$(resolve_in "$base/main")" "original unaffected"

t_case "an anchor naming an unrelated repo is ignored"
other=$(make_repo --config)
repo=$(make_repo --config)
git -C "$repo" config --local task.root "$other"
assert_eq "$repo/.task" "$(resolve_in "$repo")" "own root, not the anchor's"

t_case "a linked worktree accepts the anchor at the main worktree"
repo=$(make_repo)
git -C "$repo" commit -q --allow-empty -m seed
mkdir -p "$repo/inner"
config_at "$repo/inner"
git -C "$repo" config --local task.root "$repo/inner"
wt=$(t_tmpdir)
git -C "$repo" worktree add -q "$wt/linked" >/dev/null 2>&1
# A subdir-hosted `.task/` is out of reach of both the walk and step 3 from a
# sibling worktree — only an accepted anchor can produce this answer.
assert_eq "$repo/inner/.task" "$(resolve_in "$wt/linked")" "anchored subdir root"

t_case "bare repo: worktrees outside the container share the anchored worktree"
store=$(t_tmpdir)
git init -q --bare "$store/proj.git"
seed=$(t_tmpdir)
git clone -q "$store/proj.git" "$seed/c" 2>/dev/null
git -C "$seed/c" -c user.name=t -c user.email=t@t commit -q --allow-empty -m seed
git -C "$seed/c" push -q origin HEAD:main 2>/dev/null
work=$(t_tmpdir)
git -C "$store/proj.git" worktree add -q "$work/a" main >/dev/null 2>&1
git -C "$store/proj.git" worktree add -q --detach "$work/b" main >/dev/null 2>&1
config_at "$work/a"
git -C "$store/proj.git" config --local task.root "$work/a"
assert_eq "$work/a/.task" "$(resolve_in "$work/b")" "sibling worktree's root"

t_case "bare repo: the anchor at the container is accepted"
config_at "$store"
git -C "$store/proj.git" config --local task.root "$store"
# `$store` is no repository, so its common dir cannot match; it is accepted as
# exactly `dirname(git-common-dir)`.
assert_eq "$store/.task" "$(resolve_in "$work/b")" "bare container root"

t_case "--separate-git-dir: an anchor inside the checkout is accepted"
base=$(t_tmpdir)
mkdir -p "$base/gitdirs"
git init -q --separate-git-dir="$base/gitdirs/x.git" "$base/checkout"
mkdir -p "$base/checkout/inner" "$base/checkout/sub"
config_at "$base/checkout"
config_at "$base/checkout/inner"
git -C "$base/checkout" config --local task.root "$base/checkout/inner"
assert_eq "$base/checkout/inner/.task" "$(resolve_in "$base/checkout/sub")" "anchored root"

t_case "a submodule anchored at its superproject still resolves the superproject"
sub_src=$(make_repo)
git -C "$sub_src" commit -q --allow-empty -m seed
super=$(make_repo --config)
git -C "$super" -c protocol.file.allow=always submodule add -q "$sub_src" mod >/dev/null 2>&1
git -C "$super/mod" config --local task.root "$super"
# The superproject's common dir is not the submodule's, so the anchor is
# rejected; the walk, ceilinged at the superproject, lands on the same root.
assert_eq "$super/.task" "$(resolve_in "$super/mod")" "superproject root"

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
