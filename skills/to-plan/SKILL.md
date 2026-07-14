---
name: to-plan
description: 'Fix the chat discussion into task.md with a Plan — Description plus Goal/Touches/Logic steps, ready for a fresh session to implement. The deepest one-task capture; promotes an existing task.md that has no Plan yet, in place, instead of starting over.'
disable-model-invocation: true
user-invocable: true
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` **and** `## Plan` (the Goal/Touches/Logic step contract an implementing session consumes), plus `## Tests` when the testing policy calls for it, and the standard `## Execution` block. This is the deepest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it when you already know enough about the approach to hand straight to implementation, or run it again on a task that was only `to-task`-captured to add the Plan in place. The slug is the filename — there is no task-id and no active-task pointer; the artifact path is the handle.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far, or continue a task this conversation is clearly about (see Step 1).
- `<slug>` or a path to an existing `.task/task/<slug>.md` — target that file directly.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

**Format contract:** [docs/contract.md](../../docs/contract.md) is the single source of truth for the output structure — read it if anything below is ambiguous.

## Step 0: Setup gate

Check whether `.task/config/config.md` exists (resolve the pipeline root the same way `find_ai_dir` in `skills/_lib/resolve-ws.sh` does: `git config --local task.root` → ancestor walk for a `.task/config/config.md` ancestor → `dirname(git-common-dir)` → `$CLAUDE_PROJECT_DIR/.task` or `./.task`).

