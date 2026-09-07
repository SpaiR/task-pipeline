#!/usr/bin/env bash
# Contract under test: skills/_lib/preflight.sh — the fixed-shape entry block a
# capture skill's Step 0 is preprocessed with. Shape is the contract: the skills
# branch on these line prefixes, so a reworded line is a broken skill.
source "$(dirname "$0")/lib.sh"

PREFLIGHT="$T_REPO_ROOT/skills/_lib/preflight.sh"

p() { # <dir> <kind> → $P_OUT, $P_EXIT
  local dir="$1" kind="$2"
  P_OUT=$( (cd "$dir" && env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$PREFLIGHT" "$kind") 2>&1 )
  P_EXIT=$?
}

t_case "an unconfigured project reports CONFIG: absent and still exits 0"
bare=$(make_repo)
p "$bare" task
assert_exit 0 "$P_EXIT" "no config is not a failure"
assert_contains "$P_OUT" "CONFIG: absent" "config state"
assert_contains "$P_OUT" "ROADMAPS: none" "no roadmaps"
assert_contains "$P_OUT" "TASKS: none" "no tasks"
assert_contains "$P_OUT" "SPECS: none" "no specs"

t_case "a configured project reports its root, roadmap progress and slugs"
repo=$(make_repo --config)
mkdir -p "$repo/.task/roadmap" "$repo/.task/task" "$repo/.task/spec"
cat >"$repo/.task/roadmap/api-v2.md" <<'MD'
# API v2

### - [x] 1. Shipped item
### - [ ] 2. Open item
MD
printf '# T\n' >"$repo/.task/task/some-task.md"
printf '# S\n' >"$repo/.task/spec/event-envelope.md"
p "$repo" plan
assert_exit 0 "$P_EXIT" "configured project"
assert_contains "$P_OUT" "AI_DIR: $repo/.task" "resolved root"
assert_contains "$P_OUT" "PLUGIN_ROOT: $T_REPO_ROOT" "plugin root for the driver args"
assert_contains "$P_OUT" "CONFIG: present" "config state"
assert_contains "$P_OUT" "ROADMAPS: api-v2 1/2 unchecked=2" "progress and open item numbers"
assert_contains "$P_OUT" "TASKS: some-task" "task slugs"
assert_contains "$P_OUT" "SPECS: event-envelope" "spec slugs"

t_case "a fully ticked roadmap reports unchecked=none"
sed 's/^### - \[ \] 2\./### - [x] 2./' "$repo/.task/roadmap/api-v2.md" >"$repo/.task/roadmap/shipped.md"
p "$repo" roadmap
assert_contains "$P_OUT" "ROADMAPS: shipped 2/2 unchecked=none" "no open items"

t_case "kind 'workflow' folds in the full validate sweep"
p "$repo" workflow
assert_exit 0 "$P_EXIT" "sweep does not change the exit code"
assert_contains "$P_OUT" "VALIDATE:" "sweep section"
# The seeded roadmap has no `**Ready description:**` blocks, so the sweep must
# report errors — and preflight must still exit 0, leaving the call to the skill.
assert_contains "$P_OUT" "ERROR" "sweep output is passed through"

t_case "an unknown kind is a usage error"
p "$repo" nonsense
assert_exit 2 "$P_EXIT" "bad kind"

t_summary
