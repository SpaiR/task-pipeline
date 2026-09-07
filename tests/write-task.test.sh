#!/usr/bin/env bash
# Contract under test: skills/_lib/write-task.sh — the single owner of task.md
# assembly. What matters is that every mode leaves a file `validate.sh` accepts,
# that a collision never writes, and that revise touches nothing it was not
# asked to touch.
source "$(dirname "$0")/lib.sh"

WRITE="$T_REPO_ROOT/skills/_lib/write-task.sh"
VALIDATE="$T_REPO_ROOT/skills/validate/validate.sh"

w() { # <repo> <args…> → $W_OUT, $W_EXIT
  local dir="$1"
  shift
  W_OUT=$( (cd "$dir" && env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$WRITE" "$@") 2>&1 )
  W_EXIT=$?
}

repo=$(make_repo --config)
body=$(t_tmpdir)
printf 'Why this exists, and what it changes.\n' >"$body/desc.md"
cat >"$body/plan.md" <<'MD'
### Step 1: do the thing
**Goal:** it is done
**Touches:** `src/a.ts`
MD
cat >"$body/plan2.md" <<'MD'
### Step 1: do a different thing
**Goal:** also done
**Touches:** `src/b.ts`
MD
cat >"$body/tests.md" <<'MD'
### Test 1: it works
`src/a.test.ts`; assert the thing.
MD

t_case "--fresh writes a file validate.sh accepts, with the headers and pointer"
w "$repo" --fresh --slug alpha --title "Alpha task" --description "$body/desc.md" \
  --plan "$body/plan.md" --tests "$body/tests.md" --roadmap api-v2 --item 3 --spec event-envelope
assert_exit 0 "$W_EXIT" "fresh write"
assert_contains "$W_OUT" "WROTE: $repo/.task/task/alpha.md (fresh)" "reports the path"
written=$(cat "$repo/.task/task/alpha.md")
assert_contains "$written" "# Alpha task" "title"
assert_contains "$written" "Roadmap: [api-v2](../roadmap/api-v2.md)" "roadmap link form"
assert_contains "$written" "Source item: #3" "bare item number"
assert_contains "$written" "Spec: [event-envelope](../spec/event-envelope.md)" "spec link form"
assert_contains "$written" '> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.' "stamped pointer"
# The dangling spec reference is a WARN, never an error, so the file is valid.
assert_contains "$W_OUT" "OK 0 errors" "validate is clean"

t_case "a second --fresh without --force exits 4 and changes nothing"
before=$(cat "$repo/.task/task/alpha.md")
w "$repo" --fresh --slug alpha --title "Overwriting" --description "$body/desc.md"
assert_exit 4 "$W_EXIT" "collision"
assert_eq "$before" "$(cat "$repo/.task/task/alpha.md")" "file untouched"

t_case "--force overwrites the same slug"
w "$repo" --fresh --slug alpha --title "Overwritten" --description "$body/desc.md" --force
assert_exit 0 "$W_EXIT" "forced write"
assert_contains "$(head -1 "$repo/.task/task/alpha.md")" "# Overwritten" "new title"

t_case "--promote inserts the plan directly above the Execution pointer"
w "$repo" --fresh --slug beta --title "Beta task" --description "$body/desc.md"
w "$repo" --promote --slug beta --plan "$body/plan.md"
assert_exit 0 "$W_EXIT" "promote"
assert_eq "## Description ## Plan ## Execution" \
  "$(grep '^## ' "$repo/.task/task/beta.md" | tr '\n' ' ' | sed 's/ $//')" "section order"
assert_contains "$W_OUT" "OK 0 errors" "still valid"

t_case "--revise replaces the plan and leaves an untouched Tests section byte-identical"
w "$repo" --fresh --slug gamma --title "Gamma task" --description "$body/desc.md" \
  --plan "$body/plan.md" --tests "$body/tests.md"
tests_before=$(awk '/^## Tests/{f=1} f && !/^## Execution/{print} /^## Execution/{exit}' "$repo/.task/task/gamma.md")
w "$repo" --revise --slug gamma --plan "$body/plan2.md"
assert_exit 0 "$W_EXIT" "revise"
gamma=$(cat "$repo/.task/task/gamma.md")
assert_contains "$gamma" "### Step 1: do a different thing" "new plan"
assert_eq "0" "$(grep -c 'do the thing' <<<"$gamma")" "old plan gone"
tests_after=$(awk '/^## Tests/{f=1} f && !/^## Execution/{print} /^## Execution/{exit}' "$repo/.task/task/gamma.md")
assert_eq "$tests_before" "$tests_after" "Tests section unchanged"
assert_contains "$W_OUT" "OK 0 errors" "still valid"

t_case "a file with no '## Description' exits 3 untouched"
printf '# Not a task\n\nJust prose.\n' >"$repo/.task/task/delta.md"
before=$(cat "$repo/.task/task/delta.md")
w "$repo" --promote --slug delta --plan "$body/plan.md"
assert_exit 3 "$W_EXIT" "nothing to promote"
assert_eq "$before" "$(cat "$repo/.task/task/delta.md")" "file untouched"

t_case "promote repairs a hand-written file with no separator and no pointer"
printf '# Hand written\n## Description\n\nWhy.\n' >"$repo/.task/task/eps.md"
w "$repo" --promote --slug eps --plan "$body/plan.md"
assert_exit 0 "$W_EXIT" "repaired promote"
eps=$(cat "$repo/.task/task/eps.md")
assert_contains "$W_OUT" "OK 0 errors" "validates after repair"
assert_contains "$eps" "## Execution" "pointer stamped"

t_case "a slug that is a path is a usage error"
w "$repo" --fresh --slug ../escape --title T --description "$body/desc.md"
assert_exit 2 "$W_EXIT" "path rejected"

t_summary
