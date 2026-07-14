---
name: roadmap-to-workflow
description: 'Fan an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — one isolated worktree per unchecked item, dependency-ordered waves, per-item model control. A thin wrapper: this skill authors and invokes the Workflow tool, it does not hand-loop items itself.'
disable-model-invocation: true
user-invocable: true
---

Drive an entire approved roadmap through parallel, isolated sessions. This skill collects the roadmap's unchecked items, topologically sorts them into dependency-ordered **waves**, then authors and invokes a **dynamic Workflow** (the Workflow tool) that runs each wave's items in parallel worktrees and ticks off the roadmap as items land. It does **not** hand-roll that fan-out itself.

**Per-item model control.** Each roadmap item may carry a `**Model:**` hint (`haiku | sonnet | opus`); the Workflow passes it to that item's implement agent as `opts.model`.

**Per-item execution is a two-agent split by default: opus plans, the item's model implements.** See Step 2 — this is not an optimization to opt into, it is the default shape.

**This skill *is* the opt-in.** A skill whose instructions tell Claude to author and call the Workflow tool is the sanctioned way to reach for it — there is no magic keyword and no separate confirmation. Reading this file and following the Steps is the authorization.

**Input:** `$ARGUMENTS` — optional. A single positional `<roadmap-slug>` (or path) to skip the roadmap picker. No flags — item scope is chosen interactively (Step 0).

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for item grammar (`### - [ ] N.`, `**Dependencies:**`, `**Model:**`); [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format) for the artifact each item's plan agent writes.

<!--
What v3 drops vs the old run-roadmap (v2).

  GONE, not reimplemented:
    - the lock protocol (cross-worktree `.lock` / `set -o noclobber` mutex) —
      isolation now comes from Workflow's `parallel({ isolation: 'worktree' })`,
      a worktree per item, not a mutex over one shared workspace;
    - the active-task pointer as the per-item context handle — v3 has no
      pointer at all; the on-disk `.task/task/<item-slug>.md` IS the handle,
      read fresh by the implement agent, no pointer to write or heal;
    - per-item inline execution of build/ship skills — those skills are
      deleted in v3; each item's second agent is just told to "implement,
      /verify, /code-review, commit" per the artifact's own `## Execution`
      block, nothing to read but the task file;
    - sequential-only looping — v2 forced one active task at a time because
      only one pointer/workspace could exist. v3 has no such constraint, so
      items in the same dependency wave run in PARALLEL, each in its own
      worktree.

  NEW in v3:
    - dependency-ordered WAVES (topological sort on `**Dependencies:**`)
      instead of trusting file order to encode dependencies;
    - the driver (not the per-item agent) auto-marks the roadmap checkbox,
      specifically so parallel writers in a wave never race on one file.
-->

## Step 0: Config gate, pick roadmap, pick scope

