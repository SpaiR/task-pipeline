#!/usr/bin/env bash
# Contract under test: computeWaves() in skills/_lib/roadmap-driver.js — the
# dependency sort the skill used to do by hand. Extracted verbatim between its
# marker comments, because the driver is a Workflow script (top-level `return`,
# injected globals) and cannot be imported.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
sed -n '/--- computeWaves (pure/,/--- end computeWaves/p' "$DRIVER" >"$dir/waves.mjs"
if ! grep -q 'function computeWaves' "$dir/waves.mjs"; then
  t_case "extract computeWaves from the driver"
  assert_contains "$(cat "$dir/waves.mjs")" "function computeWaves" "marker comments still present"
  t_summary
fi

# One node run per case keeps a thrown error from masking later assertions.
run_js() { # <js body> → prints result
  { cat "$dir/waves.mjs"; printf '%s\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

# `1(—) 2(1) 3(1) 4(2,3)` — the shape the skill's own worked example used.
FIXTURE="const items = [
  { n: 1, title: 'one',   model: 'sonnet', deps: [] },
  { n: 2, title: 'two',   model: 'sonnet', deps: [1] },
  { n: 3, title: 'three', model: 'sonnet', deps: [1] },
  { n: 4, title: 'four',  model: 'sonnet', deps: [2, 3] },
]
const shape = (r) => r.error ? 'ERROR ' + r.error : JSON.stringify(r.waves.map(w => w.map(i => i.n)))"

t_case "scope 'all' sorts into dependency waves"
assert_eq "[[1],[2,3],[4]]" "$(run_js "$FIXTURE
console.log(shape(computeWaves(items, [], 'all')))")" "wave order"

t_case "scope 'next-wave' returns only the first wave"
assert_eq "[[1]]" "$(run_js "$FIXTURE
console.log(shape(computeWaves(items, [], 'next-wave')))")" "narrowed after sorting"

t_case "an already-marked dependency unblocks its item"
assert_eq "[[2,3],[4]]" "$(run_js "$FIXTURE
console.log(shape(computeWaves(items.slice(1), [1], 'all')))")" "done counts as satisfied"

t_case "a cycle is reported, not guessed around"
out=$(run_js "const items = [
  { n: 1, title: 'one', model: 'sonnet', deps: [2] },
  { n: 2, title: 'two', model: 'sonnet', deps: [1] },
]
const r = computeWaves(items, [], 'all')
console.log(r.error ? 'ERROR ' + r.error : 'NO ERROR')")
assert_contains "$out" "cycle" "names the cycle"
assert_contains "$out" "#1, #2" "names the items"

t_case "a picked scope whose dependency is neither marked nor included stops"
out=$(run_js "$FIXTURE
const r = computeWaves(items, [], [4])
console.log(r.error ? 'ERROR ' + r.error : 'NO ERROR')")
assert_contains "$out" "out of scope" "the hard stop"
assert_contains "$out" "#4 depends on #2" "names both items"

t_case "a picked scope naming an item that is not unchecked stops"
out=$(run_js "$FIXTURE
const r = computeWaves(items, [], [9])
console.log(r.error ? 'ERROR ' + r.error : 'NO ERROR')")
assert_contains "$out" "not runnable" "the hard stop"

t_case "a picked scope of independent items is one wave"
assert_eq "[[2,3]]" "$(run_js "$FIXTURE
console.log(shape(computeWaves(items, [1], [2, 3])))")" "single wave"

t_case "the whole driver script parses"
# Not `node --check`: the file is a Workflow script, so its top-level `return`
# is legal only inside the runtime's wrapper. Reproduce that wrapper.
{
  echo 'async function _wf(args, agent, parallel, log) {'
  grep -v '^export const meta' "$DRIVER" | sed '1,/^}$/d'
  echo '}'
} >"$dir/wrapped.mjs"
node --check "$dir/wrapped.mjs" >"$dir/check.out" 2>&1
assert_exit 0 "$?" "syntax: $(cat "$dir/check.out")"

t_summary
