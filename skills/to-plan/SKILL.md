---
name: to-plan
description: 'Capture the chat into `.task/task/<slug>.md` with `## Description` plus `## Plan` (Goal/Touches/Logic) — the deepest one-task capture.'
disable-model-invocation: true
user-invocable: true
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` **and** `## Plan` (Goal/Touches/Logic steps), plus `## Tests` when the testing policy calls for it, and the `## Execution` pointer. The deepest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it when you know enough about the approach to hand straight to implementation, or run it again on a `to-task`-only file to add the Plan in place. The slug is the filename; the artifact path is the handle.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far, or continue a task this conversation is clearly about (see Step 1).
- `<slug>` or a path to an existing `.task/task/<slug>.md` — target that file directly.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

**Format contract:** [docs/contract.md](../../docs/contract.md) is the single source of truth for the output structure — read it if anything below is ambiguous.

## Step 0: Setup gate

Resolve the pipeline root, then check whether its `CLAUDE.md` exists:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
echo "$AI_DIR"                                             # the resolved root — use this value verbatim in every artifact path below
[[ -f "$AI_DIR/CLAUDE.md" ]] || echo "CLAUDE.md not found"
```

Use `${CLAUDE_PLUGIN_ROOT}` — a bare `skills/…` path resolves against the user's project cwd, where it does not exist, and an unset `$AI_DIR` would send Step 7's `mkdir -p "$AI_DIR/task"` to the filesystem root.

**Once `.task/CLAUDE.md` exists, every artifact path in this skill is under that resolved `$AI_DIR`, never the cwd** (the inline setup below is the one exception — it runs before a root exists) — `.task/task/<slug>.md` below is shorthand for `$AI_DIR/task/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves `$AI_DIR` itself) never sees.

