#!/usr/bin/env bash
# Contract under test: the driver's two display helpers in
# skills/_lib/roadmap-driver.js — itemPhase(), the progress-group title all three
# stages of one item share, and runReport() + digestSummary(), the value the
# invoking skill gets back once any agent has run. runReport's first line is the
# parser-stable headline and must come through untouched. Extracted verbatim
# between their marker comments, as driver-waves.test.sh does for computeWaves.
# The last cases run the whole driver on stubbed agents, so every return
# after the first agent is held to runReport — landed items included on a stop.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
{
  sed -n '/--- itemPhase (pure/,/--- end itemPhase/p' "$DRIVER"
  sed -n '/--- runReport (pure/,/--- end runReport/p' "$DRIVER"
} >"$dir/display.mjs"
for fn in itemPhase digestSummary runReport; do
  if ! grep -q "function $fn" "$dir/display.mjs"; then
    t_case "extract $fn from the driver"
    assert_contains "$(cat "$dir/display.mjs")" "function $fn" "marker comments still present"
    t_summary
  fi
done

# One node run per case keeps a thrown error from masking later assertions.
run_js() { # <js body> → prints result
  { cat "$dir/display.mjs"; printf '%s\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "itemPhase keeps a short title whole"
assert_eq "W1 · #3 Config loader" "$(run_js "console.log(itemPhase(1, 3, 'Config loader'))")" "short title"

t_case "itemPhase cuts a long title to 32 characters with an ellipsis"
out=$(run_js "console.log(itemPhase(2, 1, 'Add retry backoff with jitter to the HTTP client layer'))")
assert_eq "W2 · #1 Add retry backoff with jitter t…" "$out" "cut title"
assert_eq "32" "$(run_js "console.log(Array.from(itemPhase(2, 1, 'x'.repeat(80)).replace('W2 · #1 ', '')).length)")" "cut length"

t_case "itemPhase cuts by code point, never inside a character"
assert_eq "W1 · #2 Подключить метрики повторов к д…" \
  "$(run_js "console.log(itemPhase(1, 2, 'Подключить метрики повторов к дашборду сервиса'))")" "Cyrillic"
assert_eq "31" "$(run_js "console.log(Array.from(itemPhase(1, 1, '🚀'.repeat(40)).replace('W1 · #1 ', '')).filter((c) => c === '🚀').length)")" \
  "astral characters are not split into surrogate halves"

t_case "itemPhase collapses whitespace and trims before cutting"
assert_eq "W1 · #4 Split the parser" "$(run_js "console.log(itemPhase(1, 4, '  Split   the\\nparser  '))")" "whitespace"

t_case "digestSummary takes the text after the OK head"
assert_eq "added jittered backoff" \
  "$(run_js "console.log(digestSummary('OK #3 retry-backoff added jittered backoff', 3, 'retry-backoff'))")" "summary"
assert_eq "[]" "$(run_js "console.log('[' + digestSummary('OK #3 retry-backoff', 3, 'retry-backoff') + ']')")" "bare head"

t_case "runReport with nothing landed is the headline alone"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b" \
  "$(run_js "console.log(runReport('roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b', []))")" "headline only"

t_case "runReport lists landed items under the headline, in landing order"
out=$(run_js "console.log(runReport('roadmap-to-workflow: all items shipped.', [
  { n: 3, slug: 'config-loader', impl: 'read TOML config', review: 'no findings' },
  { n: 1, slug: 'retry-backoff', impl: '', review: '1 fix, tests green' },
]))")
assert_eq "roadmap-to-workflow: all items shipped.
#3 config-loader — read TOML config; review: no findings
#1 retry-backoff — (no summary); review: 1 fix, tests green" "$out" "report body"

