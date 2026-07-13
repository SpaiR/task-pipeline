---
name: to-roadmap
description: 'Capture a multi-task initiative discussed in chat into `.task/roadmap/<slug>.md` (+ optional `<slug>.spec.md` sidecar) — a phase-grouped backlog of ready-to-pick-up items for `/task:to-task` / `/task:to-plan`, or for `/task:roadmap-to-workflow` to loop end to end.'
disable-model-invocation: true
user-invocable: true
---

Fix a **multi-task initiative** — something with phases, dependencies, or more than a couple of atomic steps — into `.task/roadmap/<slug>.md`. Multi-task counterpart to `/task:to-task` / `/task:to-plan` (which each fix one task). Depth is fixed: one roadmap file, no phase flags, no `--refine`. Closes with a report-only self-check — findings are surfaced, never silently rewritten into the saved file.

**Input:** `$ARGUMENTS` — a rough description of the initiative, or a reference back to a prior discussion in this conversation ("build a roadmap from what we discussed").

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for the output structure. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`.

- **`config.md not found`** → `/task:to-roadmap` is intake-capable: run the inline setup gate exactly as `skills/to-task/SKILL.md` Step 0 does (detect stack → one `AskUserQuestion` confirmation, Accept / Edit / Decline chips → write `config.md` + `git config --local task.root` + exclude `.task`), then re-run `validate.sh all`. If config is now present → continue. If the user declined setup → report "config.md not written — run `to-roadmap` again when ready" and **stop**.
- **Any other non-zero exit** (config present but malformed) → **stop**, report the validator output.

### Preconditions

- **Slug collision (soft).** Create `.task/roadmap/` if missing. If a file at the proposed slug already exists → **stop** and pose an `AskUserQuestion` (**Overwrite** / **Pick different slug**). Never silently overwrite.
- **Too small for a roadmap.** If the initiative has no obvious phases, no inter-task dependencies, and fewer than ~3 atomic steps → **stop and suggest** `/task:to-task` or `/task:to-plan` instead.

### Step 1: Load context

Read `.task/config/config.md` (Language, conventions), `CLAUDE.md` if present, and list `.task/roadmap/*` — match existing structural style and declare any in-flight related roadmap as a Prerequisite. List the `docs/` top level and skim entry points if any exist. Do not open source files — this is a shallow scan, not investigation.

### Step 2: Cold start or harvest

**Branch first.** The whole file is written from decisions settled here — where those decisions come from matters:

- **Harvest** — the conversation, *before* this call, already settled concrete decisions about **this same initiative** (multiple exchanges, small details included). Tells: "build a roadmap from what we discussed", or `$ARGUMENTS` reads as a handle for prior discussion rather than a fresh idea. → Go to Step 2H.
- **Cold start** — a rough one-to-few-line description with no prior initiative-specific discussion. → Go to Step 2C.

On the fence, prefer harvest — a false positive costs one extra confirmation; a false negative silently drops details.

#### Step 2H: Harvest — Decision Inventory

Comb the prior conversation and output (chat-only, never written to a file; heading skeleton English, prose in config language):

```
## Roadmap — Decision Inventory

{I'm building this roadmap from our earlier discussion. Before I write
the file, here is every decision I captured — confirm nothing dropped.}

### Decisions locked so far
1. {one locked decision at full specificity — small details included
   verbatim, e.g. "the button is first in the panel"}
2. {...}

### Open forks (not yet decided)
- {unresolved question left by the discussion}

### Coverage caveat
{Only if part of the discussion is out of context. Omit the heading
otherwise.}
```

Then pose an `AskUserQuestion` with chips **Accept** / **Edit** / **Decline**:

- **Accept** → proceed to Step 3 if open forks remain, else straight to Step 4 (draft).
- **Edit** → follow-up: the user adds/corrects a decision or moves it between locked/open, then proceed as Accept.
- **Decline** → you misread the discussion; ask the user to restate it, rebuild the inventory.

Include the Coverage caveat only when you suspect the discussion was truncated or summarized out of context — a false alarm erodes trust.

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
- **Technical anchors** — load-bearing technical decisions (a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation). These land in the `<slug>.spec.md` sidecar (Step 4), never in behavioral item bodies.

Before drafting, reprint the full list (behavioral + anchors) and pose an `AskUserQuestion` (**Accept** / **Edit** / **Decline**) to confirm — the cold-start twin of Step 2H's inventory.

Topics the user explicitly said to skip stay skipped — do not raise them again.

### Step 3: Draft the file

Once the decision list is confirmed, draft the full roadmap per [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd): title + intro, `## Prerequisites`, `## Phase summary` table, one `## Phase X` section per phase with `### - [ ] N. <title>` items (`**Dependencies:**`, optional `**Model:**`, `**Ready description:**` blockquote with `### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria`), `## Out of scope`, `## Backlinks`. If any technical anchor was raised, draft the `<slug>.spec.md` sidecar alongside it (see Step 4) — a flat numbered list of decisions, each cited from its item(s) as `### Spec references → §N`.

**Route every confirmed decision to a home:**

- Observable behavior / user-facing effect → the item's `### Outcomes`, or `### Acceptance criteria` when it's a testable assertion.
- Cross-item technical decision → a numbered entry in the `<slug>.spec.md` sidecar (a separate file, written alongside the roadmap — see Step 4); cite it from each steered item as `### Spec references → §N`.
- Scope exclusion → `## Out of scope`, with the reason.
- Anything else → drop it, but say so to the user with a one-line reason — never a silent omission.

A local, single-item detail decision never goes in the sidecar — it belongs in that item's `### Outcomes` / `### Acceptance criteria`. Reserve the sidecar for choices that would break cross-item consistency if a later `/task:to-plan` (or the executing session) re-derived them differently. No sidecar file is written when no technical anchor was raised — an empty sidecar is worse than none.

**`**Model:**` is optional** — set it only when you have a real basis to suggest one (e.g. the item is pure content/vocabulary editing → `haiku`; a new subsystem or cross-module change → `sonnet`; leave it off rather than guessing).

Behavioral discipline: `### Outcomes` / `### Goal` / `### Invariants` describe observable properties only — no project-specific file/symbol names (normative names from spec/CLAUDE.md are fine). If design work would be free to pick a different symbol, the name doesn't belong here — that's `/task:to-plan`'s call, not this file's.

Before saving, run a quick self-check and fix inline (not reported — this is drafting hygiene, distinct from Step 5's post-save pass):

1. Every fork raised in the brainstorm has a home in some phase, or an explicit `## Out of scope` mention.
2. Each `**Ready description:**` stands alone — a reader who hasn't seen the roadmap could pick it up in `/task:to-plan` from the blockquote alone.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`).
4. Every `**Dependencies:**` cites a task number that exists in this file.
5. Every item heading produces a unique kebab-case slug.
6. Every confirmed decision (Step 2) resolved to a concrete home — `### Outcomes`/`### Acceptance criteria`, `## Out of scope`, or a sidecar `§N` with a live citation — or was explicitly dropped with a stated reason.

### Step 4: Save

Write the file directly — no in-chat preview, no confirmation prompt.

1. Slug: kebab-case from the initiative title, ≤ 50 chars (e.g. `add-auth-flow`, `migrate-to-vite`).
2. Write `.task/roadmap/<slug>.md` with the full content.
3. If — and only if — at least one technical anchor was routed there in Step 3, write `.task/roadmap/<slug>.spec.md` next to it: a flat numbered list of decisions, each self-contained enough that `to-plan` or an executing session can treat it as a fixed anchor without re-deriving the reasoning.
4. Do not modify any other file.

### Step 5: Light self-check (report-only)

After Save, skim the just-saved file — not the in-chat draft — against three lenses, as a checklist you run yourself. **Not** a subagent fanout; there is no lens-audit machinery here.

- **Coverage** — phase/fork coverage, dependency integrity (dangling or cyclic `**Dependencies:**`).
- **Decomposition** — any item that reads as compound (spans ≥ 2 unrelated concerns, or has far more outcomes than the rest) and should be split.
- **Clarity** — behavioral discipline held, descriptions self-contained, every `### Spec references → §N` citation resolves to a real entry in the sidecar (when one was written).

Report a compact findings summary — a count per lens plus the obvious issues, a few lines. **Never rewrite the saved file** — anything found here is surfaced for the user to fix by hand or discuss further in chat; there is no inline auto-apply and no `--refine` mode to escalate to.

### Step 6: Output

- Print the path to the created file (and the sidecar path, if one was written).
- One-line summary: "*N* tasks across *M* phases. Recommended order: 1 → 2 → 4 → 3 → 5 …".
- Print the Step 5 findings summary (or "clean / minor only").
- End with the canonical next-step footer: `→ Next: \`/task:roadmap-to-workflow\`` (loop the whole roadmap) or `\`/task:to-task <slug>#1\`` (pick up the first item by hand — same for any other item number). Flag-free.

## Forbidden

- Naming project-specific files, modules, functions, types, or constants in `### Outcomes` / `### Goal` / `### Invariants` — normative names from spec/CLAUDE.md are the only exception.
- Planning implementation details (file lists with line numbers, function signatures, code blocks > 5 lines) — that is `/task:to-plan`'s job when the item is picked up.
- Modifying any file other than `.task/roadmap/<slug>.md` and, when warranted, `.task/roadmap/<slug>.spec.md`.
- Auto-checking / auto-unchecking item checkboxes — that is the `roadmap-to-workflow` **driver**'s exclusive job, never this skill's and never a per-item agent's.
- A single-direction monologue in a decomposition round — offer ≥ 2 options or explicitly justify why only one is viable. (The Decision Inventory and the cold-start sign-off are confirmation rounds, not decomposition rounds — exempt.)
- Generic risks ("watch out for bugs") — risks must be specific to the initiative and project.
- More than one initiative per file — split and pick one for this run.
- Persisting topics the user asked to skip; placeholders anywhere.
- Writing a `.refine.md` sidecar or a `.lock` file — neither exists in v3. Writing a `.spec.md` sidecar with no technical anchor behind it — an empty or filler sidecar is worse than none. Review is chat + `/code-review`, not a lens-audit pass.
