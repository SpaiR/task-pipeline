# Phase: idea

> **Inputs:** `$ARGUMENTS` forwarded from `/task:design` — rough idea (architect mode) or extra context (Socratic mode).
> **Tier:** C (shallow scan — top-level dirs, manifests, CLAUDE.md only; no source files).
> **Workspace:** Resolved via `.task-current` → `.task/workspace/<task-id>/`.
> **Note on entry.** In manual mode the open phase writes Description directly by default (quick-draft on the Tier C path). This phase runs when the user opts into a brainstorm: (a) `/task:design --idea [<context>]`, (b) an empty `/task:design` call with no task in flight (the orchestrator routes it here, opening a header-only umbrella first and forwarding the elicited idea), or (c) `--phase idea`. Empty Description on entry → Architect mode; non-empty Description on entry → Socratic refinement of the existing text.

Produce or refine the `## Description` section of `.task/workspace/<task-id>/task.md`. This phase auto-detects which mode to run from the current state of Description:

- **Empty Description → Architect mode (brainstorm).** Run an architect-style discussion: propose 2–3 concrete directions per round (with pros/cons), give an explicit recommendation, surface specific risks, ask **one** focused question. Iterate to a self-contained Description.
- **Non-empty Description → Socratic mode (refine).** Interrogate the existing Description for ambiguities, blind spots, implicit assumptions, idea critique. Ask focused questions, rewrite Description, append a `## Decisions` section.

There are no flags or sub-commands — the mode is a function of `## Description`'s content. To re-brainstorm from scratch on a task that already has a Description, blank out the Description first.

**Precondition (hard-stop) — `task.md` exists.** `.task/workspace/<task-id>/task.md` must exist with a valid header (`# [task-id] Title` followed by a `---` separator). On every orchestrated path (`--idea`, empty fresh call, or `--phase idea` with no task) the orchestrator opens a header-only umbrella **before** dispatching here, so this hard-stop is a safety net — it fires only if idea.md is entered directly, bypassing that header-creation step. If so — stop and tell the user: "Run `/task:design <context>` (quick-draft) or `/task:design --idea` (brainstorm) first to create the task header."

## Step 1: Load context and detect mode

Validate format before parsing:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task
```

If it exits non-zero, **stop** and report the validator output.

1. Read `.task/workspace/<task-id>/task.md` — capture the header (everything up to the first `---`).
2. Extract the body of `## Description` — the lines between that heading and the next `## ` heading or EOF.
3. **Mode detection (Roadmap-mode guard + Architect/Socratic routing).** Branch on the header captured at Step 1.1 and the body of `## Description`:
   - **Header has `^Roadmap: ` AND Description body is empty** (whitespace + HTML comments only) → **STOP** with: "Roadmap-mode umbrella detected (`<roadmap-slug>`) and Description is empty — this is the between-subtasks state. Run `/task:design --from <roadmap-slug>` to pick the next item; then this phase will land in Socratic mode for refinement of that item."
   - **Description body is empty** otherwise → **Architect mode**. Continue at Step A.1.
   - **Description body has non-whitespace content** (Roadmap-mode with non-empty Description routes here normally) → **Socratic mode**. Continue at Step S.1.
4. Read `.task/config/config.md` and `CLAUDE.md` (if present).

## Architect mode — brainstorm a Description from scratch

### Step A.0: Ensure a seed idea

The brainstorm needs a starting idea to restate in Round 1. On the normal orchestrated path it arrives via `$ARGUMENTS` (the `--idea <context>` text, or the sentence the orchestrator elicited and forwarded on an empty fresh call), so this step is a **fallback** and usually a no-op. Only when neither `$ARGUMENTS` nor the Description carries any idea (e.g. idea.md was entered directly, or the orchestrator forwarded nothing) — ask the user to describe what they want to build in one or two sentences and **wait** for the answer before continuing. Use that answer as the round-0 seed.

### Step A.1: Shallow structural scan

Build a coarse mental model of the project — only the parts the discussion will reference. Limit yourself to:

