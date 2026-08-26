---
name: roadmap-to-workflow
description: 'Fan an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — parallel planning, serialized implementation, dependency-ordered waves.'
disable-model-invocation: true
user-invocable: true
---

Drive an approved roadmap through a dynamic Workflow. This skill collects the roadmap's unchecked items, sorts them into dependency-ordered **waves**, then authors and invokes a **dynamic Workflow** (the Workflow tool) that, within each wave, plans all items in parallel and then implements and reviews them one item at a time in the shared working tree, ticking off the roadmap as items land. It does **not** hand-roll that fan-out itself. If the Workflow tool isn't available, it falls back to running items serially by hand, in the same dependency order (Step 2).

**Per-item model control.** Each roadmap item may carry a `**Model:**` hint (`haiku | sonnet | opus`); the Workflow passes it to that item's implement agent as `opts.model`. The review agent ignores it — `task:code-reviewer` pins its own model, so a `haiku` item never gets a `haiku` review.

**Per-item execution is a three-agent split by default — opus plans, the item's model implements and commits, `task:code-reviewer` reviews and amends (Step 2).**

**This skill *is* the opt-in** for the Workflow tool — reading it and following the Steps is the authorization; there is no magic keyword and no separate confirmation.

**Input:** `$ARGUMENTS` — optional. A single positional `<roadmap-slug>` (or path) to skip the roadmap picker. No flags — item scope is chosen interactively (Step 0).

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for item grammar (`### - [ ] N.`, `**Dependencies:**`, `**Model:**`); [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) for the artifact each item's plan agent writes.

## Step 0: Setup gate, pick roadmap, pick scope

