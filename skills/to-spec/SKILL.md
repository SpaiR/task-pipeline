---
name: to-spec
description: 'Capture load-bearing technical decisions into a standalone `.task/spec/<slug>.md` — Decision/Rationale/Constrains sections cited via `Spec:`.'
disable-model-invocation: true
user-invocable: true
---

Fix **load-bearing technical decisions** — a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation — into `.task/spec/<slug>.md`. Unlike `to-task` / `to-plan` / `to-roadmap`, a spec does not decompose work; it pins the decisions that work must honor. A task or roadmap references it via a `Spec: <slug>` header, and the executing session reads it as a fixed anchor (per `.task/CLAUDE.md` → `## Executing a task`, which its `## Execution` pointer names). One spec may be cited by many tasks and roadmaps, and can be captured before any exist.

**Input:** `$ARGUMENTS` — a rough description of the decision area, or a reference back to a prior discussion in this conversation ("write a spec from what we settled").

**Format contract:** [docs/contract.md § Spec file format](../../docs/contract.md#spec-file-format-taskspecslugmd) is the single source of truth for the output structure. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Setup gate

Resolve the pipeline root first, then validate:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # exports AI_DIR
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all
```

**Every artifact path in this skill is under that resolved `$AI_DIR`, never the cwd** — `.task/spec/<slug>.md` below is shorthand for `$AI_DIR/spec/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves `$AI_DIR` itself) never sees.

- **`CLAUDE.md not found`** → `/task:to-spec` is intake-capable: run the inline setup gate exactly as `skills/to-task/SKILL.md` Step 0 does (detect stack → write `$AI_DIR/CLAUDE.md` from the template there → record `git config --local task.root` → exclude `.task` → report what was written), then re-run `validate.sh all` and continue. No confirmation chip — the file is written first and edited afterwards if a detected value was wrong. `to-task`'s Step 0 owns the sub-steps and the template; do not restate either here. If `.task/CLAUDE.md` already exists, leave it untouched: it is user-owned, and only `task.root` and the `.git/info/exclude` line are restored when missing.
- **Exit 1** (one or more *existing* artifacts fail validation) → surface the validator output, but **do not block**: those errors are pre-existing files, not the spec you're about to write (mirrors `to-task` Step 0 and `roadmap-to-workflow`, and `validate.sh` is advisory — it never inspects `.task/CLAUDE.md` content). Only a missing `.task/CLAUDE.md` (exit 2, handled above) hard-stops.

### Preconditions

- **No real decision to pin.** If the discussion settled no load-bearing technical decision — only behavioral outcomes, or details local to one task → **stop and suggest** `/task:to-task` or `/task:to-plan` instead. Say plainly that nothing was written, and carry **both** options in the footer with the reason: "Nothing here is a cross-task technical anchor — these are outcomes local to one task. Nothing was written. `→ Next: \`/task:to-plan\` to capture it with a plan, or \`/task:to-task\` for the what-and-why only.`"

(The slug-collision check runs at save time, once the slug is derived — see Step 4.)

### Step 1: Load context

Read `.task/CLAUDE.md` (Language, conventions), `CLAUDE.md` if present, and list `.task/spec/*` — match existing structural style and avoid duplicating a decision an existing spec already pins. List the `docs/` top level and skim entry points if any exist. Open source files only as far as needed to state a decision accurately — this is decision capture, not implementation.

### Step 2: Cold start or harvest

**Branch first.** The file is written from decisions settled here — where they come from matters:

- **Harvest** — the conversation, *before* this call, already settled concrete technical decisions. Tells: "write a spec from what we settled", or `$ARGUMENTS` reads as a handle for prior discussion. → Go to Step 2H.
- **Cold start** — a rough decision area with no prior discussion. → Go to Step 2C.

On the fence, prefer harvest — a false positive costs one extra recap the user skims; a false negative silently drops reasoning.

#### Step 2H: Harvest — Decision Inventory

Comb the prior conversation and print, as message text in your reply (chat-only, never written to a file; heading skeleton English, prose in the language from `.task/CLAUDE.md`):

```
## Spec — Decision Inventory

{Writing this spec from our discussion — here is every technical decision
I captured with its load-bearing reasoning. Say so if a line is wrong.}

### Decisions locked so far
1. {decision at full specificity} — because {the load-bearing reason}
2. {...}

### Open forks (not yet decided)
- {unresolved technical question}

### Coverage caveat
{Only if part of the discussion is out of context. Omit otherwise.}
```

This inventory is a **recap** of decisions (with their reasoning) the user already reached in the discussion: print it, no confirmation chip. Then proceed — if open forks remain, resolve them first, then go to Step 3 (draft). If the recap misreads, drops, or misstates a decision or its rationale, the user says so in chat — correct it and reprint before drafting.

