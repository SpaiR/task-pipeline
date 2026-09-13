---
name: roadmap-to-workflow
description: 'Fan an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — parallel planning, serialized implementation, dependency-ordered waves.'
argument-hint: '[<roadmap-slug>]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Drive an approved roadmap through a dynamic Workflow. This skill reports the roadmap's unchecked items and the scope the user picks; the **plugin-shipped driver** (`skills/_lib/roadmap-driver.js`, invoked by name as `task:roadmap-driver`) sorts them into dependency-ordered **waves** and, per wave, plans in parallel then implements, reviews and ticks off one item at a time in the shared working tree. The driver is a static file, inspectable at any time and parameterized only through `args` (Step 2) — never hand-rolled here, never re-authored inline. Without the Workflow tool, Step 2 hard-stops instead of running the items itself.

**Per-item execution is a four-stage split:** opus plans it (sonnet at low effort when the item's `**Model:**` hint is `haiku`), the item's own model implements and commits, `task:code-reviewer` reviews and commits its fixes on top, and a cheap driver stage ticks the checkbox. The review stage ignores the hint, pinning its own model — a `haiku` item never gets a `haiku` review.

**This skill *is* the opt-in** for the Workflow tool: following its Steps is the authorization. No magic keyword, no separate confirmation.

**Input:** `$ARGUMENTS` — optional. A single positional `<roadmap-slug>` (or path) to skip the roadmap picker. No flags — item scope is chosen interactively (Step 0).

**Format contract:** [contract § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) owns the item grammar (`### - [ ] N.`, `**Dependencies:**`, `**Model:**`), and [§ execution shape](../../docs/contract.md#roadmap-to-workflow-execution-shape-driver-contract) the driver's stages.

## Step 0: Setup gate, pick roadmap, pick scope

This is **not** an intake skill: it never runs setup. A roadmap cannot exist without `.task/CLAUDE.md`, so an absent one means something upstream is broken.

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" workflow`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `PLUGIN_ROOT:` and `AI_DIR:` are Step 2's `pluginRoot` and `aiDir` args, used verbatim — the sandbox expands neither.
2. **`CONFIG: absent`** → hard-stop redirect (do **not** bootstrap here):
   > The project isn't set up yet. Capture something first with `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec` — those four set the project up inline.
   > → Next: `/task:to-roadmap`
3. **`VALIDATE:` holds `validate.sh all`'s output** — every artifact, so an error may belong to a task or roadmap unrelated to this run. Surface every `ERROR` line, block on none of them yet, and **hold** the roadmap ones: once `<slug>` is resolved below, an error against **that** file is a stop — "→ Next: fix the reported error in `.task/roadmap/<slug>.md`, then rerun `/task:roadmap-to-workflow <slug>`". `WARN` lines are informational. (`ERROR precondition: CLAUDE.md not found` is case 2, not a validation error.)
4. `ROADMAPS:` carries each roadmap's progress and open item numbers — the picker below reads it, and lists no directory of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

### Roadmap

A positional `<roadmap-slug>` in `$ARGUMENTS` is matched against the `ROADMAPS:` slugs; a positional **path** (contains `/`) is used as given for Step 1's argument — but `<slug>` from here on is always the bare slug (that path's basename without `.md`), because Step 2's `slug` arg is what the driver rebuilds the roadmap path from. No match — stop, and list what is there, rather than falling through with an unresolved path:

> no roadmap `<arg>` under `$AI_DIR/roadmap/`. Available: `<slug>` (2/7), `<slug>` (0/4).
> → Next: `/task:roadmap-to-workflow <one of those slugs>`

With no positional argument, pick from the `ROADMAPS:` lines:

- **`ROADMAPS: none`** → stop: "no roadmaps found — create one with `/task:to-roadmap`. → Next: `/task:to-roadmap`"
- **Exactly one line** → use it (still refuse if it is fully complete, `unchecked=none`).
- **More than one** → `AskUserQuestion` (convention (c)), one chip per roadmap labelled `<slug>  (<done>/<total>)`; sort partial roadmaps first, complete ones last with a `(complete)` suffix, and refuse to proceed on a complete pick.

Every refusal on a complete roadmap ends the same way: "Every item in `<slug>` is already checked off — nothing left to run. → Next: `/task:to-roadmap` for a new initiative, or uncheck the items you want rerun."

Read the roadmap's `Spec:` header lines, if any, and resolve each slug to an **absolute** `$AI_DIR/spec/<slug>.md` — the slug is the link label, or the whole value when it is a bare slug, never the relative target ([contract § Cross-artifact references](../../docs/contract.md#cross-artifact-references)). These become Step 2's `specPaths` and reach every plan agent as fixed anchors; absolute because the sandbox expands nothing.

### Item scope

No flags — always ask, unless there is nothing to ask. The open item numbers are the roadmap's `unchecked=` list; with **more than one**, one `AskUserQuestion` (convention (c)) — *"How much of `<slug>` should this run cover?"*:

- **All remaining** (default) — every unchecked item.
- **Only next wave** — `scope: 'next-wave'`. The driver sorts every unchecked item and keeps wave 1, so nothing is filtered or reordered here.
- **Pick range** — via the free-text ("Other") option, e.g. `1,3-5,8`, expanded to the numbers themselves. A number that is not in `unchecked=` is refused **with the valid set named**, which is what turns a rejection into a second attempt that works: "#9 isn't a runnable item in `<slug>` (already checked, or no such item). Unchecked right now: #2, #3, #5, #7. → Next: rerun `/task:roadmap-to-workflow <slug>` and pick from those."

One open item → skip the question, run it. `unchecked=none` → stop: "Every item in `<slug>` is already checked off — pick another roadmap, or capture new work with `/task:to-roadmap`. → Done."

## Step 1: Report the items

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-items.sh" "<slug-or-path>"
```

One line per unchecked item — `N<TAB>deps<TAB>model<TAB>title` — then `DONE<TAB><n,…>` with the already-marked numbers ([contract § Helpers](../../docs/contract.md#helpers) owns the shape). Exit 1 means the roadmap did not resolve: stop, rather than running with zero items, which reads exactly like a finished roadmap.

Pass those lines through to Step 2 as data — **every** unchecked item, unsorted and unfiltered: each item line becomes one `items` entry `{n, title, model, deps}`, the `DONE` line becomes `done`, and Step 0's pick becomes `scope`. Numbers are parsed as **integers**, and an empty field is an **empty array**: a dependency-free item is `deps: []`, and a roadmap with nothing marked yet is `done: []`. Narrowing is `scope`'s job; the driver needs the full set to see the dependencies that define a wave.

The driver's `computeWaves` sorts them and hard-stops **before spawning anything**, returning one line. Relay it as-is and add the matching footer:

- `out of scope: #4 depends on #2, …` → `→ Next: rerun \`/task:roadmap-to-workflow <slug>\` with a scope that includes #2`
- `dependency cycle among #1, #2 …` → `→ Next: edit \`.task/roadmap/<slug>.md\` to break the cycle, then rerun \`/task:roadmap-to-workflow <slug>\``
- `not runnable in this roadmap …: #9` → name the valid set, as Step 0's bad-range pick does: `Unchecked right now: #2, #3. → Next: rerun \`/task:roadmap-to-workflow <slug>\` and pick from those`
- `nothing to run — every item in scope is already marked.` → `→ Done.`

## Step 2: Invoke the Workflow driver

**Do not author a Workflow script.** The driver ships at `skills/_lib/roadmap-driver.js`, declared in the plugin manifest under `"workflows"`, so the platform registers it as `task:roadmap-driver` and reads the file itself. It is reached **by name, never by path** — a `scriptPath` into the plugin is checked for read permission against this session's working directory, which a plugin is never inside. Assemble its `args` from Steps 0–1 and invoke it:

```javascript
Workflow({
  name: "task:roadmap-driver",
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

**Args are real JSON values, every path absolute** — `items` an actual array of objects, `done` an actual array of numbers, never JSON-encoded strings. The driver asserts all of it up front and returns one explanatory line instead of launching an agent against garbage.

Per wave the driver plans every item in `parallel()` — each plan agent follows `plan-driver.md` and writes only its own task file — then runs **implement → review → mark strictly one item at a time**, so the shared tree keeps one writer and each implement sees its wave-mates' reviewed commits. A `FAIL` digest from any stage stops the run, and a barrier separates waves. The stage details are the driver's ([contract § execution shape](../../docs/contract.md#roadmap-to-workflow-execution-shape-driver-contract)); nothing here has to restate them.

**Rerun / resume.** The workflow name and args are static, so `resumeFromRunId` replays completed stages from cache — prefer it after a stop in the same session. A plain rerun is equivalent in effect: Step 1 reports only unchecked items, and ticked ones never rerun.

**Driver not registered** — the Workflow tool is there, but `task:roadmap-driver` does not resolve; the tool's error names the workflow and lists what is registered. The driver ships with the plugin, so this is an install fact rather than an environment one: a stale plugin snapshot, an update this session never reloaded, or a CLI build that does not load plugin-shipped workflows yet. Do not retry by path, and do not treat it as the no-Workflow-tool case below — that would hide a broken install behind the slowest available path. Stop, quoting the tool's own error:

```
`task:roadmap-driver` is not registered in this session, so autopilot cannot start — the `task` plugin is stale, or was updated without a restart. The Workflow tool reported: "<its error, verbatim>". The items can still be run by hand, but the fix is the reinstall.
→ Next: update or reinstall the `task` plugin, restart Claude Code, then rerun `/task:roadmap-to-workflow <slug>`.
```

**No Workflow tool** — the Workflow tool itself is absent from this environment, which is a different case from the one above (there, the tool is present but the driver's name fails to resolve). Autopilot cannot run without it, so this skill stops rather than looping the items itself. Stop, with this message:

```
Autopilot needs the Workflow tool, and it isn't available in this environment, so `/task:roadmap-to-workflow` can't run. The items can still be run by hand, one at a time, in dependency order: in this chat, run `/task:to-plan <slug>#<N>` for one unchecked item, then start a fresh session and say `implement .task/task/<item-slug>.md`. That session's `## Execution` pointer carries plan → commit → `task:code-reviewer` on its own, and ticks the roadmap checkbox itself via `## Executing a task` step 5 — nothing further to do per item.
→ Next: run `/task:to-plan <slug>#<N>` for the first unchecked item.
```

## Output

- Per item: the returned digest lines (`OK|FAIL #N <item-slug> <summary>`), one per stage, surfaced as each wave lands.
- **One run-summary line above the footer, in both outcomes** — after an unattended run, nobody should have to count `OK` lines to learn how much landed:

  ```
  Ran `<slug>`: <K> of <M> items landed and ticked, <R> still unchecked. Commits: <first-sha>..<last-sha>.
  ```

- End with the canonical next-step footer (convention (a), flag-free):
  - All items shipped → `→ Done. Roadmap complete — \`.task/roadmap/<slug>.md\` fully checked; review the landed commits with \`git log\`.`
  - Stopped on a `FAIL` → surface the failing digest, then say **where** it stopped and **what state the tree is in**: `Stopped at #<N> <item-slug> in wave <W>. Its work is left in the working tree — inspect it with \`git status\` and \`git log --oneline -3\`. → Next: fix #<N> (or re-plan it with \`/task:to-plan <slug>#<N>\`), then rerun \`/task:roadmap-to-workflow <slug>\` — already-ticked items stay ticked, only the unchecked remainder reruns.`

## Forbidden

- Running setup on a missing `.task/CLAUDE.md`. This skill hard-stops and redirects; only the four capture skills are intake-capable.
- Looping the items yourself in this session's thread, or authoring a Workflow script inline via the `script` input. The shipped driver is what gives each item fresh context, per-item model control, parallel planning and driver-side auto-mark; a hand-rolled loop or a re-authored copy drifts from it — including when the Workflow tool is unavailable, which is a hard stop, not a cue to loop the items yourself.
- Reaching the driver by path instead of by its registered name. The Workflow tool checks a `scriptPath` for read permission against this session's working directory, and a plugin's own directory is never inside it — so the run dies before the first agent, everywhere except a checkout of the plugin itself. A name that does not resolve gets the hard-stop above, never a path retry.
- Passing `args` as a JSON-encoded string, or any path relative — the sandbox expands nothing, and the driver's assertions reject both.
- Sorting the items yourself, or narrowing `items` to the chosen scope. Both are `computeWaves`' job, and a pre-narrowed set hides the dependencies that define a wave.
- Auto-marking a checkbox from inside a plan / implement / review agent — the flip is the driver's own stage, strictly after that item's review returns `OK`, so parallel writers never race on the roadmap file.
- Instructing an implement agent to run `/verify` or `/code-review`: both are `disable-model-invocation`, so a subagent skips them silently and still reports `OK`. Verification and review live inside `task:code-reviewer`.
- Passing `model` or `isolation` to the review stage — it pins its own model, and an isolated worktree would hide the very tree it must review and commit into.
- Modifying project code or any file yourself — including the roadmap. Implementation happens in the per-item agents, review fixes in the review agent, the checkbox flip in the driver's mark stage.
