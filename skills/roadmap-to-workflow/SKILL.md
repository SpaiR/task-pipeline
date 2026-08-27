---
name: roadmap-to-workflow
description: 'Fan an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — parallel planning, serialized implementation, dependency-ordered waves.'
disable-model-invocation: true
user-invocable: true
---

Drive an approved roadmap through a dynamic Workflow. This skill collects the roadmap's unchecked items, sorts them into dependency-ordered **waves**, then invokes the **plugin-shipped Workflow driver** (`skills/_lib/roadmap-driver.js`, via the Workflow tool's `scriptPath`) that, within each wave, plans all items in parallel and then implements, reviews, and ticks them off one item at a time in the shared working tree. It does **not** hand-roll that fan-out itself, and it does **not** author the Workflow script — the driver is a static file, inspectable at any time, parameterized only through `args` (Step 2). If the Workflow tool isn't available, it falls back to running items serially by hand, in the same dependency order (Step 2).

**Per-item model control.** Each roadmap item may carry a `**Model:**` hint (`haiku | sonnet | opus`); the driver passes it to that item's implement agent as `opts.model`, and scales the plan stage down for lightweight items (a `haiku`-hinted item is planned by sonnet at low effort; everything else by opus). The review agent ignores it — `task:code-reviewer` pins its own model, so a `haiku` item never gets a `haiku` review.

**Per-item execution is a three-agent split by default — opus plans (sonnet for `haiku`-hinted items), the item's model implements and commits, `task:code-reviewer` reviews and amends; a fourth, cheap driver stage then ticks the roadmap checkbox (Step 2).**

**This skill *is* the opt-in** for the Workflow tool — reading it and following the Steps is the authorization; there is no magic keyword and no separate confirmation.

**Input:** `$ARGUMENTS` — optional. A single positional `<roadmap-slug>` (or path) to skip the roadmap picker. No flags — item scope is chosen interactively (Step 0).

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for item grammar (`### - [ ] N.`, `**Dependencies:**`, `**Model:**`); [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) for the artifact each item's plan agent writes.

## Step 0: Setup gate, pick roadmap, pick scope

