# Phase: open

> **Inputs:** `$ARGUMENTS` forwarded from `/task:design`.
> **Tier:** **mixed** — A (no code navigation) on the header-only path; C (shallow scan) on the quick-draft path. In Mode 1 quick-draft (Tier C) runs for any non-empty **paraphrasable** context; the header-only Tier A path is taken only via `--idea` or when the input carries no paraphrasable prose (e.g. a bare ticket id).
> **Workspace:** Not yet resolved — this phase creates the workspace and the active-task pointer.

Prepare a task file `.task/workspace/<task-id>/task.md` from the provided context, and write the per-worktree active-task pointer (a one-line file in git's per-worktree dir, resolved via `git rev-parse --git-path task-current`) that downstream skills use to find the active workspace subfolder. The pointer lives inside the git dir, so each worktree has its own while they all share one `.task/`.

**Two modes** are supported, distinguished by argument shape:

1. **Manual mode (default).** Arguments are free-form context (a ticket number, a brief title, or a sentence/paragraph about the task). Always writes the header. The `## Description` body is **filled in this call via quick-draft** (paraphrase of the provided context — Tier C shallow scan + structured `### Problem` / `### Outcome` / `### Scope` / `### Constraints`) for any non-empty context. It is left empty only when the `--idea` flag was passed — the brainstorm opt-out: the orchestrator then runs the idea phase in architect mode against the empty Description.
2. **From-roadmap mode (`--from`).** Arguments start with `--from <path>` (auto-picks the first un-checked item) or `--from <path>#<N>` (explicit item). One roadmap = one umbrella; items become consecutive subtasks. After each `/task:ship --next`, rerun `/task:design --from <path>` to roll the umbrella to the next item (a bare `/task:ship` would close the umbrella instead).

**Precondition (hard-stop) — active-task pointer.** Refuse if the per-worktree active-task pointer already exists unless this is a from-roadmap continuation (see Mode 2 → Step 3 → "Continuation mode"). The pointer names the active umbrella's task-id (one line); its presence means an umbrella is in flight in this worktree and the workspace subfolder `.task/workspace/<task-id>/` is reserved. The pointer lives in git's per-worktree dir — resolve it with `git rev-parse --path-format=absolute --git-path task-current`; let `<id>` = `cat` of that path:

- **Self-heal a provably-stale pointer first (evaluated before every refuse case below).** If the pointer exists but is **provably stale** — its content is empty after whitespace-strip, OR its `.task/workspace/<id>/` subfolder is absent — remove it, print a one-line notice that a stale pointer was cleaned (see the mode outputs), and proceed as an **initial open** (Mode 1 fresh, or Mode 2 initial-open for `--from`) exactly as if no pointer had existed. This is the "next command self-heals and continues" behavior. The staleness definition must match the shared one in `skills/_lib/resolve-ws.sh`'s `heal_stale_pointer` (empty OR missing workspace subfolder); the executor may run that helper (via `source_resolve_ws`) or an inline `test`/`rm` against the resolved pointer path. A stale pointer can never be a valid continuation (continuation Mode 2 → Step 3 requires an existing `task.md`), so heal-then-fresh is always correct. The refuse/continuation cases below apply only to a **valid** pointer (workspace subfolder present).
- The body of `## Description` in `.task/workspace/<id>/task.md` is **non-empty** → an active subtask is in progress. Run `/task:ship` (full close) or `/task:ship --next` (transition) first.
- Description is **empty**, no `--from` argument (manual mode) → the umbrella is mid-flight between subtasks (after a `/task:ship --next` transition). Do **not** run this phase — fill Description (manually or call `/task:design --idea` to enter idea phase) and proceed with blueprint. To start a brand-new umbrella, run `/task:ship` first to drop the current one.
- Description is **empty**, `--from <path>[#<N>]` given → fall through to Mode 2 → Step 3 (Continuation mode); the existing umbrella may roll forward to the next item if all gate conditions hold.

Rationale: this phase writes the umbrella header. Overwriting an existing `task.md` (even one with empty Description) silently destroys the in-flight umbrella's task-id and title. Continuation mode preserves both — line 1, the `Roadmap:` line, and the active-task pointer are not touched.

## Mode 1 — Manual (default)

Triggered when arguments do **not** start with `--from`.

### Step 1: Determine task-id

Before extracting task-id, strip the `--idea` token from `$ARGUMENTS` if present (so it does not leak into the title slug). Remember whether the flag was present — it controls Step 2a's quick-draft skip.

Extract **task-id** from the cleaned arguments — a short identifier in square brackets:

- **If arguments contain a ticket number** (recognized by pattern: letters-digits, e.g. `DT-5177`, `PROJ-42`, `GH-123`) — use it as task-id. Example: `[DT-5177]`. (The shared `_lib/derive-task-id.sh` helper used by Mode 2 matches `[A-Z]+-[0-9]+` only — uppercase letters + hyphen + digits; mode-1 manual extraction follows the same shape to keep umbrella ids consistent across modes.)
- **If no ticket number** — generate a short kebab-case slug from the task essence (2-4 words). Example: `[fix-auth-redirect]`, `[add-export-csv]`.

task-id is written into the file header and used by `/task:ship` to determine the folder in `.task/log/`.

### Step 2: Create task file and active-task pointer

Compute `<task-id-lc>` — the lowercase form of task-id from Step 1 (used for workspace and log paths; the header preserves the original case if it carries a ticket like `DT-5177`). Then:

1. `mkdir -p .task/workspace/<task-id-lc>` — the umbrella's workspace subfolder.
2. Write `.task/workspace/<task-id-lc>/task.md` using this template:

   ```markdown
   # [task-id] {Short task title}

   Modules: {list of affected modules, if specified}
   Packages: {key packages/directories, if specified}
   Key files: {main files, if specified}

   ---

   ## Description

   <!-- Detailed task description. Filled in manually. -->
   ```

3. Write the per-worktree active-task pointer:
   ```bash
   printf '%s\n' "<task-id-lc>" > "$(git rev-parse --path-format=absolute --git-path task-current)"
   ```
   The pointer lives inside git's per-worktree dir (`.git/worktrees/<name>/task-current`, or `.git/task-current` in the main worktree), so each git worktree has its own active umbrella while they all share one `.task/`. Being inside the git dir, it is never part of the work tree and needs no git-exclude entry.

### Step 2a: Quick-draft Description (Tier C path)

Decide whether to fill the body of `## Description` in this call or leave it empty.

1. **Leave Description empty (header-only) when there is nothing to quick-draft.** Two cases trigger this — in both, **skip the rest of Step 2a**:
   - `--idea` was present in `$ARGUMENTS` (explicit brainstorm opt-out), or
   - the **paraphrasable remainder is empty** — after stripping the recognized ticket id (Step 1) and the `--idea` token, no prose is left (e.g. a bare `[DT-5177]` with no other words). There is nothing to paraphrase.

   In both cases Description stays empty (the HTML-comment template from Step 2 is the final state). Next-step differs by case: on the `--idea` path the orchestrator continues into the idea phase (architect) **in the same call**; on the bare-input path the **next** `/task:design` call auto-enters the idea phase (architect). Print the rationale in the output (see "Manual-mode output"). Otherwise (no `--idea`, non-empty prose remainder) → quick-draft; continue at Step 2a.2.
2. **Shallow scan (Tier C).** Same constraint as idea phase's Architect mode Step A.1 — top-level directory listing (1–2 levels), build/manifest files, `CLAUDE.md` at the repo root. Stop as soon as you can name the stack, the top-level modules/areas, and the obvious extension points the input gestures at. If the scan starts to feel like investigation — stop; that means you are crossing into blueprint phase's territory.
3. **Paraphrase into `## Description` body.** Write a self-contained Description using `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers — the same set Architect mode emits at Step A.4 in its final write. Rules:
   - Content is a paraphrase of the user's provided context, normalized into the structure. Do **not** invent facts the user did not provide. If a sub-section has no signal in the input, **omit that sub-section** rather than fabricating filler.
   - `### Problem` — what hurts now or what motivates the task, in the user's framing.
   - `### Outcome` — what the world looks like once the task is done.
   - `### Scope` — explicit list of what is in/out of scope, but only if the input mentioned boundaries; do not guess.
   - `### Constraints` — known limits (compatibility, performance, dependencies, conventions) — only if the input or `CLAUDE.md` flags any.
   - **Single-pass write.** No multi-round dialogue, no `## Decisions` section, no questions to the user. That is architect mode's job and requires `--idea`.
   - Language follows `config.md` → "Language" (or the language of `$ARGUMENTS` when Description was bootstrapped from English context).
4. **Save.** Replace the body of `## Description` in the just-created `.task/workspace/<task-id-lc>/task.md` with the drafted text. The header (everything above and including the first `---` separator) must not be touched.

### Manual-mode rules

- If some fields (modules, packages, files) are not mentioned in the input — do not include them in the template.
- If `.task/log/<task-id-lc>/` does not exist yet — create that folder.
- If `--idea` was present in `$ARGUMENTS`, Description is left empty by design — the orchestrator then continues into the idea phase in architect mode for the full brainstorm flow (same call). The same empty-Description outcome applies when the input has no paraphrasable prose (bare ticket id), except there the next `/task:design` call enters the idea phase.
- The `--idea` flag must not survive into the title or `## Description`. It is consumed by Step 1 (stripped from the slug source) and Step 2a (opt-out signal only).

### Manual-mode output

Branch the output by which Step 2a path was taken — the next-step hint differs. Each branch ends with the canonical next-step footer (`→ Next: <runnable command>`, per [`docs/spec/invariants.md § Interaction conventions`](../../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)):

- **If a stale pointer was self-healed on entry** (Precondition self-heal clause), open the output with the one-line notice that the stale pointer was cleaned (e.g. `note: cleared stale active-task pointer (was empty) — no active task now.`) before the branch-specific lines below, so outcome "told in one line" holds on the design path.

- **Quick-draft (Step 2a wrote a Description).** Print the path to the created file (`.task/workspace/<task-id-lc>/task.md`), the active-task pointer contents, a brief summary of the header, and a 1–2 line summary of the drafted Description (or the list of `### …` sub-headers it contains). Then print the explicit next step — review or edit the Description in `task.md`, then run `/task:design` again to build the implementation plan (`plan.md`); the next call auto-enters the **blueprint** phase — and close with the footer: `→ Next: \`/task:design\``.
- **Header-only (Description left empty).** Print the path, the active-task pointer contents, and a brief header summary. State **why** Description is empty — either `--idea` was passed (brainstorm opt-out) or the input carried no paraphrasable prose (e.g. a bare ticket id). On the `--idea` path the orchestrator continues into the **idea** phase (**architect mode**) in the same call — no footer here, idea.md's Output emits it. On the bare-input path the **next** `/task:design` call auto-enters the **idea** phase (**architect mode**); close with the footer: `→ Next: \`/task:design\``.

## Mode 2 — From roadmap (`--from`)

Triggered when the **first** argument is `--from`.

**Argument syntax:** `--from <pathOrSlug>[#<N>] [extra context...]`

- `<pathOrSlug>` — path to a roadmap file under `.task/roadmap/`. Either an explicit relative path (`.task/roadmap/social-need-and-memory-plan.md`) or a short slug (`social-need-and-memory-plan`) — in the latter case resolves to `.task/roadmap/<slug>.md`. If the slug is ambiguous (no exact match, but multiple partial matches), **stop and ask** which file.
- `#<N>` — optional integer task number. **If omitted, auto-pick the first un-checked item** (heading `^### - \[ \] [0-9]+\. .+$` — only literal `- [ ]`; `[x]` / `[~]` / `[>]` / `[-]` and headings without a checkbox are skipped). When provided, use that exact item (matching `### (- \[[ x~>-]\] )?<N>\. (.+)$`).
- `[extra context]` — optional additional notes appended to the task header (modules, packages, key files). Does **not** modify the description.

### Step 1: Locate and parse the roadmap entry

0. Validate the roadmap file format before parsing — run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <pathOrSlug>`. If it exits non-zero, **stop** and report the validator output; the roadmap is malformed and the regex parser below will produce wrong results.
1. Resolve `<pathOrSlug>` to a repo-relative path (`.task/roadmap/<slug>.md`). Verify the file exists; otherwise — **stop and ask**.
2. **Pick `N`:**
   - If `#<N>` was given, use it.
   - If `#<N>` was omitted, collect **all** headings matching `^### - \[ \] [0-9]+\. (.+)$` (the open items). If none exist — **stop** with: "All roadmap items in `<path>` are closed (or none have a `- [ ]` checkbox). Run `/task:ship` to drop the umbrella, or pick an item explicitly with `--from <path>#<N>`."
     - **More than one open item, interactive run** → **item picker.** Present one `AskUserQuestion` (single-select) — "Which item of `<slug>` do you want to open?" — with a chip per open item (`#<N> — <title>`); the first (lowest `<N>`) is the default/first option. The chosen `<N>` drives the rest of the parse. This is an instance of the structured-choice convention (c) in [docs/spec/invariants.md § Interaction conventions](../../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar) — `--from <path>#<N>` is the explicit non-interactive equivalent and skips the picker.
     - **Exactly one open item, or a non-interactive run** (the `auto-roadmap-design-runner` executing this inline — the driver always passes an explicit `#<N>`, so `#<N>` omitted here means an interactive user) → auto-pick the **first** open item without asking. The captured number drives the rest of the parse.
3. Locate the heading for the chosen `N`: `### (- \[[ x~>-]\] )?<N>\. (.+)$`. Capture group 2 is the **item title**.
4. From the heading down to the next `### ` heading or `---` boundary, locate **`**Ready description:**`** followed by a blockquote. The blockquote (lines starting with `> `) is the description body. Strip the leading `> ` from each line — that becomes `## Description`. The blockquote's sub-headings (`### Context`, `### Goal`, `### Outcomes`, `### Invariants`, optional `### Contracts`, `### Acceptance criteria`, optional `### Spec references`) are passed through unchanged. A `### Spec references` block may cite the roadmap's spec sidecar (`<slug>.spec.md §N`); copy it verbatim — design's blueprint phase reads those sections (Step 1.5 of `blueprint.md`) to ground the plan in pinned technical decisions.
5. From the same task block, locate **`**Dependencies:**`** if present and note dependencies (informational; not auto-resolved).
6. Parse the roadmap H1 for the **initiative title**: read line 1 of the file, expect `^# (.+)$`. If the H1 starts with `Implementation roadmap: ` — strip that prefix; the remainder is the initiative title. If no H1 line exists, fall back to the roadmap slug.
7. If any required structure is missing — **stop and ask** the user to verify `<N>` and the file format.

### Step 2: Determine task-id

Invoke the shared derivation helper so the algorithm is centralized in one place:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/derive-task-id.sh" <pathOrSlug-resolved> <N> "<extra-context-string>"
```

The helper applies these priorities (highest first) and prints the resulting task-id to stdout:

1. **Ticket number in `[extra context]`** (`[A-Z]+-[0-9]+`, e.g. `DT-5177`, `PROJ-42`). Case preserved. Explicit user override.
2. **Ticket number inside the item title** for the chosen `<N>`. Case preserved.
3. **Roadmap filename slug** — basename without `.md`, lowercased, ≤30 chars (truncated at the last hyphen before position 30). This is the **default for `--from` mode**: all subtasks of the same roadmap share one task-id, so the close phase archives them as numbered subfolders under a single `.task/log/<roadmap-slug>/{N}-<slug>/` umbrella.

Same priority applies to both the no-`#N` and the explicit-`#N` forms. The task-id is used **verbatim** for the `# [task-id] …` header in task.md; for the pointer contents and paths (`.task/workspace/<task-id-lc>/`, `.task/log/<task-id-lc>/`) the lowercase form is used.

### Step 3: Continuation mode (existing umbrella)

If the active-task pointer already exists when this phase runs with `--from`, the "refuse on existing pointer" precondition is locally relaxed **only** when all of the following hold (otherwise — **stop**). Let `<id>` = `cat "$(git rev-parse --path-format=absolute --git-path task-current)"` and check against `.task/workspace/<id>/task.md`:

1. The body of `## Description` in `.task/workspace/<id>/task.md` (between the heading and the next `## ` heading or EOF) is empty (whitespace and HTML comments only).
2. The existing `task.md` has a line `^Roadmap: (.+)$` somewhere in the header (above the first `---`).
3. The captured `<P>` resolves to the same repo-relative path as the new `<pathOrSlug>` (after both are normalized to `.task/roadmap/<slug>.md`).
4. The newly resolved task-id (from Step 2, lowercased for comparison) matches `<id>`.

If any condition fails → **stop** with a specific message:
- Description non-empty → "active subtask in progress. Run `/task:ship` first."
- task-id mismatch / Roadmap mismatch / Roadmap line missing → "umbrella mismatch: current is `[<old-task-id>]` (Roadmap: `<old-path>`), you passed `--from <new>`. Run `/task:ship` first to drop the current umbrella, or pass `--from <old-path>` to continue the same umbrella."

If all conditions hold, **continuation mode** applies in Step 4: line 1, the `Roadmap:` line, and the active-task pointer are not touched; only `Source item:` (and any `Modules:` / `Packages:` / `Key files:` from extra context) and the body of `## Description` are rewritten. Any `## Decisions` section stays untouched (umbrella-level, append-only).

### Step 4: Create or rewrite the task file

**Initial open** (no existing active-task pointer) — compute `<task-id-lc>`, then:

1. `mkdir -p .task/workspace/<task-id-lc>` — the umbrella's workspace subfolder.
2. Write `.task/workspace/<task-id-lc>/task.md` from scratch:

   ```markdown
   # [task-id] {Initiative title}

   Roadmap: .task/roadmap/{slug}.md
   Source item: #{N} — {item title}
   {Optional Modules: ... / Packages: ... / Key files: ... lines, only if extra context provided}

   ---

   ## Description

   {Body of the `**Ready description:**` blockquote, with `> ` prefix stripped from each line.}
   ```

3. Write the per-worktree active-task pointer into git's per-worktree dir (so it is naturally scoped to this worktree and needs no git-exclude entry):

   ```bash
   printf '%s\n' "<task-id-lc>" > "$(git rev-parse --path-format=absolute --git-path task-current)"
   ```

The `Roadmap:` line is the umbrella-level pointer (always written as a repo-relative path so `/task:ship`'s close step can resolve it). The `Source item:` line is the per-subtask pointer — `/task:ship`'s auto-mark reads it. Both live in the header (above `---`) so the idea phase, which rewrites the body of `## Description`, cannot accidentally remove them.

**Continuation** (Step 3 conditions held) — apply targeted rewrites only against `.task/workspace/<id>/task.md`:

- Leave line 1 (`# [<task-id>] <Initiative title>`) and the `Roadmap:` line as they are.
- Leave the active-task pointer untouched.
- Replace the existing `Source item:` line with the new one (`Source item: #<N> — <item title>`). If the file lacks a `Source item:` line, insert it directly under the `Roadmap:` line.
- Replace any existing `Modules:` / `Packages:` / `Key files:` lines with values from the new extra context (or remove them if extra context provided none).
- Replace the body of `## Description` with the new item's blockquote body.
- Leave any `## Decisions` section verbatim.

### Step 5: Roadmap state

- This phase does **not** modify the source roadmap file. Auto-marking `- [ ]` → `- [x]` is `/task:ship`'s responsibility (its close step reads the `Roadmap:` and `Source item:` lines from `task.md` to identify the item to mark).

### From-roadmap-mode output

- **If a stale pointer was self-healed on entry** (Precondition self-heal clause), open the output with the one-line notice that the stale pointer was cleaned (e.g. `note: cleared stale active-task pointer (was empty) — no active task now.`) before the lines below — the run then proceeds as an initial open.
- Print the path to the created or updated task file, whether this was a fresh open or a continuation, and (on initial open) that the active-task pointer was written.
- Print the resolved roadmap source (`<path>#<N>`).
- Print the chosen task-id and which rule produced it.
- One-line summary of what the item description covers.
- Print **Roadmap progress:** `<K> of <M> items remaining`.
- If dependencies are listed in the roadmap entry — print them as a reminder.
- Note that the next `/task:design` call will auto-enter blueprint phase (Description is already filled).
- End with the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)): `→ Next: \`/task:design\``.

## Forbidden

- Scan the codebase beyond the Tier C shallow-scan allowance (top-level directory listing, build/manifest files, `CLAUDE.md`). Reading source files, running `Grep` over code, or using MCP code-navigation tools is the blueprint phase's territory. In the header-only path (no quick-draft), no scan at all — that branch is Tier A.
- Add fluff to the header — facts only.
- In Mode 1 Step 2a quick-draft path: engage in multi-round dialogue, ask the user clarifying questions, or append a `## Decisions` section. Those belong to idea phase's architect mode and require explicit `--idea`. Quick-draft is a single-pass paraphrase, not a brainstorm.
- Invent content the user did not provide. If a sub-section (`### Problem` / `### Outcome` / `### Scope` / `### Constraints`) has no signal in the input, omit it.
- Modify any file other than `.task/workspace/<task-id-lc>/task.md`, the active-task pointer (git per-worktree dir; initial open only — continuation leaves it untouched), and `.task/log/<task-id-lc>/` (created if missing).
- In `--from` mode: modify the source roadmap file. `/task:ship` is the only step that flips `- [ ]` → `- [x]`.
