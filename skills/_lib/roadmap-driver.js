export const meta = {
  name: 'roadmap-driver',
  description: "Run a roadmap's unchecked items in dependency-ordered waves: parallel planning, strictly serial implement → review per item (the review ticks the checkbox), stop on FAIL",
  whenToUse: "Do not call this directly. Only the task-pipeline plugin's /task:roadmap-to-workflow skill invokes it, building {slug, aiDir, pluginRoot, specPaths, items, done, scope, recover, resume} from a validated roadmap file and a scope the user confirmed — hand-assembled args skip that and can commit work against a stale item list. To run a roadmap, invoke that skill instead.",
}

// The task-pipeline roadmap driver. The roadmap-to-workflow skill reports what
// the roadmap SAYS — the unchecked items with their dependencies, the numbers
// already marked, and the user's chosen scope — and this script derives the
// dependency waves itself (computeWaves below). Invoked as
// Workflow({name: 'task:roadmap-driver', args}): the plugin manifest declares
// this file under "workflows", so the platform registers it and reads it
// itself. A scriptPath into the plugin cannot work — the tool checks it for
// read permission against the session's cwd, and a plugin never sits inside
// it. The script never changes between runs, so resumeFromRunId replays
// completed stages from cache — a failing stage included, so it resumes only
// an interrupted run, never one that returned a stop. A returned stop is
// continued through the `resume` arg instead: the stopped item enters the
// pipeline at implement or review, on its existing task file. Contract:
// docs/contract.md § roadmap-to-workflow execution shape (driver contract).
//
// The Workflow sandbox has no filesystem access — every write (the task files,
// the code, the roadmap checkbox) happens inside an agent() stage. Auto-mark is
// the review stage's last phase (task:code-reviewer phase 7), handed the item
// number and roadmap path by runReview: the review already runs inside the
// serial per-item loop, so the flip has one writer without a stage of its own —
// a dedicated mark agent cost a whole agent spawn for one awk call.

// ---- args (real JSON values, absolute paths — asserted, not trusted) ----
const bad = (msg) => `roadmap-to-workflow: bad args — ${msg}`
if (!args || typeof args !== 'object' || Array.isArray(args)) return bad(`args must be an object, got ${Array.isArray(args) ? 'array' : typeof args}`)
const { slug, aiDir, pluginRoot, specPaths, items, done, scope, recover, resume } = args
if (typeof slug !== 'string' || !slug) return bad('slug must be a non-empty string')
if (typeof aiDir !== 'string' || !aiDir.startsWith('/')) return bad('aiDir must be an absolute path')
if (typeof pluginRoot !== 'string' || !pluginRoot.startsWith('/')) return bad('pluginRoot must be an absolute path')
if (!Array.isArray(specPaths) || specPaths.some((p) => typeof p !== 'string' || !p.startsWith('/')))
  return bad('specPaths must be an array of absolute paths ([] when the roadmap has no Spec: headers)')
if (!Array.isArray(items) || items.length === 0)
  return bad('items must be a non-empty array of {n, title, model, deps} objects — was it passed as a JSON string instead of a real array?')
const MODELS = ['haiku', 'sonnet', 'opus']
const isItemNo = (v) => Number.isInteger(v) && v >= 1
for (const it of items) {
  if (!it || typeof it !== 'object' || Array.isArray(it)) return bad('every entry of items must be an {n, title, model, deps} object')
  if (!isItemNo(it.n)) return bad('every item needs an integer n >= 1')
  if (typeof it.title !== 'string' || !it.title) return bad(`item #${it.n} needs a non-empty title`)
  if (!MODELS.includes(it.model)) return bad(`item #${it.n} model must be haiku|sonnet|opus, got ${JSON.stringify(it.model)}`)
  if (!Array.isArray(it.deps) || it.deps.some((d) => !isItemNo(d))) return bad(`item #${it.n} deps must be an array of item numbers ([] for none)`)
}
if (items.length !== new Set(items.map((it) => it.n)).size) return bad('items contains the same n twice')
if (!Array.isArray(done) || done.some((n) => !isItemNo(n)))
  return bad('done must be an array of already-marked item numbers ([] when none are)')
if (!(scope === 'all' || scope === 'next-wave' || (Array.isArray(scope) && scope.length > 0 && scope.every(isItemNo))))
  return bad("scope must be 'all', 'next-wave', or a non-empty array of item numbers")