# The whole driver, run against stubbed agent()/parallel()/log(): the only way
# to hold every return in the main loop to runReport. The body is wrapped in an
# async function (it has top-level `return`s), meta stripped. Item #2 depends on
# #1, so the run is W1: #1, #3 · W2: #2. BREAK names the stage + item to break.
# The optional second argument is JS run after `args` is built, to override it
# (e.g. `args.items = []`); a case may set `noAgent = true` to make any agent()
# call throw, so a return that should precede every agent cannot hide one.
run_driver() { # <BREAK> [<args override JS>] → prints the driver's return value
  {
    printf 'const BREAK = %s\n' "$1"
    cat <<'JS'
const args = { slug: 'retry-work', aiDir: '/p/.task', pluginRoot: '/plugin', specPaths: [], done: [], scope: 'all',
  items: [{ n: 1, title: 'Retry backoff', size: 'S', deps: [] },
          { n: 2, title: 'Retry metrics', size: 'M', deps: [1] },
          { n: 3, title: 'Config loader', size: 'L', deps: [] }] }
let noAgent = false
const SLUG = { 1: 'retry-backoff', 2: 'retry-metrics', 3: 'config-loader' }
const log = () => {}
const parallel = (thunks) => Promise.all(thunks.map((t) => t()))
const agent = async (prompt, opts) => {
  if (noAgent) throw new Error('agent() called: ' + opts.label)
  const n = Number(prompt.match(/#(\d+)/)[1])
  const stage = opts.label.split(' ')[1]
  const head = `OK #${n} ${SLUG[n]}`
  if (BREAK === `${stage}${n}`) return `FAIL #${n} ${SLUG[n]} tests red`
  if (BREAK === `nomark${n}` && stage === 'review') return `${head} done`
  if (BREAK === `markfail${n}` && stage === 'review')
    return `MARK-FAIL #${n}\nFAIL #${n} ${SLUG[n]} roadmap item #${n}: no unique '### ${n}.' heading with a status line`
  if (BREAK === `nouniq${n}` && stage === 'review') return `FAIL #${n} ${SLUG[n]} no unique index on users.email`
  if (BREAK === `emptyimpl${n}` && stage === 'implement') return ''
  if (BREAK === `driftimpl${n}` && stage === 'implement') return 'Built it.'
  if (BREAK === `drift${n}` && stage === 'plan') return 'Plan written.'
  if (BREAK === `emptyplan${n}` && stage === 'plan') return ''
  if (BREAK === `emptyreview${n}` && stage === 'review') return ''
  if (BREAK === `driftreview${n}` && stage === 'review') return `MARK-OK #${n}\nLooks good.`
  if (BREAK === `dup${n}` && stage === 'plan') return `OK #${n} ${SLUG[1]} planned`
  if (BREAK === `prompt${n}` && stage === 'plan') console.log(prompt)
  if (BREAK === `implprompt${n}` && stage === 'implement') console.log(prompt)
  if (BREAK === `opts${n}`) console.log([opts.label, opts.model, opts.effort, opts.agentType].map((v) => v || '').join('|'))
  return { plan: `${head} planned`, implement: `${head} built`, review: `MARK-OK #${n}\n${head} ok, ticked` }[stage]
}
JS
    printf '%s\n' "${2:-}"
    printf 'console.log(await (async () => {\n'
    sed '/^export const meta = {/,/^}/d' "$DRIVER"
    printf '})())\n'
  } >"$dir/run.mjs"
  node "$dir/run.mjs" 2>&1
}

t_case "an empty items list is bad args, before any agent runs"
# With the empty-run return gone from the driver, these two checks are the only
# guard: relaxing one would let a run that did nothing report "all items shipped".
assert_eq "roadmap-to-workflow: bad args — items must be a non-empty array of {n, title, size, deps} objects — was it passed as a JSON string instead of a real array?" \
  "$(run_driver "''" "args.items = []; noAgent = true")" "items: []"

t_case "a size outside S|M|L is bad args, before any agent runs"
assert_eq "roadmap-to-workflow: bad args — item #1 size must be S|M|L, got \"haiku\"" \
  "$(run_driver "''" "args.items[0].size = 'haiku'; noAgent = true")" "size: haiku"

t_case "an empty scope array is bad args, before any agent runs"
assert_eq "roadmap-to-workflow: bad args — scope must be 'all', 'next-wave', or a non-empty array of item numbers" \
  "$(run_driver "''" "args.scope = []; noAgent = true")" "scope: []"

t_case "a full run returns the headline plus every item in landing order"
assert_eq "roadmap-to-workflow: all items shipped.
#1 retry-backoff — built; review: ok, ticked
#3 config-loader — built; review: ok, ticked
#2 retry-metrics — built; review: ok, ticked" "$(run_driver "''")" "success report"

t_case "a review FAIL still lists the items that landed before it"
assert_eq "roadmap-to-workflow stopped in wave 2 (review), item #2: FAIL #2 retry-metrics tests red
#1 retry-backoff — built; review: ok, ticked
#3 config-loader — built; review: ok, ticked" "$(run_driver "'review2'")" "review stop"

t_case "a passing review without MARK-OK stops, and the report keeps what landed"
out=$(run_driver "'nomark3'")
assert_contains "$out" "roadmap-to-workflow stopped in wave 1 (review), item #3: the review passed but never reported MARK-OK #3" "flip stop headline"
assert_contains "$out" "
#1 retry-backoff — built; review: ok, ticked" "landed item kept"

t_case "a flip that found no heading stops with the tick-by-hand remedy"
out=$(run_driver "'markfail3'")
assert_contains "$out" "roadmap-to-workflow stopped in wave 1 (review), item #3: FAIL #3 config-loader roadmap item #3: no unique '### 3.' heading with a status line — tick #3 in /p/.task/roadmap/retry-work.md by hand, then rerun /task:roadmap-to-workflow retry-work" "MARK-FAIL headline"
assert_contains "$out" "
#1 retry-backoff — built; review: ok, ticked" "landed item kept"

t_case "a review FAIL that merely says no unique gets no tick-by-hand remedy"
# The remedy is keyed on the flip's own MARK-FAIL line, not on the digest's words.
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #3: FAIL #3 config-loader no unique index on users.email
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'nouniq3'")" "review stop, no remedy"

t_case "an implement FAIL stops with what landed before it"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: FAIL #3 config-loader tests red
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'implement3'")" "implement stop"

t_case "an empty implement return stops"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: implement agent returned nothing
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'emptyimpl3'")" "empty implement"

t_case "a drifted implement digest stops"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: unparsable implement digest: Built it.
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'driftimpl3'")" "drifted implement"

t_case "an empty review return stops"
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #3: review agent returned nothing
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'emptyreview3'")" "empty review"

t_case "a drifted review digest stops, even after a MARK-OK line"
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #3: unparsable review digest: Looks good.
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'driftreview3'")" "drifted review"

t_case "an empty plan return stops the wave before any of it is implemented"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #3: plan agent returned nothing" \
  "$(run_driver "'emptyplan3'")" "empty plan"

t_case "a plan FAIL before anything landed is the headline alone"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 retry-backoff tests red" \
  "$(run_driver "'plan1'")" "plan stop"

t_case "a drifted plan digest stops the wave before any of it is implemented"
# The shape check once ran lazily inside the serial loop, so #1 landed before
# the driver reached #3's unparsable digest.
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #3: unparsable plan digest: Plan written." \
  "$(run_driver "'drift3'")" "headline only, nothing landed"

t_case "two items of one wave planned on the same slug stop before either is implemented"
# Parallel planners cannot see each other's file, so both can land on one slug:
# one task file for two items, and the second implement would rebuild the first.
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #3: #1 and #3 both planned retry-backoff — one task file for two items; give one of them a more distinct title, then rerun /task:roadmap-to-workflow retry-work" \
  "$(run_driver "'dup3'")" "headline only, nothing landed"

t_case "the plan prompt names aiDir as the .task directory, not a root above it"
# "pipeline root" meant the directory holding .task/ in .task/CLAUDE.md and the
# .task directory itself here; reading one by the other built .task/.task paths.
out=$(run_driver "'prompt1'")
assert_contains "$out" "- .task directory (AI_DIR): /p/.task" "AI_DIR labelled as the .task directory"
# The ground rules (non-interactive, no implement or commit) live in
# plan-driver.md § Driver mode; the prompt only points there.
assert_contains "$out" "/plugin/skills/_lib/plan-driver.md and follow it" "prompt still names plan-driver.md"
assert_contains "$out" "Last non-empty line MUST be exactly:" "digest contract kept"

t_case "the implement prompt names aiDir/CLAUDE.md, not a cwd-relative .task/CLAUDE.md"
# A linked worktree shares the main root's .task/ through git config task.root, so
# a cwd-relative .task/CLAUDE.md does not exist there and both the Executing a
# task section and Commit Format would silently go unread.
out=$(run_driver "'implprompt1'")
assert_contains "$out" "sends you to /p/.task/CLAUDE.md → ## Executing a task" "Executing a task by absolute path"
assert_contains "$out" "/p/.task/CLAUDE.md → Commit Format" "Commit Format by absolute path"

t_case "plan and implement take model and effort from the size table, review takes neither"
# Item #1 is S, #2 M, #3 L. An omitted effort would inherit the session's, so
# implement must always carry one; the reviewer pins its own in frontmatter.
# Whole lines, compared exactly: the opts lines are the only ones with a `|`.
opts() { run_driver "'opts$1'" | grep '|'; }
assert_eq "1/3 plan|opus|medium|
2/3 implement|sonnet|medium|
3/3 review|||task:code-reviewer" "$(opts 1)" "S stages"
assert_eq "1/3 plan|opus|high|
2/3 implement|sonnet|medium|
3/3 review|||task:code-reviewer" "$(opts 2)" "M stages"
assert_eq "1/3 plan|opus|high|
2/3 implement|opus|medium|
3/3 review|||task:code-reviewer" "$(opts 3)" "L stages"

t_case "a later wave's slug that matches a landed item's stops too"
assert_contains "$(run_driver "'dup2'")" \
  "roadmap-to-workflow stopped in wave 2 (planning), item #2: #1 and #2 both planned retry-backoff" "clash with a landed item"

t_summary