`roadmap-to-workflow` is **not** an intake skill — it never runs setup itself (a roadmap can't exist without config, so an absent config means something upstream is broken).

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
[[ -f "$AI_DIR/config/config.md" ]] || { echo "no-config"; }
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all
```

- **`config.md not found`** → hard-stop redirect (do **not** bootstrap here):
  > The project isn't set up yet. Capture something first with `to-task`, `to-plan`, or `to-roadmap` — those set the project up inline.
- **Any other non-zero exit from `validate.sh`** → stop and report the validator output (this is a self-check, not a hard gate, so a non-fatal warning can be surfaced and the run continued at your judgment; a structural failure on the chosen roadmap file should stop).

### Roadmap

If `$ARGUMENTS` gives a positional `<roadmap-slug>`/path, resolve it and skip the picker. Otherwise list the available roadmaps with progress (uses the kept `roadmap.sh` helpers):

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap.sh"      # resolve_roadmap_path, roadmap_progress_counts
shopt -s nullglob
for f in "$AI_DIR"/roadmap/*.md; do
  counts=$(roadmap_progress_counts "$f")
  total=$(awk -F': ' '/^total/{print $2}'     <<<"$counts")
  done_n=$(awk -F': ' '/^done/{print $2}'      <<<"$counts")
  printf '%s\t%s/%s\t%s\n' "$(basename "$f" .md)" "$done_n" "$total" "$f"
done
```

- **No roadmap files** → stop: "no roadmaps found — create one with `to-roadmap`."
- **Exactly one** → use it (still refuse if it's fully complete, `done == total > 0`).
- **More than one** → `AskUserQuestion` (convention (c)), one chip per roadmap labelled `<slug>  (<done>/<total>)`; sort partial roadmaps first, complete ones last with a `(complete)` suffix, and refuse to proceed on a complete pick.

Read the roadmap's `Spec: <slug>` header lines, if any — collect the referenced `.task/spec/<slug>.md` paths and pass them to every item's plan agent (Step 2) as fixed technical-decision anchors.

### Item scope

No flags — always ask interactively unless there's nothing to ask. When the chosen roadmap has **more than one** unchecked item, present a single `AskUserQuestion` (convention (c)) — *"How much of `<slug>` should this run cover?"*:

- **All remaining** (default) — every unchecked item.
- **Only next wave** — just the first dependency-wave of unchecked items (see Step 1).
- **Pick range** — collect a range via the `AskUserQuestion` free-text ("Other") option, e.g. `1,3-5,8`; validate each number exists and is unchecked.

One unchecked item → skip the question, run it. Zero unchecked → stop: "all items in `<slug>` are already done."

## Step 1: Collect items and sort into dependency waves

Read the resolved roadmap. For each unchecked (`### - [ ] N.`) item in the chosen scope, capture `N`, title, `**Dependencies:**`, and `**Model:**` (default `sonnet` when absent or off-list). This prints one `N<TAB>deps<TAB>model<TAB>title` line per unchecked item:

```bash
ROADMAP=$(resolve_roadmap_path "<slug-or-path>")   # roadmap.sh, sourced in Step 0
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
  /^\*\*Dependencies:\*\*/ && pend { deps=$0; sub(/^\*\*Dependencies:\*\* */,"",deps); gsub(/[ \t]/,"",deps); if (deps=="—"||deps=="-") deps="" }
  /^\*\*Model:\*\*/       && pend { model=$0; sub(/^\*\*Model:\*\* */,"",model); gsub(/[ \t]/,"",model) }
  END { flush() }
' "$ROADMAP"
```

Filter that list to the Step 0 scope. Then **topologically sort into waves**, computed by you (not by bash — the item set is small and this is reasoning, not parsing):

- Wave 1 = every filtered item whose `Dependencies` are empty, or whose dependencies are all *already checked* (`[x]`/`[~]`/`[>]`/`[-]`) in the roadmap file — i.e. nothing left in this run blocks it.
- Wave 2 = every remaining filtered item whose dependencies are all satisfied by Wave 1 (already-checked items, or items landing in Wave 1).
- Continue until every filtered item is placed. A dependency on an item **outside** the filtered/scoped set that is still unchecked is a hard stop — surface it and ask the user to widen the scope or drop the item.

The result is a `waves: Item[][]` structure — bake it into the Workflow script's literal in Step 2.

## Step 2: Author and invoke the Workflow

Author a dynamic Workflow from the computed waves and invoke it via the **Workflow tool**. Items **within** a wave run in **parallel**, each in its own isolated worktree (`parallel({ isolation: 'worktree' })`); a **barrier** separates waves so a later wave never starts before every dependency it needs has landed. Group progress with `{ phase: \`Wave ${w} · Item #${n}\` }`.

### Per-item shape — OPUS PLANS, SONNET IMPLEMENTS (the default)

Each item runs as **two agents**, not one. Context passes between them **via the on-disk `.task/task/<item-slug>.md` artifact** — the first agent writes it, the second reads it fresh from disk — so there is no chat-context transfer to engineer:

```javascript
const slug  = "<roadmap-slug>";
const waves = [                                   // from Step 1 — dependency order
  [ { n: 1, title: "…", model: "sonnet" }, { n: 2, title: "…", model: "haiku" } ],
  [ { n: 3, title: "…", model: "opus"   } ],
  // …
];

async function runItem(n, title, model, w) {
  // 1) PLAN on a strong model — capture the item into .task/task/<item-slug>.md
  //    with ## Plan (Goal/Touches/Logic), following docs/contract.md's task.md
  //    format. This agent does NOT implement or commit.
  const plan = await agent(
    `Read skills/to-plan/SKILL.md and run it NON-INTERACTIVELY for roadmap item
     ${slug}#${n} ("${title}"). Draft .task/task/<item-slug>.md (Description +
     ## Plan, + ## Tests if the config Testing Policy calls for it), stamping
     the header with "Roadmap: ${slug}" and "Source item: #${n}", plus a
     "Spec: <spec-slug>" line for each spec the item cites (via its
     "### Spec references → <spec-slug> §N" entries or the roadmap's own
     "Spec:" headers). Read each referenced .task/spec/<spec-slug>.md first as
     a fixed technical anchor. Auto-accept every confirmation; make constructive
     assumptions; never block on a prompt. Do NOT implement or commit.
     Last non-empty line MUST be exactly:
       OK #${n} <item-slug> planned      (on success)
       FAIL #${n} <item-slug> <what failed>   (on failure)`,
    { model: "opus", phase: `Wave ${w} · Item #${n}` }
  );
  const planStatus = plan.trim().split("\n").filter(Boolean).pop();
  if (planStatus.startsWith("FAIL")) return planStatus;

  const itemSlug = planStatus.split(" ")[2];   // <item-slug>, echoed by the plan agent

  // 2) IMPLEMENT + VERIFY + REVIEW + COMMIT on the item's own model. Reads the
  //    task file fresh from disk — nothing crosses over from the planning
  //    agent's chat context.
  const r = await agent(
    `Implement .task/task/${itemSlug}.md. Follow its ## Execution block
     exactly: implement the ## Plan (or ## Description if no Plan), run
     /verify end-to-end, run /code-review on the diff and apply fixes only
     within the files named in Touches (report the rest), then commit per
     .task/config/config.md → Commit Format. Do NOT tick the roadmap
     checkbox yourself — the driver does that after this call returns OK.
     Make constructive assumptions; never block on a prompt.
     Last non-empty line MUST be exactly:
       OK #${n} ${itemSlug} <one-line summary>      (on success)
       FAIL #${n} ${itemSlug} <what failed>         (on failure)`,
    { model, phase: `Wave ${w} · Item #${n}` }
  );
  return r.trim().split("\n").filter(Boolean).pop();
}