// recover is not branched on here: it travels back in the STATE line, so the
// invoking session recovers the user's mode after a context compaction.
if (typeof recover !== 'boolean') return bad('recover must be true or false — the recovery mode picked at launch')
if (!Array.isArray(resume))
  return bad('resume must be an array of {n, slug, from, attempt, note?} objects ([] when no item is resumed)')
const itemNos = new Set(items.map((it) => it.n))
for (const r of resume) {
  if (!r || typeof r !== 'object' || Array.isArray(r)) return bad('every entry of resume must be an {n, slug, from, attempt, note?} object')
  if (!itemNos.has(r.n)) return bad(`resume names #${r.n}, which is not an unchecked item in items`)
  if (typeof r.slug !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.slug))
    return bad(`resume #${r.n} needs the kebab-case slug of its task file, got ${JSON.stringify(r.slug)}`)
  if (r.from !== 'implement' && r.from !== 'review')
    return bad(`resume #${r.n} from must be 'implement' or 'review', got ${JSON.stringify(r.from)}`)
  if (r.attempt !== 1 && r.attempt !== 2)
    return bad(`resume #${r.n} attempt must be 1 or 2, got ${JSON.stringify(r.attempt)} — past the second attempt the user decides`)
  if (r.note !== undefined && typeof r.note !== 'string') return bad(`resume #${r.n} note must be a string when given`)
}
if (resume.length !== new Set(resume.map((r) => r.n)).size) return bad('resume names the same n twice')

// --- computeWaves (pure; extracted verbatim by tests/driver-waves.test.sh) ---
// items are the roadmap's UNCHECKED items, done the numbers already marked, and
// scope the user's pick. Returns { waves } — an array of arrays of items — or
// { error } with a message meant for the operator.
//
// 'next-wave' is why the sort cannot be done on a pre-filtered set: waves are
// computed over every unchecked item and only then narrowed to the first one.
// Filtering first would hide the dependencies that define wave 1 and trip the
// out-of-scope check on items the user never excluded by hand.
function computeWaves(items, done, scope) {
  const byN = new Map(items.map((it) => [it.n, it]))
  const doneSet = new Set(done)
  let scoped = items
  if (Array.isArray(scope)) {
    const want = new Set(scope)
    const unknown = [...want].filter((n) => !byN.has(n))
    if (unknown.length)
      return { error: `not runnable in this roadmap (already marked, or no such item): #${unknown.join(', #')}` }
    scoped = items.filter((it) => want.has(it.n))
  }
  const scopedSet = new Set(scoped.map((it) => it.n))
  for (const it of scoped)
    for (const d of it.deps)
      if (!doneSet.has(d) && !scopedSet.has(d))
        return { error: `out of scope: #${it.n} depends on #${d}, which is neither marked nor in this run` }

  const placed = new Set(doneSet)
  const remaining = new Map(scoped.map((it) => [it.n, it]))
  const waves = []
  while (remaining.size) {
    const wave = [...remaining.values()].filter((it) => it.deps.every((d) => placed.has(d)))
    if (wave.length === 0)
      return { error: `dependency cycle among #${[...remaining.keys()].join(', #')} — no item is runnable` }
    for (const it of wave) remaining.delete(it.n)
    for (const it of wave) placed.add(it.n)
    waves.push(wave)
  }
  return { waves: scope === 'next-wave' ? waves.slice(0, 1) : waves }
}
// --- end computeWaves -------------------------------------------------------

// --- resumePlan (pure; extracted verbatim by tests/driver-resume.test.sh) ----
// A resumed item keeps its place in its wave but skips the plan stage: its
// task file exists, and its slug comes from the resume entry. wavePlan names
// the wave's items that still need a plan agent; waveSlugs assigns every item
// of the wave its slug — the entry's, or the one its plan digest named
// (`planned`, a Map n → slug) — and returns { slugs }, or { clash } when two
// items would share one task file. The guard spans resumed and planned items
// alike, and the items already landed in earlier waves.
function wavePlan(wave, resume) {
  const resumed = new Set(resume.map((r) => r.n))
  return wave.filter((it) => !resumed.has(it.n))
}
function waveSlugs(wave, resume, planned, landed) {
  const slugs = []
  for (const [i, { n }] of wave.entries()) {
    const r = resume.find((e) => e.n === n)
    const s = r ? r.slug : planned.get(n)
    const owner = landed.find((l) => l.slug === s) || wave.find((_, j) => j < i && slugs[j] === s)
    if (owner) return { clash: { n, owner: owner.n, slug: s } }
    slugs.push(s)
  }
  return { slugs }
}
// --- end resumePlan ---------------------------------------------------------