- **Absent → inline setup.** Run the inline setup gate exactly as [`skills/to-task/SKILL.md`](../to-task/SKILL.md) Step 0 does (detect stack → write `$AI_DIR/CLAUDE.md` from the template there → record `git config --local task.root "$ROOT"` → exclude `.task` → report what was written). No confirmation chip: the file is written first and edited afterwards if a detected value was wrong. `to-task`'s Step 0 is the single source of truth for the sub-steps *and* for the file template; do not defer to a separate setup command and do not restate the template here. One `to-plan`-specific note: create `<ROOT>/.task/task/` alongside `.task/CLAUDE.md`. Then continue to the validate call below with the original `$ARGUMENTS` unchanged.
- **Present → leave it alone.** It is user-owned; only `task.root` and the `.git/info/exclude` line are restored when missing.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` as a self-check — there is no gate, so report any findings and continue rather than blocking. Only a setup-precondition failure (exit 2) should stop the flow.

## Step 1: Resolve the target and capture mode

The artifact path is the handle. Resolve a target reference, in order:

1. **Explicit path, or a slug with evidence** — an explicit path (contains `/`, or ends in `.md`), **or** a bare slug for which `.task/task/<slug>.md` **already exists** → that path is the target. A bare slug alone is *not* enough: "matches `.task/task/<slug>.md`, existing or not" would be satisfied vacuously by any token and would swallow case 2.
2. **Roadmap reference in `$ARGUMENTS`** (`<roadmap-slug>` or `<roadmap-slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → resolve the item (Step 2a's item-picking logic) and derive its target path `.task/task/<item-slug>.md` from the item title. **A bare slug that matches no task file but does match a roadmap file lands here, not in case 1.** If it somehow matches both an existing task file and a roadmap, case 1 wins — the concrete task file is the more specific target.

   **Is the existing file this item's, or someone else's?** When the derived `.task/task/<item-slug>.md` already exists, do not assume it belongs to this item. Read its header: if its `Roadmap:` and `Source item: #N` match this roadmap slug and this item number, it **is** the same item → continue to the promote/revise branch below. The `Roadmap:` value is a Markdown link, `Roadmap: [<slug>](../roadmap/<slug>.md)` — compare against the link **text**; a hand-edited or older file may carry a bare slug, which compares the same way. If it carries different `Roadmap:` headers, or none at all, it is an unrelated task that merely kebab-cases the same → disambiguate the slug per Step 2a.5 instead, and never enter revise mode on it.
3. **No positional reference, but the chat is clearly continuing or refining a task this session already captured** (a `to-task`/`to-plan` run earlier in this conversation, or the user names an existing task by title/slug) → that file is the target. If more than one file could plausibly match, ask via `AskUserQuestion` (convention (c)) rather than guessing.
4. **Nothing resolves** → no target; go to Step 2 for a fresh capture with no prior reference.

Once a target reference is resolved (1–3), branch on whether the file exists:

- **Target file does not exist yet** → **fresh capture** at that path. If it came from a roadmap reference, continue at Step 2a; otherwise treat the resolved slug/title as a starting point and continue at Step 2b.
- **Target file exists, no `## Plan` heading present** → **promote mode.** This is the flag-free way to turn a `to-task` capture into a plan: skip Step 2 entirely — header and `## Description` already exist and are untouched. Go straight to Step 3 using the existing Description as context, then in Step 7 **insert** `## Plan` (and `## Tests`) rather than create.
- **Target file exists, `## Plan` already present** → **revise mode.** `to-plan` was already run on this file. Skip Step 2, go straight to Step 3 using the existing Description (and the current chat) as context, then in Step 7 **replace** the existing `## Plan` (and `## Tests` only if the user's edit touches it) rather than create or blindly append a duplicate section.

No target at all (case 4): if one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item **and** there is neither chat discussion nor free-form `$ARGUMENTS` to draft from, present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as Step 2a with the chosen slug. If there **is** chat discussion **or** free-form `$ARGUMENTS` to draft from (either alone is enough — a user who described the task on the command line has already said what to capture), proceed as Step 2b. Only when there is no chat discussion, no free-form `$ARGUMENTS`, and no unchecked roadmap item to draw on, **stop** and ask the user what to capture rather than drafting from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-plan <what to capture>`"

## Step 2: Fresh capture — Title and Description

Only for fresh capture (skip entirely for promote/revise — see Step 1).

### Step 2a: From-roadmap

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — **stop**, name the roadmap slugs that do exist, and close with a runnable footer (convention (a)): `→ Next: \`/task:to-plan <one of those slugs>\``.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop with "Every item in `<slug>` is already checked off." and a **runnable** footer: substitute a real item number from the file, never a literal `<N>` — `→ Next: \`/task:to-plan <slug>#3\` to redo a specific item (numbers as in the roadmap), or describe new work in chat and run \`/task:to-plan\`.` More than one open item → ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); exactly one → auto-pick it.
3. Read the item's `**Ready description:**` blockquote — its sub-headings are quoted (`> ### Context` / `> ### Goal` / `> ### Outcomes` / `> ### Invariants` / `> ### Acceptance criteria`); strip the `> ` prefix as you read. (`validate.sh` makes both the label and the blockquote a hard ERROR, so a bare unquoted `### Context` means the roadmap is malformed, not that the shape is optional.) `### Context` becomes the Description's "why"; the rest folds into the "what". `### Acceptance criteria` entries are good candidates to carry into `## Tests` (Step 4) verbatim as test intents when tests are required.
4. Note the specs this item relies on: any `### Spec references → [<spec-slug>](../spec/<spec-slug>.md) §N` in the item body, plus the roadmap's own `Spec:` header lines. Read a slug from the link **text**, never by following the link target — that target is relative to the roadmap file's directory, not your cwd; a hand-edited roadmap may carry the older bare form, read it the same way. Read each `.task/spec/<spec-slug>.md` now — carry them into Step 3 as pinned anchors (see Step 3's note), and hold the distinct `<spec-slug>`s for the `Spec:` headers in Step 7's write.
5. Derive the slug: kebab-case of the item title (2–4 words). If it collides with an existing, unrelated `.task/task/<slug>.md`, disambiguate with a short qualifier (e.g. append a second distinguishing word) rather than overwriting.
6. Hold, for Step 7's write, the header lines in the shape Step 7 writes — `# {Item title}` plus `Roadmap:` / `Source item:` and a `Spec:` line per cited spec — and the drafted `## Description` body (why from Context, what from Goal/Outcomes/Invariants/Acceptance criteria). Continue to Step 3 — do not write the file yet; the full task.md (Description + Plan + Tests) is assembled and written once, together, in Step 7.

### Step 2b: Chat-draft

1. **Slug.** Generate a short kebab-case slug (2–4 words) from the chat's essence, in English regardless of `.task/CLAUDE.md` → Language (the slug is a filename, a parser-stable string). If it collides with an existing, unrelated task file, disambiguate rather than overwriting.
2. **Read `.task/CLAUDE.md`** for Language and Testing Policy before drafting — Step 0's gate only *tests* for the file with Bash, which does not pull it into context (the platform's auto-load fires for file-read tools only).
3. **Distil the chat.** Read back over the discussion in this conversation (not the codebase yet) and draft `## Description` — the why + what, in the user's own framing, written per `.task/CLAUDE.md` → Language (the section labels themselves stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
4. Hold the header line `# {Short task title}` (no `Roadmap:` / `Source item:` lines in this mode) and the drafted Description for Step 7's write. If the discussion clearly relies on a spec in `.task/spec/`, hold a `Spec: [<slug>](../spec/<slug>.md)` header line for each relevant one too (never invent a reference; never author the spec — that is `to-spec`'s job). Continue to Step 3.

