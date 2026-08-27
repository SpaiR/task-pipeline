export const meta = {
  name: 'task-pipeline-roadmap',
  description: "Run a roadmap's unchecked items in dependency-ordered waves: parallel planning, strictly serial implement → review → mark per item, stop on FAIL",
  whenToUse: "Invoked by the task-pipeline plugin's roadmap-to-workflow skill with {slug, aiDir, pluginRoot, specPaths, waves} args — not meant to be run by hand.",
}

// The task-pipeline roadmap driver. The roadmap-to-workflow skill computes the
// dependency waves and invokes this script via Workflow({scriptPath, args}); the
// script itself never changes between runs, so resumeFromRunId replays completed
// stages from cache. Contract: docs/contract.md § roadmap-to-workflow execution
// shape (driver contract).
//
// The Workflow sandbox has no filesystem access — every write (the task files,
// the code, the roadmap checkbox) happens inside an agent() stage. Auto-mark is
// therefore its own serial driver stage (runMark), never part of the per-item
// plan/implement/review agents.

// ---- args (real JSON values, absolute paths — asserted, not trusted) ----
const bad = (msg) => `roadmap-to-workflow: bad args — ${msg}`
if (!args || typeof args !== 'object' || Array.isArray(args)) return bad(`args must be an object, got ${Array.isArray(args) ? 'array' : typeof args}`)
const { slug, aiDir, pluginRoot, specPaths, waves } = args
if (typeof slug !== 'string' || !slug) return bad('slug must be a non-empty string')
if (typeof aiDir !== 'string' || !aiDir.startsWith('/')) return bad('aiDir must be an absolute path')
if (typeof pluginRoot !== 'string' || !pluginRoot.startsWith('/')) return bad('pluginRoot must be an absolute path')
if (!Array.isArray(specPaths) || specPaths.some((p) => typeof p !== 'string' || !p.startsWith('/')))
  return bad('specPaths must be an array of absolute paths ([] when the roadmap has no Spec: headers)')
if (!Array.isArray(waves) || waves.length === 0 || waves.some((w) => !Array.isArray(w) || w.length === 0))
  return bad('waves must be a non-empty array of non-empty item arrays — was it passed as a JSON string instead of a real array?')
const MODELS = ['haiku', 'sonnet', 'opus']
for (const wave of waves) {
  for (const it of wave) {
    if (!it || typeof it !== 'object') return bad('every wave entry must be an {n, title, model} object')
    if (!Number.isInteger(it.n) || it.n < 1) return bad('every item needs an integer n >= 1')
    if (typeof it.title !== 'string' || !it.title) return bad(`item #${it.n} needs a non-empty title`)
    if (!MODELS.includes(it.model)) return bad(`item #${it.n} model must be haiku|sonnet|opus, got ${JSON.stringify(it.model)}`)
  }
}

const ROADMAP = `${aiDir}/roadmap/${slug}.md`
const SPEC_SLUGS = specPaths.map((p) => p.split('/').pop().replace(/\.md$/, ''))
const lastLine = (s) => (s || '').trim().split('\n').filter(Boolean).pop() || ''

// PLAN — writes only its own .task/task/<item-slug>.md, never the working tree,
// so a whole wave plans in parallel. Reads skills/_lib/plan-driver.md instead of
// the full to-plan skill. Planner tier: opus by default, sonnet for an item the
// roadmap hints as `haiku` (with effort scaled down) — the review stage never
// scales down, see runReview.
async function runPlan(n, title, model, w) {
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
      label: `plan #${n}`,
      phase: `Wave ${w} · Item #${n}`,
    }
  )
  return lastLine(r)
}

// IMPLEMENT + COMMIT on the item's own model, reading the task file fresh from
// disk (no chat carries over from the plan agent). Runs one at a time within a
// wave — the sole mutator of the shared working tree, so each implement sees its
// already-landed wave-mates' reviewed commits.
async function runImplement(n, itemSlug, model, w) {
  const r = await agent(
    `Implement ${aiDir}/task/${itemSlug}.md. Follow its ## Execution pointer —
     it sends you to .task/CLAUDE.md → ## Executing a task — with two carve-outs:
     implement the ## Plan (or ## Description if no Plan) plus any ## Tests it
     carries, then commit per .task/CLAUDE.md → Commit Format — and do NOT
     spawn the task:code-reviewer agent, and do NOT tick the roadmap
     checkbox. The driver runs the review as its own stage right after this
     call, and ticks the checkbox after that.
     Make constructive assumptions; never block on a prompt.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (on success)
       FAIL #${n} ${itemSlug} <what failed>         (on failure)`,
    { model, label: `implement #${n}`, phase: `Wave ${w} · Item #${n}` }
  )
  return lastLine(r)
}

