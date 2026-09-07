---
name: to-plan
description: 'Capture the chat into `.task/task/<slug>.md` with `## Description` plus `## Plan` (Goal/Touches/Logic) — the deepest one-task capture.'
argument-hint: '[<slug> | <roadmap-slug>[#N] | context]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/*.sh* *) Bash(bash *skills/validate/validate.sh* *) Bash(source *skills/_lib/*.sh*)'
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

1. `AI_DIR:` is the pipeline root. **Every artifact path in this skill is under it, never the cwd** — `.task/task/<slug>.md` below is shorthand for `$AI_DIR/task/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves the root itself) never sees. Step 7's writer resolves it the same way, on its own.
2. **`CONFIG: absent` → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it (detect stack → write `$AI_DIR/CLAUDE.md` from its template → record `git config --local task.root` → exclude `.task` → report what was written). No confirmation chip: the file is written first and edited afterwards if a detected value was wrong. `setup.md` is the single source of truth for the sub-steps *and* for the template; do not defer to a separate setup command and do not restate the template here. Then continue to Step 1 with the original `$ARGUMENTS` unchanged. (A relative `AI_DIR: .task` appears in a project that is not a git repository and has no `.task/` yet; setup establishes `<ROOT>/.task` from there.)
3. **`CONFIG: present` → leave it alone.** It is user-owned; only `task.root` and the `.git/info/exclude` line are restored when missing.
4. `ROADMAPS:` / `TASKS:` / `SPECS:` are what already exists. Step 1 resolves its target against `TASKS:` and `ROADMAPS:`, and Step 2a's collision check reads `TASKS:` — neither lists a directory of its own.

If that block arrived as a literal `` !`bash …` `` line instead of output, the preprocessing did not fire: run that one command yourself and continue exactly as above.

There is no full-scan validate call here — the file this run writes is validated after the write (Step 7), and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

## Step 1: Resolve the target and capture mode

The artifact path is the handle. Resolve a target reference, in order:

1. **Explicit path, or a slug with evidence** — an explicit path (contains `/`, or ends in `.md`), **or** a bare slug that Step 0's `TASKS:` list carries → that path is the target. A bare slug alone is *not* enough: "matches `.task/task/<slug>.md`, existing or not" would be satisfied vacuously by any token and would swallow case 2.
2. **Roadmap reference in `$ARGUMENTS`** (`<roadmap-slug>` or `<roadmap-slug>#<N>`, matching a `ROADMAPS:` slug from Step 0) → resolve the item (Step 2a's item-picking logic) and derive its target path `.task/task/<item-slug>.md` from the item title. **A bare slug that matches no task file but does match a roadmap file lands here, not in case 1.** If it somehow matches both an existing task file and a roadmap, case 1 wins — the concrete task file is the more specific target.

   **Is the existing file this item's, or someone else's?** When the derived `.task/task/<item-slug>.md` already exists, do not assume it belongs to this item. Read its header: if its `Roadmap:` and `Source item: #N` match this roadmap slug and this item number, it **is** the same item → continue to the promote/revise branch below. The `Roadmap:` value is a Markdown link, `Roadmap: [<slug>](../roadmap/<slug>.md)` — compare against the link **text**; a hand-edited or older file may carry a bare slug, which compares the same way. If it carries different `Roadmap:` headers, or none at all, it is an unrelated task that merely kebab-cases the same → disambiguate the slug per Step 2a.5 instead, and never enter revise mode on it.
3. **No positional reference, but the chat is clearly continuing or refining a task this session already captured** (a `to-task`/`to-plan` run earlier in this conversation, or the user names an existing task by title/slug) → that file is the target. If more than one file could plausibly match, ask via `AskUserQuestion` (convention (c)) rather than guessing.
4. **Nothing resolves** → no target; go to Step 2 for a fresh capture with no prior reference.

Once a target reference is resolved (1–3), branch on whether the file exists:

- **Target file does not exist yet** → **fresh capture** at that path. If it came from a roadmap reference, continue at Step 2a; otherwise treat the resolved slug/title as a starting point and continue at Step 2b.
- **Target file exists, no `## Plan` heading present** → **promote mode.** This is the flag-free way to turn a `to-task` capture into a plan: skip Step 2 entirely — header and `## Description` already exist and are untouched. Go straight to Step 3 using the existing Description as context, then in Step 7 **insert** `## Plan` (and `## Tests`) rather than create.
- **Target file exists, `## Plan` already present** → **revise mode.** `to-plan` was already run on this file. Skip Step 2, go straight to Step 3 using the existing Description (and the current chat) as context, then in Step 7 **replace** the existing `## Plan` (and `## Tests` only if the user's edit touches it) rather than create or blindly append a duplicate section.

No target at all (case 4): if some `ROADMAPS:` line carries an `unchecked=` list other than `none` **and** there is neither chat discussion nor free-form `$ARGUMENTS` to draft from, present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as Step 2a with the chosen slug. If there **is** chat discussion **or** free-form `$ARGUMENTS` to draft from (either alone is enough — a user who described the task on the command line has already said what to capture), proceed as Step 2b. Only when there is no chat discussion, no free-form `$ARGUMENTS`, and no unchecked roadmap item to draw on, **stop** and ask the user what to capture rather than drafting from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-plan <what to capture>`"

## Step 2: Fresh capture — Title and Description

Only for fresh capture (skip entirely for promote/revise — see Step 1).

### Step 2a: From-roadmap

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-item.md` — resolve the roadmap, pick `#<N>`, read the ready description, collect the spec slugs, derive `<item-slug>` and check whose file it is. That file is the one owner of those rules; `to-task` and the driver's plan agent read the same copy. Its footers take this skill's own command, so a stop reads `→ Next: \`/task:to-plan <slug>#3\``.

Hold what it produces for Step 7's write — the item title, the roadmap slug, `#<N>`, the distinct spec slugs, and the Description drafted from the ready description (why from Context, what from Goal / Outcomes / Invariants / Acceptance criteria). Do not write the file yet: Description, Plan and Tests are assembled and written once, together, in Step 7.

### Step 2b: Chat-draft

1. **Slug.** Generate a short kebab-case slug (2–4 words) from the chat's essence, in English regardless of `.task/CLAUDE.md` → Language (the slug is a filename, a parser-stable string). If it collides with an unrelated slug in Step 0's `TASKS:` list, disambiguate rather than overwriting.
2. **Read `.task/CLAUDE.md`** for Language and Testing Policy before drafting — Step 0 only *reports* whether it exists, and the platform's auto-load fires for file-read tools only, so its contents are not in front of you yet.
3. **Distil the chat.** Read back over the discussion in this conversation (not the codebase yet) and draft `## Description` — the why + what, in the user's own framing, written per `.task/CLAUDE.md` → Language (the section labels themselves stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
4. Hold the header line `# {Short task title}` (no `Roadmap:` / `Source item:` lines in this mode) and the drafted Description for Step 7's write. If the discussion clearly relies on a spec in `.task/spec/`, hold a `Spec: [<slug>](../spec/<slug>.md)` header line for each relevant one too (never invent a reference; never author the spec — that is `to-spec`'s job). Continue to Step 3.

## Steps 3–6: Anchors, analysis, `tests_required`, draft, self-check

Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/plan-driver.md` § **Core** and follow steps 1–5. It is the single owner of the plan pipeline — the anchors to read, the ascending-cost codebase analysis, the `tests_required` decision, the three-layer `### Step N:` contract, and the self-check list. The driver's per-item plan agent follows the same copy, so the interactive and non-interactive paths cannot drift.

Two things Core leaves to this skill, because they need a user:

- **`tests_required`, the testing-adjacent case** (tests mentioned, but not whether *new* ones are wanted) → resolve it with one `AskUserQuestion` (convention (c)) before drafting `## Tests`: **Add tests** / **No tests this run**. Core's fallback of `false` is for the driver, which has nobody to ask.
- **Promote / revise** → the Description already exists and is inherited as-is; Core step 4 drafts only the Plan (and Tests). In revise, reuse the prior `## Tests` resolution unless this chat's edit explicitly changes the testing ask.

## Step 7: Write

`plan-driver.md` § Core step 6 is the write: `skills/_lib/write-task.sh`, one Bash call, bodies through quoted heredocs, `--fresh` / `--promote` / `--revise` per the mode Step 1 resolved. No in-chat draft and no confirmation prompt — the chat discussion (and, in promote/revise, the existing Description) was the review, and Step 8's digest lets the user judge whether to open the file.

The two refusals are where this skill has a user, and both mean nothing was written:

- **exit 4** — `--fresh` on a slug that already exists. That is the Step 2b collision case; `--force` only after its chips.
- **exit 3** — the promote/revise target has no `## Description`, so it is not a task artifact to extend. **Stop and ask via the slug-collision overwrite guard** — this is exactly the pre-write destructive fork the one sanctioned `AskUserQuestion` chip exists for, not a free-text exchange. State first, as message text, that `.task/task/<slug>.md` has no `## Description`, then pose the chips: **Overwrite as fresh capture** / **Pick a different target** / **Decline — stop without writing**. On decline, close with `→ Next: \`/task:to-plan <a different slug>\`.`

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

- Overwrite or paraphrase-away an existing `## Description` in promote or revise mode — only `## Plan` (and, narrowly, `## Tests`) are in scope for those modes.
- Pick a new slug / target path in promote or revise mode — the existing file resolved in Step 1 is reused as-is.
- Modify the source roadmap file or any referenced `.task/spec/<slug>.md` — all are read-only from here; checkbox auto-marking is the executing session's (or, for a roadmap run, the driver's) job, and specs are authored only by `to-spec`.
- Invent or resolve an active-task pointer — the target file is resolved per Step 1 every run.
- Leave `## Plan` present with zero `### Step N:` blocks, or `## Tests` present with zero `### Test N:` blocks — both fail `validate.sh`.