`roadmap-to-workflow` is **not** an intake skill — it never runs setup itself (a roadmap can't exist without `.task/CLAUDE.md`, so an absent one means something upstream is broken).

```bash
echo "$CLAUDE_PLUGIN_ROOT"                                 # note this absolute path — bake it as PLUGIN_ROOT in the Step 2 script
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
echo "$AI_DIR"                                             # note this one too — bake it as AI_DIR in the Step 2 script
[[ -f "$AI_DIR/CLAUDE.md" ]] || echo "CLAUDE.md not found"
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all
```

- **`CLAUDE.md not found`** (the guard above echoes it; `validate.sh all` also exits 2 with the same message) → hard-stop redirect (do **not** bootstrap here):
  > The project isn't set up yet. Capture something first with `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec` — those four set the project up inline.
  > → Next: `/task:to-roadmap`
- **Any other non-zero exit from `validate.sh`** → `validate.sh all` checks every artifact, so an error may sit on a task or roadmap unrelated to this run. **Mind the timing:** at this point the roadmap has not been picked yet (that happens in the *Roadmap* sub-step below), so do not try to judge here which errors are "yours". Surface every reported error now, block on none of them, and **hold** the roadmap ones. Once `<slug>` is resolved below, check the held list: if an error was reported against **that** file, stop then — "→ Next: fix the reported error in `.task/roadmap/<slug>.md`, then rerun `/task:roadmap-to-workflow <slug>`". Errors on any other artifact never block. (The one case where the roadmap *is* already known at gate time is a positional `<roadmap-slug>` in `$ARGUMENTS`; there you may apply the check immediately.) WARN lines never set a non-zero exit; they are informational only.

### Roadmap

If `$ARGUMENTS` gives a positional `<roadmap-slug>`/path, resolve it with `resolve_artifact_path roadmap "<arg>"` and skip the picker — **but check the result before using it.** An empty return means no such roadmap (a typo is the common case); do **not** fall through to the item scan with an unresolved path, because an empty filename makes the Step 1 `awk` read stdin, come back with zero items, and report the roadmap as fully done. Stop instead, and list what is actually there (the picker query below already produces the list):

> no roadmap `<arg>` under `$AI_DIR/roadmap/`. Available: `<slug>` (2/7), `<slug>` (0/4).
> → Next: `/task:roadmap-to-workflow <one of those slugs>`

Otherwise list the available roadmaps with progress (uses the `roadmap.sh` helpers):

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # re-source: each bash block is a fresh shell, AI_DIR does not carry over from Step 0
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap.sh"      # resolve_artifact_path, roadmap_progress_counts
shopt -s nullglob
for f in "$AI_DIR"/roadmap/*.md; do
  counts=$(roadmap_progress_counts "$f")
  total=$(awk -F': ' '/^total/{print $2}'     <<<"$counts")
  done_n=$(awk -F': ' '/^done/{print $2}'      <<<"$counts")
  printf '%s\t%s/%s\t%s\n' "$(basename "$f" .md)" "$done_n" "$total" "$f"
done
```

- **No roadmap files** → stop: "no roadmaps found — create one with `/task:to-roadmap`. → Next: `/task:to-roadmap`"
- **Exactly one** → use it (still refuse if it's fully complete, `done == total > 0`).
- **More than one** → `AskUserQuestion` (convention (c)), one chip per roadmap labelled `<slug>  (<done>/<total>)`; sort partial roadmaps first, complete ones last with a `(complete)` suffix, and refuse to proceed on a complete pick.

Every refusal on a complete roadmap ends the same way, in the wording the capture skills also use: "Every item in `<slug>` is already checked off — nothing left to run. → Next: `/task:to-roadmap` for a new initiative, or uncheck the items you want rerun."

Read the roadmap's `Spec:` header lines, if any — each is a Markdown link, `Spec: [<slug>](../spec/<slug>.md)`, so take `<slug>` from the link **text** (a hand-edited roadmap may carry a bare slug; same reading) and resolve it to an **absolute** `$AI_DIR/spec/<slug>.md` path, never by following the relative link target. Echo the list. These paths are baked into the Workflow script's `SPEC_PATHS` literal (Step 2) and interpolated into every item's plan-agent prompt as fixed technical-decision anchors; the JS sandbox cannot expand `$AI_DIR`, so the absolute values must be literals.

### Item scope

No flags — always ask interactively unless there's nothing to ask. When the chosen roadmap has **more than one** unchecked item, present a single `AskUserQuestion` (convention (c)) — *"How much of `<slug>` should this run cover?"*:

- **All remaining** (default) — every unchecked item.
- **Only next wave** — just the first dependency-wave of unchecked items (see Step 1). **This one inverts Step 1's order:** compute the waves over *all* unchecked items first, then narrow the run to wave 1. Filtering before sorting would hide the dependencies that define the wave, and would trip Step 1's out-of-scope hard stop on items you yourself excluded; wave 1 computed over the full set has no unmet dependency by construction, so that stop cannot fire.
- **Pick range** — collect a range via the `AskUserQuestion` free-text ("Other") option, e.g. `1,3-5,8`; validate each number exists and is unchecked. On a bad entry, **name the valid set** rather than just refusing — that is what turns a rejection into a second attempt that works: "#9 isn't a runnable item in `<slug>` (it's already checked / doesn't exist). Unchecked right now: #2, #3, #5, #7. → Next: rerun `/task:roadmap-to-workflow <slug>` and pick from those."

One unchecked item → skip the question, run it. Zero unchecked → stop: "Every item in `<slug>` is already checked off — pick another roadmap, or capture new work with `/task:to-roadmap`. → Done."

## Step 1: Collect items and sort into dependency waves

Read the resolved roadmap. For each unchecked (`### - [ ] N.`) item in the chosen scope, capture `N`, title, `**Dependencies:**`, and `**Model:**` (default `sonnet` when absent or off-list). This prints one `N<TAB>deps<TAB>model<TAB>title` line per unchecked item:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"    # fresh shell again — re-source both helpers
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap.sh"
ROADMAP=$(resolve_artifact_path roadmap "<slug-or-path>")
# Never let an unresolved path reach awk: `awk 'prog' ""` skips the empty
# filename and reads STDIN instead, which comes back as zero items and reads
# exactly like a fully-completed roadmap.
[[ -n "$ROADMAP" && -f "$ROADMAP" ]] || { echo "roadmap not found: <slug-or-path>" >&2; exit 1; }
awk '
  function flush() { if (pend) { print n "\t" deps "\t" (model==""?"sonnet":model) "\t" title; pend=0 } }
  /^### - \[[ x~>-]\] [0-9]+\. / {
    flush()
    if ($0 ~ /^### - \[ \] /) {                     # unchecked item — start capturing
      n=$0;     sub(/^### - \[ \] /,"",n); sub(/\..*/,"",n)
      title=$0; sub(/^### - \[ \] [0-9]+\. /,"",title)
      model=""; deps=""; pend=1
    }
    next
  }
  /^\*\*Dependencies:\*\*/ && pend { deps=$0; sub(/^\*\*Dependencies:\*\* */,"",deps); gsub(/[ \t]/,"",deps); if (deps=="—"||deps=="-"||tolower(deps)=="none"||tolower(deps)=="n/a") deps="" }
  /^\*\*Model:\*\*/       && pend { model=$0; sub(/^\*\*Model:\*\* */,"",model); gsub(/[ \t]/,"",model); if (model!="haiku" && model!="sonnet" && model!="opus") model="" }
  END { flush() }
