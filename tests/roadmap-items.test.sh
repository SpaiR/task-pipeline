#!/usr/bin/env bash
# Contract under test: skills/_lib/roadmap-items.sh — the item report the
# Workflow driver's `items` / `done` args are built from verbatim. Field order
# and the DONE line are the contract.
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

**Size:** S

**Ready description:**

> **Context**
>
> c
>
> **Spec references:** [event-envelope](../spec/event-envelope.md) §2

### 4. Open, no deps, no size hint
- [ ] Done
**Dependencies:** —

### 5. No status line, never runs

**Dependencies:** —

### - [ ] 6. Checkbox left in the heading

**Dependencies:** 4

### 7. Stale model hint only

- [ ] Done

**Model:** haiku

### 8. Lowercase size

- [ ] Done

**Size:** l

## Out of scope

**Dependencies:** 99
MD

t_case "unchecked items are reported with number, deps, size and title"
i "$repo" api-v2
assert_exit 0 "$I_EXIT" "collector ran"
assert_contains "$I_OUT" "$(printf '3\t1,2\tS\tOpen, depends on one')" "item with deps and hint"
assert_contains "$I_OUT" "$(printf '4\t\tM\tOpen, no deps, no size hint')" "em dash is no deps, size defaults to M"

t_case "a stale Model hint is ignored and a lowercase Size is accepted"
assert_contains "$I_OUT" "$(printf '7\t\tM\tStale model hint only')" "Model is no longer read"
assert_contains "$I_OUT" "$(printf '8\t\tL\tLowercase size')" "size is upper-cased"

t_case "the DONE line carries every already-marked number"
assert_contains "$I_OUT" "$(printf 'DONE\t1,2')" "5-state class counts as marked"

t_case "a stray Dependencies line outside an item is not billed to the last item"
assert_eq "5" "$(grep -c . <<<"$I_OUT")" "four items plus the DONE line"

t_case "a heading without a status line, or with a checkbox in it, is no item and steals no Dependencies"
assert_eq "0" "$(grep -c -e '^5' -e '^6' <<<"$I_OUT")" "neither is reported"
assert_contains "$I_OUT" "$(printf '4\t\tM\tOpen, no deps, no size hint')" "item 4 keeps its own deps, not item 6's"

t_case "a checked-off roadmap reports no items and a full DONE line"
sed 's/^- \[ \] Done$/- [x] Done/' "$repo/.task/roadmap/api-v2.md" >"$repo/.task/roadmap/shipped.md"
i "$repo" shipped
assert_exit 0 "$I_EXIT" "all marked"
assert_eq "$(printf 'DONE\t1,2,3,4,7,8')" "$I_OUT" "only the DONE line"

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
assert_contains "$I_OUT" "$(printf '3\t\tM\tAfter')" "item past the byte, em dash still no deps"
assert_contains "$I_OUT" "$(printf 'DONE\t1')" "DONE line"

t_case "a missing argument is a usage error"
i "$repo"
assert_exit 2 "$I_EXIT" "usage"

t_summary
