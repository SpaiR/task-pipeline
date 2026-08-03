---
name: to-task
description: Capture the current chat discussion into a task, no implementation plan
disable-model-invocation: true
user-invocable: true
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`. Lightest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it to record the "what and why" before implementing directly, or before `to-plan` later. The written file is the handle — no active-task pointer, no separate execution skill; a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

## Step 0: Setup gate

Resolve the pipeline root, then check whether its `config/config.md` exists:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
[[ -f "$AI_DIR/config/config.md" ]] || echo "config.md not found"
```

The helper walks `task.root` git config → ancestor `config.md` → `dirname(git-common-dir)/.task` → `$CLAUDE_PROJECT_DIR/.task` when that path already holds a `config/config.md` → `./.task`. Use `${CLAUDE_PLUGIN_ROOT}` — a bare `skills/…` path resolves against the user's project cwd, where it does not exist.

**Once `config.md` exists, every artifact path in this skill is under that resolved `$AI_DIR`, never the cwd** — `.task/task/<slug>.md` below is shorthand for `$AI_DIR/task/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves `$AI_DIR` itself) never sees. The inline setup below is the one exception: it runs *before* a root exists, writes to `<ROOT>/.task`, and records `git config task.root "$ROOT"` — which is exactly what `$AI_DIR` resolves to on every later run.

- **Absent → inline setup.** Run it inline, do not defer to another command:
  1. Determine the pipeline root `ROOT` (main worktree root; `pwd` for a non-git dir; for a bare repo the default is a best-effort guess — surface it in the proposal below so the user can redirect it).
  2. Analyze the project: read `CLAUDE.md` if present, detect language/stack, build/test commands, a project commit-format doc (check in order `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`), detected language policy (repo's dominant natural language from `git log -10 --oneline` + `CLAUDE.md`/`README.md` prose — default to "follow `task.md` Description" for English/mixed repos), and detected testing-policy mode (`always` if a TDD convention is documented, `on-demand` otherwise — never silently detect `never`).
  3. Print the detected config as message text, then pose ONE `AskUserQuestion` confirmation in the same reply — the chips don't display it, so the call is gated on that line being printed above it. (This is the config-setup carve-out named in convention (b): it confirms *auto-detected* environment that was never discussed, so unlike a content capture it does ask before writing.):
     ```
     Detected — Language: <policy>; Testing policy: <mode>.
     ```
     Bare repo: add a third clause, `.task location: <ROOT>/.task`, editable the same way.
     Chips **Accept** / **Edit** / **Decline**:
     - **Accept** → adopt as-is.
     - **Edit** → follow-up asks which field(s) to amend (language policy / testing-policy mode / bare-repo `.task` location), same option menus as the language/testing-policy questions below, then continue.
     - **Decline** → do not write anything; report "`config.md` not written — nothing was created. If the detected language or testing policy looked wrong, re-run and pick **Edit** to change them before the write. → Next: `/task:to-task`" and **stop**.
  4. Write `.task/config/config.md` using the standard template — sections: Code Navigation, Code Editing, Library Documentation, Project Conventions, Build and Tests, Commit Format, Language, Testing Policy, Directories — Do Not Search. Reference mode (a short `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer, ≤3 summary lines) when `CLAUDE.md` already documents a section; full mode otherwise. Commit Format: reference mode with just `**Source:** <path>` when a commit-format doc was found; otherwise derive rules from `git log`, and when `git log` yields no usable convention fall back to `**Source:** ${CLAUDE_PLUGIN_ROOT}/skills/_lib/templates/conventional-commits.md`.
  5. Record `git config --local task.root "$ROOT"` (repo-common; shared by every worktree). Skip with a warning if not a git repo — the ancestor-`config.md` walk resolves `.task/` without the anchor.
  6. Exclude `.task` locally: `EXCLUDE=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"; grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"`. Skip with a warning if not a git repo.
  7. Report what was written, then continue to Step 0's validate call below with the original `$ARGUMENTS` unchanged.