- Top-level directory listing (one or two levels deep).
- Build/manifest files for stack, key dependencies, scripts.
- `CLAUDE.md` and any docs it references at the top level.

Stop as soon as you can name: the stack, the top-level modules/areas, the obvious extension points relevant to the idea. If the scan starts to feel like investigation — stop; that means you are crossing into the blueprint phase's territory.

### Step A.2: First discussion round

```
## Idea Brainstorm — Round 1

### Idea as I understand it
{1–3 sentences restating the user's idea in your own words}

### Project context (shallow)
- Stack: {language/framework}
- Relevant areas: {top-level modules/dirs that the idea likely touches}
- Notes: {anything from CLAUDE.md / config that constrains the idea}

### Possible directions
**A) {Direction name}** — {1–2 sentence sketch}
- Pros: {…}
- Cons / cost: {…}
- Fits when: {…}

**B) {Direction name}** — {1–2 sentence sketch}
- Pros: {…}
- Cons / cost: {…}
- Fits when: {…}

**C) {Direction name}** *(optional, only if a third meaningfully different option exists)*

### My recommendation
{Which direction and why, in 2–4 sentences. Reference project context where it matters.}

### Risks and forks I want to flag
- {Risk / hidden dependency / non-obvious decision point}

### What I need from you
{One focused question on the most load-bearing fork.}
```

Rules:

- Always propose **2–3 directions**, not one. If only one is plausible, say so explicitly and explain why alternatives were rejected — but still spell them out briefly.
- The recommendation must be a **real opinion**, not a hedge.
- Risks must be **specific** to the idea and project; if there are no real risks, omit the section.
- Ask **one** focused question (or one heading with numbered sub-questions for tightly-coupled decisions).

### Step A.3: Iterate

Wait for the user's response. Continue with `Round 2`, `Round 3`, … using the same structure, narrowed to the fork now in focus.

Stop iterating when **any** holds:

- The user says "fix it" / "write the description" / equivalent.
- You have enough to cover problem/motivation, desired behavior, out-of-scope, constraints, decisions on each fork.
- A new round would only restate prior conclusions.

Typical depth: **2–4 rounds**. Past 5 usually means the idea is too big for one task — say so and suggest splitting.

If the user explicitly tells you to skip a topic, drop a question, or ignore a risk — do not raise it again and do not bake it into the Description.

### Step A.4: Draft the Description

The Description must be **self-contained** — a reader who has not seen the discussion should understand the task fully. Cover:

- **Problem / motivation** — what hurts now, why this is worth doing.
- **Desired behavior / outcome** — what the world looks like after the task is done.
- **Scope and out-of-scope** — explicit list of what is *not* part of this task.
- **Constraints** — known limits (compatibility, performance, dependencies, conventions).
- **Decisions made during brainstorm** — for each fork that had a non-obvious resolution, append a top-level `## Decisions` section to `task.md` (after Description) listing each chosen path with 1-sentence rationale. This shares the same append-only namespace that Socratic mode uses; later runs append to it rather than rewriting. `/task:build` audit phase reads this section to honor explicit umbrella-level decisions.

Style: prose with subsection headers (`### Problem`, `### Outcome`, `### Scope`, `### Constraints`).

### Step A.5: Save

Write the file directly — no in-chat preview, no confirmation prompt. The user reviews and edits in the file itself.

1. Replace the body of `## Description` in `.task/workspace/<task-id>/task.md` with the drafted text. Preserve everything above and including the first `---` separator verbatim.
2. **Append** the brainstorm decisions (if any) to a top-level `## Decisions` section at the end of the file (same format and namespace Socratic mode uses; see Step S.5). If a `## Decisions` section already exists, append to it — do **not** rewrite earlier entries (append-only invariant).
3. Write the file.

Print the path and a 1–2 line summary of what was written. Tell the user to open the file to review/edit. Note that the next `/task:design` call will auto-detect blueprint phase.

## Socratic mode — refine an existing Description

