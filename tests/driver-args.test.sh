#!/usr/bin/env bash
# Contract under test: checkArgs() and the STAGES table in
# skills/_lib/roadmap-driver.js. checkArgs asserts the args the
# roadmap-to-workflow skill builds before any agent runs, and returns null or
# the reason the `bad args` headline gives; driver-display.test.sh holds the
# headline itself. STAGES maps an item's size to the plan and implement stages'
# model and effort, and plan must never sit below implement. Extracted verbatim
# from the driver's `// --- pure` block, as driver-waves.test.sh does for
# computeWaves.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
sed -n '/^\/\/ --- pure (/,/^\/\/ --- end pure/p' "$DRIVER" >"$dir/pure.mjs"
if ! grep -q 'function checkArgs' "$dir/pure.mjs" || ! grep -q 'const STAGES' "$dir/pure.mjs"; then
  t_case "extract checkArgs and STAGES from the driver"
  assert_contains "$(cat "$dir/pure.mjs")" "function checkArgs" "the pure block's marker comments still present"
  assert_contains "$(cat "$dir/pure.mjs")" "const STAGES" "STAGES inside the pure block"
  t_summary
fi

# One node run per case keeps a thrown error from masking later assertions.
run_js() { # <js body> → prints result
  { cat "$dir/pure.mjs"; printf '%s\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

# check <override JS> → prints checkArgs' verdict for valid args with the override applied
check() {
  run_js "let args = { slug: 'retry-work', aiDir: '/p/.task', pluginRoot: '/plugin', specPaths: ['/p/.task/spec/api.md'],
  items: [{ n: 1, title: 'Retry backoff', size: 'S', deps: [] }, { n: 2, title: 'Retry metrics', size: 'M', deps: [1] }],
  done: [], scope: 'all' }
$1
console.log(checkArgs(args))"
}

t_case "valid args pass"
assert_eq "null" "$(check "")" "all"
assert_eq "null" "$(check "args.scope = 'next-wave'")" "next-wave"
assert_eq "null" "$(check "args.scope = [2]; args.done = [1]")" "picked items"
assert_eq "null" "$(check "args.specPaths = []")" "no specs"

t_case "args that are not an object"
assert_eq "args must be an object, got object" "$(check "args = null")" "null"
assert_eq "args must be an object, got array" "$(check "args = []")" "array"
assert_eq "args must be an object, got string" "$(check "args = '{}'")" "JSON string"

t_case "paths must be absolute"
assert_eq "slug must be a non-empty string" "$(check "args.slug = ''")" "empty slug"
assert_eq "aiDir must be an absolute path" "$(check "args.aiDir = '.task'")" "relative aiDir"
assert_eq "pluginRoot must be an absolute path" "$(check "args.pluginRoot = undefined")" "missing pluginRoot"
assert_eq "specPaths must be an array of absolute paths ([] when the roadmap has no Spec: headers)" \
  "$(check "args.specPaths = ['spec/api.md']")" "relative spec path"
assert_eq "specPaths must be an array of absolute paths ([] when the roadmap has no Spec: headers)" \
  "$(check "args.specPaths = '/p/.task/spec/api.md'")" "string instead of an array"

t_case "items must be a non-empty array of well-formed items"
assert_eq "items must be a non-empty array of {n, title, size, deps} objects — was it passed as a JSON string instead of a real array?" \
  "$(check "args.items = '[]'")" "JSON string"
assert_eq "every entry of items must be an {n, title, size, deps} object" "$(check "args.items = [[1]]")" "array entry"
assert_eq "every item needs an integer n >= 1" "$(check "args.items[0].n = 1.5")" "fractional n"
assert_eq "item #1 needs a non-empty title" "$(check "args.items[0].title = ''")" "empty title"
assert_eq "item #2 size must be S|M|L, got undefined" "$(check "delete args.items[1].size")" "missing size"
assert_eq "item #2 deps must be an array of item numbers ([] for none)" "$(check "args.items[1].deps = [0]")" "dep 0"
assert_eq "item #2 deps must be an array of item numbers ([] for none)" "$(check "args.items[1].deps = '1'")" "deps as a string"
assert_eq "items contains the same n twice" "$(check "args.items[1].n = 1")" "duplicate n"

t_case "done and scope"
assert_eq "done must be an array of already-marked item numbers ([] when none are)" "$(check "args.done = ['1']")" "done as strings"
assert_eq "done must be an array of already-marked item numbers ([] when none are)" "$(check "delete args.done")" "missing done"
assert_eq "scope must be 'all', 'next-wave', or a non-empty array of item numbers" "$(check "args.scope = 'first'")" "unknown word"
assert_eq "scope must be 'all', 'next-wave', or a non-empty array of item numbers" "$(check "args.scope = [0]")" "item 0"

t_case "every size gives plan and implement a model and an effort"
assert_eq "S,M,L" "$(run_js "console.log(SIZES.join(','))")" "sizes"
assert_eq "ok" "$(run_js "const bad = SIZES.flatMap((s) => ['plan', 'implement'].filter((st) =>
  typeof STAGES[s][st]?.model !== 'string' || typeof STAGES[s][st]?.effort !== 'string').map((st) => s + '/' + st))
console.log(bad.length ? 'missing ' + bad.join(', ') : 'ok')")" "complete cells"

t_case "plan is never below implement, and xhigh and max are not used"
assert_eq "ok" "$(run_js "const MODEL = { haiku: 0, sonnet: 1, opus: 2 }, EFFORT = { low: 0, medium: 1, high: 2 }
const bad = SIZES.filter((s) => {
  const { plan, implement } = STAGES[s]
  return [plan, implement].some((c) => !(c.model in MODEL) || !(c.effort in EFFORT)) ||
    MODEL[plan.model] < MODEL[implement.model] || EFFORT[plan.effort] < EFFORT[implement.effort]
})
console.log(bad.length ? 'broken ' + bad.join(', ') : 'ok')")" "ordering"

t_summary