## Step 3: Analyze the codebase

Shared by every mode (fresh chat-draft, fresh from-roadmap, promote, revise): `## Plan` steps need real paths, not paraphrase.

Use the Description (fresh capture) or the existing `## Description` (promote/revise) as the "what" to ground against real code. Read code in ascending cost order per `.task/CLAUDE.md` → Code Navigation (MCP tools first, built-ins as fallback):

1. From modules/packages/files named or implied in the Description — get a structural overview.
2. Read symbol bodies selectively — only those directly affected.
3. Identify dependencies and usage locations.
4. Find existing patterns in neighboring code for reuse.
5. Assess impact on adjacent modules/components.

Reads at the same step are independent — issue them as one parallel batch, not one round-trip at a time.

**Pinned technical decisions.** If the task carries (or, on fresh capture, will carry) any `Spec:` header, take its `<slug>` from the link text and read each `.task/spec/<slug>.md`, treating its decisions as a fixed anchor — `## Plan` must honor them, not re-derive a different technical choice. No `Spec:` header at all → no anchors, proceed on the Description alone.

Stop analysis as soon as you can name every file each step will touch and how — deeper investigation than that belongs to the implementing session's own reasoning, not to planning.

## Step 4: Resolve `tests_required`

From `.task/CLAUDE.md` → Testing Policy:

