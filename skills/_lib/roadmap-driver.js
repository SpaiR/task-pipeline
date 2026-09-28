export const meta = {
  name: 'roadmap-driver',
  description: "Run a roadmap's unchecked items in dependency-ordered waves: parallel planning, strictly serial implement → review per item (the review ticks the checkbox), stop on FAIL",
  whenToUse: "Do not call this directly. Only the task-pipeline plugin's /task:roadmap-to-workflow skill invokes it, building {slug, aiDir, pluginRoot, specPaths, items, done, scope} from a validated roadmap file and a scope the user confirmed — hand-assembled args skip that and can commit work against a stale item list. To run a roadmap, invoke that skill instead.",
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
// completed stages from cache. Contract:
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
const { slug, aiDir, pluginRoot, specPaths, items, done, scope } = args
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
// headline first and unchanged, then one line per item that landed (reviewed
// AND ticked), in landing order — on a stop too, so the skill can say what made
// it in before the failure without re-deriving it from git.
function digestSummary(line, n, itemSlug) {
  return (line || '').slice(`OK #${n} ${itemSlug}`.length).trim()
}
function runReport(headline, landed) {
  return [
    headline,
    ...landed.map(({ n, slug, impl, review }) =>
      `#${n} ${slug} — ${impl || '(no summary)'}; review: ${review || '(no summary)'}`),
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
// --- end flipReported -------------------------------------------------------

const sorted = computeWaves(items, done, scope)
if (sorted.error) return `roadmap-to-workflow: ${sorted.error}`
const waves = sorted.waves
if (waves.length === 0) return 'roadmap-to-workflow: nothing to run — every item in scope is already marked.'

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
     - pipeline root: ${aiDir}
     - plugin root: ${pluginRoot}
     - roadmap-level spec files (read each as a fixed technical anchor, and stamp
       a Spec: header per slug): ${specPaths.join(', ') || '(none)'}
       — their slugs: ${SPEC_SLUGS.join(', ') || '(none)'}
     Non-interactive: auto-accept every confirmation, make constructive
     assumptions, never block on a prompt. Do NOT implement or commit.
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
// already-landed wave-mates' reviewed commits.
async function runImplement(n, itemSlug, model, phase) {
  const r = await agent(
    `Implement ${aiDir}/task/${itemSlug}.md. Follow its ## Execution pointer —
     it sends you to .task/CLAUDE.md → ## Executing a task — with two carve-outs:
     implement the ## Plan (or ## Description if no Plan) plus any ## Tests it
     carries, then commit per .task/CLAUDE.md → Commit Format — and do NOT
     spawn the task:code-reviewer agent, and do NOT tick the roadmap
     checkbox. The driver runs the review as its own stage right after this
     call, and the review ticks the checkbox when it passes.
     Make constructive assumptions; never block on a prompt.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (on success)
       FAIL #${n} ${itemSlug} <what failed>         (on failure)`,
    { model, label: '2/3 implement', phase }
  )
  return lastLine(r)
}

// REVIEW + FIX + BUILD/TESTS + COMMIT + MARK via the plugin's own agent. Runs
// inside the serial per-item loop, right after that item's implement. The item
// to tick is passed explicitly, so the flip never depends on the plan agent
// having stamped Roadmap:/Source item: headers; OK means the checkbox is ticked
// (the reviewer's phase 7 turns a failed flip into a FAIL digest). No `model` opt:
// task:code-reviewer pins its own model/effort, so a haiku item never gets a
// haiku review. No `isolation`: it must see and commit into this very working tree.
async function runReview(n, itemSlug, phase) {
  const r = await agent(
    `Review the implementation of ${aiDir}/task/${itemSlug}.md, which was just
     implemented and committed in this working tree. Reference string for your
     digest: "#${n} ${itemSlug}". Roadmap item to tick when your verdict is
     OK: #${n} in ${ROADMAP}. Work your phases in order and print each
     mandatory output.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (review passed)
       FAIL #${n} ${itemSlug} <what failed>         (review failed)`,
    { agentType: 'task:code-reviewer', label: '3/3 review', phase }
  )
  return { line: lastLine(r), flipped: flipReported(r, n) }
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

for (const [wIdx, items] of waves.entries()) {
  const w = wIdx + 1
  const phases = items.map(({ n, title }) => itemPhase(w, n, title))
  log(`Wave ${w}/${waves.length} — planning #${items.map((it) => it.n).join(', #')}${items.length > 1 ? ' in parallel' : ''}`)

  // 1) PLAN the whole wave in parallel. A single plan FAIL — or a digest of the
  //    wrong shape — stops the run before any implement of this wave starts
  //    (plans are cheap to rerun).
  const plans = await parallel(items.map(({ n, title, model }, i) => () => runPlan(n, title, model, phases[i])))
  const itemSlugs = []
  for (const [i, status] of plans.entries()) {
    const n = items[i].n
    log(`[W${w} plan] ${status || `FAIL #${n} plan agent returned nothing`}`)
    if (!status || status.startsWith('FAIL'))
      return runReport(`roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: ${status || 'plan agent returned nothing'}`, landed)
    // The digest is LLM output — assert its shape, never index into it blindly.
    const m = status.match(/^OK #(\d+) (\S+) planned$/)
    if (!m || Number(m[1]) !== n)
      return runReport(`roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: unparsable plan digest: ${status}`, landed)
    itemSlugs.push(m[2])
  }

  // 2) IMPLEMENT → REVIEW strictly one item at a time — both inside this one
  //    serial loop, so the shared tree and the roadmap file each keep exactly
  //    one writer, and item N never starts implementing while item N−1 is
  //    still under review.
  for (const [i, { n, model }] of items.entries()) {
    const itemSlug = itemSlugs[i]

    const status = await runImplement(n, itemSlug, model, phases[i])
    log(`[W${w} implement] ${status || `FAIL #${n} ${itemSlug} implement agent returned nothing`}`)
    if (!digestPassed(status, n, itemSlug))
      return runReport(`roadmap-to-workflow stopped in wave ${w}, item #${n}: ${
        !status ? 'implement agent returned nothing' : status.startsWith('FAIL') ? status : `unparsable implement digest: ${status}`}`, landed)

    const { line: review, flipped } = await runReview(n, itemSlug, phases[i])
    log(`[W${w} review] ${review || `FAIL #${n} ${itemSlug} review agent returned nothing`}`)
    if (!digestPassed(review, n, itemSlug))
      return runReport(`roadmap-to-workflow stopped in wave ${w} (review), item #${n}: ${
        !review ? 'review agent returned nothing' : review.startsWith('FAIL') ? review : `unparsable review digest: ${review}`}${
        (review || '').includes('no unique') ? ` — tick #${n} in ${ROADMAP} by hand, then rerun /task:roadmap-to-workflow ${slug}` : ''}`, landed)
    if (!flipped)
      return runReport(`roadmap-to-workflow stopped in wave ${w} (review), item #${n}: the review passed but never reported MARK-OK #${n}, so its checkbox may not be flipped. The item's work is in the tree: check ${ROADMAP}, tick #${n} by hand if it is still unchecked, then rerun /task:roadmap-to-workflow ${slug}`, landed)

    landed.push({ n, slug: itemSlug, impl: digestSummary(status, n, itemSlug), review: digestSummary(review, n, itemSlug) })
  }
  // Barrier: the next wave starts only after every item above is reviewed and ticked.
}

return runReport('roadmap-to-workflow: all items shipped.', landed)
