export const meta = {
  name: 'roadmap-driver',
  description: "Run a roadmap's unchecked items in dependency-ordered waves: parallel planning, strictly serial implement → review per item (the review ticks the checkbox), stop on FAIL",
  whenToUse: "Do not call this directly. Only the task-pipeline plugin's /task:roadmap-to-workflow skill invokes it, building {slug, aiDir, pluginRoot, specPaths, items, done, scope} from a validated roadmap file and a scope the user confirmed — hand-assembled args skip that and can commit work against a stale item list. To run a roadmap, invoke that skill instead.",
}

// The task-pipeline roadmap driver, reached as Workflow({name:
// 'task:roadmap-driver', args}) from /task:roadmap-to-workflow. The skill reports
// what the roadmap SAYS — the unchecked items, the numbers already marked, the
// user's scope — and the driver derives the dependency waves itself. The Workflow
// sandbox has no filesystem, so every write (task files, code, the roadmap
// checkbox) happens inside an agent(). The checkbox is ticked by the review's own
// phase 7, not by a stage of its own, which would cost an agent spawn for one awk
// call. Registration, resume and the rest of the contract: docs/contract.md
// § roadmap-to-workflow execution shape (driver contract).

// --- pure (extracted verbatim by tests/driver-*.test.sh) --------------------
// Everything down to `end pure` must stand alone: no Workflow globals — the
// args global, agent(), parallel(), log() — only its own parameters.

// Model and effort per stage, keyed by the item's size (its roadmap `**Size:**`
// hint, M when absent). Review is absent on purpose: task:code-reviewer pins its
// own in frontmatter, see runReview.
// Why this shape: on well-specified changes sonnet at medium matches opus's pass
// rate at a third of the cost, while opus stays ahead where judgment is needed
// (planning, finding defects); effort moves results more than the model does.
// Plan is never below implement — its errors reach two downstream agents.
// Implement stays at medium and xhigh/max are not used anywhere: in implement
// runs, opus at high and above started breaking passing tests. The planner
// writes no code, so high is safe there.
// Switching rule for M/implement, the cell the evidence supports least: if M
// items come back from the reviewer with fix commits of the "missed a file /
// skipped the ## Tests section / did not read the Spec" kind, raise it to
// sonnet/high; if the fixes are "wrong approach / missed a side effect", switch
// it to opus/medium.
const STAGES = {
  S: { plan: { model: 'opus', effort: 'medium' }, implement: { model: 'sonnet', effort: 'medium' } },
  M: { plan: { model: 'opus', effort: 'high' }, implement: { model: 'sonnet', effort: 'medium' } },
  L: { plan: { model: 'opus', effort: 'high' }, implement: { model: 'opus', effort: 'medium' } },
}
const SIZES = Object.keys(STAGES)

// The args are real JSON values with absolute paths — asserted, not trusted.
// Returns null, or what is wrong with them for the `bad args` headline.
function checkArgs(args) {
  if (!args || typeof args !== 'object' || Array.isArray(args))
    return `args must be an object, got ${Array.isArray(args) ? 'array' : typeof args}`
  const { slug, aiDir, pluginRoot, specPaths, items, done, scope } = args
  if (typeof slug !== 'string' || !slug) return 'slug must be a non-empty string'
  if (typeof aiDir !== 'string' || !aiDir.startsWith('/')) return 'aiDir must be an absolute path'
  if (typeof pluginRoot !== 'string' || !pluginRoot.startsWith('/')) return 'pluginRoot must be an absolute path'
  if (!Array.isArray(specPaths) || specPaths.some((p) => typeof p !== 'string' || !p.startsWith('/')))
    return 'specPaths must be an array of absolute paths ([] when the roadmap has no Spec: headers)'
  if (!Array.isArray(items) || items.length === 0)
    return 'items must be a non-empty array of {n, title, size, deps} objects — was it passed as a JSON string instead of a real array?'
  const isItemNo = (v) => Number.isInteger(v) && v >= 1
  for (const it of items) {
    if (!it || typeof it !== 'object' || Array.isArray(it)) return 'every entry of items must be an {n, title, size, deps} object'
    if (!isItemNo(it.n)) return 'every item needs an integer n >= 1'
    if (typeof it.title !== 'string' || !it.title) return `item #${it.n} needs a non-empty title`
    if (!SIZES.includes(it.size)) return `item #${it.n} size must be ${SIZES.join('|')}, got ${JSON.stringify(it.size)}`
    if (!Array.isArray(it.deps) || it.deps.some((d) => !isItemNo(d))) return `item #${it.n} deps must be an array of item numbers ([] for none)`
  }
  if (items.length !== new Set(items.map((it) => it.n)).size) return 'items contains the same n twice'
  if (!Array.isArray(done) || done.some((n) => !isItemNo(n)))
    return 'done must be an array of already-marked item numbers ([] when none are)'
  if (!(scope === 'all' || scope === 'next-wave' || (Array.isArray(scope) && scope.length > 0 && scope.every(isItemNo))))
    return "scope must be 'all', 'next-wave', or a non-empty array of item numbers"
  return null
}

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

