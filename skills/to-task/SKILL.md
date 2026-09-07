---
name: to-task
description: 'Capture the chat (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`.'
argument-hint: '[<roadmap-slug>[#N] | context]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/validate/validate.sh* *) Bash(source *skills/_lib/*.sh*)'
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`. Lightest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it to record the "what and why" before implementing directly, or before `to-plan` later. The written file is the handle — no active-task pointer, no separate execution skill; a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

## Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" task`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root. **Every artifact path in this skill is under it, never the cwd** — `.task/task/<slug>.md` below is shorthand for `$AI_DIR/task/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves the root itself) never sees.
2. **`CONFIG: absent` → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it: detect the stack → write `$AI_DIR/CLAUDE.md` from its template → record `git config --local task.root` → exclude `.task` → report what was written. **No confirmation chip:** the file is written first and edited afterwards if a detected value came out wrong. `setup.md` is the single source of truth for the sub-steps *and* for the `.task/CLAUDE.md` template — do not restate either here. Then continue with the original `$ARGUMENTS` unchanged. (A relative `AI_DIR: .task` appears in a project that is not a git repository and has no `.task/` yet; setup establishes `<ROOT>/.task` from there, so nothing cwd-relative is written.)
3. **`CONFIG: present` → leave the file alone.** It is user-owned: never rewrite it, never re-detect its values, never "repair" a section you find missing. Only the two markers are restored silently when absent: `git config --local task.root` and the `.task` line in `.git/info/exclude`. To regenerate the file from scratch, the user deletes it and re-runs any capture.
4. `ROADMAPS:` / `TASKS:` / `SPECS:` are what already exists. Step 1 branches on the roadmap lines and Step 2's slug-collision guard checks `TASKS:` — neither lists a directory of its own.

If that block arrived as a literal `` !`bash …` `` line instead of output, the preprocessing did not fire: run that one command yourself and continue exactly as above.

There is no full-scan validate call here — the file this run writes is validated after the write (Step 2.5 / Step 1a.6), and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle. Branch on `$ARGUMENTS`:

1. **Positional roadmap reference** (`<slug>` or `<slug>#<N>`, matching a `ROADMAPS:` slug from Step 0) → **from-roadmap mode**, Step 1a below.
2. **No positional roadmap reference, some `ROADMAPS:` line carries an `unchecked=` list other than `none`, and there is no chat discussion to draft from** → present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as from-roadmap mode with the chosen slug.
3. **There is chat discussion _or_ free-form `$ARGUMENTS` to draft from** (either alone is enough — a user who described the task on the command line has already said what to capture) → **chat-draft mode**, Step 2 below.
4. **Nothing to draft from at all** (no chat discussion, no free-form `$ARGUMENTS`, and no unchecked roadmap item) → **stop** and ask the user what to capture rather than drafting a Description from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-task <what to capture>`"

### Step 1a: From-roadmap mode

1. Follow `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-item.md` — resolve the roadmap, pick `#<N>`, read the ready description, collect the spec slugs, derive `<item-slug>` and check whose file it is. That file is the one owner of those rules; `to-plan` and the driver's plan agent read the same copy. Its footers take this skill's own command, so a stop reads `→ Next: \`/task:to-task <slug>#3\``.

2. Draft the `## Description` body from the ready description — the why from `### Context`, the what from Goal / Outcomes / Invariants / Acceptance criteria. Nothing else: `## Plan` and `## Tests` are `to-plan`'s contract.

3. **Slug collision.** `roadmap-item.md` step 5 separates this item's earlier capture from an unrelated task on the same kebab-case. When it *is* this item's and holds Description only, rewriting it is safe (pass `--force` below). When it already carries a `## Plan`, an overwrite would destroy that plan — run the Step 2.1 collision guard instead, whose chips already recommend deepening via `/task:to-plan`.

