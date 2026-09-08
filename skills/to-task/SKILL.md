---
name: to-task
description: 'Capture the chat (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`.'
argument-hint: '[<roadmap-slug>[#N] | context]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`. The lightest capture: the "what and why", recorded before implementing directly or before `to-plan` later. The written file is the handle, and a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

## Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" task`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root: `.task/task/<slug>.md` below means `$AI_DIR/task/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent` → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template. **No confirmation chip:** the file is written first, and a wrong detected value is fixed by editing it. Then continue with the original `$ARGUMENTS` unchanged. (A relative `AI_DIR: .task` means no git repository and no `.task/` yet; setup establishes `<ROOT>/.task`.)
3. **`CONFIG: present` → leave the file alone.** It is user-owned: never rewrite it, never re-detect its values, never "repair" a missing section. Only `task.root` and the `.git/info/exclude` line are restored when absent. Regenerating it is the user's move — delete, then re-run any capture.
4. `ROADMAPS:` / `TASKS:` / `SPECS:` are what already exists. Step 1 branches on the roadmap lines and Step 2's slug-collision guard checks `TASKS:` — neither lists a directory of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

There is no full-scan validate call here: the writer validates the one file it writes, and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle. Branch on `$ARGUMENTS`:

1. `$ARGUMENTS` names a `ROADMAPS:` slug, with or without `#<N>` → **from-roadmap mode**, Step 1a.
2. Otherwise, chat discussion **or** free-form `$ARGUMENTS` to draft from — either alone is enough → **chat-draft mode**, Step 2.
3. Neither, but some `ROADMAPS:` line carries an `unchecked=` list other than `none` → `AskUserQuestion` (convention (c)), "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**, the latter chipping the roadmap slugs and continuing as from-roadmap mode.
4. Nothing at all → **stop** rather than drafting a Description from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-task <what to capture>`"

### Step 1a: From-roadmap mode

1. Follow `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-item.md` — the one owner of the from-roadmap block, shared with `to-plan` and the driver's plan agent: resolve the roadmap, pick `#<N>`, read the ready description, collect the spec slugs, derive `<item-slug>`, check whose file it is. Its footers take this skill's own command, so a stop reads `→ Next: \`/task:to-task <slug>#3\``.

2. Draft the `## Description` body from the ready description — the why from `### Context`, the what from Goal / Outcomes / Invariants / Acceptance criteria. Nothing else: `## Plan` and `## Tests` are `to-plan`'s contract.

3. **Slug collision.** `roadmap-item.md` step 5 already separated this item's earlier capture from an unrelated namesake. This item's, Description only → rewriting it is safe (`--force`). This item's but already carrying a `## Plan` → an overwrite would destroy it: run Step 2.1's guard, whose chips recommend deepening via `/task:to-plan`.

4. Write it per **Step 2.4** below with `--slug <item-slug>`, `--title "{item title}"`, step 2's body as `--description`, plus `--roadmap <roadmap-slug> --item <N>` and a `--spec` per cited spec. Then continue to Step 3, using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket.

   **Slug collision.** If the slug is already in Step 0's `TASKS:` list, surface it before writing. First **read the existing file's headings** and state them as message text above the chip, so the user knows what an overwrite costs — e.g. "Existing `.task/task/<slug>.md` has: Description, Plan (4 steps), Tests (2)." Then pose an `AskUserQuestion`:
   - **The existing file has a `## Plan`** → an overwrite would destroy it, and `.task/` is git-excluded, so there is nothing to restore from. Recommend deepening instead: chips **Deepen it — `/task:to-plan`** *(Recommended)* / **Pick a different slug** / **Overwrite (loses the Plan)** / **Decline → stop without writing**.
   - **Description only** → the cheap case: chips **Accept overwrite** / **Edit → propose a different slug** / **Decline → stop without writing**.

   Either non-writing outcome says plainly that nothing was written and closes with `→ Next: \`/task:to-task <a different slug>\`` (convention (a)).
2. **Read `.task/CLAUDE.md`** for Language before drafting. Step 0 only *reports* whether the file exists; the platform's auto-load fires for file-read tools only, so nothing has put its contents in front of you yet.
3. **Distil the chat** — the discussion, not the codebase — into the `## Description` body: the why + what in the user's own framing, per `.task/CLAUDE.md` → Language (section labels stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` where the discussion gives signal; omit a sub-header rather than inventing content, and fabricate nothing that was not discussed.

   Hold a spec slug for each `SPECS:` entry the discussion clearly relies on — the executing session reads them as fixed anchors. Only ones actually relevant, never invented, and never authored here.
4. **Write it with `skills/_lib/write-task.sh`** — no in-chat draft, no confirmation prompt. The discussion was the review; the file is the deliverable, and Step 3's digest lets the user judge whether to open it. (The collision guard above still runs first.) The script owns the header link forms, the `---` separator, the stamped `## Execution` pointer and the validate call — see [contract § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) for the shape it produces. One Bash call, the Description body through a **quote-delimited** heredoc written flush-left (so backticks and `$` reach the file verbatim), **without** its `## Description` heading:

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

   No `--plan` and no `--tests`: both are `to-plan`'s contract. Exit 4 means the file already exists and nothing was written; **exit 5** means the write itself failed (unwritable `.task/`, full disk) — no `WROTE:` line was printed, so say that plainly instead of printing Step 3's digest. `--force` is earned by the collision chips above — or, in from-roadmap mode, by Step 1a.3 having identified the file as this item's own Description-only capture. The `WROTE:` / `VALIDATE:` lines it prints are what Step 3 reports; only a setup-precondition failure (validate exit 2) hard-stops.

## Step 3: Output — digest

Print the structural digest (convention (b)) as message text — enough to judge at a glance whether to open the file:

```
Wrote `.task/task/<slug>.md`
# {Title}
Sections: Description, Execution
Captured:
- {the why, one line}
- {the what / scope, one line}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

On a result that is **not** clean (any WARN or FAIL), append the re-check invocation — `validate` is not a slash command, so it is worth spelling out. Omit it on a clean result:

```
re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>
```

The file is already written — to change anything, just say so. Then close with the handoff footer (convention (a), flag-free), naming the path explicitly:

`→ Next: implement it now, deepen it into a plan with \`/task:to-plan\`, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Write a `## Plan` or `## Tests` section — both are `to-plan`'s contract; this skill captures the Description only.
- Scan the codebase beyond `CLAUDE.md` + top-level manifests. This skill captures discussion; it does not investigate implementation.
- Modify the source roadmap or write a spec file — read-only from here. Ticking `- [x]` is the executing session's job (the driver's, in a roadmap run); specs are authored only by `to-spec`.
- Silently overwrite an existing task file, or invent an active-task pointer. There is none: the artifact path is the only handle.