- `always` → `tests_required = true`.
- `never` → `tests_required = false`.
- `on-demand` → `true` only if the Description (or the chat discussion) explicitly asks for tests (phrases like "with tests", "add tests", "write tests"). Otherwise resolve two remaining cases distinctly:
  - **Silent** — nothing about tests anywhere → `tests_required = false`, no prompt.
  - **Testing-adjacent but unclear** — tests/testing mentioned but not whether *new* tests are wanted → in an interactive run, resolve it with one `AskUserQuestion` (convention (c)) before drafting `## Tests`: **Add tests** / **No tests this run**; in a non-interactive run (no user to ask — e.g. `to-plan` invoked as `roadmap-to-workflow`'s per-item planning agent) do not block, default to `false`.

`to-task` never writes `## Tests` (only `to-plan` does), so there is nothing to reuse from a prior `to-task` capture — resolve fresh here. In **revise** mode, reuse the prior `## Tests` resolution unless the current chat discussion or edit explicitly changes the testing ask.

## Step 5: Draft the Plan (and Tests)

Write `## Plan` using the three-layer step contract from `docs/contract.md`:

```markdown
## Plan

### Step 1: {short action title}
**Goal:** {the observable end state this step reaches — detailed enough that an
executor understands intent and result without guessing. Do not compress into
one line if the task has nuance; do not pad it with filler either.}
**Touches:** `{full path}` `{full path}` {…as many as this step actually changes}
**Logic:** {optional — pseudocode clarifying non-obvious branching/flow. Omit
entirely when Goal + Touches leave no ambiguity. Never include for a
straightforward step.}

### Step 2: ...
```

Rules:
- Full paths from the project root in `Touches`; no placeholders like `...` outside a `Logic` block.
- If a step is a new file, `Goal` states its role and `Touches` still names it; if a step modifies an existing file, `Goal` states the nature of the change and, where the file holds more than one unrelated concern, name the specific symbol(s) touched alongside the path (e.g. `` `src/auth/session.ts` (exports `refreshToken`) ``) so the implementing session doesn't have to guess.
- `Logic` is the only place a pseudocode block or a `...` placeholder belongs.
- Dry technical text throughout — but never at the cost of `Goal` being too thin to execute against.
- Order steps so no step depends on a fact that only a later step establishes.

If `tests_required` (Step 4) is `true`, append:

```markdown
## Tests

### Test 1: {what is asserted}
{file path; one line: the arrange/act/assert in prose. No code yet — the implementing session writes the real test.}

### Test 2: ...
```

Each `## Plan` step that satisfies a test references it by number in its `Goal` (e.g. "…; satisfies Test 2"). If `tests_required` is `false`, omit `## Tests` entirely — do not emit an empty heading.

**Not part of the format:** no `Implement-Model:` stamp (model hints live only on roadmap items as `**Model:**`), no `## Verification`, no `## Risks` — the `task.md` format ends at Execution.

## Step 6: Self-check before writing

Run through this checklist against the draft; fix inline before the write (Step 7), don't write something you already know is broken:

- [ ] Does `## Description` state the why, not just the what? (Fresh capture only — promote/revise inherit it as-is.)
- [ ] Does every `### Step N:` have a non-empty `**Touches:**` with at least one real path?
- [ ] Is `**Logic:**` present only where Goal + Touches genuinely leave ambiguity — not decoration?
- [ ] If `tests_required` is true, is `## Tests` present and does every step that satisfies a test reference it by number?
- [ ] If `tests_required` is false, is `## Tests` fully absent (no empty heading)?
- [ ] Any pinned spec decisions (`Spec:` headers, Step 3) honored, not silently overridden?
- [ ] No placeholders (`TBD`, `TODO`, `???`) anywhere outside an explicitly-marked `Logic` pseudocode block?
- [ ] Steps ordered so nothing depends on a not-yet-established fact?

## Step 7: Write

Write the file directly — no in-chat draft, no confirmation prompt. The chat discussion (and, in promote/revise, the existing Description) was the review; the written file is the deliverable, and Step 8's digest lets the user judge whether to open it.

**Fresh capture:**
```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # each Bash call is a FRESH shell — AI_DIR does not carry over from Step 0
: "${AI_DIR:?AI_DIR unresolved — re-run Step 0 before writing}"
mkdir -p "$AI_DIR/task"
# write $AI_DIR/task/<slug>.md — header + Description + Plan (+ Tests) + Execution
```
The re-source is mandatory, not decorative: sourcing `resolve-ws.sh` is idempotent (`find_ai_dir` no-ops once `AI_DIR` is set), and without it an unset `$AI_DIR` turns this into `mkdir -p /task` — the hazard Step 0 already names. `roadmap-to-workflow` re-sources in every bash block for the same reason.
Header + body, in order:
```markdown
# {Title}
Roadmap: [{slug}](../roadmap/{slug}.md)        (from-roadmap only)
Source item: #{N}                              (from-roadmap only)
Spec: [{spec-slug}](../spec/{spec-slug}.md)    (one line per relevant spec; omit if none)
---
## Description
{drafted body}

## Plan
{drafted steps}

## Tests
{drafted body, only if tests_required}

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

`{braces}` in the header and body lines are placeholders you substitute (`{Title}`, `{slug}`, `{N}`, `{drafted steps}`) — including inside the link targets, so `Roadmap: [api-v2](../roadmap/api-v2.md)`. The **Markdown-link form is the contract**: the link text is the slug that carries the identity, the target is what lets a viewer navigate. Both targets are `../<kind>/<slug>.md` because `.task/task/`, `.task/roadmap/` and `.task/spec/` are siblings — never compute a different depth. `Source item:` is a number, not a reference, and stays bare. The `## Execution` pointer is **stamped verbatim** — one line, byte-identical in every artifact, English, never translated and never expanded back into instructions. Those live in `.task/CLAUDE.md` → `## Executing a task`, in a single copy, so an edit there reaches tasks written earlier. The pointer still has to be in the file: the platform loads `.task/CLAUDE.md` only for file-read tools, so a session that opens the artifact with `cat` would otherwise see no instructions at all.

**Promote:** edit the existing `.task/task/<slug>.md` in place — insert the new `## Plan` block (and `## Tests`, if added) between `## Description`'s content and the existing `## Execution` pointer (a `to-task`-written file has no `## Tests`, so `## Plan` (+ new `## Tests`) is always inserted directly before `## Execution`). Do not touch the header, the `---` separator, `## Description`, or `## Execution` itself.

Three defensive cases, since Step 1 accepts a hand-written or hand-edited path as the target:
- **No `## Execution` pointer to anchor on** (hand-written file) → append `## Plan` (and `## Tests`) at end of file, then stamp the `## Execution` pointer after them, exactly as a fresh capture does. Same fallback revise mode already declares below — do not guess an insert position instead.
- **No `---` separator** (a hand-written file that has `## Description` but never split header from body) → insert a `---` line directly above `## Description`, leaving whatever header lines sit above it untouched. `validate.sh` treats a missing separator as a hard ERROR, so skipping this would make Step 7's own validate call fail on the file this very run just wrote.
- **No `## Description`** → the file is not a task artifact this skill can promote. **Stop and ask** rather than inventing one: "`.task/task/<slug>.md` has no `## Description` — say whether to treat it as a fresh capture at that path (overwriting it) or point me at a different file. → Next: say `fresh capture` to overwrite it, or `/task:to-plan <a different slug>`."

**Revise:** edit the existing `.task/task/<slug>.md` in place — replace the whole prior `## Plan` block with the new one (same position, still before `## Execution`). Replace `## Tests` only if the current chat's edit touched it; otherwise leave it exactly as it was. Leave `## Execution` untouched (re-stamp it only in the defensive case it's missing).