#### Step 2C: Cold start — decide the forks

For a decision area with no prior discussion, work each fork with the user before drafting. For each load-bearing choice, lay out the real options with a recommendation:

```
## Spec — Round 1

### Decision area as I understand it
{2–4 sentences.}

### Fork: {the choice to make}
**A) {option}** — {sketch}. Pros / Cons: {...}
**B) {alternative}** — {sketch}. Pros / Cons: {...}

### My recommendation
{a real opinion, not a hedge}

### What I need from you
{One focused question on the most load-bearing fork.}
```

Offer ≥2 options per fork (or justify why only one is viable). A round is **content dialogue, not a path fork** — print it as message text and close with the open question; convention (c)'s chips are for choosing a path through the skill, and would flatten the pros/cons the round exists to show. Iterate (`Round N`) until decisions are settled, then reprint the full list **as message text** — a recap: print it, no confirmation chip. If a decision or its rationale is wrong, the user corrects it in chat before drafting.

Topics the user explicitly said to skip stay skipped.

### Step 3: Draft the spec

Once you have **printed** the Step 2H inventory (or the Step 2C recap) — no user reply is required and none is awaited; a correction, if the user makes one, arrives as chat and you reprint before drafting — draft per [docs/contract.md § Spec file format](../../docs/contract.md#spec-file-format-taskspecslugmd): a `# Spec: <Title>` line, a blockquote purpose header, then one numbered `## N. <title>` section per decision:

- **Decision:** what was chosen — concrete, technical, specific (naming real symbols/protocols/shapes is expected here, unlike a roadmap item).
- **Rationale:** the reasoning that must survive, so a later plan or executing session doesn't re-litigate it.
- **Constrains:** what this pins for consumers, and what it deliberately leaves free.

Keep one decision per section. Before saving, a quick self-check, fixed inline:

1. Every decision is load-bearing (would distort work if re-derived differently) — no local, single-task details, no restating behavioral outcomes.
2. Each `## N.` section stands alone — a reader who hasn't seen this chat understands the decision and why.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`).
4. Section numbers are contiguous from 1 — `Spec references → <slug> §N` citations depend on stable numbering.

### Step 4: Save

Write the file directly — no in-chat preview, no confirmation prompt; the chat discussion (recapped in Step 2) was the review, and Step 5's digest lets the user judge whether to open the file.

1. Slug: kebab-case from the decision-area topic, ≤ 50 chars (e.g. `event-envelope`, `auth-token-model`). Its own identity — independent of any roadmap.
2. **Slug collision (soft).** Create `$AI_DIR/spec/` if missing. If `$AI_DIR/spec/<slug>.md` already exists → **stop** and pose an `AskUserQuestion` (**Overwrite** / **Pick different slug**). Never silently overwrite.
3. Write `$AI_DIR/spec/<slug>.md` with the full content.
4. Do not modify any other file — wiring a `Spec:` header into a task or roadmap is the job of `to-task` / `to-plan` / `to-roadmap` when they reference this spec.
5. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" spec <slug>` — surface any WARN/ERROR in the Step 5 digest; only a setup-precondition failure (exit 2) hard-stops.

### Step 5: Output — digest

Print the structural digest of what was written (convention (b)) as message text. A spec is read by the executing session as a **fixed anchor**, so list **every** pin in full — this is the user's one glance to catch a misstated decision:

```
Wrote `.task/spec/<slug>.md`
# Spec: {Title}
Pins:
- 1. {decision, one line}
- 2. {…}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

When the validate result is **not** clean (any WARN or FAIL), append `re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" spec <slug>` — `validate` is not a slash command, so the invocation is worth spelling out. Omit it on a clean result.

The file is already written — to change any pin, just say so. Then close with the handoff footer (convention (a), flag-free), leading with the path it just wrote and keeping the command itself pasteable: `→ Next: \`/task:to-plan\` for a task that leans on \`.task/spec/<slug>.md\` — or add the line \`Spec: <slug>\` above the \`---\` of an existing task or roadmap to attach it.`

## Forbidden

- Writing a `## Plan`, a step list, file paths with line numbers, or implementation code — a spec pins decisions, it does not plan or implement.
- Capturing behavioral outcomes or single-task details that belong in a task's `### Outcomes` / `### Acceptance criteria` — those are not spec material.
- Modifying any file other than `.task/spec/<slug>.md` — stamping a `Spec:` header onto a task or roadmap is the referencing skill's job, never this one's.
- Silently overwriting an existing `.task/spec/<slug>.md` — surface the collision and let the user choose.
- Writing an empty or filler spec when no load-bearing decision was actually settled — stop and redirect instead.
- Placeholders anywhere; persisting topics the user asked to skip.