- **Present → skip silently**, proceed to validate.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` — an optional self-check, not a gate: report any WARN/ERROR lines, but only hard-stop when `.task/config/config.md` is genuinely absent (Step 0 just handled that). Never block on a pre-existing artifact failing validation.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle. Branch on `$ARGUMENTS`:

1. **Positional roadmap reference** (`<slug>` or `<slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → **from-roadmap mode**, Step 1a below.
2. **No positional roadmap reference, and one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item, and there is no chat discussion to draft from** → present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as from-roadmap mode with the chosen slug.
3. **There is chat discussion _or_ free-form `$ARGUMENTS` to draft from** (either alone is enough — a user who described the task on the command line has already said what to capture) → **chat-draft mode**, Step 2 below.
4. **Nothing to draft from at all** (no chat discussion, no free-form `$ARGUMENTS`, and no unchecked roadmap item) → **stop** and ask the user what to capture rather than drafting a Description from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-task <what to capture>`"

### Step 1a: From-roadmap mode

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — stop and ask.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop with "Every item in `<slug>` is already checked off." and a **runnable** footer: substitute a real item number from the file, never a literal `<N>` — `→ Next: \`/task:to-task <slug>#3\` to redo a specific item (numbers as in the roadmap), or describe new work in chat and run \`/task:to-task\`.` If more than one open item, ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); if exactly one, auto-pick it.
3. Read the item's `**Ready description:**` blockquote — its sub-headings are quoted (`> ### Context` / `> ### Goal` / `> ### Outcomes` / `> ### Invariants` / `> ### Acceptance criteria`); strip the `> ` prefix as you read. (`validate.sh` makes both the label and the blockquote a hard ERROR, so a bare unquoted `### Context` means the roadmap is malformed, not that the shape is optional.) `### Context` becomes the Description's "why"; the rest folds into the "what". Also note any `### Spec references → <spec-slug> §N` the item carries, and the roadmap's own `Spec: <slug>` header lines — collect the distinct `<spec-slug>`s to stamp as `Spec:` headers on the task (step 5).
4. Derive `<item-slug>` — kebab-case English from the item's own title (not the roadmap's). No task-id, no `derive-task-id` helper: the item gets its own `<item-slug>.md`, independent of the roadmap's slug.
5. Write `$AI_DIR/task/<item-slug>.md` directly (creating `$AI_DIR/task/` if needed) — no in-chat draft, no confirmation prompt; the roadmap item is the settled source:

   ```markdown
   # {Item title}
   Roadmap: {slug}
   Source item: #{N}
   Spec: {spec-slug}          (one line per spec the item cites; omit entirely if none)
   ---
   ## Description

   {Why: paraphrase of ### Context. What: paraphrase of ### Goal / ### Outcomes / ### Invariants / ### Acceptance criteria.}

   ## Execution
   > If `Spec:` headers are present, read each `.task/spec/<slug>.md` first and honor its
   > decisions as fixed. `.task/` is pipeline-internal and invisible to the repo: never name
   > `.task/` paths, spec/roadmap/task slugs, or `§` numbers in code, comments, commits, or PR
   > text. Implement the Plan above (or the Description if none) with the tools in
   > `.task/config/config.md` → Code Navigation / Code Editing, then commit per
   > `.task/config/config.md` → Commit Format. Then spawn the `task:code-reviewer` agent on this
   > file: it proves each finding, fixes confirmed defects within **Touches** plus regressions
   > this diff introduced outside them, runs Build and Tests, and amends the commit; with no
   > `## Plan`, scope fixes to what you changed. If `Roadmap:` + `Source item:` are present,
   > tick item #N's checkbox in `.task/roadmap/<slug>.md` once the review returns OK.
   ```

   **Two notations in one template — do not mix them up.** `{braces}` in the header lines are placeholders you substitute (`{Item title}`, `{slug}`, `{N}`). The `## Execution` blockquote is **stamped verbatim**: its `<slug>`, `#N` and `.task/…` strings stay literal, exactly as written. Do **not** helpfully substitute this roadmap's slug or item number into it — the header lines above already carry them, the block is agent-facing boilerplate that must stay byte-identical across every artifact, and `validate.sh` checks only that `## Execution` is *present*, so a paraphrased block ships unflagged.
6. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <item-slug>` — surface any WARN/ERROR in Step 3's digest; only a config-precondition failure (exit 2) hard-stops.
7. Continue to Step 3 (digest + footer), using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket.

   **Slug collision.** If `.task/task/<slug>.md` already exists, surface it before writing. First **read the existing file's headings** and state them as message text above the chip, so the user knows what an overwrite costs — e.g. "Existing `.task/task/<slug>.md` has: Description, Plan (4 steps), Tests (2)." Then pose an `AskUserQuestion`:
   - **The existing file has a `## Plan`** → an overwrite would destroy it, and `.task/` is git-excluded, so there is nothing to restore from. Recommend deepening instead: chips **Deepen it — `/task:to-plan`** *(Recommended)* / **Pick a different slug** / **Overwrite (loses the Plan)** / **Decline → stop without writing**.
   - **Description only** → the cheap case: chips **Accept overwrite** / **Edit → propose a different slug** / **Decline → stop without writing**.
2. **Distil the chat.** Read back over the discussion in this conversation (not the codebase) and write:
   - `## Description` — the why + what, in the user's own framing, written per `config.md` → Language (the section labels themselves stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
   - **No `## Plan` and no `## Tests`** — both are `to-plan`'s job; run `to-plan` later to add them (Tests when Testing Policy warrants).
   - **Specs (optional).** If `.task/spec/` holds a spec the discussion clearly relies on, add a `Spec: <slug>` header line for each (ASCII, above `---`) so the executing session reads it as a fixed anchor. Only reference specs actually relevant — never invent one, and never write the spec file here (that is `to-spec`'s job).
3. **Write `$AI_DIR/task/<slug>.md` directly** (creating `$AI_DIR/task/` if needed) — no in-chat draft, no confirmation prompt. The chat discussion was the review; the written file is the deliverable, and the Step 3 digest lets the user judge whether to open it. (The Step 2.1 slug-collision guard still runs before this write.) No `Roadmap:` / `Source item:` lines in this mode; include a `Spec:` line per relevant spec, or none:

   ```markdown
   # {Short task title}
   Spec: {spec-slug}          (one line per relevant spec; omit entirely if none)
   ---
   ## Description

   {drafted body}

   ## Execution
   {the canonical `## Execution` block, stamped verbatim — byte-for-byte identical
    to the blockquote in Step 1a's template above; do not paraphrase it}
   ```
4. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>` — surface any WARN/ERROR in Step 3's digest.

## Step 3: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file, without re-reading a full draft:

```
Wrote `.task/task/<slug>.md`
# {Title}
Sections: Description, Execution
Captured:
- {the why, one line}
- {the what / scope, one line}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

When the validate result is **not** clean (any WARN or FAIL), append one more line so the user can re-check after editing the file by hand — `validate` is not a slash command, so the invocation is worth spelling out. Omit it entirely on a clean result:

```
re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>
```

The file is already written — to change anything, just say so. Then close with the handoff footer (convention (a), flag-free), naming the path explicitly:

`→ Next: implement it now, deepen it into a plan with \`/task:to-plan\`, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Write a `## Plan` section — that's `to-plan`'s contract.
- Write a `## Tests` section — also `to-plan`'s contract; `to-task` captures the Description only.
- Scan the codebase beyond `CLAUDE.md` + top-level manifests — this skill captures discussion, it doesn't investigate implementation.
- Modify the source roadmap file in from-roadmap mode — auto-marking `- [x]` happens inside the executing session (or the `roadmap-to-workflow` driver), never here.
- Invent, read, or write any active-task pointer — the artifact path is the only handle.
- Bracket the title with a task-id (`# [TASK-ID] Title`) — the title line is plain `# <Title>`; the slug lives only in the filename.
- Silently overwrite an existing `.task/task/<slug>.md` — surface the collision and let the user choose.
- Write or edit a `.task/spec/<slug>.md` file — referencing a spec via a `Spec:` header is fine, but authoring specs is `to-spec`'s job.
