---
name: roadmap
description: 'Brainstorm a multi-item roadmap for a large initiative into `.task/roadmap/<slug>.md`, with task descriptions ready for `/task:design --from`. `--refine` runs a parallel three-lens audit over an existing roadmap.'
disable-model-invocation: true
user-invocable: true
---

Brainstorm a **multi-stage roadmap** for a large initiative — multi-phase, multi-task — and write it to `.task/roadmap/<slug>.md` with a phase-grouped table, dependencies, and **ready-to-paste task descriptions** that subsequent `/task:design --from` invocations consume. Multi-task counterpart to design's idea phase (which produces one task description).

**Input:** `$ARGUMENTS` — one of:

- Rough description of a multi-stage initiative → brainstorm mode (Steps 1–8 below).
- `--refine [<slug>]` → refine mode: parallel three-lens audit of an existing roadmap (Coverage / Decomposition / Clarity), bounded ≤2 iterations, sidecar findings in `.task/roadmap/<slug>.refine.md`. See [`phases/refine.md`](phases/refine.md).

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-c--shallow-scan) — no bash context script here; preconditions enforced inline. `/task:roadmap` is the primary Tier-C consumer of `docs/` (entry points like `docs/README.md`, `docs/spec/README.md`). Refine mode tier and read policy live in [`phases/refine.md`](phases/refine.md).

**Precondition (soft, brainstorm mode only) — slug collision.** If `.task/roadmap/` does not exist — create it. If a file with the proposed slug already exists — **stop and ask** whether to overwrite or pick a different slug. Never silently overwrite a roadmap. (Refine mode requires an existing roadmap — collision check is inverted: stop if the slug does not resolve to an existing file.)

**Precondition (interactive, brainstorm mode only) — too small for a roadmap.** If the initiative is small enough to be a single task (no obvious phases, no inter-task dependencies, < ~3 atomic steps) — **stop and suggest** design's idea phase instead. Roadmap overhead is wasted on small ideas.

**Language — bilingual by convention** (roadmap-specific override of Tier C): **structural labels stay English** regardless of `config.md` — file section headers (`## Prerequisites`, `## Phase summary`, `## Phase A — …`, `## Out of scope`, `## Backlinks`), table column names, per-task field labels (`**Size:**` / `**Class:**` / `**Dependencies:**` / `**Ready description:**`), the blockquote sub-headings (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / optional `### Contracts` / `### Acceptance criteria` / optional `### Spec references`), and brainstorm round headings (`## Roadmap Brainstorm — Round N`, `### Decomposition options`, `### My recommendation`, etc.) are parser contracts. **The optional spec sidecar `<slug>.spec.md` follows the same split** — its structural labels (`## N.` section headers, `**Decision:**` / `**Rationale:**` / `**Constrains:**`) stay English; the decision/rationale prose follows config language. **Content follows `config.md` → "Language"** — initiative title, task titles, prose (intros, body of `### Context`/`### Goal`/`### Outcomes`/`### Invariants`/`### Contracts`/AC/spec items, `## Out of scope` items, summary-table rationale, brainstorm proposal/recommendation/risk text). Normative names from spec/CLAUDE.md stay verbatim; **project-specific** file paths, type names, and function names do NOT belong in `### Outcomes` / `### Goal` / `### Invariants` / `### Contracts` (see "Forbidden" below) — they belong in `/task:design`'s blueprint phase.

## Instructions

### Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. If it exits with the `config.md not found` message, redirect the user to `/task:bootstrap` and stop — without `config.md` the roadmap cannot resolve the project's Language policy, which controls every prose field in the output file. The `all` subcommand tolerates a missing `.task-current` (which is the expected state when starting a new roadmap).

### Step 0a: Mode dispatch

Parse `$ARGUMENTS`. If it contains the literal token `--refine` (anywhere, with or without an accompanying slug), this is **refine mode**: read [`${CLAUDE_PLUGIN_ROOT}/skills/roadmap/phases/refine.md`](phases/refine.md) and follow its Steps R1–R7 verbatim, passing `$ARGUMENTS` through. Otherwise the rest of `## Instructions` (brainstorm mode) applies.