// A title as one display line: whitespace runs collapsed, ends trimmed.
function oneLine(title) {
  return title.replace(/\s+/g, ' ').trim()
}

// The progress-group title every stage of one item shares, so an item's three
// agents land in one box named after what it IS, not just its number. The
// Phases pane is narrow, so the title is cut — by code point, never mid-way
// through a surrogate pair — with a trailing ellipsis. `#N` keeps two items
// with the same cut title in separate groups.
function itemPhase(w, n, title) {
  const MAX = 32
  const chars = Array.from(oneLine(title))
  const short = chars.length > MAX ? `${chars.slice(0, MAX - 1).join('').trimEnd()}…` : chars.join('')
  return `W${w} · #${n} ${short}`
}

// The plan stage ends on `OK #N <item-slug> planned`, and that slug becomes the
// next two agents' file path. Returns the slug, or null for anything else — a
// FAIL, an empty line, another item's number, or a drifted shape.
function parsePlanDigest(line, n) {
  const m = (line || '').match(/^OK #(\d+) (\S+) planned$/)
  return m && Number(m[1]) === n ? m[2] : null
}

// The head an implement or review digest must open with to count as a pass.
function okHead(n, itemSlug) {
  return `OK #${n} ${itemSlug}`
}

// The implement and review stages end on `OK|FAIL #N <item-slug> <summary>`.
// Only an exact `OK #N <item-slug>` head counts as a pass. Anything else — a
// FAIL, an empty line, or a drifted one (`**FAIL** #3 …`, a closing code fence,
// `Review: FAIL`) — is a stop: a bare startsWith('FAIL') test would read those
// drifted lines as passes and let the next item build on one whose review failed.
function digestPassed(line, n, itemSlug) {
  const head = okHead(n, itemSlug)
  return line === head || (line || '').startsWith(`${head} `)
}

// Why a digest that did not pass stops the run, for the headline: the FAIL line
// itself when the agent reported one, else what was wrong with it.
function whyNot(stage, line) {
  if (!line) return `${stage} agent returned nothing`
  return line.startsWith('FAIL') ? line : `unparsable ${stage} digest: ${line}`
}

// The review's OK digest is not proof the checkbox was ticked: the reviewer's
// phase 7 prints the flip command's own stdout line, so the driver asks for it.
// Only a whole line counts — `MARK-OK #13` is not item 1's, and a passing digest
// without `MARK-OK #N` means phase 7 never ran, which would leave the item
// unchecked and have the next run re-implement work already committed.
// `MARK-FAIL #N` is the only proof a FAIL came from the checkbox: the reviewer's
// FAIL summary is free text, so a defect reported as "no unique index" must not
// be routed to the tick-by-hand remedy.
function hasOwnLine(text, line) {
  return (text || '').split('\n').some((l) => l.trim() === line)
}
function flipReported(text, n) {
  return hasOwnLine(text, `MARK-OK #${n}`)
}
function flipFailed(text, n) {
  return hasOwnLine(text, `MARK-FAIL #${n}`)
}

// What the invoking skill gets back once any agent has run: the parser-stable
// headline first and unchanged, then one line per item that landed (reviewed
// AND ticked), in landing order — on a stop too, so the skill can say what made
// it in before the failure without re-deriving it from git.
function digestSummary(line, n, itemSlug) {
  return (line || '').slice(okHead(n, itemSlug).length).trim()
}
function runReport(headline, landed) {
  return [
    headline,
    ...landed.map(({ n, slug, impl, review }) =>
      `#${n} ${slug} — ${impl || '(no summary)'}; review: ${review || '(no summary)'}`),
  ].join('\n')
}
// --- end pure ---------------------------------------------------------------

const argError = checkArgs(args)
if (argError) return `roadmap-to-workflow: bad args — ${argError}`
const { slug, aiDir, pluginRoot, specPaths, items, done, scope } = args

const { error, waves } = computeWaves(items, done, scope)
if (error) return `roadmap-to-workflow: ${error}`

const ROADMAP = `${aiDir}/roadmap/${slug}.md`
const SPEC_SLUGS = specPaths.map((p) => p.split('/').pop().replace(/\.md$/, ''))
const RERUN = `then rerun /task:roadmap-to-workflow ${slug}`
const lastLine = (s) => (s || '').trim().split('\n').filter(Boolean).pop() || ''

// PLAN — writes only its own .task/task/<item-slug>.md, never the working tree,
// so a whole wave plans in parallel. Reads skills/_lib/plan-driver.md instead of
// the full to-task skill. Model and effort come from STAGES by size.
async function runPlan(n, title, size, phase) {
  const report = await agent(
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
    { ...STAGES[size].plan, label: '1/3 plan', phase }
  )
  return lastLine(report)
}

// IMPLEMENT + COMMIT on the size's model and an explicit effort — never the
// session's, which an omitted effort would inherit. Reads the task file fresh from
// disk (no chat carries over from the plan agent). Runs one at a time within a
// wave — the sole mutator of the shared working tree, so each implement sees its
// already-landed wave-mates' reviewed commits.
async function runImplement(n, itemSlug, size, phase) {
  const report = await agent(
    `Implement ${aiDir}/task/${itemSlug}.md. Follow its ## Execution pointer —
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
    { ...STAGES[size].implement, label: '2/3 implement', phase }
  )
  return lastLine(report)
}

// REVIEW + FIX + BUILD/TESTS + COMMIT + MARK via the plugin's own agent. Runs
// inside the serial per-item loop, right after that item's implement. The item
// to tick is passed explicitly, so the flip never depends on the plan agent
// having stamped Roadmap:/Source item: headers; OK means the checkbox is ticked
// (the reviewer's phase 7 turns a failed flip into a FAIL digest). No `model` or
// `effort` opt: task:code-reviewer pins its own, so an item's size never lowers
// its review. No `isolation`: it must see and commit into this very working tree.
async function runReview(n, itemSlug, phase) {
  const report = await agent(
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
  return { digest: lastLine(report), marked: flipReported(report, n), markFailed: flipFailed(report, n) }
}

// Items reviewed AND ticked, in landing order — the body of every report. Only
// the wave loop at the bottom writes it.
const landed = []

// The parser-stable stop headline. tag names the stage the skill routes on:
// ' (planning)', ' (review)', or '' for implement.
const stopped = (w, tag, n, reason) => `roadmap-to-workflow stopped in wave ${w}${tag}, item #${n}: ${reason}`
const logDigest = (w, stage, digest, ref) => log(`[W${w} ${stage}] ${digest || `FAIL ${ref} ${stage} agent returned nothing`}`)

// The run's shape, up front: which items, in which waves, waiting on what —
// one line per wave, so a long roadmap is not clipped to one terminal width. A
// dependency already marked before this run is not worth naming.
function logRunShape() {
  const doneSet = new Set(done)
  const describeItem = (it) => {
    const open = it.deps.filter((d) => !doneSet.has(d))
    return `#${it.n} ${oneLine(it.title)}${open.length ? ` (after #${open.join(', #')})` : ''}`
  }
  const total = waves.reduce((k, wave) => k + wave.length, 0)
  log(`${slug}: ${total} item(s) in ${waves.length} wave(s)${scope === 'next-wave' ? ' (next wave only)' : ''}`)
  for (const [i, wave] of waves.entries()) log(`  W${i + 1}: ${wave.map(describeItem).join(', ')}`)
}

// PLAN the whole wave in parallel. A single plan FAIL — or a digest of the wrong
// shape — stops the run before any implement of this wave starts (plans are
// cheap to rerun). Returns { slugs, phases }, index-aligned with wave, or { stop }.
async function planWave(w, wave) {
  const phases = wave.map(({ n, title }) => itemPhase(w, n, title))
  log(`Wave ${w}/${waves.length} — planning #${wave.map((it) => it.n).join(', #')}${wave.length > 1 ? ' in parallel' : ''}`)
  const digests = await parallel(wave.map(({ n, title, size }, i) => () => runPlan(n, title, size, phases[i])))
  // Every digest is logged before any is judged, so a stop on one item still
  // shows how its wave-mates' plans came out.
  for (const [i, digest] of digests.entries()) logDigest(w, 'plan', digest, `#${wave[i].n}`)
  const slugs = []
  for (const [i, digest] of digests.entries()) {
    const { n } = wave[i]
    // The digest is LLM output — assert its shape, never index into it blindly.
    const itemSlug = parsePlanDigest(digest, n)
    if (!itemSlug) return { stop: stopped(w, ' (planning)', n, whyNot('plan', digest)) }
    // Each planner derives its slug alone, and parallel ones cannot see each
    // other's file. Two items on one slug share one task file: implementing
    // both would build one plan twice and tick the other item unbuilt.
    const owner = landed.find((l) => l.slug === itemSlug) || wave.find((_, j) => slugs[j] === itemSlug)
    if (owner)
      return { stop: stopped(w, ' (planning)', n, `#${owner.n} and #${n} both planned ${itemSlug} — one task file for two items; give one of them a more distinct title, ${RERUN}`) }
    slugs.push(itemSlug)
  }
  return { slugs, phases }
}

// IMPLEMENT → REVIEW for one item. Returns { entry } for landed, or { stop }.
async function shipItem(w, { n, size }, itemSlug, phase) {
  const implDigest = await runImplement(n, itemSlug, size, phase)
  logDigest(w, 'implement', implDigest, `#${n} ${itemSlug}`)
  if (!digestPassed(implDigest, n, itemSlug)) return { stop: stopped(w, '', n, whyNot('implement', implDigest)) }

  const { digest: reviewDigest, marked, markFailed } = await runReview(n, itemSlug, phase)
  logDigest(w, 'review', reviewDigest, `#${n} ${itemSlug}`)
  if (!digestPassed(reviewDigest, n, itemSlug)) {
    const remedy = markFailed ? ` — tick #${n} in ${ROADMAP} by hand, ${RERUN}` : ''
    return { stop: stopped(w, ' (review)', n, whyNot('review', reviewDigest) + remedy) }
  }
  if (!marked)
    return { stop: stopped(w, ' (review)', n, `the review passed but never reported MARK-OK #${n}, so its checkbox may not be flipped. The item's work is in the tree: check ${ROADMAP}, tick #${n} by hand if it is still unchecked, ${RERUN}`) }
  return { entry: { n, slug: itemSlug, impl: digestSummary(implDigest, n, itemSlug), review: digestSummary(reviewDigest, n, itemSlug) } }
}

logRunShape()
for (const [i, wave] of waves.entries()) {
  const w = i + 1
  const planned = await planWave(w, wave)
  if (planned.stop) return runReport(planned.stop, landed)
  // IMPLEMENT → REVIEW strictly one item at a time, so the shared tree and the
  // roadmap file each keep exactly one writer, and item N never starts
  // implementing while item N−1 is still under review.
  for (const [j, item] of wave.entries()) {
    const shipped = await shipItem(w, item, planned.slugs[j], planned.phases[j])
    if (shipped.stop) return runReport(shipped.stop, landed)
    landed.push(shipped.entry)
  }
  // Barrier: the next wave starts only after every item above is reviewed and ticked.
}

return runReport('roadmap-to-workflow: all items shipped.', landed)