' "$ROADMAP"
```

Filter that list to the Step 0 scope, then **topologically sort into waves**, computed by you (not by bash — the item set is small and this is reasoning, not parsing). **Exception — the "Only next wave" scope:** sort *before* filtering (sort all unchecked items, then keep wave 1), per Step 0's note on that option.

- Wave 1 = every filtered item whose `Dependencies` are empty, or whose dependencies are all *already checked* (`[x]`/`[~]`/`[>]`/`[-]`) in the roadmap file — i.e. nothing left in this run blocks it.
- Wave 2 = every remaining filtered item whose dependencies are all satisfied by Wave 1 (already-checked items, or items landing in Wave 1).
- Continue until every filtered item is placed. A dependency on an item **outside** the filtered/scoped set that is still unchecked is a hard stop — surface which item depends on which, and ask the user to widen the scope or drop the item: "→ Next: rerun `/task:roadmap-to-workflow <slug>` with a scope that includes #N".
- If a round places **no** new item while items remain unplaced, the scoped items form a dependency **cycle** (e.g. #1 depends on #2 and #2 on #1). Hard stop — report the cycle and ask the user to break it; never guess an order that would run an item before its dependency lands: "→ Next: edit `.task/roadmap/<slug>.md` to break the cycle, then rerun `/task:roadmap-to-workflow <slug>`". (Roadmaps are user-edited and `to-roadmap`'s cyclic-deps check is report-only, so a cycle can reach this skill.)

The result is a `waves: Item[][]` structure — bake it into the Workflow script's literal in Step 2.

## Step 2: Author and invoke the Workflow

Author a dynamic Workflow from the computed waves and invoke it via the **Workflow tool**. Within each wave, **plan agents run in parallel** (`parallel()`) — safe because each writes only its own `.task/task/<item-slug>.md`, never the working tree — and then each item is **implemented and reviewed strictly one at a time**, both inside the same serial loop, so the shared working tree keeps exactly one writer and item N never starts implementing while item N−1 is still under review. A **barrier** separates waves so a later wave never starts before every dependency it needs has landed; each implement therefore sees its already-landed wave-mates' reviewed commits, and the reviewer's Build and Tests run against the integrated state.

### Per-item shape — OPUS PLANS, SONNET IMPLEMENTS, `task:code-reviewer` REVIEWS (the default)

Each item runs as **three agents**, not one. Context passes between them **via the on-disk `.task/task/<item-slug>.md` artifact** — the plan agent writes it, the other two read it fresh from disk — so there is no chat-context transfer to engineer:

```javascript
const slug  = "<roadmap-slug>";
const PLUGIN_ROOT = "<absolute value of $CLAUDE_PLUGIN_ROOT>";   // bake the LITERAL path
// the JS sandbox can't expand env vars, and a relative "skills/…" path is resolved
// against the agent's cwd, not this repo — Read needs the absolute plugin path
// (echo it in Step 0).
const AI_DIR  = "<absolute value of $AI_DIR>";    // bake the LITERAL path (echo it in Step 0)
const ROADMAP = `${AI_DIR}/roadmap/${slug}.md`;   // the file the driver's auto-mark rewrites
const SPEC_PATHS = [];                            // from Step 0 — absolute $AI_DIR/spec/<slug>.md
// paths for the roadmap's own `Spec:` headers, baked as literals ([] when it has none)
const SPEC_SLUGS = SPEC_PATHS.map(p => p.split("/").pop().replace(/\.md$/, ""));
// A `Spec:` header is `Spec: [<slug>](../spec/<slug>.md)` — the slug carries the
// identity, the relative target is what makes it navigable in a viewer. Stamp the
// header from SPEC_SLUGS (never an absolute path — SPEC_PATHS is absolute, and the
// header target must stay `../spec/<slug>.md`); read the spec files from SPEC_PATHS.
const waves = [                                   // from Step 1 — dependency order
  [ { n: 1, title: "…", model: "sonnet" }, { n: 2, title: "…", model: "haiku" } ],
  [ { n: 3, title: "…", model: "opus"   } ],
  // …
];

