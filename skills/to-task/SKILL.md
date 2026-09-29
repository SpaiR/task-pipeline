---
name: to-task
description: 'Capture the chat (or a roadmap item) into `.task/task/<slug>.md` — `## Description` plus `## Plan` (Goal/Touches/Logic), and `## Tests` when the testing policy calls for it.'
argument-hint: '[<roadmap-slug>[#N] | context]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` **and** `## Plan` (Goal/Touches/Logic steps), plus `## Tests` when the testing policy calls for it, and the `## Execution` pointer. The one single-task capture: a task worth an artifact is a task whose approach is worth writing down, so the Plan is never optional. The slug is the filename; the artifact path is the handle, and a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

**Format contract:** [docs/contract.md](../../docs/contract.md) is the single source of truth for the output structure — read it if anything below is ambiguous.

## Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" task`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the `.task` directory: `.task/task/<slug>.md` below means `$AI_DIR/task/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent` → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template, and there is no separate setup command. **No confirmation chip:** the file is written first, and a wrong detected value is fixed by editing it. Then continue with the original `$ARGUMENTS` unchanged. (A relative `AI_DIR: .task` means no git repository and no `.task/` yet; setup establishes `<ROOT>/.task`.)
3. **`CONFIG: present` → leave the file alone.** It is user-owned: never rewrite it, never re-detect its values, never "repair" a missing section. Only a missing `.task/.gitignore` is recreated, by the preflight above itself; `task.root` is written by first-run setup and not restored afterwards. Regenerating it is the user's move — delete, then re-run any capture.
4. `ROADMAPS:` / `TASKS:` / `SPECS:` are what already exists. Step 1 branches on the roadmap lines and the slug-collision guards check `TASKS:` — neither lists a directory of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

There is no full-scan validate call here — the file this run writes is validated after the write (Step 7), and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle, and every run is a fresh capture. Branch on `$ARGUMENTS`:

1. `$ARGUMENTS` names a `ROADMAPS:` slug, with or without `#<N>` → **from-roadmap mode**, Step 1a.
2. Otherwise, chat discussion **or** free-form `$ARGUMENTS` to draft from — either alone is enough → **chat-draft mode**, Step 2.
3. Neither, but some `ROADMAPS:` line carries an `unchecked=` list other than `none` or `unreadable` → `AskUserQuestion` (convention (c)), "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**, the latter chipping the roadmap slugs and continuing as from-roadmap mode.
4. Nothing at all → **stop** rather than drafting from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-task <what to capture>`"

### Step 1a: From-roadmap mode

1. Follow `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-item.md` — the one owner of the from-roadmap block, shared with the driver's plan agent: resolve the roadmap, pick `#<N>`, read the ready description, collect the spec slugs, derive `<item-slug>`, check whose file it is, and note the roadmap's `## Architecture` if it has one. Its footers take this skill's own command, so a stop reads `→ Next: \`/task:to-task <slug>#3\``.

2. **Slug collision.** `roadmap-item.md` step 5 already separated this item's earlier capture from an unrelated namesake (the namesake gets a disambiguated slug and is never touched). When the file is **this item's own**, run the one sanctioned chip (convention (b)) before writing anything: state the existing file's headings as message text first ("Existing `.task/task/<item-slug>.md` has: Description, Plan (4 steps), Tests (2)."), then pose an `AskUserQuestion`: **Regenerate from the item** *(Recommended — the Description is re-derived from the ready description, so only the old Plan and any hand edits are replaced)* / **Decline — stop without writing**. Only the first chip earns `--force` in Step 7. **Decline** says plainly that nothing was written and closes with `→ Next: implement the existing file in a fresh session: \`implement .task/task/<item-slug>.md\``.

3. Hold what it produces for Step 7's write — the item title, the roadmap slug, `#<N>`, the distinct spec slugs, and the Description drafted from the ready description (why from Context, what from Goal / Outcomes / Invariants / Acceptance criteria). Do not write the file yet: Description, Plan and Tests are assembled and written once, together, in Step 7. Continue to Steps 3–6.

## Step 2: Chat-draft mode

1. **Slug.** A short kebab-case slug (2–4 words) from the chat's essence, in English whatever `.task/CLAUDE.md` → Language says — it is a filename, a parser-stable string. This is both the filename and the task's identity — no task-id, no bracket.

   **Slug collision.** If it is already in `TASKS:`, surface that before writing — this is the one sanctioned chip (convention (b)), a pre-write guard on a destructive action. State the existing file's headings as message text first, so the user knows what an overwrite costs ("Existing `.task/task/<slug>.md` has: Description, Plan (4 steps)."), then pose an `AskUserQuestion`: **Pick a different slug** *(Recommended)* / **Overwrite it** / **Decline — stop without writing**. `.task/` is ignored by its own `.task/.gitignore` and never committed, so an overwritten file cannot be restored. Only the middle chip earns `--force` in Step 7; an unrelated namesake is always better disambiguated than overwritten. **Decline** says plainly that nothing was written and closes with `→ Next: \`/task:to-task <a different slug>\`` (convention (a)).