for (const [w, items] of waves.entries()) {
  // Items in one wave are independent by construction (Step 1) — run them
  // together, each in its own worktree, so they never collide on the working tree.
  const results = await parallel(
    items.map(({ n, title, model }) => () => runItem(n, title, model, w + 1)),
    { isolation: "worktree" }
  );

  for (const [i, status] of results.entries()) {
    const { n } = items[i];
    console.log(status);                                  // per-item digest, printed as it lands
    if (status.startsWith("FAIL"))
      return `roadmap-to-workflow stopped in wave ${w + 1}, item #${n}: ${status}`;

    // AUTO-MARK is the DRIVER's job, done here — one write at a time, never
    // inside the (possibly parallel) per-item agents, so wave-mates never
    // race on the roadmap file.
    const itemSlug = status.split(" ")[2];
    markRoadmapItemDone(slug, n, itemSlug);   // flips "### - [ ] N." → "### - [x] N." in
                                               // .task/roadmap/<slug>.md with an inline
                                               // sed/awk edit keyed on item number N —
                                               // roadmap.sh has no flip helper (it exposes
                                               // only path/mtime/progress-count helpers)
  }
  // Barrier: do not start wave w+2 until every item in wave w+1 above is marked.
}
return "roadmap-to-workflow: all items shipped.";
```

**Graceful fallback:** if the Workflow tool isn't available in this environment, run the items one at a time by hand, respecting the same wave order: for each item, run `to-plan` for that roadmap item (writes `.task/task/<item-slug>.md`), then in a plain session say `implement .task/task/<item-slug>.md`, then manually tick its checkbox in `.task/roadmap/<slug>.md` before moving to the next.

## Output

- Per item: the returned digest line (`OK|FAIL #N <item-slug> <summary>`), printed as each wave lands.
- End with the canonical next-step footer (convention (a), flag-free):
  - All items shipped → `→ Done. Roadmap complete — \`.task/roadmap/<slug>.md\` fully checked.`
  - Stopped on a `FAIL` → surface the failing digest, then `→ Next: fix the item, then rerun \`roadmap-to-workflow\` — completed items stay checked, only the unchecked remainder reruns.`

## Forbidden

- Running setup / bootstrap on a missing `config.md` — this skill hard-stops and redirects; only `to-task` / `to-plan` / `to-roadmap` are intake-capable.
- Looping the items yourself in this session's main thread instead of authoring a Workflow — the Workflow tool is what gives per-item isolation, per-item model control, and safe parallelism; a hand-rolled loop reintroduces the accumulation and collision problems this skill exists to remove. (The one-at-a-time manual fallback is only for when the Workflow tool is unavailable.)
- Running items whose dependencies are still unchecked, or placing an item in an earlier wave than its `Dependencies` allow.
- Auto-marking roadmap checkboxes from inside a per-item agent — that is the driver's job, strictly after the agent returns `OK`, to avoid parallel writers racing on the roadmap file.
- Modifying project code yourself, or touching any file other than the roadmap (for scope reading) and, via the driver step, the roadmap's checkboxes — all implementation happens inside the per-item agents' own worktrees.