// PLAN on a strong model — writes .task/task/<item-slug>.md (see prompt below).
// Safe to run in parallel across a wave: a plan agent writes only its own task
// file, never the working tree. Opus is the planner floor (the default shape);
// scale reasoning effort down for lightweight items so a tiny `haiku` item
// doesn't pay a full deep-reasoning pass. Returns the digest line.
async function runPlan(n, title, model, w) {
  const plan = await agent(
    `Read ${PLUGIN_ROOT}/skills/to-plan/SKILL.md and run it NON-INTERACTIVELY for roadmap item
     ${slug}#${n} ("${title}"). Draft ${AI_DIR}/task/<item-slug>.md (Description +
     ## Plan, + ## Tests if .task/CLAUDE.md → Testing Policy calls for it), stamping
     the header with "Roadmap: [${slug}](../roadmap/${slug}.md)" and
     "Source item: #${n}", plus a "Spec: [<spec-slug>](../spec/<spec-slug>.md)"
     line for each spec the item cites (via its
     "### Spec references → [<spec-slug>](../spec/<spec-slug>.md) §N" entries) plus
     every roadmap-level spec — those slugs are: ${SPEC_SLUGS.join(", ") || "(none)"}.
     Cross-artifact headers are Markdown links whose text is the slug and whose
     target is always "../<kind>/<slug>.md" — never an absolute path, and never a
     bare slug. Read the corresponding spec
     files first as fixed technical anchors: ${SPEC_PATHS.join(", ") || "(none)"}. Auto-accept every confirmation; make constructive
     assumptions; never block on a prompt. Do NOT implement or commit.
     Suppress to-plan's "→ Next:" handoff footer (its Step 8 driver-mode
     carve-out) so the digest line below is genuinely last.
     Last non-empty line MUST be exactly:
       OK #${n} <item-slug> planned      (on success)
       FAIL #${n} <item-slug> <what failed>   (on failure)`,
    { model: "opus", effort: model === "haiku" ? "low" : "medium",
      phase: `Wave ${w} · Item #${n}` }
  );
  return plan.trim().split("\n").filter(Boolean).pop();
}

// IMPLEMENT + COMMIT on the item's own model, reading the task file fresh from
// disk (no chat carries over from the plan agent). Run one at a time within a
// wave — this is the sole mutator of the shared working tree, so each implement
// sees its already-landed wave-mates' commits. Review is NOT its job: it does
// not spawn the reviewer itself (despite ## Executing a task step 4), because the
// driver runs the review as its own stage below. Returns the digest.
async function runImplement(n, itemSlug, model, w) {
  const r = await agent(
    `Implement ${AI_DIR}/task/${itemSlug}.md. Follow its ## Execution pointer —
     it sends you to .task/CLAUDE.md → ## Executing a task — with two carve-outs:
     implement the ## Plan (or ## Description if no Plan), then commit per
     .task/CLAUDE.md → Commit Format — and do
     NOT spawn the task:code-reviewer agent, and do NOT tick the roadmap
     checkbox. The driver runs the review as its own stage right after this
     call, and ticks the checkbox after that.
     Make constructive assumptions; never block on a prompt.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (on success)
       FAIL #${n} ${itemSlug} <what failed>         (on failure)`,
    { model, phase: `Wave ${w} · Item #${n}` }
  );
  return r.trim().split("\n").filter(Boolean).pop();
}

// REVIEW + FIX + BUILD/TESTS + AMEND via the plugin's own agent. Runs INSIDE the
// serial per-item loop, right after that item's implement — never as a separate
// pipeline() stage, so the shared tree still has exactly one writer and item N
// cannot start implementing while item N−1 is still being reviewed. No `model`
// opt: task:code-reviewer pins its own model/effort, so a haiku item does not
// get a haiku review. Returns the digest.
async function runReview(n, itemSlug, w) {
  const r = await agent(
    `Review the implementation of ${AI_DIR}/task/${itemSlug}.md, which was just
     implemented and committed in this working tree. Reference string for your
     digest: "#${n} ${itemSlug}". Work your phases in order and print each
     mandatory output. Do NOT tick the roadmap checkbox — the driver does that
     after this call returns OK.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (review passed)
       FAIL #${n} ${itemSlug} <what failed>         (review failed)`,
    { agentType: "task:code-reviewer", phase: `Wave ${w} · Item #${n}` }
  );
  return r.trim().split("\n").filter(Boolean).pop();
}

