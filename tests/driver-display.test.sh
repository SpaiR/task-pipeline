#!/usr/bin/env bash
# Contract under test: the driver's two display helpers in
# skills/_lib/roadmap-driver.js — itemPhase(), the progress-group title all three
# stages of one item share, and runReport() + digestSummary(), the value the
# invoking skill gets back once any agent has run. runReport's first line is the
# parser-stable headline and must come through untouched; the STATE / STOPPED
# block follows it, then the landed items with their declared deviations. Extracted verbatim
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

t_case "runReport with nothing landed is the headline and the state block"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b
STATE recover=off attempts=none
STOPPED #1 - stage=plan" \
  "$(run_js "console.log(runReport('roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b', [],
    { recover: false, resume: [], stopped: { n: 1, slug: null, stage: 'plan', deviations: [] } }))")" "headline + state"

t_case "runReport lists landed items under the state block, in landing order, deviations indented"
out=$(run_js "console.log(runReport('roadmap-to-workflow: all items shipped.', [
  { n: 3, slug: 'config-loader', impl: 'read TOML config', review: 'no findings', deviations: [] },
  { n: 1, slug: 'retry-backoff', impl: '', review: '1 fix, tests green', deviations: ['step 2 kept the old cache', 'spec §3 timeout 5s, not 3s'] },
], { recover: true, resume: [{ n: 4, attempt: 1 }, { n: 1, attempt: 2 }], stopped: null }))")
assert_eq "roadmap-to-workflow: all items shipped.
STATE recover=on attempts=#1:2,#4:1
#3 config-loader — read TOML config; review: no findings
#1 retry-backoff — (no summary); review: 1 fix, tests green
  deviation: step 2 kept the old cache
  deviation: spec §3 timeout 5s, not 3s" "$out" "report body"

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
  recover: false, resume: [],
  items: [{ n: 1, title: 'Retry backoff', model: 'sonnet', deps: [] },
          { n: 2, title: 'Retry metrics', model: 'haiku', deps: [1] },
          { n: 3, title: 'Config loader', model: 'opus', deps: [] }] }
