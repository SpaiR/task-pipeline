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

Check whether `.task/config/config.md` exists — resolve the pipeline root via `skills/_lib/resolve-ws.sh` (source it; it exports `AI_DIR`, walking `task.root` → ancestor `config.md` → git-common-dir → `.task`).

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
     - **Decline** → do not write anything; report "`config.md` not written. → Next: run `/task:to-task` again when ready" and **stop**.
  4. Write `.task/config/config.md` using the standard template — sections: Code Navigation, Code Editing, Library Documentation, Project Conventions, Build and Tests, Commit Format, Language, Testing Policy, Directories — Do Not Search. Reference mode (a short `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer, ≤3 summary lines) when `CLAUDE.md` already documents a section; full mode otherwise. Commit Format: reference mode with just `**Source:** <path>` when a commit-format doc was found, else derive rules from `git log`.
  5. Record `git config --local task.root "$ROOT"` (repo-common; shared by every worktree). Skip with a warning if not a git repo — the ancestor-`config.md` walk resolves `.task/` without the anchor.
  6. Exclude `.task` locally: `EXCLUDE=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"; grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"`. Skip with a warning if not a git repo.
  7. Report what was written, then continue to Step 0's validate call below with the original `$ARGUMENTS` unchanged.
- **Present → skip silently**, proceed to validate.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` — an optional self-check, not a gate: report any WARN/ERROR lines, but only hard-stop when `.task/config/config.md` is genuinely absent (Step 0 just handled that). Never block on a pre-existing artifact failing validation.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle. Branch on `$ARGUMENTS`:

1. **Positional roadmap reference** (`<slug>` or `<slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → **from-roadmap mode**, Step 1a below.
2. **No positional roadmap reference, and one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item, and there is no chat discussion to draft from** → present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as from-roadmap mode with the chosen slug.
3. **There is chat discussion to draft from** (with or without extra free-form `$ARGUMENTS` context) → **chat-draft mode**, Step 2 below.
4. **Nothing to draft from** (no chat discussion, no unchecked roadmap item, and empty `$ARGUMENTS`) → **stop** and ask the user what to capture rather than drafting a Description from nothing.

### Step 1a: From-roadmap mode

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — stop and ask.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop: "all items in `<slug>` are closed; pick one explicitly with `<slug>#<N>`, or draft from chat instead." If more than one open item, ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); if exactly one, auto-pick it.
3. Read the item's `### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria` block. `### Context` becomes the Description's "why"; the rest folds into the "what". Also note any `### Spec references → <spec-slug> §N` the item carries, and the roadmap's own `Spec: <slug>` header lines — collect the distinct `<spec-slug>`s to stamp as `Spec:` headers on the task (step 5).
4. Derive `<item-slug>` — kebab-case English from the item's own title (not the roadmap's). No task-id, no `derive-task-id` helper: the item gets its own `<item-slug>.md`, independent of the roadmap's slug.
5. Write `.task/task/<item-slug>.md` directly (creating `.task/task/` if needed) — no in-chat draft, no confirmation prompt; the roadmap item is the settled source:

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
   > `.task/config/config.md` → Code Navigation / Code Editing. Run `/verify` end-to-end and
   > `/code-review`, applying fixes ONLY within **Touches** (report the rest); with no `## Plan`,
   > scope fixes to what you changed. Commit per `.task/config/config.md` → Commit Format. If
   > `Roadmap:` + `Source item:` are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
   ```
6. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <item-slug>` — surface any WARN/ERROR in Step 3's digest; only a config-precondition failure (exit 2) hard-stops.
7. Continue to Step 3 (digest + footer), using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket. If `.task/task/<slug>.md` already exists, surface it before writing: pose an `AskUserQuestion` (Accept overwrite / Edit → propose a different slug / Decline → stop without writing).
2. **Distil the chat.** Read back over the discussion in this conversation (not the codebase) and write:
   - `## Description` — the why + what, in the user's own framing. Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
   - **No `## Plan` and no `## Tests`** — both are `to-plan`'s job; run `to-plan` later to add them (Tests when Testing Policy warrants).
   - **Specs (optional).** If `.task/spec/` holds a spec the discussion clearly relies on, add a `Spec: <slug>` header line for each (ASCII, above `---`) so the executing session reads it as a fixed anchor. Only reference specs actually relevant — never invent one, and never write the spec file here (that is `to-spec`'s job).
3. **Write `.task/task/<slug>.md` directly** (creating `.task/task/` if needed) — no in-chat draft, no confirmation prompt. The chat discussion was the review; the written file is the deliverable, and the Step 3 digest lets the user judge whether to open it. (The Step 2.1 slug-collision guard still runs before this write.) No `Roadmap:` / `Source item:` lines in this mode; include a `Spec:` line per relevant spec, or none:

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

The file is already written — to change anything, just say so. Then close with the handoff footer (convention (a), flag-free), naming the path explicitly:

`→ Next: implement it now, deepen it into a plan with \`/task:to-plan\`, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Write a `## Plan` section — that's `to-plan`'s contract.
- Write a `## Tests` section — also `to-plan`'s contract; `to-task` captures the Description only.
- Scan the codebase beyond `CLAUDE.md` + top-level manifests (Tier C-equivalent) — this skill captures discussion, it doesn't investigate implementation.
- Modify the source roadmap file in from-roadmap mode — auto-marking `- [x]` happens inside the executing session (or the `roadmap-to-workflow` driver), never here.
- Invent, read, or write any active-task pointer — v3 has none; the artifact path is the only handle.
- Bracket the title with a task-id (`# [TASK-ID] Title`) — v3's title line is plain `# <Title>`; the slug lives only in the filename.
- Silently overwrite an existing `.task/task/<slug>.md` — surface the collision and let the user choose.
- Write or edit a `.task/spec/<slug>.md` file — referencing a spec via a `Spec:` header is fine, but authoring specs is `to-spec`'s job.