for (const [w, items] of waves.entries()) {
  // 1) PLAN the whole wave in parallel — plan agents only write .task/, never the
  //    working tree, so there is no collision. A single plan FAIL stops the run
  //    before any implement of this wave starts (plans are cheap to rerun).
  const plans = await parallel(
    items.map(({ n, title, model }) => () => runPlan(n, title, model, w + 1))
  );
  for (const [i, status] of plans.entries()) {
    console.log(status);                                  // per-item plan digest
    if (status.startsWith("FAIL"))
      return `roadmap-to-workflow stopped in wave ${w + 1} (planning), item #${items[i].n}: ${status}`;
  }

  // 2) IMPLEMENT then REVIEW each item STRICTLY ONE AT A TIME — both stages live
  //    in this one serial loop, so the shared tree has a single writer and item N
  //    never starts implementing while item N−1 is still under review.
  for (const [i, { n, model }] of items.entries()) {
    // The digest is LLM output — ASSERT its shape, never index into it blindly.
    // `plans[i].split(" ")[2]` on a drifted line ("OK planned #3", a trailing
    // sentence, a code fence) yields undefined or a stray word, and the next
    // agent is launched against `${AI_DIR}/task/undefined.md` — after this whole
    // wave's planning is already paid for. Fail loudly here instead.
    const m = plans[i].match(/^OK #(\d+) (\S+) planned$/);
    if (!m || Number(m[1]) !== n)
      return `roadmap-to-workflow stopped in wave ${w + 1} (planning), item #${n}: unparsable plan digest: ${plans[i]}`;
    const itemSlug = m[2];
    const status = await runImplement(n, itemSlug, model, w + 1);
    console.log(status);                                  // per-item implement digest
    if (status.startsWith("FAIL"))
      return `roadmap-to-workflow stopped in wave ${w + 1}, item #${n}: ${status}`;

    // The plugin's own review pass: proves each finding, fixes what it confirms
    // within Touches (plus regressions this diff introduced outside them), runs
    // .task/CLAUDE.md → Build and Tests, and amends the implement agent's commit. A
    // failed review stops the wave exactly as a failed implement does.
    const review = await runReview(n, itemSlug, w + 1);
    console.log(review);                                  // per-item review digest
    if (review.startsWith("FAIL"))
      return `roadmap-to-workflow stopped in wave ${w + 1} (review), item #${n}: ${review}`;

    // AUTO-MARK is the DRIVER's job, done here right after the REVIEW returns
    // OK — never inside the per-item agents, so parallel plan agents never race
    // on the roadmap file. There is NO markRoadmapItemDone() helper — flip item
    // N's checkbox with an anchored, macOS-portable awk rewrite (no GNU-only
    // `sed -i`, no roadmap.sh helper). Match ONLY `^### - \[ \] N\. ` so a `> `
    // blockquote line or a substring number is never touched.
    //
    // COUNT THE MATCH AND CHECK IT. The anchor is deliberately narrow, so a
    // heading that drifted from the exact form (a mid-run hand edit, a
    // renumber, a double space after the checkbox) matches nothing — and a
    // zero-match rewrite copies the file over itself in silence. The item's
    // commit lands, the checkbox never flips, the run still ends "all items
    // shipped", and the NEXT run re-plans and re-implements work already in the
    // tree. Exactly one match is the only acceptable result:
    //
    //   awk -v n="${n}" '
    //     $0 ~ ("^### - \\[ \\] " n "\\. ") { sub(/\[ \]/, "[x]"); hits++ } { print }
    //     END { exit (hits == 1 ? 0 : 1) }
    //   ' "${ROADMAP}" > "${ROADMAP}.tmp" && mv "${ROADMAP}.tmp" "${ROADMAP}"
    //
    // On a non-zero exit do NOT move the temp file into place; stop the wave
    // with `FAIL #${n} ${itemSlug} auto-mark matched no unique '### - [ ] ${n}.'
    // heading in ${ROADMAP}` — a silent miss is worse than a stopped run,
    // because the commit is already in the tree.
    //
    // ROADMAP is the baked absolute literal from the top of this script — there
    // is no shell variable to inherit here, and a relative `.task/…` would
    // resolve against the agent's cwd. This is the single driver-side write for N.
  }
  // Barrier: do not start wave w+2 until every item in wave w+1 above is marked.
}
return "roadmap-to-workflow: all items shipped.";
```

**Graceful fallback:** if the Workflow tool isn't available in this environment, run the items one at a time by hand, respecting the same wave order: for each item, run `to-plan` for that roadmap item (writes `.task/task/<item-slug>.md`) and take the exact written path from `to-plan`'s own Step 8 output digest — do **not** reconstruct `<item-slug>` from the item title, since `to-plan` may disambiguate the slug on a collision (its Step 2a.5). Then in a plain session say `implement <that path>`: its `## Execution` pointer sends that session to `.task/CLAUDE.md` → `## Executing a task`, which already carries the plan → commit → `task:code-reviewer` sequence, so the review happens there rather than as a driver stage. Tell that session **not to tick the roadmap checkbox itself** (despite `## Executing a task` step 5); then — as the driver — manually tick that item's checkbox in `.task/roadmap/<slug>.md` once the review came back OK, before moving to the next. This keeps the auto-mark the driver's job, exactly as in the Workflow path.

## Output

- Per item: the returned digest lines (`OK|FAIL #N <item-slug> <summary>`) — one from the implement stage, one from the review stage — printed as each wave lands.
- **One run-summary line above the footer, in both outcomes.** After an unattended autopilot the operator should not have to count `OK` lines by hand to learn how much landed:

  ```
  Ran `<slug>`: <K> of <M> items landed and ticked, <R> still unchecked. Commits: <first-sha>..<last-sha>.
  ```

- End with the canonical next-step footer (convention (a), flag-free):
  - All items shipped → `→ Done. Roadmap complete — \`.task/roadmap/<slug>.md\` fully checked; review the landed commits with \`git log\`.`
  - Stopped on a `FAIL` → surface the failing digest, then name **where** it stopped and **what state the tree is in** — without those the operator has to scroll back through waves of digests to find out what broke and whether anything is uncommitted: `Stopped at #<N> <item-slug> in wave <W>. Its work is left in the working tree — inspect it with \`git status\` and \`git log --oneline -3\`. → Next: fix #<N> (or re-plan it with \`/task:to-plan <slug>#<N>\`), then rerun \`/task:roadmap-to-workflow <slug>\` — already-ticked items stay ticked, only the unchecked remainder reruns.`

## Forbidden

- Running setup / bootstrap on a missing `.task/CLAUDE.md` — this skill hard-stops and redirects; only `to-task` / `to-plan` / `to-roadmap` / `to-spec` are intake-capable.
- Looping the items yourself in this session's main thread instead of authoring a Workflow — the Workflow tool is what gives each item fresh per-item context, per-item model control, parallel planning, and driver-side auto-mark; a hand-rolled loop reintroduces the accumulation problems this skill exists to remove. (The one-at-a-time manual fallback is only for when the Workflow tool is unavailable.)
- Running items whose dependencies are still unchecked, or placing an item in an earlier wave than its `Dependencies` allow.
- Auto-marking roadmap checkboxes from inside a per-item agent — that is the driver's job, strictly after the item's **review** returns `OK`, to avoid parallel writers racing on the roadmap file.
- Running the review as a `pipeline()` stage, or otherwise outside the per-item serial loop — the shared working tree tolerates exactly one writer, and the reviewer amends a commit while the next item would be implementing on top of it.
- Instructing an implement agent to run `/verify` or `/code-review` — both platform commands are `disable-model-invocation`, so a subagent silently skips them and still reports `OK`; verification and review live inside `task:code-reviewer`.
- Passing `model` (or `isolation`) to the review stage — `task:code-reviewer` pins its own model/effort, and worktree isolation would hide the very tree it must review and amend.
- Modifying project code yourself, or touching any file other than the roadmap (for scope reading) and, via the driver step, the roadmap's checkboxes — all implementation happens inside the per-item implement agents, run one at a time in the shared working tree, and all review fixes inside the review agent.