// --- digestPassed (pure; extracted verbatim by tests/driver-digest.test.sh) --
// The implement and review stages end on `OK|FAIL #N <item-slug> <summary>`.
// Only an exact `OK #N <item-slug>` head counts as a pass. Anything else — a
// FAIL, an empty line, or a drifted one (`**FAIL** #3 …`, a closing code fence,
// `Review: FAIL`) — is a stop: a bare startsWith('FAIL') test would read those
// drifted lines as passes and let the next item build on one whose review failed.
function digestPassed(line, n, itemSlug) {
  const head = `OK #${n} ${itemSlug}`
  return line === head || (line || '').startsWith(`${head} `)
}
// --- end digestPassed -------------------------------------------------------

// --- itemPhase (pure; extracted verbatim by tests/driver-display.test.sh) ----
// The progress-group title every stage of one item shares, so an item's three
// agents land in one box named after what it IS, not just its number. The
// Phases pane is narrow, so the title is cut — by code point, never mid-way
// through a surrogate pair — with a trailing ellipsis. `#N` keeps two items
// with the same cut title in separate groups.
function itemPhase(w, n, title) {
  const MAX = 32
  const chars = Array.from(title.replace(/\s+/g, ' ').trim())
  const short = chars.length > MAX ? `${chars.slice(0, MAX - 1).join('').trimEnd()}…` : chars.join('')
  return `W${w} · #${n} ${short}`
}
// --- end itemPhase ----------------------------------------------------------

// --- runReport (pure; extracted verbatim by tests/driver-display.test.sh) ----
// What the invoking skill gets back once any agent has run: the parser-stable
// headline first and unchanged, then the state block, then one line per item
// that landed (reviewed AND ticked), in landing order — on a stop too, so the
// skill can say what made it in before the failure without re-deriving it from
// git. The state block is what the skill's recovery reads after a compaction:
// `STATE recover=<on|off> attempts=<#N:k,…|none>` always, and on a stop
// `STOPPED #N <item-slug|-> stage=<plan|implement|review|mark>`. Every
// deviation a resumed implement declared follows its item's line, indented.
function digestSummary(line, n, itemSlug) {
  return (line || '').slice(`OK #${n} ${itemSlug}`.length).trim()
}
function runReport(headline, landed, state) {
  const attempts = [...state.resume].sort((a, b) => a.n - b.n).map((r) => `#${r.n}:${r.attempt}`).join(',')
  const { stopped } = state
  return [
    headline,
    `STATE recover=${state.recover ? 'on' : 'off'} attempts=${attempts || 'none'}`,
    ...(stopped ? [`STOPPED #${stopped.n} ${stopped.slug || '-'} stage=${stopped.stage}`] : []),
    ...landed.flatMap(({ n, slug, impl, review, deviations }) => [
      `#${n} ${slug} — ${impl || '(no summary)'}; review: ${review || '(no summary)'}`,
      ...deviations.map((d) => `  deviation: ${d}`),
    ]),
  ].join('\n')
}
// --- end runReport ----------------------------------------------------------

// --- flipReported (pure; extracted verbatim by tests/driver-digest.test.sh) -
// The review's OK digest is not proof the checkbox was ticked: the reviewer's
// phase 7 prints the flip command's own stdout line, so the driver asks for it.
// Only a whole line `MARK-OK #N` counts — `MARK-OK #13` is not item 1's, and a
// passing digest without it means phase 7 never ran, which would leave the item
// unchecked and have the next run re-implement work already committed.
function flipReported(text, n) {
  return (text || '').split('\n').some((l) => l.trim() === `MARK-OK #${n}`)
}
// The flip's failure line is the only proof the FAIL came from the checkbox: the
// reviewer's FAIL summary is free text, so a defect reported as "no unique index"
// must not be routed to the fix-the-heading remedy. Whole line `MARK-FAIL #N` only.
function flipFailed(text, n) {
  return (text || '').split('\n').some((l) => l.trim() === `MARK-FAIL #${n}`)
}
// --- end flipReported -------------------------------------------------------