4. Write the file with `skills/_lib/write-task.sh` — no in-chat draft, no confirmation prompt; the roadmap item is the settled source. The script owns the header link forms, the `---` separator, the stamped `## Execution` pointer and the validate call ([docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) is the shape it produces), so none of that is assembled here. One Bash call, the Description body via a **quote-delimited** heredoc (so backticks and `$` reach the file verbatim) and **without** its `## Description` heading. Write the heredoc lines flush-left in the real command — a quoted heredoc keeps whatever indentation you type:

   ```bash
   d=$(mktemp)
   cat >"$d" <<'DESC'
   {Why: paraphrase of ### Context. What: paraphrase of ### Goal / ### Outcomes / ### Invariants / ### Acceptance criteria.}
   DESC
   bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/write-task.sh" --fresh \
     --slug <item-slug> --title "{Item title}" --description "$d" \
     --roadmap <roadmap-slug> --item <N> --spec <spec-slug>   # repeat --spec per spec the item cites; omit if none
   rm -f "$d"
   ```

   No `--plan` and no `--tests`: those are `to-plan`'s contract. Exit 4 means the slug already exists and nothing was written — that is the collision case above, and `--force` is only for after its chips. The `WROTE:` / `VALIDATE:` lines it prints are what Step 3's digest reports; only a setup-precondition failure (validate exit 2) hard-stops.

5. Continue to Step 3 (digest + footer), using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket.

   **Slug collision.** If the slug is already in Step 0's `TASKS:` list, surface it before writing. First **read the existing file's headings** and state them as message text above the chip, so the user knows what an overwrite costs — e.g. "Existing `.task/task/<slug>.md` has: Description, Plan (4 steps), Tests (2)." Then pose an `AskUserQuestion`:
   - **The existing file has a `## Plan`** → an overwrite would destroy it, and `.task/` is git-excluded, so there is nothing to restore from. Recommend deepening instead: chips **Deepen it — `/task:to-plan`** *(Recommended)* / **Pick a different slug** / **Overwrite (loses the Plan)** / **Decline → stop without writing**.
   - **Description only** → the cheap case: chips **Accept overwrite** / **Edit → propose a different slug** / **Decline → stop without writing**.
2. **Read `.task/CLAUDE.md`** for Language before drafting. Step 0 only *reports* whether the file exists; the platform's auto-load fires for file-read tools only, so nothing has put its contents in front of you yet.
3. **Distil the chat.** Read back over the discussion in this conversation (not the codebase) and write:
   - `## Description` — the why + what, in the user's own framing, written per `.task/CLAUDE.md` → Language (the section labels themselves stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
   - **No `## Plan` and no `## Tests`** — both are `to-plan`'s job; run `to-plan` later to add them (Tests when Testing Policy warrants).
   - **Specs (optional).** If `.task/spec/` holds a spec the discussion clearly relies on, add a `Spec: [<slug>](../spec/<slug>.md)` header line for each (ASCII, above `---`) so the executing session reads it as a fixed anchor. Only reference specs actually relevant — never invent one, and never write the spec file here (that is `to-spec`'s job).
4. **Write the file with `skills/_lib/write-task.sh`** — no in-chat draft, no confirmation prompt. The chat discussion was the review; the written file is the deliverable, and the Step 3 digest lets the user judge whether to open it. (The Step 2.1 slug-collision guard still runs before this write.) Same one call as Step 1a.5, minus `--roadmap` / `--item`, which this mode has no source for:

   ```bash
   d=$(mktemp)
   cat >"$d" <<'DESC'
   {drafted Description body}
   DESC
   bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/write-task.sh" --fresh \
     --slug <slug> --title "{Short task title}" --description "$d" \
     --spec <spec-slug>                                    # one per relevant spec; omit if none
   rm -f "$d"
   ```

   The `## Execution` pointer is stamped by the script, byte-identical in every artifact — never write or paraphrase it by hand. Exit 4 means the file already exists and nothing was written; `--force` only after the Step 2.1 chips.

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
