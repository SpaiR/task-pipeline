---
name: to-plan
description: 'Capture the chat into `.task/task/<slug>.md` with `## Description` plus `## Plan` (Goal/Touches/Logic) — the deepest one-task capture.'
argument-hint: '[<slug> | <roadmap-slug>[#N] | context]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` **and** `## Plan` (Goal/Touches/Logic steps), plus `## Tests` when the testing policy calls for it, and the `## Execution` pointer. The deepest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it when you know enough about the approach to hand straight to implementation, or run it again on a `to-task`-only file to add the Plan in place. The slug is the filename; the artifact path is the handle.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far, or continue a task this conversation is clearly about (see Step 1).
- `<slug>` or a path to an existing `.task/task/<slug>.md` — target that file directly.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

**Format contract:** [docs/contract.md](../../docs/contract.md) is the single source of truth for the output structure — read it if anything below is ambiguous.

## Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" plan`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root: `.task/task/<slug>.md` below means `$AI_DIR/task/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent` → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template, and there is no separate setup command. No confirmation chip. Then continue to Step 1 with the original `$ARGUMENTS` unchanged. (A relative `AI_DIR: .task` means no git repository and no `.task/` yet; setup establishes `<ROOT>/.task`.)
3. **`CONFIG: present` → leave it alone.** It is user-owned; only `task.root` and the `.git/info/exclude` line are restored when missing.
4. `ROADMAPS:` / `TASKS:` / `SPECS:` are what already exists. Step 1 resolves its target against `TASKS:` and `ROADMAPS:`, and Step 2a's collision check reads `TASKS:` — neither lists a directory of its own.

If that block arrived as a literal `` !`bash …` `` line instead of output, the preprocessing did not fire: run that one command yourself and continue exactly as above.

There is no full-scan validate call here — the file this run writes is validated after the write (Step 7), and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

## Step 1: Resolve the target and capture mode

The artifact path is the handle — there is no pointer to resolve, and the target is re-resolved every run. Take the **first** case that matches:

1. `$ARGUMENTS` holds an explicit path (contains `/`, or ends in `.md`), or a slug that Step 0's `TASKS:` list carries → that file is the target. A slug absent from `TASKS:` does **not** match here; it falls to case 2.
2. `$ARGUMENTS` holds a `ROADMAPS:` slug, with or without `#<N>` → the target is `.task/task/<item-slug>.md`, derived in Step 2a. (Matching both an existing task file and a roadmap is case 1: the concrete file is the more specific target.)
3. No positional reference, but this chat is clearly continuing a task it already captured, or the user names one by title or slug → that file is the target. More than one plausible match → ask via `AskUserQuestion` (convention (c)) rather than guessing.
4. Nothing matches → no target; go to Step 2 as a fresh capture.

A path target is reduced to its `<slug>` — basename without `.md` — before Step 7: `write-task.sh` takes `--slug` and resolves `$AI_DIR/task/<slug>.md` itself.

For cases 1 and 3, branch on whether the target file exists:

- **Does not exist** → **fresh capture.** From case 2, continue at Step 2a; otherwise Step 2b.
- **Exists, no `## Plan`** → **promote mode** — the flag-free way to deepen a `to-task` capture. Skip Step 2; the header and `## Description` are already there and stay untouched.
- **Exists, `## Plan` present** → **revise mode.** Skip Step 2; the new Plan replaces the old one, and `## Tests` moves only if this chat's edit touches it.

Both modes read the existing `## Description` as context and go straight to Steps 3–6.

**Case 2 always continues at Step 2a**, existing file or not: the slug is only derived there, and `roadmap-item.md` step 5 is what decides whether a file already carrying it is *this item's* earlier capture (promote / revise, per the branch above) or an unrelated namesake (disambiguate and write fresh, never overwrite). This is the one way into Step 2 that promote / revise take, and they take **only** its slug and header metadata — never its Description draft; see Step 2a.

Case 4 has three sub-cases, in order: some `ROADMAPS:` line carries an `unchecked=` list other than `none` **and** there is nothing in the chat or `$ARGUMENTS` to draft from → `AskUserQuestion` (convention (c)), "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**, the latter chipping the roadmap slugs and proceeding as Step 2a. There **is** chat discussion or free-form `$ARGUMENTS` (either alone is enough) → Step 2b. Neither → **stop**, rather than drafting from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-plan <what to capture>`"

## Step 2: Fresh capture — Title and Description

Only for fresh capture (skip entirely for promote/revise — see Step 1). The one exception is Step 2a, which promote/revise enter for the slug and header metadata alone.

### Step 2a: From-roadmap

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-item.md` — resolve the roadmap, pick `#<N>`, read the ready description, collect the spec slugs, derive `<item-slug>` and check whose file it is. That file is the one owner of those rules; `to-task` and the driver's plan agent read the same copy. Its footers take this skill's own command, so a stop reads `→ Next: \`/task:to-plan <slug>#3\``.

Hold what it produces for Step 7's write — the item title, the roadmap slug, `#<N>`, the distinct spec slugs, and, **in fresh capture only**, the Description drafted from the ready description (why from Context, what from Goal / Outcomes / Invariants / Acceptance criteria). Do not write the file yet: Description, Plan and Tests are assembled and written once, together, in Step 7.

