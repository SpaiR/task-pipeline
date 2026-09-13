#!/usr/bin/env bash
# Contract under test: skills/_lib/roadmap.sh — `roadmap_progress_counts` over
# the 5-state checkbox class, and `resolve_artifact_path`'s three lookup
# branches.
source "$(dirname "$0")/lib.sh"

AI_DIR=""            # roadmap.sh reads it; each case sets it explicitly
# shellcheck source=../skills/_lib/roadmap.sh
source "$T_REPO_ROOT/skills/_lib/roadmap.sh"

t_case "roadmap_progress_counts treats [x] [~] [>] [-] as done, [ ] as unchecked"
dir=$(t_tmpdir)
cat >"$dir/r.md" <<'MD'
# Roadmap
### - [ ] 1. open one
### - [x] 2. shipped
### - [~] 3. in progress
### - [>] 4. deferred
### - [-] 5. dropped
### - [ ] 6. open two
### Spec references → [s](../spec/s.md) §1
MD
counts=$(roadmap_progress_counts "$dir/r.md")
assert_eq "total: 6
done: 4
unchecked: 2" "$counts" "five-state tally"

t_case "resolve_artifact_path: explicit path, bare slug, slug + .md"
AI_DIR=$(t_tmpdir)/.task
mkdir -p "$AI_DIR/task"
printf '# T\n' >"$AI_DIR/task/alpha.md"
printf '# T\n' >"$AI_DIR/task/beta"
printf '# T\n' >"$dir/loose.md"
assert_eq "$dir/loose.md" "$(resolve_artifact_path task "$dir/loose.md")" "explicit path"
assert_eq "$AI_DIR/task/beta" "$(resolve_artifact_path task beta)" "bare name under AI_DIR"
assert_eq "$AI_DIR/task/alpha.md" "$(resolve_artifact_path task alpha)" "slug + .md"
assert_eq "" "$(resolve_artifact_path task nope)" "no match is empty"

t_summary
