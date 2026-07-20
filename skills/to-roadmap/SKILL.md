---
name: to-roadmap
description: 'Capture a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items.'
disable-model-invocation: true
user-invocable: true
---

Fix a **multi-task initiative** (phases, dependencies, or more than a couple of atomic steps) into `.task/roadmap/<slug>.md`. Multi-task counterpart to `/task:to-task` / `/task:to-plan` (which each fix one task). Depth is fixed: one roadmap file, flag-free.

**Input:** `$ARGUMENTS` — a rough description of the initiative, or a reference back to a prior discussion in this conversation ("build a roadmap from what we discussed").

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for the output structure. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`.

- **`config.md not found`** → `/task:to-roadmap` is intake-capable: run the inline setup gate exactly as `skills/to-task/SKILL.md` Step 0 does (detect stack → one `AskUserQuestion` confirmation, Accept / Edit / Decline chips → write `config.md` + `git config --local task.root` + exclude `.task`), then re-run `validate.sh all`. If config is now present → continue. If the user declined setup → report "`config.md` not written. → Next: run `/task:to-roadmap` again when ready" and **stop**.
- **Exit 1** (one or more *existing* artifacts fail validation) → surface the validator output, but **do not block**: those errors are pre-existing files, not the roadmap you're about to write (mirrors `to-task` Step 0 and `roadmap-to-workflow`, and `validate.sh` is advisory, never config-malformed — it doesn't inspect `config.md` content). Only a missing `config.md` (exit 2, handled above) hard-stops.

### Preconditions

- **Too small for a roadmap.** If the initiative has no obvious phases, no inter-task dependencies, and fewer than ~3 atomic steps → **stop and suggest** `/task:to-task` or `/task:to-plan` instead.

(The slug-collision check runs at save time, once the slug is derived — see Step 4.)

### Step 1: Load context

Issue these independent reads and listings as one parallel batch — none depends on another. Read `.task/config/config.md` (Language, conventions), `CLAUDE.md` if present, and list `.task/roadmap/*` — match existing structural style and declare any in-flight related roadmap as a Prerequisite. List the `docs/` top level and skim entry points if any exist. Do not open source files — this is a shallow scan, not investigation.

### Step 2: Cold start or harvest

**Branch first** — where the decisions come from matters:

- **Harvest** — the conversation, *before* this call, already settled concrete decisions about **this same initiative** (multiple exchanges, small details included). Tells: "build a roadmap from what we discussed", or `$ARGUMENTS` reads as a handle for prior discussion rather than a fresh idea. → Go to Step 2H.
- **Cold start** — a rough one-to-few-line description with no prior initiative-specific discussion. → Go to Step 2C.

On the fence, prefer harvest — a false positive costs one extra recap the user skims; a false negative silently drops details.

#### Step 2H: Harvest — Decision Inventory

Comb the prior conversation and print, as message text in your reply (chat-only, never written to a file; heading skeleton English, prose in config language):

```
## Roadmap — Decision Inventory

{Building this roadmap from our discussion — here is every decision I
captured; confirm nothing dropped.}

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

This inventory is a **recap** of decisions the user already reached in the discussion: print it, no confirmation chip. Then proceed — if open forks remain, resolve them first (a focused round as in Step 2C), then go to Step 3 (draft). If the recap misreads or drops something, the user says so in chat — correct it and reprint before drafting.

#### Step 2C: Cold start — brainstorm round

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

Always propose **2–3 decomposition options** with different phase boundaries (behavioral milestones — observable state changes — not technical layers like "substrate" vs "UI"). Iterate with the user (`Round N`, same structure, narrowed to the fork in focus). Typical depth 3–6 rounds; past 6, say the initiative is too big and suggest splitting. Stop when the user signals "write it" / "that's enough", or a new round would only restate prior conclusions.

**Track decisions as you go, not in your head.** Two kinds surface:

- **Behavioral decisions** — observable properties the user locked in (including small details). These land in an item's `### Outcomes` / `### Acceptance criteria`.
- **Technical anchors** — load-bearing technical decisions (a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation). These belong in a standalone spec, never in item bodies — route at draft time (Step 3).

Before drafting, reprint the full list (behavioral + anchors) **as message text** — the cold-start twin of Step 2H's inventory, a recap of the decisions the user reached across the rounds: print it, no confirmation chip. If a line is wrong, the user corrects it in chat before drafting.

Topics the user explicitly said to skip stay skipped — do not raise them again.

### Step 3: Draft the file

Once the decision list is confirmed, draft the full roadmap per [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd): title + intro, `## Prerequisites`, `## Phase summary` table, one `## Phase X` section per phase with `### - [ ] N. <title>` items (`**Dependencies:**`, optional `**Model:**`, `**Ready description:**` blockquote with `### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria`), `## Out of scope`, `## Backlinks`.

**Route every confirmed decision to a home:**

- Observable behavior / user-facing effect → the item's `### Outcomes`, or `### Acceptance criteria` when it's a testable assertion.
- Cross-item technical decision → a standalone spec. If a `.task/spec/<spec-slug>.md` already covers it, add a `Spec: <spec-slug>` header line to the roadmap (ASCII, above the title/intro) and cite it from each steered item as `### Spec references → <spec-slug> §N`. If no spec exists yet, **do not write one here** — surface the decision with a one-line recommendation to capture it via `/task:to-spec`, then reference it on a later run.
- Scope exclusion → `## Out of scope`, with the reason.
- Anything else → drop it, but say so to the user with a one-line reason — never a silent omission.

A local, single-item detail decision never goes in a spec — it belongs in that item's `### Outcomes` / `### Acceptance criteria`. Reserve specs for choices that would break cross-item consistency if a later `/task:to-plan` (or the executing session) re-derived them differently.

**`**Model:**` is optional** — set it only when you have a real basis to suggest one (e.g. the item is pure content/vocabulary editing → `haiku`; a new subsystem or cross-module change → `sonnet`; leave it off rather than guessing).

Behavioral discipline: `### Outcomes` / `### Goal` / `### Invariants` describe observable properties only — no project-specific file/symbol names (normative names from spec/CLAUDE.md are fine). If design work would be free to pick a different symbol, the name doesn't belong here — that's `/task:to-plan`'s call, not this file's.

Before saving, self-check and fix inline (drafting hygiene, distinct from Step 5's post-save pass):

1. Every fork raised in the brainstorm has a home in some phase, or an explicit `## Out of scope` mention.
2. Each `**Ready description:**` stands alone — a reader who hasn't seen the roadmap could pick it up in `/task:to-plan` from the blockquote alone.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`).
4. Every `**Dependencies:**` cites a task number that exists in this file.
5. Every item heading produces a unique kebab-case slug.
6. Every confirmed decision (Step 2) resolved to a concrete home — `### Outcomes`/`### Acceptance criteria`, `## Out of scope`, a spec `### Spec references → <spec-slug> §N` citation (or a decision flagged for a `/task:to-spec` follow-up) — or was explicitly dropped with a stated reason.

### Step 4: Save

Write the file directly — no in-chat preview, no confirmation prompt.

1. Slug: kebab-case from the initiative title, ≤ 50 chars (e.g. `add-auth-flow`, `migrate-to-vite`).
2. **Slug collision (soft).** Create `.task/roadmap/` if missing. If `.task/roadmap/<slug>.md` already exists → **stop** and pose an `AskUserQuestion` (**Overwrite** / **Pick different slug**). Never silently overwrite.
3. Write `.task/roadmap/<slug>.md` with the full content, including any `Spec: <spec-slug>` header lines for specs referenced in Step 3.
4. Modify no file other than `.task/roadmap/<slug>.md` (spec authorship is `to-spec`'s job — see Forbidden).
5. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — surface any WARN/ERROR in the Step 6 digest; only a config-precondition failure (exit 2) hard-stops.

### Step 5: Light self-check (report-only)

After Save, skim the just-saved file (not the in-chat draft) against three lenses yourself — **not** a subagent fanout, no lens-audit machinery.

- **Coverage** — phase/fork coverage, dependency integrity (dangling or cyclic `**Dependencies:**`).
- **Decomposition** — any item that reads as compound (spans ≥ 2 unrelated concerns, or has far more outcomes than the rest) and should be split.
- **Clarity** — behavioral discipline held, descriptions self-contained, every `### Spec references → <spec-slug> §N` citation names a `Spec:`-referenced `.task/spec/<spec-slug>.md` that actually contains that `§N`.

Report a compact findings summary — a count per lens plus the obvious issues, a few lines. **Never rewrite the saved file** — anything found here is surfaced for the user to fix by hand or discuss further in chat; there is no inline auto-apply and no `--refine` mode to escalate to.

### Step 6: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file:

```
Wrote `.task/roadmap/<slug>.md`
{Title}
Items: {N} tasks across {M} phases — recommended order: 1 → 2 → 4 → 3 → 5 …
- 1. {item title}
- 2. {…}
Specs referenced: {slug, …}   (or "none"; plus any decision flagged for a `/task:to-spec` follow-up)
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

- Print the Step 5 findings summary (or "clean / minor only").
- The file is already written — to change anything, just say so.
- End with the canonical next-step footer: `→ Next: \`/task:roadmap-to-workflow\`` (loop the whole roadmap) or `\`/task:to-task <slug>#1\`` (pick up the first item by hand — same for any other item number). Flag-free.

## Forbidden

- Naming project-specific files, modules, functions, types, or constants in `### Outcomes` / `### Goal` / `### Invariants` — normative names from spec/CLAUDE.md are the only exception.
- Planning implementation details (file lists with line numbers, function signatures, code blocks > 5 lines) — that is `/task:to-plan`'s job when the item is picked up.
- Modifying any file other than `.task/roadmap/<slug>.md` — specs live at `.task/spec/<slug>.md` and are authored only by `to-spec`, never written or edited here.
- Auto-checking / auto-unchecking item checkboxes — that is the `roadmap-to-workflow` **driver**'s exclusive job, never this skill's and never a per-item agent's.
- A single-direction monologue in a decomposition round — offer ≥ 2 options or explicitly justify why only one is viable. (The Decision Inventory and the cold-start recap are chat-only recaps, not decomposition rounds — exempt.)
- Generic risks ("watch out for bugs") — risks must be specific to the initiative and project.
- More than one initiative per file — split and pick one for this run.
- Persisting topics the user asked to skip; placeholders anywhere.
- Writing a `.refine.md` sidecar, a `.spec.md` sidecar, or a `.lock` file — none exists in v3.