// --- deviationsReported (pure; extracted verbatim by tests/driver-digest.test.sh)
// A resumed implement may depart from its plan, and from a cited spec where no
// invariant breaks, and declares each departure as a whole line
// `DEVIATION #N <what departed and why>`. Returns those texts, in order. Whole
// lines only — `DEVIATION #13` is not item 1's, and a mention mid-sentence or a
// bolded `**DEVIATION**` is no declaration the review could be asked to judge.
function deviationsReported(text, n) {
  const head = `DEVIATION #${n} `
  return (text || '').split('\n').map((l) => l.trim())
    .filter((l) => l.startsWith(head) && l.slice(head.length).trim())
    .map((l) => l.slice(head.length).trim())
}
// --- end deviationsReported -------------------------------------------------

const sorted = computeWaves(items, done, scope)
if (sorted.error) return `roadmap-to-workflow: ${sorted.error}`
const waves = sorted.waves
// A resumed item the scope leaves out would never run, yet the STATE line would
// still count its attempt.
const inRun = new Set(waves.flat().map((it) => it.n))
const unscoped = resume.filter((r) => !inRun.has(r.n)).map((r) => r.n)
if (unscoped.length) return `roadmap-to-workflow: resume names #${unscoped.join(', #')}, which this run's scope leaves out`
const RESUME = new Map(resume.map((r) => [r.n, r]))

const ROADMAP = `${aiDir}/roadmap/${slug}.md`
const SPEC_SLUGS = specPaths.map((p) => p.split('/').pop().replace(/\.md$/, ''))
const lastLine = (s) => (s || '').trim().split('\n').filter(Boolean).pop() || ''

// PLAN — writes only its own .task/task/<item-slug>.md, never the working tree,
// so a whole wave plans in parallel. Reads skills/_lib/plan-driver.md instead of
// the full to-task skill. Planner tier: opus by default, sonnet for an item the
// roadmap hints as `haiku` (with effort scaled down) — the review stage never
// scales down, see runReview.
async function runPlan(n, title, model, phase) {
  const r = await agent(
    `Read ${pluginRoot}/skills/_lib/plan-driver.md and follow it. Your item:
     - roadmap file: ${ROADMAP}
     - roadmap slug: ${slug}
     - item: #${n} — ${title}
     - .task directory (AI_DIR): ${aiDir}
     - plugin root: ${pluginRoot}
     - roadmap-level spec files (read each as a fixed technical anchor, and stamp
       a Spec: header per slug): ${specPaths.join(', ') || '(none)'}
       — their slugs: ${SPEC_SLUGS.join(', ') || '(none)'}
     Last non-empty line MUST be exactly:
       OK #${n} <item-slug> planned            (on success)
       FAIL #${n} <item-slug> <what failed>    (on failure)`,
    {
      model: model === 'haiku' ? 'sonnet' : 'opus',
      effort: model === 'haiku' ? 'low' : 'medium',
      label: '1/3 plan',
      phase,
    }
  )
  return lastLine(r)
}

// IMPLEMENT + COMMIT on the item's own model, reading the task file fresh from
// disk (no chat carries over from the plan agent). Runs one at a time within a
// wave — the sole mutator of the shared working tree, so each implement sees its
// already-landed wave-mates' reviewed commits. A resumed item gets the
// continuation prompt: the earlier attempt's work is built on, never redone,
// and every departure from the plan or a spec is declared as a DEVIATION line.
async function runImplement(n, itemSlug, model, phase, resumed) {
  const lead = resumed
    ? `Item #${n}: continue implementing ${aiDir}/task/${itemSlug}.md — recovery attempt
     ${resumed.attempt} of 2. An earlier attempt may already have done part or all of this work:
     the commits on this branch and the working tree hold it. Read git log, git status and
     git diff first, build on that work, and do not redo or revert it.${resumed.note ? `
     Why the earlier attempt stopped, and what it left: ${resumed.note}` : ''}
     The task file's acceptance criteria and its ## Tests stand as written: never weaken,
     skip or delete one to reach OK. You may depart from its ## Plan, and from a spec it
     cites as long as the departure breaks none of the invariants that spec states, when
     that is what meeting them takes. Print each departure as its own whole line, before
     the last line:
       DEVIATION #${n} <what departed from which plan step or spec section, and why>
     Never edit the task file, the roadmap or a spec.
     Follow the task file's ## Execution pointer —`
    : `Implement ${aiDir}/task/${itemSlug}.md. Follow its ## Execution pointer —`
  const r = await agent(
    `${lead}
     it sends you to ${aiDir}/CLAUDE.md → ## Executing a task — with two carve-outs:
     implement the ## Plan plus any ## Tests it carries, then commit per
     ${aiDir}/CLAUDE.md → Commit Format — and do NOT
     spawn the task:code-reviewer agent, and do NOT tick the roadmap
     checkbox. The driver runs the review as its own stage right after this
     call, and the review ticks the checkbox when it passes.
     Make constructive assumptions; never block on a prompt.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (on success)
       FAIL #${n} ${itemSlug} <what failed>         (on failure)`,
    { model, label: '2/3 implement', phase }
  )
  return { line: lastLine(r), deviations: resumed ? deviationsReported(r, n) : [] }
}

