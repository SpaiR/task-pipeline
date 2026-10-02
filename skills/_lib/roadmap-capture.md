# Capture a roadmap

The roadmap capture flow, in one place. `to-roadmap` owns its Step 0 setup gate and its digest; everything between — context, the decomposition, the technical context, the architecture, the draft, the save and the post-save self-check — is `## Core` below, and `to-roadmap` Steps 1–7 point here. Every roadmap it writes carries its `## Architecture` section, drafted in the same pass and written in the same single write. [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the artifact shape it produces, and [§ Roadmap architecture section](../../docs/contract.md#roadmap-architecture-section) the section's.

**From the caller:** Step 0's `AI_DIR:` (every `.task/roadmap/<slug>.md` below means `$AI_DIR/roadmap/<slug>.md`, never a cwd-relative path), its `ROADMAPS:` list, which step 1 reads for structural style and step 6 for the slug collision, and its `SPECS:` list, which steps 3 and 5 may cite — none needs a listing call of its own. The digest printed after step 7 is the caller's.

## Core

### 1. Load context

One parallel batch, since none of these depends on another: `.task/CLAUDE.md` with a **file-read tool** (Language, Code Navigation if declared, conventions), the project's `CLAUDE.md` if present, and the `docs/` top level. Structural style comes from the caller's `ROADMAPS:` list — open one only when this initiative may overlap it, and declare that one as a Prerequisite. No source files yet: the decomposition stays behavioral, and step 3 reads the code once the items are fixed.

### 2. Decomposition — cold start or harvest

**Branch first** — where the decisions come from matters:

- **Harvest** — this conversation already settled concrete decisions about **this same initiative**, small details included. Tells: "build a roadmap from what we discussed", or `$ARGUMENTS` reading as a handle for prior discussion. → 2H.
- **Cold start** — a rough few-line description, no prior initiative-specific discussion. → 2C.

On the fence, prefer harvest: a false positive costs one recap the user skims, a false negative silently drops details.

#### 2H. Harvest — Decision Inventory

Comb the prior conversation and print, as message text in your reply (chat-only, never written to a file; heading skeleton English, prose in the language from `.task/CLAUDE.md`):

```
## Roadmap — Decision Inventory

{Building this roadmap from our discussion — here is every decision I
captured. Say so if a line is wrong.}

### Decisions locked so far
1. {one locked decision at full specificity — small details included
   verbatim, e.g. "the button is first in the panel"}
2. {...}

### Open forks (not yet decided)
- {unresolved question left by the discussion}

### Coverage caveat
{Only if part of the discussion is out of context — a false alarm
erodes trust. Omit the heading otherwise.}
```

It is a **recap** of decisions the user already reached: print it, no confirmation chip. Open forks left → resolve them in one focused round (2C's shape) first, then move on. A misread arrives as chat: correct it and reprint before moving on.

#### 2C. Cold start — brainstorm round

```
## Roadmap — Round 1

### Initiative as I understand it
{2–4 sentences, including scope ambition.}

### Decomposition options
**A) {name}** — {sketch}
- Phases: {...}
- Pros / Cons: {...}
- Fits when: {...}

**B) {alternative}** — {sketch}
...

### My recommendation
{2–4 sentences, a real opinion, not a hedge.}

### Risks and forks I want to flag
- {specific to this initiative — not generic}

### What I need from you
{One focused question on the most load-bearing fork.}
```

Always **2–3 decomposition options** with different phase boundaries — behavioral milestones, observable state changes, not technical layers like "substrate" vs "UI". Iterate as `Round N`, same structure, narrowed to the fork in focus. A round is **content dialogue, not a path fork**: print it as message text and close on the open question, because convention (c)'s chips would flatten the pros and cons the round exists to show. Typical depth 3–6 rounds; past 6, say the initiative is too big and suggest splitting. Stop when the user says "write it", or when another round would only restate conclusions.

**Track decisions as you go, not in your head.** Three kinds surface: **behavioral** ones, observable properties the user locked in, which land in an item's `**Outcomes**` / `**Acceptance criteria**`; **technical anchors** — a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning would not survive re-derivation — which belong in a standalone spec, never in an item body; and **technical shape** — which components the initiative builds or changes, what one item hands another — which is neither, and is held for step 4's `## Architecture`. Step 5 routes all three.

Before moving on, reprint the full list as message text — the cold-start twin of 2H's inventory, no confirmation chip. Topics the user said to skip stay skipped.

The decomposition is now fixed: the items, their numbers, their phases. Steps 3 and 4 key on those numbers; a later change to the item list means redoing them for the items it touched.

### 3. Load the technical context

One parallel batch where the reads are independent:

- Every spec from `SPECS:` the discussion leaned on, and any already slated for a `Spec:` header. Their decisions are **fixed anchors**: the architecture may cite them and must never contradict them.
- The code **at module level**, in ascending cost per `.task/CLAUDE.md` → Code Navigation: the structural overview of the areas the items imply, then the boundaries between them — public entry points, existing interfaces, where a new component would attach.

**Stop as soon as every component can be named with its real module path** and every interface placed; symbol bodies and file-level detail are the planner's job when an item is picked up. For a greenfield initiative with no code yet, every component is `new` and the paths are the ones the discussion or the project's conventions imply.

### 4. Architecture — harvest or cold start

**Branch first**, since the section is written from technical shape settled somewhere:

- **Harvest** — the conversation, or the decomposition, already settled the initiative's technical shape: components, boundaries, what one item hands another. Tells: "capture the roadmap with its architecture", a discussion that already went technical. → 4H.
- **Cold start** — the items exist, the technical shape does not. → 4C.

On the fence, prefer harvest: a false positive costs one recap the user skims, a false negative silently drops a settled boundary.

#### 4H. Harvest — Architecture Inventory

Comb the conversation and step 3's reading, and print, as message text in your reply (chat-only; heading skeleton English, prose in the language from `.task/CLAUDE.md`):

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

It is a **recap**, printed without a confirmation chip. Open forks left → resolve them in one 4C round first, then draft. A misread arrives as chat: correct it and reprint before drafting.

#### 4C. Cold start — architecture round

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

Two options per fork at least, or a stated reason why only one is viable. Like 2C's rounds, it is content dialogue, printed as message text and closed on the open question. Iterate as `Round N` until the shape is settled, then reprint the full inventory in 4H's shape as a recap — no confirmation chip. Topics the user said to skip stay skipped.

### 5. Draft the file

Once the architecture inventory is **printed** — no reply is awaited; a correction arrives as chat, and you reprint before drafting — draft the whole file per [contract § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd), which owns the section skeleton, the item grammar and the link rules. `## Architecture` is part of this draft, per [§ Roadmap architecture section](../../docs/contract.md#roadmap-architecture-section): directly above the first `## Phase <N> — …` heading (after `## Phase summary`) — in a file without numbered phases, above the `## ` section holding the first item — with the intro blockquote, `### Components` (required), `### Interfaces between items` (omit when none), `### Item sketches` (one bullet per item), `### Technical ordering` (omit when none).

Things it is easy to get wrong:

- The item heading is `### N. <title>`, and the first line under it is the status line `- [ ] Done`. The checkbox never goes into the heading: a Markdown preview renders it there as literal text.
- `**Dependencies:**` is an em dash `—` for none, otherwise a comma-separated list of item numbers, ASCII digits. Any other word reads as a dependency on a missing item and hard-stops the autopilot. When a technical ordering line gives an item its first dependency, the em dash is **replaced** by the number, never appended to — `—, 3` is unparsable.
- A `**Ready description:**` blockquote must stand alone, and its sub-headings are **quoted bold lines** (`> **Context**`, …), never headings. `validate.sh` treats a missing or unquoted one as a hard error, because `to-task` and the driver's plan agent strip the `> ` prefix to find the body. The item's spec citation, `> **Spec references:** [<spec-slug>](../spec/<spec-slug>.md) §N`, closes the same quote.
- **A blank line between blocks.** The status line, each `**Field:**`, each `Spec:` header line, and each quoted sub-heading (with a bare `>` line before and after it) is its own paragraph. Adjacent lines merge into one paragraph in a Markdown preview.

**Route every confirmed decision to a home:**

- Observable behavior / user-facing effect → the item's `**Outcomes**`, or `**Acceptance criteria**` when it's a testable assertion.
- Cross-item technical decision → a standalone spec. One that already exists gets a `Spec:` header line **directly under `# <Title>`**, above the intro, plus a `> **Spec references:** [<spec-slug>](../spec/<spec-slug>.md) §N` citation in each steered item; the architecture cites it inline as `[<slug>](../spec/<slug>.md) §N`. A spec reaches the driver's plan agents only through those header lines, so every spec the architecture cites gets one too. One that does not exist is **not written here**: surface the decision with a one-line recommendation to capture it via `/task:to-spec`; once the spec exists, the user adds `Spec: [<slug>](../spec/<slug>.md)` directly under the roadmap's `# <Title>` by hand, as `to-spec`'s footer says — this flow never edits an existing roadmap.
- Technical shape — a component, a boundary, what crosses between items, a module-level sketch → `## Architecture`, never an item body. Real module paths and symbol names are expected there.
- A technical ordering constraint → a `### Technical ordering` line **and** the dependent item's `**Dependencies:**`, since that field is what the driver's waves read.
- Scope exclusion → `## Out of scope`, with the reason.
- Anything else → drop it, but say so to the user with a one-line reason — never a silent omission.

Reserve specs for choices that would break cross-item consistency if a later `/task:to-task` re-derived them differently. A single-item detail is that item's `**Outcomes**` / `**Acceptance criteria**`, never a spec. Observable behavior already lives in the items; restating it in `## Architecture` is drift — drop it there.

**`**Model:**` is optional** — only with a real basis: pure content editing → `haiku`, a new subsystem or cross-module change → `sonnet`. Leave it off rather than guess.

Behavioral discipline: `**Outcomes**` / `**Goal**` / `**Invariants**` state observable properties only, with no project-specific file or symbol names (normative names from a spec or `CLAUDE.md` are fine). The names belong in `## Architecture`; if design work would be free to pick a different symbol, the name is `/task:to-task`'s call, not this file's.

Before saving, self-check and fix inline (drafting hygiene; step 7 is the post-save pass):

1. Every fork raised in the brainstorm has a home in some phase, or an explicit `## Out of scope` mention.
2. Each `**Ready description:**` stands alone — a reader who hasn't seen the roadmap could pick it up in `/task:to-task` from the blockquote alone.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`) anywhere.
4. Every `**Dependencies:**` cites a task number that exists in this file, and every `### Technical ordering` line is reflected in the dependent item's `**Dependencies:**`, with no cycle — dependencies point at earlier-running items only.
5. Every item heading produces a unique kebab-case slug.
6. Item numbers unique across the whole file — the reviewer's auto-mark keys on the number, so two items sharing one would be ticked together.
7. Every confirmed decision (step 2) and every piece of technical shape (step 4) has a concrete home, or was explicitly dropped with a stated reason.
8. Every cross-artifact reference is a Markdown link — `Spec:` headers, `**Spec references:**` citations, `## Prerequisites`, `## Backlinks`, the architecture's inline spec citations.
9. Every `#N` in `## Architecture` names an item heading in this file, and every item has exactly one `### Item sketches` bullet.
10. Nothing in `## Architecture` contradicts a cited or header-named spec.
11. No `### <digits>.` sub-heading and no copy of a `### N.` item heading inside `## Architecture` — items are referenced as `#N` inside bullets.
12. No `file:line`, no step list, no code block over 5 lines in `## Architecture` — plan-level detail is the planner's.
13. Every item heading has its `- [ ] Done` status line as the first line under it, and no two blocks — status line, fields, `Spec:` header lines, quoted sub-headings — sit on adjacent lines.

### 6. Save

Write the file directly — no in-chat preview, no confirmation prompt.

1. Slug: kebab-case from the initiative title, ≤ 50 chars (`add-auth-flow`, `migrate-to-vite`), in English whatever `.task/CLAUDE.md` → Language says — it is a filename, a parser-stable string.
2. **Slug collision.** If that slug is already in the caller's `ROADMAPS:` list → **stop** and pose an `AskUserQuestion` (**Pick different slug** *(Recommended)* / **Overwrite**). Say first, as message text, what an overwrite destroys — the existing file's items and progress, and its `## Architecture` if it has one — since `.task/` is ignored by its own `.task/.gitignore` and never committed, so none of it is recoverable. Never silently overwrite. That list is a snapshot taken before the brainstorm rounds, and unlike the task captures there is no writer script to refuse a collision here — so when the slug is *absent* from it, confirm with a file read that nothing is there before writing.
3. Write `$AI_DIR/roadmap/<slug>.md` (creating the directory if needed) with the full content, `Spec:` headers and `## Architecture` included — one write. Nothing else is written — spec authorship is `to-spec`'s. If the write fails (unwritable `.task/roadmap`, full disk), report the failure plainly, skip the caller's digest — it would name a path that does not exist — and close with `→ Next: fix the write failure (permissions or free space under \`$AI_DIR\`), then rerun \`/task:to-roadmap\`.` Stop there; there is nothing to validate.
4. Validate it: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — surface any WARN/ERROR in the caller's digest; only a setup-precondition failure (exit 2) hard-stops. Report it and close with `→ Next: rerun \`/task:to-roadmap\` — its setup writes \`.task/CLAUDE.md\` first.`

### 7. Light self-check (report-only)

Skim the **saved file** (not the in-chat draft) yourself — no subagent fanout, no lens-audit machinery — against four lenses:

- **Coverage** — phase and fork coverage, dependency integrity (dangling or cyclic).
- **Decomposition** — any item reading as compound: two unrelated concerns, or far more outcomes than its neighbours.
- **Clarity** — behavioral discipline held, descriptions self-contained, and each `**Spec references:**` citation naming a `Spec:`-referenced `$AI_DIR/spec/<spec-slug>.md` that really has that `§N`, with a target matching its label (a copied citation pointing at the previous spec still resolves for an agent and misleads the human).
- **Architecture** — every item has its sketch, every interface names two real items, and each component carries a module path a planner can open.

Report a count per lens plus the obvious issues, a few lines, in the caller's digest. **Never rewrite the saved file** — findings are for the user to fix or discuss; there is no auto-apply.

## Forbidden

Binding on every roadmap this flow writes:

- Naming project-specific files, modules, functions, types, or constants in `**Outcomes**` / `**Goal**` / `**Invariants**` — normative names from spec/CLAUDE.md are the only exception; the real names live in `## Architecture`.
- Planning implementation details — in the items: file lists, function signatures, code blocks > 5 lines; in `## Architecture`, where real module paths and symbol names are expected: `file:line` references, step lists, code blocks > 5 lines. That depth is `/task:to-task`'s job when the item is picked up.
- Modifying any file other than `.task/roadmap/<slug>.md` — specs live at `.task/spec/<slug>.md` and are authored only by `to-spec`, never written or edited here.
- Editing an existing roadmap in place — this flow only writes new files; an existing one is overwritten only through step 6's chip.
- Auto-checking / auto-unchecking item checkboxes — ticking `- [x]` is `task:code-reviewer`'s last phase, once its review of the item passes, never here and never inside a plan or implement agent.
- A single-direction monologue in a decomposition or architecture round — offer ≥ 2 options or explicitly justify why only one is viable. (The inventories and the cold-start recaps are chat-only recaps, not rounds — exempt.)
- Restating the items' behavioral outcomes as architecture.
- Generic risks ("watch out for bugs") — risks must be specific to the initiative and project.
- More than one initiative per file — split and pick one for this run. More than one `## Architecture` section in a file.
- Persisting topics the user asked to skip; placeholders anywhere.