2. **Read `.task/CLAUDE.md`** for Language and Testing Policy. Step 0 only *reports* that it exists; the platform's auto-load fires for file-read tools only, so its contents are not in front of you yet.
3. **Distil the chat** — not the codebase yet — into the `## Description` body: the why + what in the user's own framing, per `.task/CLAUDE.md` → Language (section labels stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` where the discussion gives signal; omit a sub-header rather than inventing content, and fabricate nothing that was not discussed.
4. Hold the title and that body for Step 7, plus a spec slug for each `SPECS:` entry the discussion clearly relies on — the executing session reads them as fixed anchors. Never invent a reference, and never author the spec — that is `to-spec`'s job. Continue to Steps 3–6.

## Steps 3–6: Anchors, analysis, `tests_required`, draft, self-check

Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/plan-driver.md` § **Core** and follow steps 1–5. It is the single owner of the plan pipeline — the anchors to read (roadmap architecture included), the ascending-cost codebase analysis, the `tests_required` decision, the three-layer `### Step N:` contract, and the self-check list. The driver's per-item plan agent follows the same copy, so the interactive and non-interactive paths cannot drift.

One thing Core leaves to this skill, because it needs a user: **`tests_required`, the testing-adjacent case** (tests mentioned, but not whether *new* ones are wanted) → resolve it with one `AskUserQuestion` (convention (c)) before drafting `## Tests`: **Add tests** / **No tests this run**. Core's fallback of `false` is for the driver, which has nobody to ask.

## Step 7: Write

`plan-driver.md` § Core step 6 is the write: `skills/_lib/write-task.sh`, one Bash call, bodies through quoted heredocs, always `--fresh` — plus `--roadmap <roadmap-slug> --item <N>` from a roadmap item and one `--spec` per cited spec. No in-chat draft and no confirmation prompt — the chat discussion was the review, and Step 8's digest lets the user judge whether to open the file.

- **exit 4** — `--fresh` on a slug that already exists, and nothing was written. That is the collision guard's job (Step 1a.2 / Step 2.1), so the file appeared after Step 0 listed `TASKS:`: go back to your mode's collision guard for that slug, exactly as if it had been listed, and write again from its answer. From a roadmap item that is `roadmap-item.md` step 5's header check, then Step 1a.2's chip when the file is this item's own — an unrelated namesake is disambiguated, never overwritten; from chat it is Step 2.1's chip. `--force` only after an overwrite or regenerate chip, and that chip's **Decline** footer when the user stops.
- **exit 5** — the write itself could not happen (unwritable `.task/`, full disk). No `WROTE:` line was printed, so report the failure plainly, never print Step 8's digest for a path that does not exist, and close with `→ Next: fix the write failure (permissions or free space under \`$AI_DIR\`), then rerun \`/task:to-task\`.`

The `WROTE:` / `VALIDATE:` lines it prints are what Step 8's digest reports; only a setup-precondition failure hard-stops. Its signal is the line `ERROR precondition: CLAUDE.md not found` inside the `VALIDATE:` block — `write-task.sh` exits 0 once the file is written, so validate's own exit code never reaches you. Report it and close with `→ Next: rerun \`/task:to-task\` — its setup writes \`.task/CLAUDE.md\` first.`

## Step 8: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file, without re-reading a full draft:

```
Wrote `.task/task/<slug>.md`
# {Title}
Sections: Description, Plan ({N} steps)[, Tests ({N})], Execution
Plan:
- Step 1: {short title}
- Step 2: {…}
architecture: {followed | deviated in step N — {reason} | none}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

The `architecture:` line reports how the Plan relates to the source roadmap's `## Architecture` (`plan-driver.md` § Core step 1); `none` when the task has no roadmap or the roadmap has no such section.

When the validate result is **not** clean (any WARN or FAIL), append one more line so the user can re-check after editing the file by hand — `validate` is not a slash command, so the invocation is worth spelling out. Omit it entirely on a clean result:

```
re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>
```

The file is already written — to change anything, just say so. Then close with the handoff footer (convention (a), flag-free), naming the path explicitly:

`→ Next: implement it now, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Silently overwrite an existing task file — every existing slug goes through a collision chip first — or invent an active-task pointer. There is none: the artifact path is the only handle.
- Modify the source roadmap or any referenced spec — read-only from here. Ticking a checkbox is `task:code-reviewer`'s job, once its review of the item passes; specs are authored only by `to-spec`.
- Write a task file without a `## Plan` — a Description with no approach is chat, not an artifact.
