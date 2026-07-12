---
name: to-task
description: Capture the current chat discussion into a task, no implementation plan
disable-model-invocation: true
user-invocable: true
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`. This is the lightest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it when you just want the "what and why" recorded before diving into implementation directly, or before running `to-plan` later. The written file is the handle — there is no active-task pointer and no separate execution skill; a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

## Step 0: Setup gate

Check whether `.task/config/config.md` exists (resolve the pipeline root the same way `find_ai_dir` in `skills/_lib/resolve-ws.sh` does: `git config --local task.root` → ancestor walk → `dirname(git-common-dir)` → `.task` relative to cwd).

- **Absent → inline setup.** This skill is the home of what used to be a separate `bootstrap` step; run it inline, do not defer to another command:
  1. Determine the pipeline root `ROOT` (main worktree root; `pwd` for a non-git dir; for a bare repo the default is a best-effort guess — surface it in the proposal below so the user can redirect it).
  2. Analyze the project: read `CLAUDE.md` if present, detect language/stack, build/test commands, a project commit-format doc (check in order `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`), detected language policy (repo's dominant natural language from `git log -10 --oneline` + `CLAUDE.md`/`README.md` prose — default to "follow `task.md` Description" for English/mixed repos), and detected testing-policy mode (`always` if a TDD convention is documented, `on-demand` otherwise — never silently detect `never`).
  3. Present ONE accept/decline/edit proposal (convention (b)):
     ```
     Detected — Language: <policy>; Testing policy: <mode>.
     accept / decline / edit
     ```
     Bare repo: add a third clause, `.task location: <ROOT>/.task`, editable the same way.
     - **accept** → adopt as-is.
     - **edit** → ask which field(s) to amend (language policy / testing-policy mode / bare-repo `.task` location), same option menus as the language/testing-policy questions below, then continue.
     - **decline** → do not write anything; report "config.md not written — run `to-task` again when ready" and **stop**.
  4. Write `.task/config/config.md` using the standard template — sections: Code Navigation, Code Editing, Library Documentation, Project Conventions, Build and Tests, Commit Format, Language, Testing Policy, Directories — Do Not Search. Reference mode (a short `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer, ≤3 summary lines) when `CLAUDE.md` already documents a section; full mode otherwise. Commit Format: reference mode with just `**Source:** <path>` when a commit-format doc was found, else derive rules from `git log`.
  5. Record `git config --local task.root "$ROOT"` (repo-common, shared by every worktree — this is what gives all worktrees the same `.task/` with no symlink or join step).
  6. Exclude `.task` locally: `EXCLUDE=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"; grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"`. Skip with a warning if not a git repo.
  7. Report what was written, then continue to Step 0's validate call below with the original `$ARGUMENTS` unchanged.
- **Present → skip silently**, proceed to validate.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. This is an optional self-check, not a gate: report any WARN/ERROR lines alongside the rest of the output, but only hard-stop when `.task/config/config.md` is genuinely absent (the case Step 0 just handled) — never block on a pre-existing artifact failing validation.

## Step 1: Entry

There is no active-task pointer to resolve — the artifact path is always the handle, so nothing to check before drafting.

Branch on `$ARGUMENTS`:

1. **Positional roadmap reference** (`<slug>` or `<slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → **from-roadmap mode**, Step 1a below.
2. **No positional roadmap reference, and one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item, and there is no chat discussion to draft from** → present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as from-roadmap mode with the chosen slug.
3. **Otherwise** (there is chat discussion to draft from, with or without extra free-form `$ARGUMENTS` context) → **chat-draft mode**, Step 2 below.

### Step 1a: From-roadmap mode

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — stop and ask.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop: "all items in `<slug>` are closed; pick one explicitly with `<slug>#<N>`, or draft from chat instead." If more than one open item, ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); if exactly one, auto-pick it.
3. Read the item's `### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria` block. `### Context` becomes the Description's "why"; the rest folds into the "what".
4. Derive `<item-slug>` — kebab-case English from the item's own title (not the roadmap's). No task-id, no `derive-task-id` helper: the item gets its own `<item-slug>.md`, independent of the roadmap's slug.
5. Present the drafted Description body for accept/decline/edit (same grammar as chat-draft mode) before writing anything.
6. **On accept**, write `.task/task/<item-slug>.md` (creating `.task/task/` if needed):

   ```markdown
   # {Item title}
   Roadmap: {slug}
   Source item: #{N} — {item title}
   ---
   ## Description

   {Why: paraphrase of ### Context. What: paraphrase of ### Goal / ### Outcomes / ### Invariants / ### Acceptance criteria.}

   ## Tests

   {Per config.md Testing Policy resolution below — omit the whole section if tests are not required.}

   ## Execution
   > Implement the plan above (or the Description if there is no Plan). Then run the
   > `/verify` skill end-to-end and `/code-review` on the diff; apply review fixes ONLY
   > within the files named in **Touches** (report the rest). Commit per
   > `.task/config/config.md` → Commit Format. If `Roadmap:` + `Source item:` headers are
   > present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
   ```
7. Continue to Step 3 (footer), using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket. If `.task/task/<slug>.md` already exists, surface it before writing: ask (accept/decline/edit grammar) whether to overwrite it, or pick a more specific slug instead.
2. **Distil the chat.** Read back over the discussion in this conversation (not the codebase) and write:
   - `## Description` — the why + what, in the user's own framing. Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
   - `## Tests` — only if `.task/config/config.md` → Testing Policy resolves `tests_required` true for this task (`always`, or `on-demand` with the discussion explicitly asking for tests). List test intents as `### Test N: <what it checks>`; no code yet — the executing session writes the real tests.
   - **No `## Plan` section** — that is `to-plan`'s job.
3. **Present the draft** for accept/decline/edit (convention (b)):
   - accept → write the file as drafted.
   - edit → apply the requested changes, re-show, repeat until accepted.
   - decline → do not write anything; stop with "task.md not written."
4. **On accept**, write `.task/task/<slug>.md` (creating `.task/task/` if needed, no `Roadmap:` / `Source item:` lines in this mode):

   ```markdown
   # {Short task title}
   ---
   ## Description

   {drafted body}

   ## Tests

   {drafted body, only if present}

   ## Execution
   > Implement the plan above (or the Description if there is no Plan). Then run the
   > `/verify` skill end-to-end and `/code-review` on the diff; apply review fixes ONLY
   > within the files named in **Touches** (report the rest). Commit per
   > `.task/config/config.md` → Commit Format. If `Roadmap:` + `Source item:` headers are
   > present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
   ```

## Step 3: Output

Report the path to the written `task.md` and a 1–2 line summary of the Description (and whether `## Tests` was included). Close with the v3 handoff footer (convention (a), flag-free) — the path IS the handle, name it explicitly:

`→ Next: implement it now, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Write a `## Plan` section — that's `to-plan`'s contract.
- Scan the codebase beyond `CLAUDE.md` + top-level manifests (Tier C-equivalent) — this skill captures discussion, it doesn't investigate implementation.
- Modify the source roadmap file in from-roadmap mode — auto-marking `- [x]` happens inside the executing session (or the `roadmap-to-workflow` driver), never here.
- Invent, read, or write any active-task pointer — v3 has none; the artifact path is the only handle.
- Bracket the title with a task-id (`# [TASK-ID] Title`) — v3's title line is plain `# <Title>`; the slug lives only in the filename.
- Silently overwrite an existing `.task/task/<slug>.md` — surface the collision and let the user choose.