Then validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>` — surface any WARN/ERROR in Step 8's digest; only a setup-precondition failure (exit 2) hard-stops.

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

**Driver mode — suppress the footer.** In a non-interactive run as `roadmap-to-workflow`'s per-item plan agent (the same run Step 4 already carves out), print the digest but **omit** the `→ Next:` line and end with the driver's parser-stable line instead — `OK #N <item-slug> planned` on success, or `FAIL #N <item-slug> <what failed>` if you could not produce the plan (the driver's plan stage branches on both; a stop with no digest line at all leaves it nothing to read, so emit one of these two even when failing). The driver reads the last non-empty line and takes `<item-slug>` from it; a trailing footer would hand it a garbage slug and the next agent a non-existent task path.

## Forbidden

- Overwrite or paraphrase-away an existing `## Description` in promote or revise mode — only `## Plan` (and, narrowly, `## Tests`) are in scope for those modes.
- Pick a new slug / target path in promote or revise mode — the existing file resolved in Step 1 is reused as-is.
- Modify the source roadmap file or any referenced `.task/spec/<slug>.md` — all are read-only from here; checkbox auto-marking is the executing session's (or, for a roadmap run, the driver's) job, and specs are authored only by `to-spec`.
- Invent or resolve an active-task pointer — the target file is resolved per Step 1 every run.
- Leave `## Plan` present with zero `### Step N:` blocks, or `## Tests` present with zero `### Test N:` blocks — both fail `validate.sh`.