`roadmap-to-workflow` is **not** an intake skill — it never runs setup itself (a roadmap can't exist without `.task/CLAUDE.md`, so an absent one means something upstream is broken).

```bash
echo "$CLAUDE_PLUGIN_ROOT"                                 # note this absolute path — pass it as `pluginRoot` in Step 2's args
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
echo "$AI_DIR"                                             # note this one too — pass it as `aiDir` in Step 2's args
[[ -f "$AI_DIR/CLAUDE.md" ]] || echo "CLAUDE.md not found"
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all
```

- **`CLAUDE.md not found`** (the guard above echoes it; `validate.sh all` also exits 2 with the same message) → hard-stop redirect (do **not** bootstrap here):
  > The project isn't set up yet. Capture something first with `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec` — those four set the project up inline.
  > → Next: `/task:to-roadmap`
- **Any other non-zero exit from `validate.sh`** → `validate.sh all` checks every artifact, so an error may sit on a task or roadmap unrelated to this run. **Mind the timing:** at this point the roadmap has not been picked yet (that happens in the *Roadmap* sub-step below), so do not try to judge here which errors are "yours". Surface every reported error now, block on none of them, and **hold** the roadmap ones. Once `<slug>` is resolved below, check the held list: if an error was reported against **that** file, stop then — "→ Next: fix the reported error in `.task/roadmap/<slug>.md`, then rerun `/task:roadmap-to-workflow <slug>`". Errors on any other artifact never block. (The one case where the roadmap *is* already known at gate time is a positional `<roadmap-slug>` in `$ARGUMENTS`; there you may apply the check immediately.) WARN lines never set a non-zero exit; they are informational only.

### Roadmap

If `$ARGUMENTS` gives a positional `<roadmap-slug>`/path, resolve it and skip the picker — **but source the helpers first, and check the result before using it.** Each bash call is a fresh shell, and the only other block that sources `roadmap.sh` is the picker query below, which this branch skips: without its own source, `resolve_artifact_path` is an undefined command whose empty output reads as "no such roadmap" for a slug that is perfectly valid.

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # exports AI_DIR
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap.sh"      # defines resolve_artifact_path
resolve_artifact_path roadmap "<arg>"
```

An empty return means no such roadmap (a typo is the common case); do **not** fall through to the item scan with an unresolved path, because an empty filename makes the Step 1 `awk` read stdin, come back with zero items, and report the roadmap as fully done. Stop instead, and list what is actually there (the picker query below already produces the list):

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

Read the roadmap's `Spec:` header lines, if any — each is a Markdown link, `Spec: [<slug>](../spec/<slug>.md)`, so take `<slug>` from the link **text** (a hand-edited roadmap may carry a bare slug; same reading) and resolve it to an **absolute** `$AI_DIR/spec/<slug>.md` path, never by following the relative link target. Echo the list. These paths are passed as Step 2's `specPaths` arg and reach every item's plan-agent prompt as fixed technical-decision anchors; the JS sandbox cannot expand `$AI_DIR`, so the values must be absolute.

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
  # `### Spec references → …` is a top-level heading that lives INSIDE an item
  # (the same tolerance validate.sh grants it), so it is NOT a terminator — it
  # may sit above **Dependencies:**, and flushing here would drop them.
  /^### Spec references/ { next }
  # A heading that ATTEMPTED to be an item and drifted (`[X]`, a double space
  # after the checkbox, `####`, a missing `- `) closes the current item.
  # Otherwise its Dependencies/Model are attributed to the item ABOVE it — a
  # phantom dependency, a wrong wave, or the wrong model, with no signal.
  # Matched the same way `validate.sh` reports it, so both parsers agree on what
  # counts as an item attempt.
  /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ { flush(); next }
  /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/       { flush(); next }
  # The section terminators `validate.sh`'s block parser uses. Deliberately NOT
  # every `#`-prefixed line: a `#### Notes` sub-heading, or a `#` comment inside
  # a fenced block, sits INSIDE an item — flushing on those would drop that
  # item's Dependencies/Model on a file that validates perfectly clean.
  /^### / { flush(); next }
  /^## /  { flush(); next }
  /^---[[:space:]]*$/ { flush(); next }
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

The result is a `waves` structure — an array of waves, each an array of `{n, title, model}` items — passed as Step 2's `waves` arg.

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
    waves: [                                                 // from Step 1 — dependency order
      [ { n: 1, title: "…", model: "sonnet" }, { n: 2, title: "…", model: "haiku" } ],
      [ { n: 3, title: "…", model: "opus" } ],
    ],
  },
})
```

**Args are real JSON values, every path absolute.** `waves` is an actual array of arrays of `{n, title, model}` objects — never a JSON-encoded string — and the sandbox cannot expand `$AI_DIR` or `$CLAUDE_PLUGIN_ROOT`, so the echoed absolute values go in verbatim. The driver asserts all of this up front and returns a `bad args` line instead of launching an agent against a garbage path.

What the driver does, per wave: **plans all items in parallel** — each plan agent reads `skills/_lib/plan-driver.md` (the non-interactive counterpart of `to-plan`) and writes only its own `.task/task/<item-slug>.md`, never the working tree; the planner model is opus, or sonnet at low effort for a `haiku`-hinted item — then runs **implement → review → mark strictly one item at a time**: the item's own model implements and commits, `task:code-reviewer` reviews, fixes within **Touches**, runs Build and Tests, and amends (no `model`/`isolation` opts), and a cheap serial mark agent flips exactly one `### - [ ] N.` checkbox in the roadmap (zero or multiple matches FAIL the wave rather than pass silently — the commit is already in the tree, and a silent miss would make the next run redo landed work). A `FAIL` digest from any stage stops the run; a barrier separates waves, so each implement sees its already-landed wave-mates' reviewed commits.

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

- Running setup / bootstrap on a missing `.task/CLAUDE.md` — this skill hard-stops and redirects; only `to-task` / `to-plan` / `to-roadmap` / `to-spec` are intake-capable.
- Looping the items yourself in this session's main thread instead of invoking the shipped driver — the Workflow tool is what gives each item fresh per-item context, per-item model control, parallel planning, and driver-side auto-mark; a hand-rolled loop reintroduces the accumulation problems this skill exists to remove. (The one-at-a-time manual fallback is only for when the Workflow tool is unavailable.)
- Authoring a Workflow script inline (via the `script` input) instead of invoking `skills/_lib/roadmap-driver.js` via `scriptPath` — the shipped driver is the contract; a re-authored copy drifts.
- Passing `args` as a JSON-encoded string, or passing relative paths — the sandbox cannot expand env vars, and a stringified `waves` fails the driver's assertions.
- Running items whose dependencies are still unchecked, or placing an item in an earlier wave than its `Dependencies` allow.
- Auto-marking roadmap checkboxes from inside a per-item plan/implement/review agent — the flip belongs to the driver's own mark stage, strictly after the item's **review** returns `OK`, to avoid parallel writers racing on the roadmap file.
- Instructing an implement agent to run `/verify` or `/code-review` — both platform commands are `disable-model-invocation`, so a subagent silently skips them and still reports `OK`; verification and review live inside `task:code-reviewer`.
- Passing `model` (or `isolation`) to the review stage — `task:code-reviewer` pins its own model/effort, and worktree isolation would hide the very tree it must review and amend.
- Modifying project code yourself, or touching any file other than the roadmap (for scope reading) and, via the driver step, the roadmap's checkboxes — all implementation happens inside the per-item implement agents, run one at a time in the shared working tree, and all review fixes inside the review agent.