// REVIEW + FIX + BUILD/TESTS + COMMIT + MARK via the plugin's own agent. Runs
// inside the serial per-item loop, right after that item's implement. The item
// to tick is passed explicitly, so the flip never depends on the plan agent
// having stamped Roadmap:/Source item: headers; OK means the checkbox is ticked
// (the reviewer's phase 7 turns a failed flip into a FAIL digest). No `model` opt:
// task:code-reviewer pins its own model/effort, so a haiku item never gets a
// haiku review. No `isolation`: it must see and commit into this very working tree.
// A resumed review carries the earlier attempt's note; a review after a resumed
// implement lists the deviations it declared, for the reviewer to judge.
async function runReview(n, itemSlug, phase, resumed, deviations) {
  const context = [
    resumed && resumed.from === 'review' && resumed.note
      ? `This review resumes a stopped run. What the earlier attempt left: ${resumed.note}` : '',
    deviations.length
      ? `The implementation declared these deviations — judge each one as your phases say for declared deviations:
${deviations.map((d) => `       DEVIATION #${n} ${d}`).join('\n')}` : '',
  ].filter(Boolean).map((c) => `\n     ${c}`).join('')
  const r = await agent(
    `Review the implementation of ${aiDir}/task/${itemSlug}.md, which was just
     implemented and committed in this working tree. Reference string for your
     digest: "#${n} ${itemSlug}". Roadmap item to tick when your verdict is
     OK: #${n} in ${ROADMAP}. Work your phases in order and print each
     mandatory output.${context}
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (review passed)
       FAIL #${n} ${itemSlug} <what failed>         (review failed)`,
    { agentType: 'task:code-reviewer', label: '3/3 review', phase }
  )
  return { line: lastLine(r), flipped: flipReported(r, n), flipFailed: flipFailed(r, n) }
}