> **Plan-already-built warning.** If `.task/workspace/<task-id>/plan.md` exists when this mode runs, print a one-line warning first: the implementation plan is already built, so refining the Description now may desync it — the user should re-run `/task:design` (blueprint) afterwards to reconcile. Do not block (the user invoked `--idea` deliberately); just surface it.

### Step S.1: Analyze the Description

Permitted inputs: `CLAUDE.md` (module/package terminology), `.task/workspace/<task-id>/task.md`. Do not read code.

Walk the Description against these aspects:

**Completeness** — Is it clear what must be done? Why (motivation/context)? Are scope boundaries defined? Are there acceptance criteria?

**Clarity** — Statements open to double interpretation? Undefined pronouns ("this", "that component", "like before")? Terms that could be understood differently?

**Implicit assumptions** — Assumptions made without stating them? Dependencies on something not described?

**Blind spots** — Edge cases? Error scenarios? Adjacent areas affected? Backward compatibility, data migration, UX implications?

**Idea critique** — Does the solution actually solve a real problem? Is the effort justified? Simpler alternatives? Could existing tools solve this without new development? Risks that the solution adds more complexity than it removes?

### Step S.2: Formulate questions

Each question must be **actionable** — answering it would change the plan or implementation. Group by aspect; omit aspects that have no questions. If the Description is genuinely clear and complete, say so — do not invent questions for the sake of it.

```
## Task Discussion

### What is clear
- {brief retelling}

### Questions

**Completeness**
1. {question}

**Clarity**
2. {question}

**Assumptions**
3. {question}

**Blind spots**
4. {question}

**Idea critique**
5. {question or alternative proposal}
```

### Step S.3: Wait, then evaluate answers

After outputting questions, **wait** for the user's answers. After receiving answers, check whether any open new gaps — if so, prefix follow-up questions `[Follow-up]`. Repeat until no significant remaining gaps.

### Step S.4: Rewrite the Description

1. Read the current `task.md`.
2. **Rewrite the `## Description` section** incorporating the received answers:
   - Make it **self-contained**.
   - Improve structure and clarity; remove vague references.
   - Integrate accepted decisions naturally into the body.
   - **Do not change the meaning** — only clarify and supplement.
   - **Do not add** information the user explicitly told to ignore.
   - **Preserve the original language**.

### Step S.5: Save and append `## Decisions`

Write the file directly — no in-chat preview, no confirmation prompt. The user reviews and edits in the file itself.

1. Replace the `## Description` body with the rewritten text.
2. **Append** a top-level `## Decisions` section at the end of the file. If `## Decisions` already exists, append new entries — do **not** rewrite earlier entries (append-only invariant).

```markdown
## Decisions

- **{Topic}**: {Accepted decision — brief, third person}
```

3. Record only answers that **clarify or supplement** the Description. Do not record obvious confirmations. Omit topics the user asked to ignore.

Print the path and a brief summary of what was written. Tell the user to open the file to review/edit. Note that the next `/task:design` call will auto-detect blueprint phase.

## Forbidden (both modes)

- Read project source files (`*.ts`, `*.go`, `*.java`, `*.py`, `*.rs`, etc.) — even via `Read`. Allowed reads are restricted to the list in the Tier C "shallow scan" constraint.
- `Grep` over source, MCP code-navigation tools, deep exploration.
- Plan implementation — file lists, function signatures, step-by-step changes belong to the blueprint phase.
- Run builds or tests.
- Modify any file other than `.task/workspace/<task-id>/task.md`.
- Modify the `task.md` header (everything above the first `---`).
- Single-direction monologue in architect mode — every round must offer ≥2 directions or explicitly justify why only one is viable.
- Generic risks ("watch out for bugs", "consider edge cases") — must be specific.
- Persist topics the user explicitly asked to skip or ignore.
- Invent problems in Socratic mode — if the Description is clear, say so.
- Change the **meaning** of the Description in Socratic mode — only clarify, restructure, and supplement.
- Rewrite or modify earlier entries in `## Decisions` — the section is append-only and shared with architect mode and refine phase.
