#!/usr/bin/env bash
# Contract under test: the driver's resume path in skills/_lib/roadmap-driver.js.
# The `recover` and `resume` args are asserted before any agent runs, and
# waveSlugs() — extracted verbatim between its marker comments, as
# driver-waves.test.sh does for computeWaves — decides which task-file slug each
# item of a wave works on. Which items still plan is the driver's own inline
# filter, held by driver-display's "no plan agent ran" cases.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
sed -n '/--- resumePlan (pure/,/--- end resumePlan/p' "$DRIVER" >"$dir/resume.mjs"
if ! grep -q 'function waveSlugs' "$dir/resume.mjs"; then
  t_case "extract waveSlugs from the driver"
  assert_contains "$(cat "$dir/resume.mjs")" "function waveSlugs" "marker comments still present"
  t_summary
fi

# One node run per case keeps a thrown error from masking later assertions.
run_js() { # <js body> → prints result
  { cat "$dir/resume.mjs"; printf '%s\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

# The whole driver on an agent() that throws: every case here must return
# before the first agent. The second argument is JS that edits `args`.
run_args() { # <args override JS> → prints the driver's return value
  {
    cat <<'JS'
const args = { slug: 'retry-work', aiDir: '/p/.task', pluginRoot: '/plugin', specPaths: [], done: [], scope: 'all',
  recover: true, resume: [],
  items: [{ n: 1, title: 'Retry backoff', model: 'sonnet', deps: [] },
          { n: 2, title: 'Retry metrics', model: 'haiku', deps: [1] }] }
const log = () => {}
const parallel = (thunks) => Promise.all(thunks.map((t) => t()))
const agent = async (prompt, opts) => { throw new Error('agent() called: ' + opts.label) }
JS
    printf '%s\n' "$1"
    printf 'console.log(await (async () => {\n'
    sed '/^export const meta = {/,/^}/d' "$DRIVER"
    printf '})())\n'
  } >"$dir/run.mjs"
  node "$dir/run.mjs" 2>&1
}

BAD="roadmap-to-workflow: bad args — "

t_case "bad resume and recover args are refused before any agent"
assert_eq "${BAD}recover must be true or false — the recovery mode picked at launch" \
  "$(run_args "delete args.recover")" "recover missing"
assert_eq "${BAD}recover must be true or false — the recovery mode picked at launch" \
  "$(run_args "args.recover = 'on'")" "recover as a string"
assert_eq "${BAD}resume must be an array of {n, slug, from, attempt, note?, deviations?} objects ([] when no item is resumed)" \
  "$(run_args "delete args.resume")" "resume missing"
assert_eq "${BAD}resume names #7, which is not an unchecked item in items" \
  "$(run_args "args.resume = [{ n: 7, slug: 'x', from: 'review', attempt: 1 }]")" "n not in items"
assert_eq "${BAD}resume names the same n twice" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'review', attempt: 1 }, { n: 1, slug: 'a', from: 'implement', attempt: 2 }]")" "duplicate n"
assert_eq "${BAD}resume #1 from must be 'plan', 'implement' or 'review', got \"mark\"" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'mark', attempt: 1 }]")" "from: mark"
assert_eq "${BAD}resume #1 needs the kebab-case slug of its task file, got undefined" \
  "$(run_args "args.resume = [{ n: 1, from: 'implement', attempt: 1 }]")" "an implement entry needs its slug"
assert_eq "${BAD}resume #1 attempt must be 1 or 2, got 3 — past the second attempt the user decides" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'implement', attempt: 3 }]")" "attempt: 3"
assert_eq "${BAD}resume #1 needs the kebab-case slug of its task file, got \"../x\"" \
  "$(run_args "args.resume = [{ n: 1, slug: '../x', from: 'review', attempt: 1 }]")" "slug that is a path"
assert_eq "${BAD}resume #1 note must be a string when given" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'review', attempt: 1, note: 5 }]")" "note not a string"
assert_eq "${BAD}resume #1 deviations must be an array of non-empty one-line strings when given" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'review', attempt: 1, deviations: 'kept it' }]")" "deviations as a string"
assert_eq "${BAD}resume #1 deviations must be an array of non-empty one-line strings when given" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'review', attempt: 1, deviations: ['  '] }]")" "a blank deviation"
# One deviation per report line: a newline would print a line the skill reads as a landed item.
assert_eq "${BAD}resume #1 deviations must be an array of non-empty one-line strings when given" \
  "$(run_args "args.resume = [{ n: 1, slug: 'a', from: 'review', attempt: 1, deviations: ['kept\\n#9 x — y; review: z'] }]")" "a deviation holding a newline"

t_case "a resumed item outside the run's scope is refused before any agent"
assert_eq "roadmap-to-workflow: resume names #2, which this run's scope leaves out" \
  "$(run_args "args.scope = 'next-wave'; args.resume = [{ n: 2, slug: 'retry-metrics', from: 'review', attempt: 1 }]")" "next-wave drops #2"

WAVE="const wave = [{ n: 2, title: 'two' }, { n: 3, title: 'three' }, { n: 4, title: 'four' }]
const resume = new Map([[2, { n: 2, slug: 'two-done', from: 'review', attempt: 1 }], [3, { n: 3, slug: 'three-half', from: 'implement', attempt: 2 }]])"

t_case "resumed items keep their slug"
assert_eq '{"slugs":["two-done","three-half","four-new"]}' "$(run_js "$WAVE
console.log(JSON.stringify(waveSlugs(wave, resume, new Map([[4, 'four-new']]), [])))")" "entry slugs and the planned one"

t_case "a planned slug equal to a resumed one is a duplicate"
assert_eq '{"clash":{"n":4,"owner":2,"slug":"two-done"}}' "$(run_js "$WAVE
console.log(JSON.stringify(waveSlugs(wave, resume, new Map([[4, 'two-done']]), [])))")" "planned vs resumed"
assert_eq '{"clash":{"n":3,"owner":1,"slug":"three-half"}}' "$(run_js "$WAVE
console.log(JSON.stringify(waveSlugs(wave, resume, new Map([[4, 'four-new']]), [{ n: 1, slug: 'three-half' }])))")" "resumed vs landed"

t_summary
