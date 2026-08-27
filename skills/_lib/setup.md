# First-run setup — write `.task/CLAUDE.md`

Read and followed by a capture skill's Step 0 (`to-task` / `to-plan` / `to-roadmap` / `to-spec` — the intake-capable four) when the resolved `$AI_DIR/CLAUDE.md` does not exist yet. Run it inline, do not defer to another command. **No confirmation chip:** write the file, then report what it says. Detection that came out wrong is fixed by editing the file, not by re-running setup — same grammar as every capture (convention (b)).

1. Determine the pipeline root `ROOT` (main worktree root; `pwd` for a non-git dir; for a bare repo the default is a best-effort guess — name it in the Step 0 report so the user can move it).
2. Analyze the project: read `CLAUDE.md` if present, detect language/stack, build/test commands, a project commit-format doc (check in order `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`), detected language policy (repo's dominant natural language from `git log -10 --oneline` + `CLAUDE.md`/`README.md` prose — default to "follow `task.md` Description" for English/mixed repos), and detected testing-policy mode (`always` if a TDD convention is documented, `on-demand` otherwise — never silently detect `never`).
3. Write `$AI_DIR/CLAUDE.md` (creating `$AI_DIR/` and `$AI_DIR/task/` if needed) using the template below. It is a nested `CLAUDE.md`: the platform loads it into any session that reads a file under `.task/`, which is how the executing session and `task:code-reviewer` get these settings without being told to.

   ```markdown
   # task-pipeline

   Rules for capturing and implementing the `.task/` artifacts. Project-wide conventions
   stay in the repository's own `CLAUDE.md`.

   ## Language
   {language policy — how artifact prose is written. Parser-stable strings (section
    headers, `Roadmap:` / `Source item:` / `Spec:` header keys, the `## Execution`
    pointer, commit trailers) stay English regardless.}

   ## Testing Policy
   {always | on-demand | never} — {one line on what it means here. Under `on-demand`,
    `to-plan` writes `## Tests` only when the Description asks for tests.}

   ## Build and Tests
   {the command(s) `task:code-reviewer` runs end to end before amending the commit,
    or the literal line `None declared.` — the reviewer then reports the skip in words}

   ## Commit Format
   {`**Source:** <path>` when the project documents its own convention; otherwise the
    rules derived from `git log`; otherwise `**Source:** ${CLAUDE_PLUGIN_ROOT}/skills/_lib/templates/conventional-commits.md`}

   ## Code Navigation
   {tool priority for reading code — MCP tools first when the project has them, else built-ins}

   ## Code Editing
   {tool priority for editing code}

   ## Executing a task

   Follow this when you are asked to implement a `.task/task/<slug>.md`:

   1. If the file carries `Spec:` headers, read each `.task/spec/<slug>.md` first and
      honor its decisions as fixed. A header value is a Markdown link,
      `Spec: [<slug>](../spec/<slug>.md)` — take `<slug>` from the link text and open
      `.task/spec/<slug>.md` from the pipeline root; never follow the relative link
      target, which resolves against your cwd, not the artifact's directory. An older
      or hand-edited artifact may carry a bare `Spec: <slug>`; read it the same way.
   2. `.task/` is pipeline-internal and invisible to the repo: never name `.task/`
      paths, spec/roadmap/task slugs, or `§` numbers in code, comments, commits or PR text.
   3. Implement the `## Plan` (or the `## Description` when there is none) with the tools
      this file declares under Code Navigation / Code Editing, if any. When the file
      carries a `## Tests` section, write the assertions it names as part of the same
      change. Then commit per Commit Format above.
   4. Spawn the `task:code-reviewer` agent on that task file: it proves each finding, fixes
      confirmed defects within **Touches** plus regressions this diff introduced outside
      them, runs Build and Tests, and amends the commit. With no `## Plan`, scope fixes to
      what you changed.
   5. If the file carries `Roadmap:` + `Source item: #N`, tick item #N's checkbox in
      `.task/roadmap/<slug>.md` once the review returns OK — `<slug>` read from the
      `Roadmap:` link's text, or from a bare `Roadmap: <slug>`, same rule as step 1.
   ```

   Substitute every `{…}` with a real value — except `${CLAUDE_PLUGIN_ROOT}` inside the Commit Format option, which is not a placeholder but a shell variable: `echo` it first and write the resolved absolute path, never the literal `${CLAUDE_PLUGIN_ROOT}` (nothing expands it inside a user's `.task/CLAUDE.md`). Keep the section headings and the `## Executing a task` steps as they stand — `.task/task/<slug>.md` points at that heading by name, and the reviewer and `to-plan` look their settings up by heading.

   **`## Language`, `## Testing Policy`, `## Build and Tests`, `## Commit Format` and `## Executing a task` are always written**, even when the repository's own `CLAUDE.md` covers the same ground — downstream an absent section reads as *nothing declared*, not as *look it up elsewhere* (`agents/code-reviewer.md` phase 5 turns a missing **Build and Tests** into a skipped verification run). When the project already documents one, keep the section and make its body a one-line pointer — `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` — instead of restating the content. Only `## Code Navigation` / `## Code Editing` may be dropped outright, when the project offers nothing beyond the built-in tools.
4. Record `git config --local task.root "$ROOT"` (repo-common; shared by every worktree). Skip with a warning if not a git repo — the ancestor-`CLAUDE.md` walk resolves `.task/` without the anchor.
5. Exclude `.task` locally: `EXCLUDE=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"; grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"`. Skip with a warning if not a git repo.
6. Report as message text: the path written, each section with its value on one line, and the closing sentence that the file is the user's to edit. Then return to the calling skill's Step 0 and continue with the original `$ARGUMENTS` unchanged.

   ```
   Wrote `.task/CLAUDE.md`
   Language: {policy}
   Testing Policy: {mode}
   Build and Tests: {command | None declared}
   Commit Format: {source or "derived from git log"}
   Loaded automatically whenever a session reads a file under `.task/`.
   To change any of it, edit the file — setup never rewrites it.
   ```