### Step 1: Load context

1. Read `.task/config/config.md` (Language, conventions, MCP priority) and `CLAUDE.md` if it exists.
2. List `.task/roadmap/*` — match the structural style of existing files; declare any in-flight related roadmap as a Prerequisite.
3. List `docs/` top level and read entry points (`docs/README.md`, `docs/spec/README.md`, `docs/architecture.md`). If `docs/spec/` has a typed architectural specification, read its index files (`README.md`, `00-overview.md` or equivalent) — reference these by section number from the roadmap.

### Step 2: Shallow structural scan

Build a coarse mental model of the initiative's surface in the project. Limit yourself to:

- Top-level directory listing (one or two levels deep).
- Manifest files for stack, key dependencies.
- The `docs/` and `.task/` content already loaded.

Do not open source files. Stop as soon as you can name: the stack, the top-level modules the initiative touches, the documented systems it builds on, the obvious extension points. If the scan starts to feel like investigation — stop; this is a roadmap, not a plan.

### Step 3: First brainstorm round (architect mode)

Output the first round in this format:

```
## Roadmap Brainstorm — Round 1

### Initiative as I understand it
{2–4 sentences restating the user's idea, including its scope ambition.}

### Project context (shallow)
- Stack: {language/framework}
- Documented systems touched: {modules, specs, doc files relevant to this initiative}
- Existing roadmaps in flight: {list of `.task/roadmap/*` if any, with one-line note on relevance}
- Notes from CLAUDE.md / config that constrain this initiative: {…}

### Decomposition options
**A) {Phase decomposition name}** — {1–2 sentence sketch of the phase split}
- Phases: {bullet list}
- Pros: {…}
- Cons / cost: {…}
- Fits when: {…}

**B) {Alternative decomposition}** — {1–2 sentence sketch}
- Phases: {bullet list}
- Pros: {…}
- Cons / cost: {…}
- Fits when: {…}

**C) {Optional third decomposition, only if meaningfully different}**

### My recommendation
{Which decomposition and why, in 2–4 sentences. Reference project context where it matters.}

### Risks and forks I want to flag
- {Risk / hidden dependency / non-obvious decision point}
- {…}

### What I need from you
{One focused question on the most load-bearing fork. Not "tell me more" — name the specific decision.}
```

Rules for this output:

- Always propose **2–3 decomposition options**, not one. Different decompositions = different phase boundaries, not just different orderings of the same phases.
- **Phase boundaries are behavioral milestones** (observable changes in system state, world, or user-facing effect), not technical layers (modules, files, classes). "Phase A — substrate" / "Phase B — UI" is a technical split; "Phase A — single agent has a full lifecycle" / "Phase B — multiple agents interact" is a behavioral split. Prefer the latter; it carries through to task-level outcomes more cleanly.
- The recommendation must be a **real opinion**, not a hedge.
- Risks must be **specific** to the initiative and project — not generic.
- Ask **one** focused question, or one heading with numbered sub-questions for tightly-coupled decisions.

### Step 4: Iterate

Wait for the user, then continue with `Round N` (same structure, narrowed to the fork in focus). Typical progression: phase boundaries → task decomposition → dependencies/scope boundaries → self-contained-description check. Stop when **any** holds: user says "fix it" / "write the roadmap" / "that's enough" / equivalent; you can write the full file (phases, tasks-per-phase, dependencies, ready descriptions covering Goal / Outcomes / Invariants / AC); or a new round would only restate prior conclusions. Typical depth **3–6 rounds**; past 6 means the initiative is too big — say so and suggest splitting.

**Track technical anchors as you iterate.** The behavioral discipline (below) strips project-specific implementation detail from the roadmap proper — but a brainstorm legitimately surfaces *load-bearing technical decisions* (a chosen protocol/algorithm, a cross-cutting data shape, a "we picked X over Y because…" with reasoning that would not survive re-derivation). Keep a running mental list of these. They do **not** go into the behavioral item bodies; they go into the optional spec sidecar (Step 5). In the **final** round, before writing, name the anchors you intend to pin in `<slug>.spec.md` so the user can confirm or correct them — this is the skill's own decision to create a spec, surfaced for sign-off, not a separate prompt. If no genuine anchors accumulated, say so and create no sidecar.

**Exception:** topics the user explicitly told you to skip or ignore stay skipped — do not raise them again and do not bake them into the file.

### Step 5: Draft the roadmap

Once iteration ends, draft the full file. The structure is fixed (the entire pipeline downstream depends on it). See "Output format" below.

**Derive `Size` and `Class` mechanically — never ask the user for either.** Both are computed while drafting, not deliberated:

- **`Size` is a function of `### Outcomes` bullet count.** After drafting each task's `### Outcomes`, count the bullets and set `**Size:**` to the matching token: `small` = 1–2, `medium` = 3–6, `large` = 7+. Never treat it as a free choice; the outcome count decides it. (If a count lands at ≥ 7 — or the outcomes span ≥ 2 unrelated domains — the item is compound; split it rather than labeling it `large`.)
- **`Class` is inferred from the task's shape** via this rubric, mapping to the existing closed list; the user is free to override it in-file:
  - refactor with no behavior change → `rote-refactor`
  - introduces a new subsystem / contract → `new-substrate`
  - moves or changes behavior across several modules → `cross-module-migration`
  - user-facing capability → `product-feature`
  - vocabulary / wording / content edits → `content-vocabulary`
  - pipeline / build / infra changes → `tooling`

  Pick the closest single token; when two fit, prefer the one describing the task's dominant effect. `Class` stays a best-effort hint (not validated) — the inference fills a sensible default, it does not lock the field.

**Then, if technical anchors accumulated (Step 4), draft the spec sidecar.** Compose `<slug>.spec.md` (format + boundary test in "Spec sidecar" under "Output contract" below) holding one numbered section per load-bearing decision, and add a `### Spec references` sub-heading citing `<slug>.spec.md §N` to each roadmap item that the decision steers. The sidecar captures the **why** that the behavioral item bodies cannot carry — not a full plan (that is per-task `plan.md`). **No anchors → no sidecar**; never write an empty or placeholder spec.

### Step 6: Self-review pass

Before saving, run a quick self-check (do not dispatch a subagent — this is a checklist you run yourself):

1. **Phase coverage:** Does every fork raised during the brainstorm have a home in some phase, or an explicit "what's not in this plan" mention?
2. **Description completeness:** Skim each task's `**Ready description:**` blockquote. Does it stand alone (a reader who has not seen the roadmap could write a design's blueprint phase from it)? Are `### Context`, `### Goal`, `### Outcomes`, `### Invariants`, `### Contracts` (when present), `### Acceptance criteria`, and `### Spec references` (when present) each concrete and self-contained? Context must answer "why this task, what it unblocks" — not restate Goal.
3. **Behavioral discipline:** `### Outcomes` / `### Goal` / `### Invariants` / `### Contracts` describe **observable properties of the system / world**, not implementation choices. They MUST NOT name project-specific files, modules, functions, types, or constants. Normative names from the project's spec or `CLAUDE.md` ARE allowed (they address shared concepts, not implementation choices). When in doubt, ask: "would design's blueprint be free to pick a different file or symbol name?" — if yes, the name doesn't belong in the roadmap.
4. **Sizing by outcomes count:** verify each computed `Size:` still matches its `### Outcomes` bullet count (Step 5 sets it; this catches a miscount, not a mislabel). `small` = 1–2 outcomes, `medium` = 3–6, `large` = 7+ — by count, not modules or files. If an item lists ≥ 7 outcomes or outcomes spanning ≥ 2 unrelated domains — split it.
5. **No placeholders:** Search the draft for `TBD`, `TODO`, `???`, `fill in`, `add appropriate ...`, `handle edge cases` — these are plan failures. Either fill them in or remove them.
6. **Dependency consistency:** Each task's `**Dependencies:**` line cites task numbers that exist elsewhere in the file. No dangling references.
7. **Slug uniqueness within file:** Each task heading produces a unique kebab-case slug (used by `/task:design --from <file>#<slug>`).
8. **Spec sidecar integrity (only if a sidecar was drafted):** every `<slug>.spec.md §N` cited by an item resolves to an existing `## N.` section in the sidecar; every sidecar section is referenced by at least one item (no orphan decisions); each section is a load-bearing *anchor* (passes the boundary test), not a per-task implementation plan; no placeholders inside the sidecar.

If you find issues — fix them inline before saving.

### Step 7: Save

Write the file directly — no in-chat preview, no confirmation prompt. The user reviews and edits in the file itself.

1. Determine slug for the filename: kebab-case from the initiative title, ≤ 50 chars. Examples: `add-auth-flow`, `social-need-and-memory-plan`, `migrate-to-vite`.
2. Write `.task/roadmap/<slug>.md` with the full content.
3. **If a spec sidecar was drafted (Step 5)**, write `.task/roadmap/<slug>.spec.md` (same slug). Skip entirely when no anchors accumulated.
4. **Do not** modify any other file.

### Step 8: Output

- Print the path to the created file. Tell the user to open it to review/edit.
- If a spec sidecar was written, print its path too and note that blueprint will read it for items carrying `### Spec references`.
- One-line summary: "*N* tasks across *M* phases. Recommended order: 1 → 2 → 4 → 3 → 5 …".
- End with the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)), naming the first task's `--from` command, where `<N>` is the recommended starting point: `→ Next: \`/task:design --from .task/roadmap/<slug>.md#<N>\``.

## Output contract

The roadmap file follows this structure exactly. Language policy: see the canonical paragraph at the top of this file — structural labels English, content config language. Downstream tooling (`/task:design --from`) parses the English labels.

```markdown
# Implementation roadmap: <initiative title in config language>

<1–2 paragraph context (in config language): what this is, why now, what
triggered the brainstorm. Set the stage for someone reading the file
in 6 months.>

## Summary

<Two-sentence summary of the initiative (in config language), the
absolute minimum a reader needs.>

## Prerequisites

<Bulleted list of preconditions outside this roadmap, in config
language. If none, write the equivalent of «None — this roadmap is
self-contained.» in the config language.>

- <Prerequisite 1>
- <Prerequisite 2>

## Phase summary

<Single table, one row per task. Phases group rows. Dependencies cite
task numbers from this file only. The TABLE HEADER is English; cell
contents (phase names, task titles, size labels) are in config language
EXCEPT size values, which are the fixed tokens `small` / `medium` / `large`.>

| # | Phase | Task | Size | Depends on |
|---|---|---|---|---|
| 1 | A. <Phase name> | <Task title> | small | — |
| 2 | A. <Phase name> | <Task title> | small | 1 |
| ... | ... | ... | ... | ... |

<Recommended execution order line, in config language. Example in
English:>
Recommended execution order: **1 → 2 → 4 → 3 → 5 → ...** <plus 1–2
sentence justification>.

<Per-task verification reminder, in config language. Use the project's own
format → lint → test commands from `config.md` (whatever the stack is).
Example shape:>
After each task: format → lint → test (the project-specific commands from
`config.md` → "Build and Tests"). Commit per task.

---

## Phase A — <Phase name>

<Optional 1–2 sentence phase intro in config language, if useful.>

### - [ ] 1. <Task title in config language>

**Size:** small / medium / large.
**Class:** rote-refactor | new-substrate | cross-module-migration | product-feature | content-vocabulary | tooling.
**Dependencies:** — / 1, 2, ...

**Ready description:**

> ### Context
> <1–3 sentences (config language) explaining why this task, what
> it unblocks. Answers "why now" — distinct from Goal, which is the
> target state.>
>
> ### Goal
> <1–3 sentences (config language). What state of the world this task
> achieves. Behavioral — no project file/symbol names.>
>
> ### Outcomes
> - <Observable property of the system / world after this task — what
>   a reader, user, or downstream developer would see / measure / grep.
>   NO project-specific file paths, type names, function names, or
>   constants. Normative names from spec or CLAUDE.md ARE allowed
>   (they address shared concepts, not implementation choices).>
> - <Outcome 2>
> - <...>
>
> ### Invariants
> <Expected for new items, but not enforced by `validate.sh` — existing
> items without it stay valid; the Clarity auditor flags absence where it matters.>
> - <Contract that must hold across the change — determinism, ordering,
>   capacity, idempotency, etc. Same naming rules as Outcomes.>
> - <Invariant 2>
> - <...>
>
> ### Contracts
> <Optional. Recommended for Class: new-substrate or cross-module-migration.
> One bullet per substrate boundary, in the form "X observes event Y and
> reacts Z" / "A reads state B before phase C". No symbol names — describe
> the shape of the contract, not the API.>
> - <Contract 1>
> - <...>
>
> ### Acceptance criteria
> - <Testable assertion 1, in config language>
> - <Testable assertion 2>
> - <...>
>
> ### Spec references
> - <`<slug>.spec.md §N` — which decision anchors this item, brief note in config language>
> - <`docs/spec/<file>.md` §X.Y — what aspect, brief note in config language>
> - <CLAUDE.md section, `.claude/rules/...` — if relevant>

### - [ ] 2. <Task title>

... (same structure)

---

## Phase B — <Phase name>

... (same structure)

---

## Out of scope

<Bulleted list (config language) of related work explicitly NOT in
this roadmap. Reference Known Gaps in spec if applicable.>

- <Item 1 with brief reason>
- <Item 2>

## Backlinks

<Bulleted list of paths/links. Path syntax stays as-is; surrounding
prose is in config language.>

- <Path to spec / docs / related roadmap, with one-line description>
- <CLAUDE.md, rules, etc.>
```

### Format notes

- **Checkboxes `- [ ]`** mean "not started"; `/task:ship` auto-marks `- [x]` via `close.sh:Step 1.5`. `/task:roadmap` and `/task:design --from` never flip them.
- **Task numbering** is global within the file (`1`, `2`, `3`, …), continuous across phases; table order mirrors file order. The `Recommended execution order` line gives the dependency-driven sequence (may differ from file order).
- **`**Ready description:**` is a blockquote** with H3 sub-headings (`### Context`, `### Goal`, `### Outcomes`, `### Invariants`, optional `### Contracts`, `### Acceptance criteria`, optional `### Spec references`) — `/task:design --from` strips `> ` and copies the body into `task.md` verbatim. Sub-headings stay English; their bodies follow config language. Renaming/translating breaks the parser and the validator.
- **`### Context` precedes `### Goal`** — propagates into `task.md` via `--from` so blueprint/audit can read the "why" without re-opening the roadmap. Context is motivation; Goal is target state.
- **Sizing is computed from `### Outcomes` bullet count** at author time (Step 5), not deliberated and not by file count or estimated hours: `small` = 1–2, `medium` = 3–6, `large` = 7+. An item with ≥ 7 outcomes — or outcomes spanning ≥ 2 unrelated domains — is compound; split it. A `Size:` label disagreeing with the count is drift from a hand-edit — the refine-phase decomposition auditor flags it.
- **`### Contracts` is optional** structurally. Recommended for `Class: new-substrate` or `Class: cross-module-migration` — substrate boundaries deserve to be pinned before blueprint picks a shape. Refine-phase clarity auditor surfaces a `missing contracts` finding (severity `med`) when those classes omit it.
- **`### Spec references`** — omit the entire heading if no relevant spec; never leave an empty heading. Reference specs by section number, not quoted text (quotes rot with spec edits). A reference may point at an external project spec (`docs/spec/<file>.md §X.Y`) or at this roadmap's own spec sidecar (`<slug>.spec.md §N`). The sidecar form is what design's blueprint phase reads to ground its plan in pre-agreed technical decisions.
- **`**Class:**` is a best-effort hint**, not a validated field. The skill infers a default from task shape at author time (Step 5 rubric), but the user may override it in-file. Empty / off-list values are tolerated by `validate.sh`, but downstream (`/task:design`'s `Implement-Model:` rubric, clarity auditor's missing-contracts check) reads it — leave it populated.

### Spec sidecar (`<slug>.spec.md`)

**Optional** companion to the roadmap, written in brainstorm mode only (Step 5) when the discussion produced load-bearing technical decisions. It is the pressure-release valve that lets the roadmap proper stay behavioral: the **why** behind a decision lives here instead of leaking project-specific names into `### Outcomes` / `### Goal`. Lifecycle is independent of `<slug>.md` and `<slug>.refine.md`; `/task:roadmap --refine` never touches it; `validate.sh` does not enforce it (the Clarity auditor flags dangling references).

Structure — one numbered section per decision; items reference sections by `§N`:

```markdown
# Spec: <initiative title>

> Companion to `<slug>.md`. KEY technical decisions surfaced during the
> roadmap brainstorm — anchors whose loss would distort the initiative if
> blueprint re-derived them freely. NOT a full implementation plan (per-task
> `plan.md` owns that). One numbered section per load-bearing decision; items
> reference sections by number via `### Spec references`.

## 1. <decision title>

**Decision:** <the load-bearing technical choice that was made>
**Rationale:** <why this and not the alternatives — the reasoning that would
otherwise evaporate with the brainstorm>
**Constrains:** <what this pins for blueprint, and explicitly what stays free>

## 2. <decision title>
...
```

**Boundary test — spec vs `plan.md` (the whole point; get this wrong and the spec degrades into a duplicate plan).** A decision belongs in the sidecar **iff both** hold: (a) blueprint, re-deriving freely, could plausibly pick something different; **and** (b) that divergence would break consistency *across items* or distort the initiative's intent. Excluded — these belong to per-task `plan.md`, not the spec: file layouts, function signatures, per-step lists, anything local to one item and easily re-derived. **`### Contracts` vs spec are complementary**: `### Contracts` keeps the *behavioral* shape of a boundary in the roadmap; the sidecar holds the *technical decision behind* it. Do not duplicate.

Language: structural labels (`## N.`, `**Decision:**`, `**Rationale:**`, `**Constrains:**`) English; decision/rationale prose follows `config.md` → "Language".

## Forbidden

- **Name project-specific files, modules, functions, types, or constants in `### Outcomes` / `### Goal` / `### Invariants` / `### Contracts`** — those names are design's blueprint choice, not roadmap's. Normative names from the project's spec or `CLAUDE.md` are permitted (they address shared concepts). Heuristic: if design's blueprint phase would be free to pick a different symbol or file, the name doesn't belong here.
- Plan implementation details (per-task file lists with line numbers, function signatures, code blocks > 5 lines) — that belongs to design's blueprint.
- Modify any file other than `.task/roadmap/<slug>.md`, (brainstorm mode, optional) the spec sidecar `.task/roadmap/<slug>.spec.md`, and (refine mode only) the sidecar `.task/roadmap/<slug>.refine.md`.
- Auto-check / auto-uncheck task checkboxes (brainstorm creates new files; refine rewrites item bodies but never flips `- [ ]` → `- [x]` — that is `/task:ship`'s exclusive responsibility).
- Single-direction monologue (brainstorm) — every round must offer ≥ 2 decomposition options or explicitly justify why only one is viable.
- Generic risks ("watch out for bugs", "consider edge cases") — risks must be specific to the initiative and project.
- Multi-initiative roadmap — one initiative per file; if the idea spans unrelated initiatives, split and pick one for this run.
- Persist topics the user explicitly asked to skip; placeholders (`TBD`, `TODO`, `fill in`, `???`) anywhere.

Refine-mode forbiddens live in [`phases/refine.md`](phases/refine.md).
