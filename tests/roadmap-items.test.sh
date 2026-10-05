#!/usr/bin/env bash
# Contract under test: skills/_lib/roadmap-items.sh — the item report the
# Workflow driver's `items` / `done` args are built from verbatim. Field order
# and the DONE line are the contract; field 5 is the slug of the item's own
# task file, when one was already written for it.
source "$(dirname "$0")/lib.sh"

ITEMS="$T_REPO_ROOT/skills/_lib/roadmap-items.sh"

i() { # <repo> <arg> → $I_OUT, $I_EXIT
  local dir="$1"
  shift
  I_OUT=$( (cd "$dir" && env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$ITEMS" "$@") 2>&1 )
  I_EXIT=$?
}

repo=$(make_repo --config)
mkdir -p "$repo/.task/roadmap"
cat >"$repo/.task/roadmap/api-v2.md" <<'MD'
# API v2

Spec: [event-envelope](../spec/event-envelope.md)

## Phase 1

### 1. Already shipped

- [x] Done

**Dependencies:** —

### 2. In progress elsewhere

- [~] Done

**Dependencies:** —

### 3. Open, depends on one

- [ ] Done

**Dependencies:** 1, 2

**Model:** haiku

**Ready description:**

> **Context**
>
> c
>
> **Spec references:** [event-envelope](../spec/event-envelope.md) §2

### 4. Open, no deps, no model hint
- [ ] Done
**Dependencies:** —

### 5. No status line, never runs

**Dependencies:** —

### - [ ] 6. Checkbox left in the heading

**Dependencies:** 4

## Out of scope

**Dependencies:** 99
MD

t_case "unchecked items are reported with number, deps, model and title"
i "$repo" api-v2
assert_exit 0 "$I_EXIT" "collector ran"
assert_contains "$I_OUT" "$(printf '3\t1,2\thaiku\tOpen, depends on one\t')" "item with deps and hint"
assert_contains "$I_OUT" "$(printf '4\t\tsonnet\tOpen, no deps, no model hint\t')" "em dash is no deps, model defaults"
assert_eq "0" "$(awk -F'\t' '$1 ~ /^[0-9]+$/ && $5 != ""' <<<"$I_OUT" | grep -c .)" "no task files, so no planned slug"

t_case "the DONE line carries every already-marked number"
assert_contains "$I_OUT" "$(printf 'DONE\t1,2')" "5-state class counts as marked"

t_case "a stray Dependencies line outside an item is not billed to the last item"
assert_eq "3" "$(grep -c . <<<"$I_OUT")" "two items plus the DONE line"

t_case "a heading without a status line, or with a checkbox in it, is no item and steals no Dependencies"
assert_eq "0" "$(grep -c -e '^5' -e '^6' <<<"$I_OUT")" "neither is reported"
assert_contains "$I_OUT" "$(printf '4\t\tsonnet\tOpen, no deps, no model hint')" "item 4 keeps its own deps, not item 6's"

t_case "a checked-off roadmap reports no items and a full DONE line"
sed 's/^- \[ \] Done$/- [x] Done/' "$repo/.task/roadmap/api-v2.md" >"$repo/.task/roadmap/shipped.md"
i "$repo" shipped
assert_exit 0 "$I_EXIT" "all marked"
assert_eq "$(printf 'DONE\t1,2,3,4')" "$I_OUT" "only the DONE line"

t_case "an unresolvable roadmap is an error, never an empty item list"
i "$repo" nosuchthing
assert_exit 1 "$I_EXIT" "no such roadmap"
assert_contains "$I_OUT" "roadmap not found" "says so"

t_case "a roadmap that resolves but cannot be read is an error, never an empty item list"
# The resolve step only checks the file exists; awk is what fails on the read.
chmod a-r "$repo/.task/roadmap/shipped.md"
if [[ -r "$repo/.task/roadmap/shipped.md" ]]; then
  echo "$T_NAME: SKIP — the roadmap stays readable after chmod (running as root)"
else
  i "$repo" shipped
  assert_exit 1 "$I_EXIT" "unreadable roadmap"
  assert_contains "$I_OUT" "cannot read roadmap" "says so"
fi
chmod u+r "$repo/.task/roadmap/shipped.md"

t_case "a byte that is not UTF-8 does not truncate the item list"
t_utf8_locale
# macOS awk decodes by locale and aborts on an invalid byte: the list once
# stopped at that item, with no DONE line and an exit code no caller handles.
printf '# L\n\n### 1. Done\n\n- [x] Done\n\n**Dependencies:** \342\200\224\n\n### 2. Caf\351\n\n- [ ] Done\n\n**Dependencies:** 1\n\n### 3. After\n\n- [ ] Done\n\n**Dependencies:** \342\200\224\n' \
  >"$repo/.task/roadmap/latin1.md"
LC_ALL=$T_UTF8 i "$repo" latin1
assert_exit 0 "$I_EXIT" "collector ran"
assert_contains "$I_OUT" "$(printf '3\t\tsonnet\tAfter')" "item past the byte, em dash still no deps"
assert_contains "$I_OUT" "$(printf 'DONE\t1')" "DONE line"

# Planned-file cases: a fresh roadmap, so the item lines above stay as they were.
cat >"$repo/.task/roadmap/plans.md" <<'MD'
# Plans

### 1. Shipped

- [x] Done

**Dependencies:** —

### 2. Half way

- [ ] Done

**Dependencies:** 1

### 3. Hand-captured

- [ ] Done

**Dependencies:** —
MD
mkdir -p "$repo/.task/task"
w_task() { # <slug> <header lines…> → a task file with those headers above ---
  local f="$repo/.task/task/$1.md"
  shift
  { printf '# T\n\n'; printf '%s\n\n' "$@"; printf -- '---\n## Description\n\nd\n\n## Plan\n\n### Step 1: x\n'; } >"$f"
}

t_case "an unchecked item with its own task file reports that slug as field 5"
w_task half-way 'Roadmap: [plans](../roadmap/plans.md)' 'Source item: #2'
i "$repo" plans
assert_exit 0 "$I_EXIT" "collector ran"
assert_contains "$I_OUT" "$(printf '2\t1\tsonnet\tHalf way\thalf-way')" "item 2 names its plan"
assert_eq "" "$(awk -F'\t' '$1 == "3" { print $5 }' <<<"$I_OUT")" "item 3 has none"
assert_contains "$I_OUT" "$(printf 'DONE\t1')" "DONE line unchanged"

t_case "a namesake task file does not count as the item's plan"
rm -f "$repo/.task/task/half-way.md"
w_task other-roadmap 'Roadmap: [api-v2](../roadmap/api-v2.md)' 'Source item: #2'
w_task prefix-roadmap 'Roadmap: [plans-v2](../roadmap/plans-v2.md)' 'Source item: #2'
w_task bare-header 'Roadmap: plans' 'Source item: #3'
w_task no-headers
# A Source item: in the body, below ---, is prose, not a header.
printf '# T\n\n---\nRoadmap: plans\n\nSource item: #2\n' >"$repo/.task/task/body-only.md"
i "$repo" plans
assert_exit 0 "$I_EXIT" "collector ran"
assert_eq "" "$(awk -F'\t' '$1 == "2" { print $5 }' <<<"$I_OUT")" "item 2: other roadmaps and body text are no plan"
assert_eq "bare-header" "$(awk -F'\t' '$1 == "3" { print $5 }' <<<"$I_OUT")" "item 3: a bare Roadmap: slug counts"

t_case "the newest of two plans for one item wins"
w_task older-plan 'Roadmap: [plans](../roadmap/plans.md)' 'Source item: #2'
touch -t 202001010000 "$repo/.task/task/older-plan.md"
w_task newer-plan 'Roadmap: [plans](../roadmap/plans.md)' 'Source item: #2'
i "$repo" plans
assert_eq "newer-plan" "$(awk -F'\t' '$1 == "2" { print $5 }' <<<"$I_OUT")" "most recently modified"

t_case "an unreadable task file is skipped, never an error"
chmod a-r "$repo/.task/task/newer-plan.md"
if [[ -r "$repo/.task/task/newer-plan.md" ]]; then
  echo "$T_NAME: SKIP — the task file stays readable after chmod (running as root)"
else
  i "$repo" plans
  assert_exit 0 "$I_EXIT" "collector ran"
  assert_eq "older-plan" "$(awk -F'\t' '$1 == "2" { print $5 }' <<<"$I_OUT")" "the readable plan is reported"
  assert_contains "$I_OUT" "$(printf 'DONE\t1')" "DONE line"
fi
chmod u+r "$repo/.task/task/newer-plan.md"

t_case "a missing argument is a usage error"
i "$repo"
assert_exit 2 "$I_EXIT" "usage"

t_summary
