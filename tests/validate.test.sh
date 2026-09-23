#!/usr/bin/env bash
# Contract under test: skills/validate/validate.sh — exit 0 clean / 1 format
# error / 2 usage-or-precondition, and the ERROR lines the skills branch on.
source "$(dirname "$0")/lib.sh"

VALIDATE="$T_REPO_ROOT/skills/validate/validate.sh"

# Run validate.sh with <dir> as cwd (that is what AI_DIR resolution keys on)
# and leave the merged output in $V_OUT, the status in $V_EXIT. Both are set as
# globals rather than echoed: a `$(v …)` call would put the assignment in a
# subshell and lose the exit code, which is half of what this file asserts.
v() {
  local dir="$1"
  shift
  V_OUT=$( (cd "$dir" && env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$VALIDATE" "$@") 2>&1 )
  V_EXIT=$?
}

t_case "a well-formed task validates clean (exit 0)"
repo=$(make_repo --config)
mkdir -p "$repo/.task/task"
cat >"$repo/.task/task/good.md" <<'MD'
# A good task
---
## Description
Why and what.

## Plan

### Step 1: do the thing
**Goal:** it is done
**Touches:** `src/a.ts`

## Tests

### Test 1: it works
`src/a.test.ts`; assert the thing.

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
MD
v "$repo" task good
assert_exit 0 "$V_EXIT" "clean task"
assert_contains "$V_OUT" "OK 0 errors" "summary line"

t_case "a task with no '---' separator is an error (exit 1)"
sed '2d' "$repo/.task/task/good.md" >"$repo/.task/task/nosep.md"
v "$repo" task nosep
assert_exit 1 "$V_EXIT" "missing separator"
assert_contains "$V_OUT" "missing '---' separator" "names the separator"

t_case "'## Plan' with no '### Step N:' block is an error"
cat >"$repo/.task/task/emptyplan.md" <<'MD'
# Planless plan
---
## Description
Why.

## Plan

Prose, no steps.

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
MD
v "$repo" task emptyplan
assert_exit 1 "$V_EXIT" "plan without steps"
assert_contains "$V_OUT" "contains no '### Step N:' blocks" "names the step blocks"

t_case "a roadmap with a duplicate item number is an error"
mkdir -p "$repo/.task/roadmap"
cat >"$repo/.task/roadmap/dup.md" <<'MD'
# Dup roadmap

### - [ ] 1. First
**Dependencies:** —
**Ready description:**
> ### Context
> c
> ### Goal
> g
> ### Outcomes
> o
> ### Acceptance criteria
> a

### - [ ] 1. Also first
**Dependencies:** —
**Ready description:**
> ### Context
> c
> ### Goal
> g
> ### Outcomes
> o
> ### Acceptance criteria
> a
MD
v "$repo" roadmap dup
assert_exit 1 "$V_EXIT" "duplicate number"
assert_contains "$V_OUT" "duplicate item number 1" "names the number"

t_case "item numbers compare numerically — 1. and 01. are a duplicate"
sed 's/^### - \[ \] 1\. Also first/### - [ ] 01. Also first/' \
  "$repo/.task/roadmap/dup.md" >"$repo/.task/roadmap/dup01.md"
v "$repo" roadmap dup01
assert_exit 1 "$V_EXIT" "leading-zero duplicate"
assert_contains "$V_OUT" "duplicate item number 1" "names the number once"

t_case "a dependency on a number with no item heading is an error"
sed 's/^### - \[ \] 1\. Also first/### - [ ] 2. Second/; s/^\*\*Dependencies:\*\* —$/**Dependencies:** 9/' \
  "$repo/.task/roadmap/dup.md" >"$repo/.task/roadmap/dangling.md"
v "$repo" roadmap dangling
assert_exit 1 "$V_EXIT" "dangling dependency"
assert_contains "$V_OUT" "which has no item heading in this file" "names the missing item"

t_case "CRLF line endings in a roadmap are an error"
sed 's/^### - \[ \] 1\. Also first/### - [ ] 2. Second/' "$repo/.task/roadmap/dup.md" \
  | awk '{ printf "%s\r\n", $0 }' >"$repo/.task/roadmap/crlf.md"
v "$repo" roadmap crlf
assert_exit 1 "$V_EXIT" "CRLF"
assert_contains "$V_OUT" "CRLF line endings" "names the line endings"

# --- `## Architecture` (optional, WARN-only) ---------------------------------
# A two-item roadmap; `arch_roadmap <file> <section>` writes it with <section>
# placed above the first phase, the position to-architecture inserts it at.
arch_roadmap() {
  {
    printf '# Arch roadmap\n\nIntro.\n\n## Phase summary\n\n| Phase | Items |\n|---|---|\n| 1 | 1, 2 |\n\n'
    printf '%s\n' "$2"
    cat <<'MD'
## Phase 1 — Core

### - [ ] 1. First
**Dependencies:** —
**Ready description:**
> ### Context
> c
> ### Goal
> g
> ### Outcomes
> o
> ### Acceptance criteria
> a

### - [ ] 2. Second
**Dependencies:** 1
**Ready description:**
> ### Context
> c
> ### Goal
> g
> ### Outcomes
> o
> ### Acceptance criteria
> a

## Out of scope

- nothing
MD
  } >"$1"
}
ARCH_OK='## Architecture

> Intended technical shape.

### Components
- `EventBus` — new · `src/bus` — carries events; colour `#333` stays prose.

### Interfaces between items
- #1 → #2 — `Envelope`: the event shape; see [spec](../spec/x.md#2-decision), (#2 again).

### Item sketches
- #1 — adds the bus.
- #2 — subscribes to it.

### Technical ordering
- #1 before #2 — the bus must exist first.
'

t_case "a roadmap with a well-formed '## Architecture' validates clean"
arch_roadmap "$repo/.task/roadmap/arch-ok.md" "$ARCH_OK"
v "$repo" roadmap arch-ok
assert_exit 0 "$V_EXIT" "clean architecture"
assert_contains "$V_OUT" "OK 0 errors, 0 warning(s)" "no false positive on #333, a link anchor or (#2)"

t_case "the section does not change what the item collector sees"
arch_roadmap "$repo/.task/roadmap/arch-none.md" ""
with=$(bash "$T_REPO_ROOT/skills/_lib/roadmap-items.sh" "$repo/.task/roadmap/arch-ok.md" 2>&1)
without=$(bash "$T_REPO_ROOT/skills/_lib/roadmap-items.sh" "$repo/.task/roadmap/arch-none.md" 2>&1)
assert_eq "$without" "$with" "roadmap-items.sh output identical with and without the section"

t_case "an '#N' in '## Architecture' with no item heading is a WARN, not an error"
arch_roadmap "$repo/.task/roadmap/arch-dangling.md" "${ARCH_OK}- #9 — a sketch for an item that was renumbered away.
"
v "$repo" roadmap arch-dangling
assert_exit 0 "$V_EXIT" "WARN only"
assert_contains "$V_OUT" "cites #9, which has no item heading" "names the reference"
assert_contains "$V_OUT" "OK 0 errors, 1 warning(s)" "the awk WARN is counted in the summary"

t_case "two '## Architecture' sections are a WARN"
arch_roadmap "$repo/.task/roadmap/arch-twice.md" "$ARCH_OK
$ARCH_OK"
v "$repo" roadmap arch-twice
assert_exit 0 "$V_EXIT" "WARN only"
assert_contains "$V_OUT" "2 \`## Architecture\` sections" "names the count"

t_case "missing required sub-headings are WARNs"
arch_roadmap "$repo/.task/roadmap/arch-bare.md" '## Architecture

Prose only.
'
v "$repo" roadmap arch-bare
assert_exit 0 "$V_EXIT" "WARN only"
assert_contains "$V_OUT" "no \`### Components\` sub-heading" "components"
assert_contains "$V_OUT" "no \`### Item sketches\` sub-heading" "item sketches"

t_case "a numbered sub-heading inside '## Architecture' is an error with its own message"
arch_roadmap "$repo/.task/roadmap/arch-numbered.md" "${ARCH_OK}
### 2. Second item sketch
"
v "$repo" roadmap arch-numbered
assert_exit 1 "$V_EXIT" "reads as an item"
assert_contains "$V_OUT" "numbered sub-heading in ## Architecture reads as item 2" "section-aware message"

t_case "a spec with no '## N.' decision section is an error"
mkdir -p "$repo/.task/spec"
printf '# Spec: nothing pinned\n\nProse only.\n' >"$repo/.task/spec/bare.md"
v "$repo" spec bare
assert_exit 1 "$V_EXIT" "spec without decisions"
assert_contains "$V_OUT" "no numbered decision sections" "names the sections"

t_case "an unconfigured project is a precondition failure (exit 2)"
bare=$(make_repo)
v "$bare" task whatever
assert_exit 2 "$V_EXIT" "no .task/CLAUDE.md"
assert_contains "$V_OUT" "CLAUDE.md not found" "the substring the skills branch on"

t_case "a missing slug argument is a usage error (exit 2)"
v "$repo" task
assert_exit 2 "$V_EXIT" "no slug"

t_summary
