#!/usr/bin/env bash
# Contract under test: skills/_lib/write-task.sh — the single owner of task.md
# assembly. What matters is that every write leaves a file `validate.sh`
# accepts, that a collision never writes, and that a failed write never
# reports success or damages the file it was replacing.
source "$(dirname "$0")/lib.sh"

WRITE="$T_REPO_ROOT/skills/_lib/write-task.sh"

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
assert_eq "## Description ## Plan ## Tests ## Execution" \
  "$(grep '^## ' "$repo/.task/task/alpha.md" | tr '\n' ' ' | sed 's/ $//')" "section order"
# The dangling spec reference is a WARN, never an error, so the file is valid.
assert_contains "$W_OUT" "OK 0 errors" "validate is clean"

t_case "a second --fresh without --force exits 4 and changes nothing"
before=$(cat "$repo/.task/task/alpha.md")
w "$repo" --fresh --slug alpha --title "Overwriting" --description "$body/desc.md" --plan "$body/plan.md"
assert_exit 4 "$W_EXIT" "collision"
assert_eq "$before" "$(cat "$repo/.task/task/alpha.md")" "file untouched"

t_case "--force rewrites the same slug whole"
w "$repo" --fresh --slug alpha --title "Overwritten" --description "$body/desc.md" \
  --plan "$body/plan.md" --force
assert_exit 0 "$W_EXIT" "forced write"
assert_contains "$(head -1 "$repo/.task/task/alpha.md")" "# Overwritten" "new title"
assert_eq "0" "$(grep -c '^## Tests' "$repo/.task/task/alpha.md")" "nothing of the old file survives"

t_case "a write with no --plan is a usage error and writes nothing"
# Every task file carries a Plan: validate.sh errors on a file without one.
w "$repo" --fresh --slug beta --title "Beta task" --description "$body/desc.md"
assert_exit 2 "$W_EXIT" "missing --plan"
assert_eq "no" "$([[ -f "$repo/.task/task/beta.md" ]] && echo yes || echo no)" "nothing created"

t_case "a value flag given last with no value is a usage error, not a hang"
# `shift 2` with one argument left fails without shifting, and the parse loop
# once spun on the trailing flag forever. Run under a watchdog, so a regression
# fails this case instead of hanging the suite (stock macOS has no `timeout`).
w_bounded() { # <repo> <args…> → $W_OUT, $W_EXIT ("hung" when killed)
  local dir="$1" out pid i=0
  shift
  out=$(t_tmpdir)/out
  (cd "$dir" && exec env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$WRITE" "$@") >"$out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( i < 50 )); do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"; wait "$pid" 2>/dev/null; W_EXIT=hung
  else
    wait "$pid"; W_EXIT=$?
  fi
  W_OUT=$(cat "$out")
}
w_bounded "$repo" --fresh --slug beta --title "Beta task" --description "$body/desc.md" --plan
assert_eq "2" "$W_EXIT" "trailing --plan"
assert_contains "$W_OUT" "--plan needs a value" "names the flag"
w_bounded "$repo" --fresh --slug beta --title "Beta task" --description "$body/desc.md" --plan "$body/plan.md" --spec
assert_eq "2" "$W_EXIT" "trailing --spec"
assert_eq "no" "$([[ -f "$repo/.task/task/beta.md" ]] && echo yes || echo no)" "nothing created"

t_case "--help prints the whole header, and nothing past it"
# A fixed line range once cut the header's last lines when it grew.
w "$repo" --help
assert_exit 2 "$W_EXIT" "help is a usage exit"
assert_contains "$W_OUT" "the VALIDATE block." "last header line"
assert_eq "0" "$(grep -c '^set -u' <<<"$W_OUT")" "stops at the code"

t_case "a mode other than --fresh is a usage error"
w "$repo" --revise --slug alpha --plan "$body/plan.md"
assert_exit 2 "$W_EXIT" "no revise mode"

t_case "a write that fails partway exits 5 and leaves the old file alone"
# A failing tool stands in for a full disk or an unwritable `.task/`: a PATH
# shim, since a chmod does not bite as root. The write once redirected straight
# into the target: a failed body step still printed `WROTE:`, and `--force` had
# already truncated the original.
w "$repo" --fresh --slug lambda --title "Lambda task" --description "$body/desc.md" --plan "$body/plan.md"
before=$(cat "$repo/.task/task/lambda.md")
shim=$(t_tmpdir)
for tool in mktemp awk mv; do
  rm -f "$shim"/*
  printf '#!/bin/sh\nexit 1\n' >"$shim/$tool" && chmod +x "$shim/$tool"
  PATH="$shim:$PATH" w "$repo" --fresh --force --slug lambda --title "Replaced" \
    --description "$body/desc.md" --plan "$body/plan.md"
  assert_exit 5 "$W_EXIT" "$tool failed"
  assert_eq "0" "$(grep -c 'WROTE:' <<<"$W_OUT")" "$tool: no success line"
  assert_eq "$before" "$(cat "$repo/.task/task/lambda.md")" "$tool: target untouched"
  assert_eq "" "$(find "$repo/.task/task" -name '.lambda.*')" "$tool: no staging file left"
done

t_case "a byte that is not UTF-8 survives a UTF-8 locale"
# macOS awk decodes by locale and aborts on an invalid byte (`towc: multibyte
# conversion failure`), which surfaced as a write failure. The helper's awk
# runs under LC_ALL=C.
printf 'Caf\351, saved as Latin-1.\n' >"$body/latin1.md"
LC_ALL=en_US.UTF-8 w "$repo" --fresh --slug xi --title "Xi task" \
  --description "$body/latin1.md" --plan "$body/plan.md"
assert_exit 0 "$W_EXIT" "fresh"
assert_eq "1" "$(LC_ALL=C grep -c $'Caf\351' "$repo/.task/task/xi.md")" "byte kept"

t_case "a slug that is a path is a usage error"
w "$repo" --fresh --slug ../escape --title T --description "$body/desc.md" --plan "$body/plan.md"
assert_exit 2 "$W_EXIT" "path rejected"

t_summary