// REVIEW + FIX + BUILD/TESTS + AMEND via the plugin's own agent. Runs inside the
// serial per-item loop, right after that item's implement. No `model` opt:
// task:code-reviewer pins its own model/effort, so a haiku item never gets a
// haiku review. No `isolation`: it must see and amend this very working tree.
async function runReview(n, itemSlug, w) {
  const r = await agent(
    `Review the implementation of ${aiDir}/task/${itemSlug}.md, which was just
     implemented and committed in this working tree. Reference string for your
     digest: "#${n} ${itemSlug}". Work your phases in order and print each
     mandatory output. Do NOT tick the roadmap checkbox — the driver does that
     after this call returns OK.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (review passed)
       FAIL #${n} ${itemSlug} <what failed>         (review failed)`,
    { agentType: 'task:code-reviewer', label: `review #${n}`, phase: `Wave ${w} · Item #${n}` }
  )
  return lastLine(r)
}

// MARK — the driver-side checkbox flip, as its own serial stage right after the
// review returns OK (the sandbox cannot write files itself). The command is
// fully baked: the anchored awk matches ONLY `### - [ ] N. ` so a blockquoted
// line or a substring number is never touched, and `hits == 1` gates the mv — a
// zero-match rewrite discards the temp file and FAILs loudly instead of copying
// the file over itself in silence (the item's commit is already in the tree; a
// silent miss would make the next run re-implement landed work).
async function runMark(n, itemSlug, w) {
  const r = await agent(
    `Run EXACTLY this bash command, once, verbatim — do not modify it, do not
     retry with a different command, and do not edit any file yourself:

       awk -v n="${n}" '
         $0 ~ ("^### - \\\\[ \\\\] " n "\\\\. ") { sub(/\\[ \\]/, "[x]"); hits++ } { print }
         END { exit (hits == 1 ? 0 : 1) }
       ' "${ROADMAP}" > "${ROADMAP}.tmp" \\
         && mv "${ROADMAP}.tmp" "${ROADMAP}" \\
         || rm -f "${ROADMAP}.tmp"

     If the command exited 0, your last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} marked
     Otherwise (the checkbox was NOT flipped and the temp file was discarded):
       FAIL #${n} ${itemSlug} auto-mark matched no unique '### - [ ] ${n}.' heading`,
    { model: 'haiku', effort: 'low', label: `mark #${n}`, phase: `Wave ${w} · Item #${n}` }
  )
  return lastLine(r)
}

for (const [wIdx, items] of waves.entries()) {
  const w = wIdx + 1

  // 1) PLAN the whole wave in parallel. A single plan FAIL stops the run before
  //    any implement of this wave starts (plans are cheap to rerun).
  const plans = await parallel(items.map(({ n, title, model }) => () => runPlan(n, title, model, w)))
  for (const [i, status] of plans.entries()) {
    log(status || `FAIL #${items[i].n} plan agent returned nothing`)
    if (!status || status.startsWith('FAIL'))
      return `roadmap-to-workflow stopped in wave ${w} (planning), item #${items[i].n}: ${status || 'plan agent returned nothing'}`
  }

  // 2) IMPLEMENT → REVIEW → MARK strictly one item at a time — all three inside
  //    this one serial loop, so the shared tree keeps exactly one writer and
  //    item N never starts implementing while item N−1 is still under review.
  for (const [i, { n, model }] of items.entries()) {
    // The digest is LLM output — assert its shape, never index into it blindly.
    const m = plans[i].match(/^OK #(\d+) (\S+) planned$/)
    if (!m || Number(m[1]) !== n)
      return `roadmap-to-workflow stopped in wave ${w} (planning), item #${n}: unparsable plan digest: ${plans[i]}`
    const itemSlug = m[2]

    const status = await runImplement(n, itemSlug, model, w)
    log(status || `FAIL #${n} ${itemSlug} implement agent returned nothing`)
    if (!status || status.startsWith('FAIL'))
      return `roadmap-to-workflow stopped in wave ${w}, item #${n}: ${status || 'implement agent returned nothing'}`

    const review = await runReview(n, itemSlug, w)
    log(review || `FAIL #${n} ${itemSlug} review agent returned nothing`)
    if (!review || review.startsWith('FAIL'))
      return `roadmap-to-workflow stopped in wave ${w} (review), item #${n}: ${review || 'review agent returned nothing'}`

    const marked = await runMark(n, itemSlug, w)
    log(marked || `FAIL #${n} ${itemSlug} mark agent returned nothing`)
    const mm = (marked || '').match(/^OK #(\d+) (\S+) marked$/)
    if (!mm || Number(mm[1]) !== n)
      return `roadmap-to-workflow stopped in wave ${w} (mark), item #${n}: ${marked || 'mark agent returned nothing'} — the item's commit is in the tree but its checkbox is not flipped`
  }
  // Barrier: the next wave starts only after every item above is reviewed and marked.
}

return 'roadmap-to-workflow: all items shipped.'
