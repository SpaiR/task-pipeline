---
name: to-spec
description: 'Capture load-bearing technical decisions into a standalone `.task/spec/<slug>.md` — Decision/Rationale/Constrains sections cited via `Spec:`.'
argument-hint: '[decision area]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Fix **load-bearing technical decisions** — a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation — into `.task/spec/<slug>.md`. Unlike `to-task` / `to-plan` / `to-roadmap`, a spec does not decompose work; it pins the decisions that work must honor. A task or roadmap references it via a `Spec: [<slug>](../spec/<slug>.md)` header, and the executing session reads it as a fixed anchor (per `.task/CLAUDE.md` → `## Executing a task`, which its `## Execution` pointer names). One spec may be cited by many tasks and roadmaps, and can be captured before any exist.

**Input:** `$ARGUMENTS` — a rough description of the decision area, or a reference back to a prior discussion in this conversation ("write a spec from what we settled").

**Format contract:** [docs/contract.md § Spec file format](../../docs/contract.md#spec-file-format-taskspecslugmd) is the single source of truth for the output structure. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" spec`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root: `.task/spec/<slug>.md` below means `$AI_DIR/spec/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent`** → this skill is intake-capable: read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template — then continue. No confirmation chip; a wrong detected value is fixed by editing the file.
3. **`CONFIG: present`** → leave the file untouched: it is user-owned, and only `task.root` and the `.git/info/exclude` line are restored when missing.
4. `SPECS:` lists the specs that already exist — Step 1 matches structural style against them and avoids re-pinning a decision one of them already carries; Step 4's slug-collision check reads the same list. Neither needs a listing call of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

There is no full-scan validate call here: Step 4 validates the one file it writes, and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

### Preconditions

- **No real decision to pin** — only behavioral outcomes, or details local to one task → **stop and suggest** `/task:to-task` or `/task:to-plan`. Say plainly that nothing was written, and carry **both** options with the reason: "Nothing here is a cross-task technical anchor — these are outcomes local to one task. Nothing was written. `→ Next: \`/task:to-plan\` to capture it with a plan, or \`/task:to-task\` for the what-and-why only.`"

(The slug-collision check runs at save time, once the slug is derived — see Step 4.)

### Step 1: Load context

Read `.task/CLAUDE.md` (Language, conventions), the project's `CLAUDE.md` if present, and the `docs/` top level. Structural style comes from Step 0's `SPECS:` list — open one only when this decision area may overlap it, so a decision it already pins is not duplicated. Open source files only as far as stating a decision accurately requires: this is decision capture, not implementation.

### Step 2: Cold start or harvest

**Branch first**, since the file is written from decisions settled somewhere:

- **Harvest** — this conversation already settled concrete technical decisions. Tells: "write a spec from what we settled", or `$ARGUMENTS` reading as a handle for prior discussion. → Step 2H.
- **Cold start** — a rough decision area, no prior discussion. → Step 2C.

On the fence, prefer harvest: a false positive costs one recap the user skims, a false negative silently drops reasoning.

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

It is a **recap** of decisions and their reasoning, already reached: print it, no confirmation chip. Open forks left → resolve them first, then draft. A misread decision or rationale arrives as chat: correct it and reprint before drafting.

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

Two options per fork at least, or a stated reason why only one is viable. A round is **content dialogue, not a path fork**: print it as message text and close on the open question, because convention (c)'s chips would flatten the pros and cons the round exists to show. Iterate as `Round N` until the decisions are settled, then reprint the full list as message text — a recap, no confirmation chip. Topics the user said to skip stay skipped.

### Step 3: Draft the spec

Once the Step 2H inventory (or the Step 2C recap) is **printed** — no reply is awaited; a correction arrives as chat, and you reprint before drafting — draft per [contract § Spec file format](../../docs/contract.md#spec-file-format-taskspecslugmd), which owns the file shape. Each `## N. <title>` section carries three parts:

- **Decision:** what was chosen — concrete, technical, specific (naming real symbols/protocols/shapes is expected here, unlike a roadmap item).
- **Rationale:** the reasoning that must survive, so a later plan or executing session doesn't re-litigate it.
- **Constrains:** what this pins for consumers, and what it deliberately leaves free.

Keep one decision per section. Before saving, a quick self-check, fixed inline:

1. Every decision is load-bearing: work would come out different if it were re-derived. No single-task details, no restated behavioral outcomes.
2. Each `## N.` section stands alone — a reader who hasn't seen this chat understands the decision and why.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`).
4. Section numbers contiguous from 1 — the `### Spec references → [<slug>](../spec/<slug>.md) §N` citations that other artifacts carry depend on stable numbering.

### Step 4: Save

Write the file directly — no in-chat preview, no confirmation prompt. Step 2's recap was the review, and Step 5's digest lets the user judge whether to open it.

1. Slug: kebab-case from the decision-area topic, ≤ 50 chars (`event-envelope`, `auth-token-model`). Its own identity, independent of any roadmap.
2. **Slug collision.** If that slug is already in Step 0's `SPECS:` list → **stop** and pose an `AskUserQuestion` (**Overwrite** / **Pick different slug**). Never silently overwrite. That list is a snapshot taken before the rounds and no writer script guards this path, so when the slug is *absent* from it, confirm with a file read that nothing is there before writing.
3. Write `$AI_DIR/spec/<slug>.md` (creating the directory if needed), and nothing else — wiring a `Spec:` header into a task or roadmap is `to-task` / `to-plan` / `to-roadmap`'s job when they reference this spec.
4. Validate it: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" spec <slug>` — surface any WARN/ERROR in the Step 5 digest; only a setup-precondition failure (exit 2) hard-stops.

### Step 5: Output — digest

Print the structural digest (convention (b)) as message text. A spec is read by the executing session as a **fixed anchor**, so list **every** pin — this is the user's one glance to catch a misstated decision:

```
Wrote `.task/spec/<slug>.md`
# Spec: {Title}
Pins:
- 1. {decision, one line}
- 2. {…}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

On a result that is **not** clean, append `re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" spec <slug>` — `validate` is not a slash command, so it is worth spelling out. Omit it on a clean result.

The file is already written — to change any pin, just say so. Then the handoff footer (convention (a)): `→ Next: \`/task:to-plan\` for a task that leans on \`.task/spec/<slug>.md\` — or attach it by hand with the line \`Spec: [<slug>](../spec/<slug>.md)\`, above the \`---\` in a task or directly under a roadmap's \`# <Title>\`.`

## Forbidden

- Writing a `## Plan`, a step list, paths with line numbers, or implementation code. A spec pins decisions; it neither plans nor implements.
- Capturing behavioral outcomes or single-task details — those belong in a task's `### Outcomes` / `### Acceptance criteria`.
- Modifying any file but `.task/spec/<slug>.md`, or overwriting one silently. Stamping a `Spec:` header onto a task or roadmap is the referencing skill's job.
- Writing a filler spec when no load-bearing decision was settled — stop and redirect instead.
- Placeholders anywhere; re-raising topics the user asked to skip.