In **promote / revise** — the file already exists and is this item's — stop here and go to Steps 3–6. Draft no Description: the existing one is inherited untouched, and `--promote` / `--revise` ignore a `--description` anyway.

### Step 2b: Chat-draft

1. **Slug.** A short kebab-case slug (2–4 words) from the chat's essence, in English whatever `.task/CLAUDE.md` → Language says — it is a filename, a parser-stable string.

   **Slug collision.** If it is already in `TASKS:`, surface that before writing — this is the one sanctioned chip (convention (b)), a pre-write guard on a destructive action. State the existing file's headings as message text first, so the user knows what an overwrite costs ("Existing `.task/task/<slug>.md` has: Description, Plan (4 steps)."), then pose an `AskUserQuestion`: **Pick a different slug** *(Recommended)* / **Overwrite it** / **Decline — stop without writing**. Only the middle chip earns `--force` in Step 7. An unrelated namesake is always better disambiguated than overwritten.
2. **Read `.task/CLAUDE.md`** for Language and Testing Policy. Step 0 only *reports* that it exists; the platform's auto-load fires for file-read tools only, so its contents are not in front of you yet.
3. **Distil the chat** — not the codebase yet — into the `## Description` body: the why + what in the user's own framing, per `.task/CLAUDE.md` → Language (section labels stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` where the discussion gives signal; omit a sub-header rather than inventing content, and fabricate nothing that was not discussed.
4. Hold the title and that body for Step 7, plus a spec slug for each `.task/spec/` spec the discussion clearly relies on. Never invent a reference, and never author the spec — that is `to-spec`'s job. Continue to Steps 3–6.

## Steps 3–6: Anchors, analysis, `tests_required`, draft, self-check

Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/plan-driver.md` § **Core** and follow steps 1–5. It is the single owner of the plan pipeline — the anchors to read, the ascending-cost codebase analysis, the `tests_required` decision, the three-layer `### Step N:` contract, and the self-check list. The driver's per-item plan agent follows the same copy, so the interactive and non-interactive paths cannot drift.

Two things Core leaves to this skill, because they need a user:

- **`tests_required`, the testing-adjacent case** (tests mentioned, but not whether *new* ones are wanted) → resolve it with one `AskUserQuestion` (convention (c)) before drafting `## Tests`: **Add tests** / **No tests this run**. Core's fallback of `false` is for the driver, which has nobody to ask.
- **Promote / revise** → the Description already exists and is inherited as-is; Core step 4 drafts only the Plan (and Tests). In revise, reuse the prior `## Tests` resolution unless this chat's edit explicitly changes the testing ask.

## Step 7: Write

`plan-driver.md` § Core step 6 is the write: `skills/_lib/write-task.sh`, one Bash call, bodies through quoted heredocs, `--fresh` / `--promote` / `--revise` per the mode Step 1 resolved. No in-chat draft and no confirmation prompt — the chat discussion (and, in promote/revise, the existing Description) was the review, and Step 8's digest lets the user judge whether to open the file.

Three exits mean nothing was written. The first two are refusals, where this skill has a user; **exit 5** is a write that could not happen (unwritable `.task/`, full disk) — no `WROTE:` line was printed, so report the failure plainly and never print Step 8's digest for a path that does not exist.

- **exit 4** — `--fresh` on a slug that already exists. That is Step 2b's collision guard; `--force` only after its **Overwrite it** chip.
- **exit 3** — the promote/revise target has no `## Description`, so it is not a task artifact to extend. **Stop and ask via the slug-collision overwrite guard** — this is exactly the pre-write destructive fork the one sanctioned `AskUserQuestion` chip exists for, not a free-text exchange. State first, as message text, that `.task/task/<slug>.md` has no `## Description`, then pose the chips: **Overwrite as fresh capture** / **Pick a different target** / **Decline — stop without writing**. "Overwrite as fresh capture" re-enters Step 2b for a title and a Description — a promote/revise run drafted neither — and only then calls `--fresh --force`. On decline, close with `→ Next: \`/task:to-plan <a different slug>\`.`

The `WROTE:` / `VALIDATE:` lines it prints are what Step 8's digest reports; only a setup-precondition failure (validate exit 2) hard-stops.

## Step 8: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file, without re-reading a full draft. Tailor it to the mode:

```
Wrote `.task/task/<slug>.md`  ({fresh | promote | revise})
# {Title}
Sections: Description, Plan ({N} steps)[, Tests ({N})], Execution
Plan:
- Step 1: {short title}
- Step 2: {…}
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

When the validate result is **not** clean (any WARN or FAIL), append one more line so the user can re-check after editing the file by hand — `validate` is not a slash command, so the invocation is worth spelling out. Omit it entirely on a clean result:

```
re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>
```

For **promote** / **revise**, note plainly what stayed untouched (Description, and pre-existing Tests unless the edit touched them). The file is already written — to change anything, just say so. Then close with the handoff footer (convention (a), flag-free):

`→ Next: implement it now, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Overwrite or paraphrase-away an existing `## Description`, or pick a new slug, in promote or revise mode.
- Modify the source roadmap or any referenced spec — read-only from here. Ticking a checkbox is the executing session's job (the driver's, in a roadmap run); specs are authored only by `to-spec`.
- Invent or resolve an active-task pointer. There is none.
