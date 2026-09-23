---
name: to-architecture
description: 'Capture an initiative''s technical shape into a roadmap''s `## Architecture` section — components, interfaces between items, per-item sketches — writing the roadmap too when none exists.'
argument-hint: '[<roadmap-slug> | initiative]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Fix an initiative's **technical shape** — which components it builds or changes, what crosses between items, a module-level sketch per item, the technical ordering — into the `## Architecture` section of `.task/roadmap/<slug>.md`. The roadmap's items stay behavioral; a spec pins decisions with rationale; this section is the layer between them, the one a component map would otherwise leak into a spec from. Initiative-level counterpart to `to-plan`: as `to-plan` adds `## Plan` to a task, this adds `## Architecture` to a roadmap, and writes the roadmap itself when none exists yet. Planners — `to-plan` on an item, and `roadmap-to-workflow`'s per-item plan agent — follow it as the intended shape.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- `<roadmap-slug>` or a path to an existing `.task/roadmap/<slug>.md` — add the section to that roadmap, or revise the one it has.
- (empty) — the roadmap this conversation is clearly about, or a fresh capture from the discussion (see Step 1).
- anything else — a rough description of the initiative, or a reference back to a prior discussion ("capture the architecture we settled").

**Format contract:** [docs/contract.md § Roadmap architecture section](../../docs/contract.md#roadmap-architecture-section) owns the section's shape, and [§ Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) the file around it. This file describes the authoring flow.

## Instructions

### Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" architecture`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root: `.task/roadmap/<slug>.md` below means `$AI_DIR/roadmap/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent`** → this skill is intake-capable: read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template — then continue. No confirmation chip; a wrong detected value is fixed by editing the file.
3. **`CONFIG: present`** → leave the file untouched: it is user-owned, and only a missing `.task/.gitignore` is recreated, by the preflight above itself; `task.root` is written by first-run setup and not restored afterwards.
4. `ROADMAPS:` lists the roadmaps that already exist, with progress — Step 1 resolves its target against it, and a fresh capture's slug-collision check reads the same list. `SPECS:` lists the specs Step 2 may cite.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

There is no full-scan validate call here: Step 5 validates the one file it writes, and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

### Step 1: Resolve the target and mode

Take the **first** case that matches:

1. `$ARGUMENTS` holds a `ROADMAPS:` slug, or a path to a roadmap file → that roadmap is the target: **enrich** when it has no `## Architecture` yet, **revise** when it has one.
2. No positional reference, but this conversation is clearly about one existing roadmap — it was just captured with `/task:to-roadmap`, or the user names it by title or slug → that roadmap, enrich or revise as above. More than one plausible match → ask via `AskUserQuestion` (convention (c)) rather than guessing.
3. Nothing matches → **fresh**: there is no roadmap yet. Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-capture.md` and follow its `## Core` — the too-small precondition, then steps 1–5 — with Step 0's `AI_DIR:` and `ROADMAPS:` as its inputs and **this skill as the caller**: technical shape surfacing in its decision routing is carried into this run's section, not recommended as a follow-up. When its slug-collision chip fires, it offers **Enrich existing** too; that answer switches this run to enrich (or revise) on the existing file. When the precondition stops the run as too small, nothing is written and the too-small message is the whole output — one task's technical shape is `/task:to-plan`'s `## Plan`. Otherwise, once Core has written and validated the file, continue at Step 2 on it; Core's self-check findings go into the Step 6 digest.

**Stop — nothing left to plan.** If the target's `ROADMAPS:` line reads `unchecked=none`, every item is already checked off and no planner will read a new section: stop without writing. `→ Next: \`/task:to-roadmap\` to capture the next initiative, or describe new work in chat.`

**Hard stop — a roadmap run in progress.** If the user says a `/task:roadmap-to-workflow` run is active on the target, stop without writing: its mark stage rewrites the file and would drop this edit, and its waves were computed at launch, so an added dependency would not apply anyway. `→ Next: \`/task:to-architecture <slug>\` once the run has finished.`

### Step 2: Load the technical context

One parallel batch where the reads are independent:

- The target roadmap, in full — its intro, `Spec:` headers, phases, every item's ready description, and the existing `## Architecture` in revise mode.
- `bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-items.sh" <slug>` — number, dependencies and title for each **unchecked** item, plus a `DONE` line listing the already-ticked numbers (their dependencies and titles come from the full roadmap read above); the sketches and the ordering key on these numbers.
- Every spec the roadmap's `Spec:` headers name, plus any from `SPECS:` the discussion leaned on. Their decisions are **fixed anchors**: the section may cite them and must never contradict them.
- `.task/CLAUDE.md` with a **file-read tool** — Language, and Code Navigation if declared — and the project's `CLAUDE.md` if present.

Then read the code **at module level**, in ascending cost per `.task/CLAUDE.md` → Code Navigation: the structural overview of the areas the items imply, then the boundaries between them — public entry points, existing interfaces, where a new component would attach. **Stop as soon as every component can be named with its real module path** and every interface placed; symbol bodies and file-level detail are the planner's job when an item is picked up.

### Step 3: Harvest, cold start or revise

**Branch first**, since the section is written from technical shape settled somewhere:

- **Harvest** — this conversation already settled the initiative's technical shape: components, boundaries, what one item hands another. Tells: "capture the architecture we settled", a fresh capture whose discussion already went technical. → 3H.
- **Cold start** — the items exist, the technical shape does not. → 3C.
- **Revise** — the target has an `## Architecture`: it is the baseline, and 3H or 3C runs as a delta against it.

On the fence, prefer harvest: a false positive costs one recap the user skims, a false negative silently drops a settled boundary.

#### 3H: Harvest — Architecture Inventory

Comb the prior conversation and print, as message text in your reply (chat-only, never written to a file; heading skeleton English, prose in the language from `.task/CLAUDE.md`):

```
## Architecture — Inventory

{Writing the architecture from our discussion — here is every piece of
technical shape I captured. Say so if a line is wrong.}

### Components
- `{name}` — {new | existing} · `{module path}` — {role}

### Interfaces between items
- #{N} → #{M} — `{name}`: {what crosses}

### Item sketches
- #{N} — {module-level sketch}

### Technical ordering
- #{N} before #{M} — {reason}

### Open forks (not yet decided)
- {unresolved technical question}

### Coverage caveat
{Only if part of the discussion is out of context. Omit otherwise.}
```

In **revise**, mark each line against the baseline — `+` added, `~` changed, `−` removed — and list every removed line explicitly: `.task/` is git-excluded, so a line dropped here is not recoverable from history.

It is a **recap**, printed without a confirmation chip. Open forks left → resolve them in one 3C round first, then draft. A misread arrives as chat: correct it and reprint before drafting.

#### 3C: Cold start — architecture round

For each load-bearing fork of the technical shape — where a component's boundary falls, which item introduces a shared interface, whether an existing module is extended or a new one added — lay out the real options:

```
## Architecture — Round 1

### Shape as I understand it
{2–4 sentences: what gets built, over which existing modules.}

### Fork: {the boundary or placement to decide}
**A) {option}** — {sketch}. Pros / Cons: {…}
**B) {alternative}** — {sketch}. Pros / Cons: {…}

### My recommendation
{a real opinion, not a hedge}

### What I need from you
{One focused question on the most load-bearing fork.}
```

Two options per fork at least, or a stated reason why only one is viable. A round is **content dialogue, not a path fork**: print it as message text and close on the open question, because convention (c)'s chips would flatten the pros and cons the round exists to show. Iterate as `Round N` until the shape is settled, then reprint the full inventory in 3H's shape as a recap — no confirmation chip. Topics the user said to skip stay skipped.

### Step 4: Draft the section

Once the inventory is **printed** — no reply is awaited; a correction arrives as chat, and you reprint before drafting — draft `## Architecture` per [contract § Roadmap architecture section](../../docs/contract.md#roadmap-architecture-section): the intro blockquote, `### Components` (required), `### Interfaces between items` (omit when none), `### Item sketches` (one bullet per **unchecked** item; a shipped item may keep or drop its bullet), `### Technical ordering` (omit when none).

**Route what surfaces:**

- A component, a boundary, what crosses between items, a module-level sketch → this section. Real module paths and symbol names are expected here.
- A choice whose **reasoning** must survive re-derivation — "X over Y because…", a protocol, a shared data shape's exact form → a spec. One that exists is cited inline as `[<slug>](../spec/<slug>.md) §N`; one that does not is not written here — recommend `/task:to-spec` in the digest and cite it on a later run.
- A technical ordering constraint → a `### Technical ordering` line **and** the dependent item's `**Dependencies:**` (Step 5), since that field is what the driver's waves read.
- Observable behavior → it already lives in the items; restating it here is the drift this section exists to end. Drop it.

Before saving, self-check and fix inline:

1. Every `#N` names an item heading in this file.
2. Every unchecked item has exactly one `### Item sketches` bullet.
3. Nothing contradicts a cited or header-named spec.
4. Every `### Technical ordering` line is reflected in the dependent item's `**Dependencies:**`, after Step 5's additions, with no cycle — dependencies point at earlier-running items only.
5. No `### <digits>.` sub-heading and no copy of a `### - [ ] N.` item heading — items are referenced as `#N` inside bullets.
6. No `file:line`, no step list, no code block over 5 lines — plan-level detail is the planner's.
7. No placeholders (`TBD`, `TODO`, `???`, `fill in`).

### Step 5: Save

Edit the roadmap in place — no in-chat preview, no confirmation prompt; Step 3's inventory was the review. Three edits, and nothing else in the file changes:

1. **The section.** Enrich: insert it directly above the first `## Phase <N> — …` heading (after `## Phase summary`); in a file without numbered phases, above the `## ` section holding the first item. Revise: replace everything from `## Architecture` up to the next `## ` heading.
2. **Dependencies**, for each `### Technical ordering` line whose dependency is missing — on **unchecked** target items only, **adding, never removing**. A no-dependency value (`—`, `-`, `none`, `n/a`, or an empty value) is **replaced** by the list — appending to an empty one would leave `, <N>`, which `validate.sh` rejects; an existing list gains `, <N>`; ASCII digits, comma-separated. An item with no `**Dependencies:**` line gets one, directly above its `**Model:**` line, or above `**Ready description:**` when there is no model hint.
3. **`Spec:` headers**, for each spec the section cites that the roadmap's header does not name yet: add `Spec: [<slug>](../spec/<slug>.md)` directly under `# <Title>`, beside any existing ones. A spec reaches the driver's plan agents only through those header lines, so a citation without one would be invisible to them.

Then validate: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — surface any WARN/ERROR in the Step 6 digest; only a setup-precondition failure (exit 2) hard-stops.

### Step 6: Output — digest

Print the structural digest (convention (b)) as message text — enough for the user to judge at a glance whether to open the file:

```
Wrote `.task/roadmap/<slug>.md`  ({fresh | enrich | revise})
{Title}
Items: {N} tasks across {M} phases — recommended order: 1 → 2 → 4 → 3 …   (fresh only)
Architecture: {C} components, {I} interfaces, {S} item sketches
- `{component}` — {new | existing}, {role in a few words}
Interfaces: {#2 → #4, #5 `Name`; … | none}
Dependencies added: {#6 ← 3; … | none}
Spec headers added: {slug, … | none}
Specs referenced: {slug, … | none}   (plus any decision flagged for a `/task:to-spec` follow-up)
Stale dependencies: {#6 ← 2 — no ordering line backs it any more; remove by hand if obsolete}   (revise only; omit when none)
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

- One line per component: the component map is what a later planner follows, so this is the user's one glance to catch a misplaced boundary.
- On a result that is **not** clean, append `re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — `validate` is not a slash command, so it is worth spelling out. Omit it on a clean result.
- Fresh only: print the roadmap self-check findings from `roadmap-capture.md` Core step 5 (or "clean / minor only").
- The file is already written — to change anything, just say so.
- End with the next-step footer, naming the slug in **both** halves so either is pasteable as-is: `→ Next: \`/task:roadmap-to-workflow <slug>\` (run it — every item's planner now follows this architecture) or \`/task:to-plan <slug>#1\` (plan one item by hand — any item number works).`

## Forbidden

- Anything the contract's section rules exclude: a `### <digits>.` sub-heading, a copied item heading, `file:line` references, step lists, code blocks over 5 lines.
- Editing the roadmap beyond the three Step 5 edits — no item titles, ready descriptions, `**Model:**` hints or phases; above all no checkbox, which only the executing session or the driver's mark stage ticks.
- Removing a dependency, or adding one to a checked item.
- Writing or editing a spec — spec authorship is `to-spec`'s; this skill only cites and wires the header.
- Restating the items' behavioral outcomes as architecture.
- A single-direction monologue in a round — offer ≥ 2 options or explicitly justify why only one is viable. (The inventory and its recap are chat-only recaps — exempt.)
- More than one `## Architecture` section in a file.
- In fresh mode, everything in `roadmap-capture.md` § **Forbidden** too.
- Placeholders anywhere; persisting topics the user asked to skip.
