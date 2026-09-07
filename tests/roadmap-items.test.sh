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

### - [x] 1. Already shipped
**Dependencies:** —

### - [~] 2. In progress elsewhere
**Dependencies:** —

### - [ ] 3. Open, depends on one
**Dependencies:** 1, 2
**Model:** haiku
### Spec references → [event-envelope](../spec/event-envelope.md) §2
**Ready description:**
> ### Context
> c

### - [ ] 4. Open, no deps, no model hint
**Dependencies:** —

## Out of scope

**Dependencies:** 99
MD

t_case "unchecked items are reported with number, deps, model and title"
i "$repo" api-v2
assert_exit 0 "$I_EXIT" "collector ran"
assert_contains "$I_OUT" "$(printf '3\t1,2\thaiku\tOpen, depends on one')" "item with deps and hint"
assert_contains "$I_OUT" "$(printf '4\t\tsonnet\tOpen, no deps, no model hint')" "em dash is no deps, model defaults"

t_case "the DONE line carries every already-marked number"
assert_contains "$I_OUT" "$(printf 'DONE\t1,2')" "5-state class counts as marked"

t_case "a stray Dependencies line outside an item is not billed to the last item"
assert_eq "3" "$(grep -c . <<<"$I_OUT")" "two items plus the DONE line"

t_case "a checked-off roadmap reports no items and a full DONE line"
sed 's/^### - \[ \] /### - [x] /' "$repo/.task/roadmap/api-v2.md" >"$repo/.task/roadmap/shipped.md"
i "$repo" shipped
assert_exit 0 "$I_EXIT" "all marked"
assert_eq "$(printf 'DONE\t1,2,3,4')" "$I_OUT" "only the DONE line"

t_case "an unresolvable roadmap is an error, never an empty item list"
i "$repo" nosuchthing
assert_exit 1 "$I_EXIT" "no such roadmap"
assert_contains "$I_OUT" "roadmap not found" "says so"

t_case "a missing argument is a usage error"
i "$repo"
assert_exit 2 "$I_EXIT" "usage"

t_summary