// The run's shape, up front: which items, in which waves, waiting on what —
// one line per wave, so a long roadmap is not clipped to one terminal width. A
// dependency already marked before this run is not worth naming.
const doneSet = new Set(done)
const itemLine = (it) => {
  const open = it.deps.filter((d) => !doneSet.has(d))
  return `#${it.n} ${it.title.replace(/\s+/g, ' ').trim()}${open.length ? ` (after #${open.join(', #')})` : ''}`
}
const total = waves.reduce((k, wave) => k + wave.length, 0)
log(`${slug}: ${total} item(s) in ${waves.length} wave(s)${scope === 'next-wave' ? ' (next wave only)' : ''}`)
for (const [i, wave] of waves.entries()) log(`  W${i + 1}: ${wave.map(itemLine).join(', ')}`)

// Items reviewed AND ticked, in landing order — the body of runReport.
const landed = []
// Every return after the first agent: the headline, the state block, the landed items.
const stop = (n, itemSlug, stage, headline) =>
  runReport(headline, landed, { recover, resume, stopped: { n, slug: itemSlug, stage } })

for (const [wIdx, items] of waves.entries()) {
  const w = wIdx + 1
  const phases = items.map(({ n, title }) => itemPhase(w, n, title))
  const toPlan = wavePlan(items, resume)
  const resumedHere = items.filter((it) => RESUME.has(it.n))
  log(`Wave ${w}/${waves.length} — ${[
    toPlan.length ? `planning #${toPlan.map((it) => it.n).join(', #')}${toPlan.length > 1 ? ' in parallel' : ''}` : '',
    resumedHere.length ? `resuming ${resumedHere.map((it) => `#${it.n} at ${RESUME.get(it.n).from}`).join(', ')}` : '',
  ].filter(Boolean).join('; ')}`)

  // 1) PLAN the wave's unresumed items in parallel. A single plan FAIL — or a
  //    digest of the wrong shape — stops the run before any implement of this
  //    wave starts (plans are cheap to rerun).
  const plans = await parallel(toPlan.map((it) => () => runPlan(it.n, it.title, it.model, phases[items.indexOf(it)])))
  // Every digest is logged before any is judged, so a stop on one item still
  // shows how its wave-mates' plans came out.
  for (const [i, status] of plans.entries())
    log(`[W${w} plan] ${status || `FAIL #${toPlan[i].n} plan agent returned nothing`}`)
  const planned = new Map()
  for (const [i, status] of plans.entries()) {
    const n = toPlan[i].n
    if (!status || status.startsWith('FAIL'))
      return stop(n, null, 'plan', `roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: ${status || 'plan agent returned nothing'}`)
    // The digest is LLM output — assert its shape, never index into it blindly.
    const m = status.match(/^OK #(\d+) (\S+) planned$/)
    if (!m || Number(m[1]) !== n)
      return stop(n, null, 'plan', `roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: unparsable plan digest: ${status}`)
    planned.set(n, m[2])
  }
  // Each planner derives its slug alone, and parallel ones cannot see each
  // other's file. Two items on one slug share one task file: implementing
  // both would build one plan twice and tick the other item unbuilt.
  const assigned = waveSlugs(items, resume, planned, landed)
  if (assigned.clash) {
    const { n, owner, slug: s } = assigned.clash
    return stop(n, s, 'plan', `roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: #${owner} and #${n} both planned ${s} — one task file for two items; give one of them a more distinct title, then rerun /task:roadmap-to-workflow ${slug}`)
  }
  const itemSlugs = assigned.slugs

  // 2) IMPLEMENT → REVIEW strictly one item at a time — both inside this one
  //    serial loop, so the shared tree and the roadmap file each keep exactly
  //    one writer, and item N never starts implementing while item N−1 is
  //    still under review. An item resumed at review skips implement: its work
  //    is committed already.
  for (const [i, { n, model }] of items.entries()) {
    const itemSlug = itemSlugs[i]
    const resumed = RESUME.get(n)

    let impl = 'resumed at review'
    let deviations = []
    if (!resumed || resumed.from === 'implement') {
      const { line: status, deviations: declared } = await runImplement(n, itemSlug, model, phases[i], resumed)
      log(`[W${w} implement] ${status || `FAIL #${n} ${itemSlug} implement agent returned nothing`}`)
      if (!digestPassed(status, n, itemSlug))
        return stop(n, itemSlug, 'implement', `roadmap-to-workflow stopped in wave ${w}, item #${n}: ${
          !status ? 'implement agent returned nothing' : status.startsWith('FAIL') ? status : `unparsable implement digest: ${status}`}`)
      impl = digestSummary(status, n, itemSlug)
      deviations = declared
      for (const d of deviations) log(`[W${w} implement] DEVIATION #${n} ${d}`)
    } else log(`[W${w} implement] #${n} ${itemSlug} resumed at review — implement skipped`)

    const { line: review, flipped, flipFailed: markFailed } = await runReview(n, itemSlug, phases[i], resumed, deviations)
    log(`[W${w} review] ${review || `FAIL #${n} ${itemSlug} review agent returned nothing`}`)
    if (!digestPassed(review, n, itemSlug))
      return stop(n, itemSlug, markFailed ? 'mark' : 'review', `roadmap-to-workflow stopped in wave ${w} (review), item #${n}: ${
        !review ? 'review agent returned nothing' : review.startsWith('FAIL') ? review : `unparsable review digest: ${review}`}${
        markFailed ? ` — its work is committed but the checkbox could not be flipped: fix ${ROADMAP} so #${n} has one heading with a status line, then rerun /task:roadmap-to-workflow ${slug} and resume #${n} at review` : ''}`)
    if (!flipped)
      return stop(n, itemSlug, 'mark', `roadmap-to-workflow stopped in wave ${w} (review), item #${n}: the review passed but never reported MARK-OK #${n}, so its checkbox may not be flipped. The item's work is in the tree: if #${n} is still unchecked in ${ROADMAP}, rerun /task:roadmap-to-workflow ${slug} and resume #${n} at review`)

    landed.push({ n, slug: itemSlug, impl, review: digestSummary(review, n, itemSlug), deviations })
  }
  // Barrier: the next wave starts only after every item above is reviewed and ticked.
}

return runReport('roadmap-to-workflow: all items shipped.', landed, { recover, resume, stopped: null })