let noAgent = false
const SLUG = { 1: 'retry-backoff', 2: 'retry-metrics', 3: 'config-loader' }
const log = () => {}
const parallel = (thunks) => Promise.all(thunks.map((t) => t()))
let agent = async (prompt, opts) => {
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
  if (BREAK === `dup${n}` && stage === 'plan') return `OK #${n} ${SLUG[1]} planned`
  if (BREAK === `prompt${n}` && stage === 'plan') console.log(prompt)
  if (BREAK === `implprompt${n}` && stage === 'implement') console.log(prompt)
  if (BREAK === `reviewprompt${n}` && stage === 'review') console.log(prompt)
  if (BREAK === `deviate${n}` && stage === 'implement')
    return `DEVIATION #${n} kept the old cache\nnote: DEVIATION #${n} inline is no declaration\n${head} built`
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
assert_eq "roadmap-to-workflow: bad args — items must be a non-empty array of {n, title, model, deps} objects — was it passed as a JSON string instead of a real array?" \
  "$(run_driver "''" "args.items = []; noAgent = true")" "items: []"

t_case "an empty scope array is bad args, before any agent runs"
assert_eq "roadmap-to-workflow: bad args — scope must be 'all', 'next-wave', or a non-empty array of item numbers" \
  "$(run_driver "''" "args.scope = []; noAgent = true")" "scope: []"

t_case "a full run returns the headline, the state block and every item in landing order"
assert_eq "roadmap-to-workflow: all items shipped.
STATE recover=off attempts=none
#1 retry-backoff — built; review: ok, ticked
#3 config-loader — built; review: ok, ticked
#2 retry-metrics — built; review: ok, ticked" "$(run_driver "''")" "success report"

t_case "a review FAIL still lists the items that landed before it"
assert_eq "roadmap-to-workflow stopped in wave 2 (review), item #2: FAIL #2 retry-metrics tests red
STATE recover=off attempts=none
STOPPED #2 retry-metrics stage=review
#1 retry-backoff — built; review: ok, ticked
#3 config-loader — built; review: ok, ticked" "$(run_driver "'review2'")" "review stop"

t_case "a passing review without MARK-OK stops, and the report keeps what landed"
out=$(run_driver "'nomark3'")
assert_contains "$out" "roadmap-to-workflow stopped in wave 1 (review), item #3: the review passed but never reported MARK-OK #3" "flip stop headline"
assert_contains "$out" "
STOPPED #3 config-loader stage=mark" "a missing flip is a mark stop"
assert_contains "$out" "
#1 retry-backoff — built; review: ok, ticked" "landed item kept"

t_case "a flip that found no heading stops with the fix-the-heading remedy"
out=$(run_driver "'markfail3'")
assert_contains "$out" "roadmap-to-workflow stopped in wave 1 (review), item #3: FAIL #3 config-loader roadmap item #3: no unique '### 3.' heading with a status line — its work is committed but the checkbox could not be flipped: fix /p/.task/roadmap/retry-work.md so #3 has one heading with a status line, then rerun /task:roadmap-to-workflow retry-work and resume #3 at review" "MARK-FAIL headline"
assert_contains "$out" "
STOPPED #3 config-loader stage=mark" "a failed flip is a mark stop"
assert_contains "$out" "
#1 retry-backoff — built; review: ok, ticked" "landed item kept"

t_case "a review FAIL that merely says no unique gets no fix-the-heading remedy"
# The remedy is keyed on the flip's own MARK-FAIL line, not on the digest's words.
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #3: FAIL #3 config-loader no unique index on users.email
STATE recover=off attempts=none
STOPPED #3 config-loader stage=review
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'nouniq3'")" "review stop, no remedy"

t_case "an implement FAIL stops with what landed before it"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: FAIL #3 config-loader tests red
STATE recover=off attempts=none
STOPPED #3 config-loader stage=implement
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'implement3'")" "implement stop"

t_case "an empty implement return stops"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: implement agent returned nothing
STATE recover=off attempts=none
STOPPED #3 config-loader stage=implement
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'emptyimpl3'")" "empty implement"

t_case "a drifted implement digest stops"
assert_eq "roadmap-to-workflow stopped in wave 1, item #3: unparsable implement digest: Built it.
STATE recover=off attempts=none
STOPPED #3 config-loader stage=implement
#1 retry-backoff — built; review: ok, ticked" "$(run_driver "'driftimpl3'")" "drifted implement"

t_case "a plan FAIL before anything landed is the headline alone"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 retry-backoff tests red
STATE recover=off attempts=none
STOPPED #1 - stage=plan" \
  "$(run_driver "'plan1'")" "plan stop"

t_case "a drifted plan digest stops the wave before any of it is implemented"
# The shape check once ran lazily inside the serial loop, so #1 landed before
# the driver reached #3's unparsable digest.
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #3: unparsable plan digest: Plan written.
STATE recover=off attempts=none
STOPPED #3 - stage=plan" \
  "$(run_driver "'drift3'")" "headline and state, nothing landed"

t_case "two items of one wave planned on the same slug stop before either is implemented"
# Parallel planners cannot see each other's file, so both can land on one slug:
# one task file for two items, and the second implement would rebuild the first.
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #3: #1 and #3 both planned retry-backoff — one task file for two items; give one of them a more distinct title, then rerun /task:roadmap-to-workflow retry-work
STATE recover=off attempts=none
STOPPED #3 retry-backoff stage=plan" \
  "$(run_driver "'dup3'")" "headline and state, nothing landed"

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

t_case "a later wave's slug that matches a landed item's stops too"
assert_contains "$(run_driver "'dup2'")" \
  "roadmap-to-workflow stopped in wave 2 (planning), item #2: #1 and #2 both planned retry-backoff" "clash with a landed item"

# Resumed runs. #1 lands first in every case, so the report always has a body.
RESUME3='args.recover = true; args.resume = [{ n: 3, slug: "config-loader", from: "review", attempt: 2, note: "implement committed, digest missing" }]'
RESUME1='args.recover = true; args.resume = [{ n: 1, slug: "retry-backoff", from: "implement", attempt: 1, note: "acceptance 2 missed" }]'

t_case "a stop in review of a resumed item carries STATE and STOPPED under the unchanged headline"
out=$(run_driver "'review3'" "$RESUME3")
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #3: FAIL #3 config-loader tests red" "$(head -1 <<<"$out")" "headline byte-identical"
assert_eq "STATE recover=on attempts=#3:2
STOPPED #3 config-loader stage=review
#1 retry-backoff — built; review: ok, ticked" "$(sed 1d <<<"$out")" "state block, then what landed"

t_case "an item resumed at review is neither planned nor implemented, and its review gets the note"
out=$(run_driver "'reviewprompt3'" "$RESUME3")
assert_contains "$out" "This review resumes a stopped run. What the earlier attempt left: implement committed, digest missing" "note in the review prompt"
assert_contains "$out" "#3 config-loader — resumed at review; review: ok, ticked" "landed without an implement summary"
assert_eq "0" "$(run_driver "'plan3'" "$RESUME3" | grep -c 'stopped')" "no plan agent ran for #3"
assert_eq "0" "$(run_driver "'implement3'" "$RESUME3" | grep -c 'stopped')" "no implement agent ran for #3"

t_case "a resumed implement gets the continuation prompt, without a plan agent"
out=$(run_driver "'implprompt1'" "$RESUME1")
assert_contains "$out" "Item #1: continue implementing /p/.task/task/retry-backoff.md — recovery attempt" "continuation prompt"
assert_contains "$out" "Why the earlier attempt stopped, and what it left: acceptance 2 missed" "note in the implement prompt"
assert_contains "$out" "DEVIATION #1 <what departed" "deviation format asked for"
assert_contains "$out" "sends you to /p/.task/CLAUDE.md → ## Executing a task" "Execution pointer kept"
assert_eq "0" "$(run_driver "'plan1'" "$RESUME1" | grep -c 'stopped')" "no plan agent ran for #1"

t_case "a resumed implement's deviations reach the review prompt and the report"
out=$(run_driver "'deviate1'" "$RESUME1")
assert_contains "$out" "STATE recover=on attempts=#1:1" "state line"
assert_contains "$out" "#1 retry-backoff — built; review: ok, ticked
  deviation: kept the old cache
#3" "one deviation line, the inline mention dropped"
assert_eq "0" "$(grep -c 'STOPPED' <<<"$out")" "a clean run carries STATE but no STOPPED"
out=$(run_driver "'deviate1'" "$RESUME1
const stub = agent
agent = async (p, o) => { if (o.label === '3/3 review' && p.includes('#1 ')) console.log(p); return stub(p, o) }")
assert_contains "$out" "The implementation declared these deviations" "deviations announced"
assert_contains "$out" "       DEVIATION #1 kept the old cache" "deviation listed"

t_case "a review stop after a resumed implement keeps its deviations under STOPPED"
out=$(run_driver "'deviate1'" "$RESUME1
const stub = agent
agent = async (p, o) => o.label === '3/3 review' && p.includes('#1 ') ? 'FAIL #1 retry-backoff tests red' : stub(p, o)")
assert_eq "roadmap-to-workflow stopped in wave 1 (review), item #1: FAIL #1 retry-backoff tests red
STATE recover=on attempts=#1:1
STOPPED #1 retry-backoff stage=review
  deviation: kept the old cache" "$out" "unjudged deviation travels with the stop"

t_case "a review entry's carried deviations reach the review prompt and the report"
CARRY='args.recover = true; args.resume = [{ n: 3, slug: "config-loader", from: "review", attempt: 2, deviations: ["kept the old cache"] }]'
out=$(run_driver "'reviewprompt3'" "$CARRY")
assert_contains "$out" "       DEVIATION #3 kept the old cache" "listed for the reviewer"
assert_contains "$out" "#3 config-loader — resumed at review; review: ok, ticked
  deviation: kept the old cache" "listed under the landed item"

t_case "an implement entry's carried deviations are shown to the implement agent, not collected"
CARRY='args.recover = true; args.resume = [{ n: 1, slug: "retry-backoff", from: "implement", attempt: 2, deviations: ["kept the old cache"] }]'
out=$(run_driver "'implprompt1'" "$CARRY")
assert_contains "$out" "Declare again each one the code
     still makes" "asked to re-declare"
assert_contains "$out" "       DEVIATION #1 kept the old cache" "earlier deviation listed"
assert_eq "0" "$(run_driver "''" "$CARRY" | grep -c 'deviation:')" "only re-declared ones count"

t_case "a fresh implement's DEVIATION lines are not collected"
assert_eq "0" "$(run_driver "'deviate3'" | grep -c 'deviation:')" "only a resumed implement may deviate"

t_summary
