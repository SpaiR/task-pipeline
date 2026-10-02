#!/usr/bin/env bash
# Contract under test: skills/_lib/roadmap.sh — `roadmap_progress_counts` over
# the 5-state checkbox class of each item's status line, and `resolve_artifact_path`'s three lookup
# branches.
source "$(dirname "$0")/lib.sh"

AI_DIR=""            # roadmap.sh reads it; each case sets it explicitly
# shellcheck source=../skills/_lib/roadmap.sh
source "$T_REPO_ROOT/skills/_lib/roadmap.sh"

t_case "roadmap_progress_counts reads the status line: [x] [~] [>] [-] are done, [ ] is unchecked"
dir=$(t_tmpdir)
cat >"$dir/r.md" <<'MD'
# Roadmap

### 1. open one

- [ ] Done

### 2. shipped

- [x] Done

### 3. in progress
- [~] Done

### 4. deferred

- [>] Done

### 5. dropped

- [-] Done

**Dependencies:** —

### 6. open two

- [ ] Done

> **Spec references:** [s](../spec/s.md) §1

### 7. a heading with no status line

**Dependencies:** —
MD
counts=$(roadmap_progress_counts "$dir/r.md")
assert_eq "total: 6
done: 4
open: 1,6" "$counts" "five-state tally and open item numbers; no status line, no item"

t_case "roadmap_progress_counts counts past a non-UTF-8 byte, and fails on a missing file"
# macOS awk decodes by locale and aborts on an invalid byte; the counts came
# back empty, which preflight.sh printed as a finished roadmap.
printf '### 1. Caf\351\n\n- [x] Done\n\n### 2. open\n\n- [ ] Done\n' >"$dir/latin1.md"
assert_eq "total: 2
done: 1
open: 2" "$(LC_ALL=en_US.UTF-8 roadmap_progress_counts "$dir/latin1.md")" "tally and open list survive the byte"
printf '### 1. shipped\n\n- [x] Done\n\n### 2. dropped\n\n- [-] Done\n' >"$dir/none-open.md"
assert_eq "total: 2
done: 2
open: " "$(roadmap_progress_counts "$dir/none-open.md")" "no open item leaves the list empty"
roadmap_progress_counts "$dir/nosuch.md" >/dev/null 2>&1
assert_eq "no" "$([[ $? -eq 0 ]] && echo yes || echo no)" "a failed read is a non-zero status"

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

t_case "resolve_artifact_path: a bare slug never resolves to a file in the cwd"
# A stray `alpha` beside the caller once shadowed $AI_DIR/task/alpha.md.
printf '# stray\n' >"$dir/alpha"
assert_eq "$AI_DIR/task/alpha.md" "$(cd "$dir" && resolve_artifact_path task alpha)" "slug wins over a cwd file"
assert_eq "" "$(cd "$dir" && resolve_artifact_path task loose.md)" "a cwd file is not a slug"
assert_eq "./loose.md" "$(cd "$dir" && resolve_artifact_path task ./loose.md)" "a path still is, used as given"

t_summary