- **Absent → inline setup.** Identical to `to-task`'s Step 0 — this skill does not defer to a separate setup command:
  1. Determine the pipeline root `ROOT` (main worktree root; `pwd` for a non-git dir; for a bare repo the default is a best-effort guess — surface it in the proposal below so the user can redirect it).
  2. Analyze the project: read `CLAUDE.md` if present, detect language/stack, build/test commands, a project commit-format doc (check in order `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`), detected language policy (repo's dominant natural language from `git log -10 --oneline` + `CLAUDE.md`/`README.md` prose — default to "follow `task.md` Description" for English/mixed repos), and detected testing-policy mode (`always` if a TDD convention is documented, `on-demand` otherwise — never silently detect `never`).
  3. Show the detected config, then pose ONE `AskUserQuestion` confirmation (convention (b)):
     ```
     Detected — Language: <policy>; Testing policy: <mode>.
     ```
     Bare repo: add a third clause, `.task location: <ROOT>/.task`, editable the same way.
     Chips **Accept** / **Edit** / **Decline**:
     - **Accept** → adopt as-is.
     - **Edit** → follow-up asks which field(s) to amend (language policy / testing-policy mode / bare-repo `.task` location), then continue.
     - **Decline** → do not write anything; report "`config.md` not written — run `/task:to-plan` again when ready" and **stop**.
  4. Write `.task/config/config.md` (create `.task/task/` alongside it) using the standard template — sections: Code Navigation, Code Editing, Library Documentation, Project Conventions, Build and Tests, Commit Format, Language, Testing Policy, Directories — Do Not Search. Reference mode (a short `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer, ≤3 summary lines) when `CLAUDE.md` already documents a section; full mode otherwise. Commit Format: reference mode with just `**Source:** <path>` when a commit-format doc was found, else derive rules from `git log`.
  5. Record `git config --local task.root "$ROOT"` (repo-common, shared by every worktree).
  6. Exclude `.task` locally: `EXCLUDE=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"; grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"`. Skip with a warning if not a git repo.
  7. Report what was written, then continue to Step 0's validate call below with the original `$ARGUMENTS` unchanged.
- **Present → skip silently**, proceed to validate.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` as a self-check — v3 has no gate, so report any findings and continue rather than blocking. The only thing that should stop the flow here is a genuine config-precondition failure (exit 2), which shouldn't occur since Step 0 just confirmed `config.md` exists.

## Step 1: Resolve the target and capture mode

There is **no active-task pointer** in v3 — the artifact path is the handle. Resolve a target reference, in order:

1. **Explicit slug or path in `$ARGUMENTS`** matching `.task/task/<slug>.md` (existing or not) → that path is the target.
2. **Roadmap reference in `$ARGUMENTS`** (`<roadmap-slug>` or `<roadmap-slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → resolve the item (Step 2a's item-picking logic) and derive its target path `.task/task/<item-slug>.md` from the item title.
3. **No positional reference, but the chat is clearly continuing or refining a task this session already captured** (a `to-task`/`to-plan` run earlier in this conversation, or the user names an existing task by title/slug) → that file is the target. If more than one file could plausibly match, ask via `AskUserQuestion` (convention (c)) rather than guessing.
4. **Nothing resolves** → no target; go to Step 2 for a fresh capture with no prior reference.

Once a target reference is resolved (1–3), branch on whether the file exists:

- **Target file does not exist yet** → **fresh capture** at that path. If it came from a roadmap reference, continue at Step 2a; otherwise treat the resolved slug/title as a starting point and continue at Step 2b.
- **Target file exists, no `## Plan` heading present** → **promote mode.** This is the flag-free way to turn a `to-task` capture into a plan: skip Step 2 entirely — header and `## Description` already exist and are untouched. Go straight to Step 3 using the existing Description as context, then in Step 8 **insert** `## Plan` (and `## Tests`) rather than create.
- **Target file exists, `## Plan` already present** → **revise mode.** `to-plan` was already run on this file. Skip Step 2, go straight to Step 3 using the existing Description (and the current chat) as context, then in Step 8 **replace** the existing `## Plan` (and `## Tests` only if the user's edit touches it) rather than create or blindly append a duplicate section.

No target at all (case 4): if one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item **and** there is no chat discussion to draft from, present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as Step 2a with the chosen slug. Otherwise (there is chat discussion to draft from, with or without extra free-form `$ARGUMENTS`) proceed as Step 2b.

## Step 2: Fresh capture — Title and Description

Only for fresh capture (skip entirely for promote/revise — see Step 1).

### Step 2a: From-roadmap

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — stop and ask.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop: "all items in `<slug>` are closed; pick one explicitly with `<slug>#<N>`, or draft from chat instead." More than one open item → ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); exactly one → auto-pick it.
3. Read the item's `### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria` block. `### Context` becomes the Description's "why"; the rest folds into the "what". `### Acceptance criteria` entries are good candidates to carry into `## Tests` (Step 4) verbatim as test intents when tests are required.
4. Note the specs this item relies on: any `### Spec references → <spec-slug> §N` in the item body, plus the roadmap's own `Spec: <slug>` header lines. Read each `.task/spec/<spec-slug>.md` now — carry them into Step 3 as pinned anchors (see Step 3's note), and hold the distinct `<spec-slug>`s for the `Spec:` headers in Step 8's write.
5. Derive the slug: kebab-case of the item title (2–4 words). If it collides with an existing, unrelated `.task/task/<slug>.md`, disambiguate with a short qualifier (e.g. append a second distinguishing word) rather than overwriting.
6. Hold the header lines for Step 8's write:
   ```
   # {Item title}

   Roadmap: {slug}
   Source item: #{N}
   Spec: {spec-slug}          (one line per spec the item cites; omit if none)
   ```
   and the drafted `## Description` body (why from Context, what from Goal/Outcomes/Invariants/Acceptance criteria). Continue to Step 3 — do not write the file yet; the full task.md (Description + Plan + Tests) is presented once, together, in Step 7.

### Step 2b: Chat-draft

1. **Slug.** Generate a short kebab-case slug (2–4 words) from the chat's essence, in English regardless of `config.md` → Language (the slug is a filename, a parser-stable string). If it collides with an existing, unrelated task file, disambiguate rather than overwriting.
2. **Distil the chat.** Read back over the discussion in this conversation (not the codebase yet) and draft `## Description` — the why + what, in the user's own framing. Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
3. Hold the header line `# {Short task title}` (no `Roadmap:` / `Source item:` lines in this mode) and the drafted Description for Step 8. If the discussion clearly relies on a spec in `.task/spec/`, hold a `Spec: <slug>` header line for each relevant one too (never invent a reference; never author the spec — that is `to-spec`'s job). Continue to Step 3.

## Step 3: Analyze the codebase

Shared by every mode (fresh chat-draft, fresh from-roadmap, promote, revise) — this is what makes `to-plan` deeper than `to-task`: `## Plan` steps need real paths, not paraphrase.

Use the Description (fresh capture) or the existing `## Description` (promote/revise) as the "what" to ground against real code. Read code in ascending cost order per `config.md` → Code Navigation (MCP tools first, built-ins as fallback):

1. From modules/packages/files named or implied in the Description — get a structural overview.
2. Read symbol bodies selectively — only those directly affected.
3. Identify dependencies and usage locations.
4. Find existing patterns in neighboring code for reuse.
5. Assess impact on adjacent modules/components.

**Pinned technical decisions.** If the task carries (or, on fresh capture, will carry) any `Spec: <slug>` header, read each `.task/spec/<slug>.md` and treat its decisions as a fixed anchor — `## Plan` must honor them, not re-derive a different technical choice. No `Spec:` header at all → no anchors, proceed on the Description alone.

Stop analysis as soon as you can name every file each step will touch and how — deeper investigation than that belongs to the implementing session's own reasoning, not to planning.

## Step 4: Resolve `tests_required`

From `.task/config/config.md` → Testing Policy → Mode:

- `always` → `tests_required = true`.
- `never` → `tests_required = false`.
- `on-demand` → `true` only if the Description (or the chat discussion) explicitly asks for tests (phrases like "with tests", "add tests", "write tests"). Otherwise resolve two remaining cases distinctly:
  - **Silent** — nothing about tests anywhere → `tests_required = false`, no prompt.
  - **Testing-adjacent but unclear** — tests/testing mentioned but not whether *new* tests are wanted → in an interactive run, ask one yes/no question before drafting `## Tests`; in a non-interactive run (no user to ask — e.g. `to-plan` invoked as `roadmap-to-workflow`'s per-item planning agent) do not block, default to `false`.

If `tests_required` was already decided by an earlier `to-task` capture, note that `to-task` never writes `## Tests` in v3 (only `to-plan` does) — so there is nothing to reuse from it; resolve fresh here. In **revise** mode, reuse the prior `## Tests` resolution unless the current chat discussion or edit explicitly changes the testing ask.

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
- Order steps so a later step never depends on a fact only a later step establishes.

If `tests_required` (Step 4) is `true`, append:

```markdown
## Tests

### Test 1: {what is asserted}
{file path; one line: the arrange/act/assert in prose. No code yet — the implementing session writes the real test.}

### Test 2: ...
```

Each `## Plan` step that satisfies a test references it by number in its `Goal` (e.g. "…; satisfies Test 2"). If `tests_required` is `false`, omit `## Tests` entirely — do not emit an empty heading.

**Dropped on purpose:** no `Implement-Model:` stamp (model hints now live only on roadmap items as `**Model:**`, unrelated to this file), no `## Verification` section, no `## Risks` section. `docs/contract.md`'s `task.md` format is header → Description → Plan → Tests → Execution, nothing else.

## Step 6: Self-check before presenting

Run through this checklist against the draft; fix inline before Step 7, don't present something you already know is broken:

- [ ] Does `## Description` state the why, not just the what? (Fresh capture only — promote/revise inherit it as-is.)
- [ ] Does every `### Step N:` have a non-empty `**Touches:**` with at least one real path?
- [ ] Is `**Logic:**` present only where Goal + Touches genuinely leave ambiguity — not decoration?
- [ ] If `tests_required` is true, is `## Tests` present and does every step that satisfies a test reference it by number?
- [ ] If `tests_required` is false, is `## Tests` fully absent (no empty heading)?
- [ ] Any pinned spec decisions (`Spec:` headers, Step 3) honored, not silently overridden?
- [ ] No placeholders (`TBD`, `TODO`, `???`) anywhere outside an explicitly-marked `Logic` pseudocode block?
- [ ] Steps ordered so nothing depends on a not-yet-established fact?

## Step 7: Present for confirmation

Content shown depends on mode (convention (b) throughout):

- **Fresh capture** — show the full drafted `task.md` (header + Description + Plan + Tests + Execution).
- **Promote** — show only the new `## Plan` (+ `## Tests` if newly added); state plainly that the existing Description is untouched.
- **Revise** — show the new `## Plan` next to a one-line note of what changed from the old one; state plainly that Description and any pre-existing Tests are untouched unless the chat explicitly asked to change them too.

Then pose an `AskUserQuestion` with chips **Accept** / **Edit** / **Decline**:

- **Accept** → proceed to Step 8 as drafted.
- **Edit** → follow-up asks what to change, apply it, re-show, repeat until accepted.
- **Decline** → write nothing, stop with "`task.md` not written" (promote/revise: "no changes made to `task.md`").

## Step 8: Write

**Fresh capture:**
```bash
mkdir -p .task/task
# write .task/task/<slug>.md — header + Description + Plan (+ Tests) + Execution
```
Header + body, in order:
```markdown
# {Title}
Roadmap: {slug}            (from-roadmap only)
Source item: #{N}          (from-roadmap only)
Spec: {spec-slug}          (one line per relevant spec; omit if none)
---
## Description
{drafted body}

## Plan
{drafted steps}

## Tests
{drafted body, only if tests_required}

## Execution
> If any `Spec:` headers are present, first read each referenced `.task/spec/<slug>.md`
> as a fixed technical anchor — honor its decisions, do not re-derive them. Then implement
> the plan above (or the Description if there is no Plan), reading and editing code with the
> tools in `.task/config/config.md` → Code Navigation / Code Editing (MCP tools first,
> built-ins as fallback). Then run the `/verify` skill end-to-end and `/code-review` on the
> diff; apply review fixes ONLY within the files named in **Touches** (report the rest). If
> there is no `## Plan`, and so no **Touches**, scope review fixes to the files you changed
> for the Description. Commit per `.task/config/config.md` → Commit Format. If `Roadmap:` +
> `Source item:` headers are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
```

**Promote:** edit the existing `.task/task/<slug>.md` in place — insert the new `## Plan` block (and `## Tests`, if added) between `## Description`'s content and the existing `## Execution` block (a `to-task`-written file has no `## Tests`, so `## Plan` (+ new `## Tests`) is always inserted directly before `## Execution`). Do not touch the header, the `---` separator, `## Description`, or `## Execution` itself.

**Revise:** edit the existing `.task/task/<slug>.md` in place — replace the whole prior `## Plan` block with the new one (same position, still before `## Execution`). Replace `## Tests` only if Step 7's edit touched it; otherwise leave it exactly as it was. Leave `## Execution` untouched (re-stamp it only in the defensive case it's missing).

## Step 9: Output

Report the path to the written `task.md`, the mode used (fresh / promote / revise), and a 1–2 line summary of `## Plan` (step count, whether `## Tests` is present). Close with the v3 handoff footer — the artifact path is the handle, there is no pointer (convention (a), flag-free):

`→ Next: implement it now, or in a fresh session run: \`implement .task/task/<slug>.md\``

## Forbidden

- Stamp an `Implement-Model:` field, or emit `## Verification` / `## Risks` sections — none of that exists in v3's `task.md` format.
- Overwrite or paraphrase-away an existing `## Description` in promote or revise mode — only `## Plan` (and, narrowly, `## Tests`) are in scope for those modes.
- Pick a new slug / target path in promote or revise mode — the existing file resolved in Step 1 is reused as-is.
- Scan the codebase beyond what Step 3 needs to name real `Touches` paths — this is planning depth, not a full implementation read.
- Modify the source roadmap file or any referenced `.task/spec/<slug>.md` — all are read-only from here; checkbox auto-marking is the executing session's (or, for a roadmap run, the driver's) job, and specs are authored only by `to-spec`.
- Invent or resolve an active-task pointer — none exists in v3; the target file is resolved per Step 1 every run.
- Leave `## Plan` present with zero `### Step N:` blocks, or `## Tests` present with zero `### Test N:` blocks — both fail `validate.sh`.
