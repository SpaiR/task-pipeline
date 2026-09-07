---
name: roadmap-to-workflow
description: 'Fan an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — parallel planning, serialized implementation, dependency-ordered waves.'
argument-hint: '[<roadmap-slug>]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/*.sh* *) Bash(bash *skills/validate/validate.sh* *) Bash(source *skills/_lib/*.sh*)'
---

Drive an approved roadmap through a dynamic Workflow. This skill reports the roadmap's unchecked items and the scope the user picks, then invokes the **plugin-shipped Workflow driver** (`skills/_lib/roadmap-driver.js`, via the Workflow tool's `scriptPath`). The driver sorts the items into dependency-ordered **waves** and, within each wave, plans them in parallel and then implements, reviews and ticks them off one at a time in the shared working tree. It is a static file, inspectable at any time, parameterized only through `args` (Step 2) — never hand-rolled here, never re-authored inline. If the Workflow tool is unavailable, Step 2's fallback runs the items serially by hand.

**Per-item execution is a four-stage split:** opus plans the item (sonnet at low effort when its `**Model:**` hint is `haiku`), the item's own model implements and commits, `task:code-reviewer` reviews and commits its fixes on top, and a cheap driver stage ticks the checkbox. The review stage ignores the hint — it pins its own model, so a `haiku` item never gets a `haiku` review.

**This skill *is* the opt-in** for the Workflow tool: reading it and following the Steps is the authorization. No magic keyword, no separate confirmation.

**Input:** `$ARGUMENTS` — optional. A single positional `<roadmap-slug>` (or path) to skip the roadmap picker. No flags — item scope is chosen interactively (Step 0).

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for item grammar (`### - [ ] N.`, `**Dependencies:**`, `**Model:**`); [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) for the artifact each item's plan agent writes.

## Step 0: Setup gate, pick roadmap, pick scope

`roadmap-to-workflow` is **not** an intake skill — it never runs setup itself (a roadmap can't exist without `.task/CLAUDE.md`, so an absent one means something upstream is broken).

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" workflow`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `PLUGIN_ROOT:` and `AI_DIR:` are Step 2's `pluginRoot` and `aiDir` args — use them verbatim; the JS sandbox cannot expand either.
2. **`CONFIG: absent`** → hard-stop redirect (do **not** bootstrap here):
   > The project isn't set up yet. Capture something first with `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec` — those four set the project up inline.
   > → Next: `/task:to-roadmap`
3. **`VALIDATE:` holds `validate.sh all`'s output** — every artifact, so an error may belong to a task or roadmap unrelated to this run. Surface every `ERROR` line, block on none of them yet, and **hold** the roadmap ones: once `<slug>` is resolved below, an error against **that** file is a stop — "→ Next: fix the reported error in `.task/roadmap/<slug>.md`, then rerun `/task:roadmap-to-workflow <slug>`". `WARN` lines are informational. (`ERROR precondition: CLAUDE.md not found` is case 2, not a validation error.)
4. `ROADMAPS:` is the roadmap list, with progress and the open item numbers — the picker below reads it instead of listing the directory.

If that block arrived as a literal `` !`bash …` `` line instead of output, the preprocessing did not fire: run that one command yourself and continue exactly as above.

### Roadmap

If `$ARGUMENTS` gives a positional `<roadmap-slug>`, match it against the `ROADMAPS:` slugs; a positional **path** (contains `/`) is used as given. No match means no such roadmap (a typo is the common case) — stop, and list what is actually there:

> no roadmap `<arg>` under `$AI_DIR/roadmap/`. Available: `<slug>` (2/7), `<slug>` (0/4).
> → Next: `/task:roadmap-to-workflow <one of those slugs>`

Do **not** fall through to the item scan with an unresolved path: an empty filename makes the Step 1 `awk` read stdin, come back with zero items, and report the roadmap as fully done.

With no positional argument, pick from the `ROADMAPS:` lines:

- **`ROADMAPS: none`** → stop: "no roadmaps found — create one with `/task:to-roadmap`. → Next: `/task:to-roadmap`"
- **Exactly one line** → use it (still refuse if it is fully complete, `unchecked=none`).
- **More than one** → `AskUserQuestion` (convention (c)), one chip per roadmap labelled `<slug>  (<done>/<total>)`; sort partial roadmaps first, complete ones last with a `(complete)` suffix, and refuse to proceed on a complete pick.

Every refusal on a complete roadmap ends the same way, in the wording the capture skills also use: "Every item in `<slug>` is already checked off — nothing left to run. → Next: `/task:to-roadmap` for a new initiative, or uncheck the items you want rerun."

Read the roadmap's `Spec:` header lines, if any — each is a Markdown link, `Spec: [<slug>](../spec/<slug>.md)`, so take `<slug>` from the link **text** (a hand-edited roadmap may carry a bare slug; same reading) and resolve it to an **absolute** `$AI_DIR/spec/<slug>.md` path, never by following the relative link target. Echo the list. These paths are passed as Step 2's `specPaths` arg and reach every item's plan-agent prompt as fixed technical-decision anchors; the JS sandbox cannot expand `$AI_DIR`, so the values must be absolute.

### Item scope

No flags — always ask interactively unless there's nothing to ask. The chosen roadmap's open item numbers are its `unchecked=` list. When there is **more than one**, present a single `AskUserQuestion` (convention (c)) — *"How much of `<slug>` should this run cover?"*:

- **All remaining** (default) — every unchecked item.
- **Only next wave** — just the first dependency-wave of unchecked items. Pass it through as `scope: 'next-wave'`; the driver sorts every unchecked item and then keeps wave 1, so nothing has to be filtered or reordered here.
- **Pick range** — collect a range via the `AskUserQuestion` free-text ("Other") option, e.g. `1,3-5,8`; validate each number exists and is unchecked. On a bad entry, **name the valid set** rather than just refusing — that is what turns a rejection into a second attempt that works: "#9 isn't a runnable item in `<slug>` (it's already checked / doesn't exist). Unchecked right now: #2, #3, #5, #7. → Next: rerun `/task:roadmap-to-workflow <slug>` and pick from those."

One open item → skip the question, run it. `unchecked=none` → stop: "Every item in `<slug>` is already checked off — pick another roadmap, or capture new work with `/task:to-roadmap`. → Done."

## Step 1: Report the items

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-items.sh" "<slug-or-path>"
```

One line per unchecked item — `N<TAB>deps<TAB>model<TAB>title`, `deps` empty for none and `model` defaulting to `sonnet` — then a trailing `DONE<TAB><n,…>` naming the already-marked numbers. Exit 1 means the roadmap did not resolve; stop there rather than running with zero items, which reads exactly like a fully-completed roadmap. [contract § Helpers](../../docs/contract.md#helpers) owns the shape.

That is the whole of Step 1: **report what the roadmap says, do not sort it.** The driver computes the waves itself (`computeWaves` in `skills/_lib/roadmap-driver.js`), so pass the collector's output through as Step 2's args and nothing more:

- every `N<TAB>deps<TAB>model<TAB>title` line → one `items` entry `{n, title, model, deps: [<numbers>]}`, with `deps: []` for an em dash or an empty value;
- the trailing `DONE<TAB><n,…>` line → `done: [<numbers>]` (`[]` when nothing is marked yet);
- the Step 0 scope pick → `scope`: `'all'`, `'next-wave'`, or the picked numbers as an array.

`items` carries **every** unchecked item, not the scoped subset — narrowing is `scope`'s job, and the driver needs the full set to see the dependencies that define a wave. That is also what makes "Only next wave" correct without any special handling here: the driver sorts everything, then keeps wave 1.

The driver hard-stops before spawning a single agent, with a message naming the items, when the scope leaves a dependency unmet ("out of scope: #4 depends on #2, …") or when the scoped items form a cycle ("dependency cycle among #1, #2 …"). Relay it as-is and close with `→ Next: rerun \`/task:roadmap-to-workflow <slug>\` with a scope that includes #N` for the first case, or `→ Next: edit \`.task/roadmap/<slug>.md\` to break the cycle, then rerun \`/task:roadmap-to-workflow <slug>\`` for the second. (Roadmaps are user-edited and `to-roadmap`'s cyclic-deps check is report-only, so a cycle can reach here.)

## Step 2: Invoke the Workflow driver

**Do not author a Workflow script.** The driver ships with the plugin at `skills/_lib/roadmap-driver.js` and never changes between runs — [docs/contract.md § roadmap-to-workflow execution shape](../../docs/contract.md#roadmap-to-workflow-execution-shape-driver-contract) is its contract. Your job is only to assemble its `args` from Steps 0–1 and invoke it:

```javascript
Workflow({
  scriptPath: "<absolute $CLAUDE_PLUGIN_ROOT>/skills/_lib/roadmap-driver.js",
  args: {
    slug: "<roadmap-slug>",
    aiDir: "<absolute value of $AI_DIR>",                    // echoed in Step 0
    pluginRoot: "<absolute value of $CLAUDE_PLUGIN_ROOT>",   // echoed in Step 0
    specPaths: ["<absolute $AI_DIR/spec/<slug>.md>"],        // from Step 0 — [] when the roadmap has no Spec: headers
    items: [                                                 // from Step 1 — EVERY unchecked item, unsorted
      { n: 1, title: "…", model: "sonnet", deps: [] },
      { n: 2, title: "…", model: "haiku",  deps: [1] },
      { n: 3, title: "…", model: "opus",   deps: [1] },
    ],
    done: [],                                                // from Step 1's DONE line — already-marked numbers
    scope: "all",                                            // from Step 0 — "all" | "next-wave" | [2, 3]
  },
})
```

**Args are real JSON values, every path absolute.** `items` is an actual array of `{n, title, model, deps}` objects and `done` an actual array of numbers — never JSON-encoded strings — and the sandbox cannot expand `$AI_DIR` or `$CLAUDE_PLUGIN_ROOT`, so the values from Step 0's block go in verbatim. The driver asserts all of this up front, computes the waves itself, and returns a single explanatory line instead of launching an agent against garbage.

What the driver does, per wave: **plans all items in parallel** — each plan agent reads `skills/_lib/plan-driver.md` (the non-interactive counterpart of `to-plan`) and writes only its own `.task/task/<item-slug>.md`, never the working tree; the planner model is opus, or sonnet at low effort for a `haiku`-hinted item — then runs **implement → review → mark strictly one item at a time**: the item's own model implements and commits, `task:code-reviewer` reviews, fixes within **Touches**, runs Build and Tests, and commits its fixes as a second commit on top of the implementation's (no `model`/`isolation` opts), and a cheap serial mark agent flips item N's checkbox in the roadmap (the flip is idempotent — an already-ticked item reports OK — but a missing, renumbered or duplicated `### - [ ] N.` heading FAILs the wave rather than passing silently, since the commit is already in the tree and a silent miss would make the next run redo landed work). A `FAIL` digest from any stage stops the run; a barrier separates waves, so each implement sees its already-landed wave-mates' reviewed commits.

**Rerun / resume.** Because the script and args are static, the Workflow tool's `resumeFromRunId` replays completed stages from cache — prefer it when re-running after a stop in the same session. Otherwise a plain rerun of `/task:roadmap-to-workflow <slug>` is equivalent in effect: Step 1 collects only unchecked items, and ticked items never rerun.

**Graceful fallback:** if the Workflow tool isn't available in this environment, run the items one at a time by hand, respecting the same wave order: for each item, run `to-plan` for that roadmap item (writes `.task/task/<item-slug>.md`) and take the exact written path from `to-plan`'s own Step 8 output digest — do **not** reconstruct `<item-slug>` from the item title, since `to-plan` may disambiguate the slug on a collision (its Step 2a.5). Then in a plain session say `implement <that path>`: its `## Execution` pointer sends that session to `.task/CLAUDE.md` → `## Executing a task`, which already carries the plan → commit → `task:code-reviewer` sequence, so the review happens there rather than as a driver stage. Tell that session **not to tick the roadmap checkbox itself** (despite `## Executing a task` step 5); then — as the driver — manually tick that item's checkbox in `.task/roadmap/<slug>.md` once the review came back OK, before moving to the next. This keeps the auto-mark the driver's job, exactly as in the Workflow path.

## Output

- Per item: the returned digest lines (`OK|FAIL #N <item-slug> <summary>`) — one each from the plan, implement, review, and mark stages — surfaced as each wave lands.
- **One run-summary line above the footer, in both outcomes.** After an unattended autopilot the operator should not have to count `OK` lines by hand to learn how much landed:

  ```
  Ran `<slug>`: <K> of <M> items landed and ticked, <R> still unchecked. Commits: <first-sha>..<last-sha>.
  ```

- End with the canonical next-step footer (convention (a), flag-free):
  - All items shipped → `→ Done. Roadmap complete — \`.task/roadmap/<slug>.md\` fully checked; review the landed commits with \`git log\`.`
  - Stopped on a `FAIL` → surface the failing digest, then name **where** it stopped and **what state the tree is in** — without those the operator has to scroll back through waves of digests to find out what broke and whether anything is uncommitted: `Stopped at #<N> <item-slug> in wave <W>. Its work is left in the working tree — inspect it with \`git status\` and \`git log --oneline -3\`. → Next: fix #<N> (or re-plan it with \`/task:to-plan <slug>#<N>\`), then rerun \`/task:roadmap-to-workflow <slug>\` — already-ticked items stay ticked, only the unchecked remainder reruns.`

## Forbidden

- Running setup on a missing `.task/CLAUDE.md`. This skill hard-stops and redirects; only the four capture skills are intake-capable.
- Looping the items yourself in this session's thread, or authoring a Workflow script inline via the `script` input. The shipped driver is what gives each item fresh context, per-item model control, parallel planning and driver-side auto-mark; a hand-rolled loop or a re-authored copy drifts from it. (The one-at-a-time manual fallback is only for when the Workflow tool is unavailable.)
- Passing `args` as a JSON-encoded string, or any path relative — the sandbox expands nothing, and the driver's assertions reject both.
- Sorting the items yourself, or narrowing `items` to the chosen scope. Both are `computeWaves`' job, and a pre-narrowed set hides the dependencies that define a wave.
- Auto-marking a checkbox from inside a plan / implement / review agent — the flip is the driver's own stage, strictly after that item's review returns `OK`, so parallel writers never race on the roadmap file.
- Instructing an implement agent to run `/verify` or `/code-review`: both are `disable-model-invocation`, so a subagent skips them silently and still reports `OK`. Verification and review live inside `task:code-reviewer`.
- Passing `model` or `isolation` to the review stage — it pins its own model, and an isolated worktree would hide the very tree it must review and commit into.
- Modifying project code yourself, or touching any file but the roadmap. Implementation happens in the per-item agents, review fixes in the review agent.
