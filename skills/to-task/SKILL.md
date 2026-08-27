---
name: to-task
description: 'Capture the chat (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`.'
disable-model-invocation: true
user-invocable: true
---

Distil the chat discussion so far (or a roadmap item) into `.task/task/<slug>.md` — `## Description` only, no `## Plan`. Lightest of the three capture skills (`to-task` / `to-plan` / `to-roadmap`): use it to record the "what and why" before implementing directly, or before `to-plan` later. The written file is the handle — no active-task pointer, no separate execution skill; a fresh session implements it by reading `## Execution`.

**Input:** `$ARGUMENTS` — optional. Recognized forms:
- (empty) — draft from the chat discussion so far.
- `<roadmap-slug>` or `<roadmap-slug>#<N>` — open from that roadmap item instead of the chat.
- anything else — free-form context to fold into the draft alongside the chat discussion.

## Step 0: Setup gate

Resolve the pipeline root, then check whether its `CLAUDE.md` exists:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve-ws.sh"   # sourcing runs find_ai_dir → sets AI_DIR
echo "$AI_DIR"                                             # the resolved root — use this value verbatim in every artifact path below
[[ -f "$AI_DIR/CLAUDE.md" ]] || echo "CLAUDE.md not found"
```

The helper walks `task.root` git config when that path already holds a `.task/CLAUDE.md` → ancestor `.task/CLAUDE.md` (the walk stops at the top of this project, so it never claims a neighbouring one's `.task/`) → `dirname(git-common-dir)/.task` → `$CLAUDE_PROJECT_DIR/.task` when that path already holds a `CLAUDE.md` → `./.task`. Use `${CLAUDE_PLUGIN_ROOT}` — a bare `skills/…` path resolves against the user's project cwd, where it does not exist.

The echoed value is normally absolute. In a project that is not a git repository and has no `.task/` yet it can be the bare relative `.task` — the historical default; treat that as "unconfigured" and let the inline setup below establish `<ROOT>/.task`, rather than writing a cwd-relative artifact from a subdirectory.

**Once `.task/CLAUDE.md` exists, every artifact path in this skill is under that resolved `$AI_DIR`, never the cwd** — `.task/task/<slug>.md` below is shorthand for `$AI_DIR/task/<slug>.md`. A cwd-relative write from a subdirectory or a linked worktree would create a second `.task/` that `validate.sh` (which resolves `$AI_DIR` itself) never sees. The inline setup below is the one exception: it runs *before* a root exists, writes to `<ROOT>/.task`, and records `git config task.root "$ROOT"` — which is exactly what `$AI_DIR` resolves to on every later run.

- **Absent → inline setup.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it: detect the stack → write `$AI_DIR/CLAUDE.md` from its template → record `git config --local task.root` → exclude `.task` → report what was written. **No confirmation chip:** the file is written first and edited afterwards if a detected value came out wrong. `setup.md` is the single source of truth for the sub-steps *and* for the `.task/CLAUDE.md` template — do not restate either here. Then continue with the original `$ARGUMENTS` unchanged.
- **Present → leave it alone.** The file is user-owned: never rewrite it, never re-detect its values, never "repair" a section you find missing. Only the two markers are restored silently when absent: `git config --local task.root` and the `.task` line in `.git/info/exclude`. To regenerate the file from scratch, the user deletes it and re-runs any capture.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` — an optional self-check, not a gate: report any WARN/ERROR lines, but only hard-stop when `.task/CLAUDE.md` is genuinely absent (Step 0 just handled that). Never block on a pre-existing artifact failing validation.

## Step 1: Entry

No pointer to resolve — the artifact path is the handle. Branch on `$ARGUMENTS`:

1. **Positional roadmap reference** (`<slug>` or `<slug>#<N>`, matching an existing `.task/roadmap/<slug>.md`) → **from-roadmap mode**, Step 1a below.
2. **No positional roadmap reference, and one or more `.task/roadmap/*.md` files have an unchecked (`- [ ]`) item, and there is no chat discussion to draft from** → present an `AskUserQuestion` fork (convention (c)): "How do you want to start this task?" — **Draft from this chat** / **Open from a roadmap**. The latter opens a second `AskUserQuestion` listing the roadmap slugs, then proceeds as from-roadmap mode with the chosen slug.
3. **There is chat discussion _or_ free-form `$ARGUMENTS` to draft from** (either alone is enough — a user who described the task on the command line has already said what to capture) → **chat-draft mode**, Step 2 below.
4. **Nothing to draft from at all** (no chat discussion, no free-form `$ARGUMENTS`, and no unchecked roadmap item) → **stop** and ask the user what to capture rather than drafting a Description from nothing: "nothing to capture yet — describe the task in chat, or name it directly. → Next: `/task:to-task <what to capture>`"

### Step 1a: From-roadmap mode

1. Resolve `<slug>` to `.task/roadmap/<slug>.md`; if ambiguous or missing — **stop**, name the roadmap slugs that do exist, and close with a runnable footer (convention (a)): `→ Next: \`/task:to-task <one of those slugs>\``.
2. Pick `<N>`: if given, use it. Otherwise collect open items (`- [ ]` checkbox headings); if none — stop with "Every item in `<slug>` is already checked off." and a **runnable** footer: substitute a real item number from the file, never a literal `<N>` — `→ Next: \`/task:to-task <slug>#3\` to redo a specific item (numbers as in the roadmap), or describe new work in chat and run \`/task:to-task\`.` If more than one open item, ask via `AskUserQuestion` (chip per `#<N> — <title>`, first/lowest default); if exactly one, auto-pick it.
3. Read the item's `**Ready description:**` blockquote — its sub-headings are quoted (`> ### Context` / `> ### Goal` / `> ### Outcomes` / `> ### Invariants` / `> ### Acceptance criteria`); strip the `> ` prefix as you read. (`validate.sh` makes both the label and the blockquote a hard ERROR, so a bare unquoted `### Context` means the roadmap is malformed, not that the shape is optional.) `### Context` becomes the Description's "why"; the rest folds into the "what". Also note any `### Spec references → [<spec-slug>](../spec/<spec-slug>.md) §N` the item carries, and the roadmap's own `Spec:` header lines — collect the distinct `<spec-slug>`s to stamp as `Spec:` headers on the task (step 5). Read a slug from the link **text**, not from the link target: the target is relative to the roadmap file's own directory and would not resolve from your cwd. A hand-edited roadmap may carry the older bare `Spec: <slug>` / `### Spec references → <slug> §N` form — read it the same way.
4. Derive `<item-slug>` — kebab-case English from the item's own title (not the roadmap's). No task-id, no `derive-task-id` helper: the item gets its own `<item-slug>.md`, independent of the roadmap's slug.

   **Slug collision.** If `$AI_DIR/task/<item-slug>.md` already exists, do not assume it is this item's — read its header first. A `Roadmap:` whose link text matches this roadmap's slug plus a matching `Source item: #<N>` means it **is** this item's earlier capture: Description-only → rewriting it in place is safe; if it already carries a `## Plan`, an overwrite would destroy that plan — run the Step 2.1 slug-collision guard instead (its chips already recommend deepening via `/task:to-plan`). Different headers, or none, mean an unrelated task that merely kebab-cases the same title: disambiguate `<item-slug>` with a short qualifier (as `to-plan` Step 2a.5 does) rather than overwriting.
5. Write `$AI_DIR/task/<item-slug>.md` directly (creating `$AI_DIR/task/` if needed) — no in-chat draft, no confirmation prompt; the roadmap item is the settled source:

   ```markdown
   # {Item title}
   Roadmap: [{slug}](../roadmap/{slug}.md)
   Source item: #{N}
   Spec: [{spec-slug}](../spec/{spec-slug}.md)   (one line per spec the item cites; omit entirely if none)
   ---
   ## Description

   {Why: paraphrase of ### Context. What: paraphrase of ### Goal / ### Outcomes / ### Invariants / ### Acceptance criteria.}

   ## Execution
   > Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
   ```

   `{braces}` in the header lines are placeholders you substitute (`{Item title}`, `{slug}`, `{N}`) — including inside the link targets, so `Roadmap: [api-v2](../roadmap/api-v2.md)`. The **Markdown-link form is the contract**: the link text is the slug that carries the identity, the target is what lets a viewer navigate. Both targets are `../<kind>/<slug>.md` because `.task/task/`, `.task/roadmap/` and `.task/spec/` are siblings — never compute a different depth. `Source item:` is a number, not a reference, and stays bare. The `## Execution` pointer is **stamped verbatim** — one line, byte-identical in every artifact, English, never translated and never expanded back into instructions. The instructions themselves live in `.task/CLAUDE.md` → `## Executing a task`, in one copy, so editing them there reaches tasks that were written earlier. The pointer still has to be in the file: the platform loads `.task/CLAUDE.md` only for file-read tools, so a session that opens the artifact with `cat` would otherwise see no instructions at all.
6. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <item-slug>` — surface any WARN/ERROR in Step 3's digest; only a setup-precondition failure (exit 2) hard-stops.
7. Continue to Step 3 (digest + footer), using `<item-slug>` as `<slug>` there.

### Step 2: Chat-draft mode

1. **Slug.** Derive a kebab-case English slug (2–5 words) from the chat's essence / the drafted title. This is both the filename and the task's identity — no task-id, no bracket.

   **Slug collision.** If `.task/task/<slug>.md` already exists, surface it before writing. First **read the existing file's headings** and state them as message text above the chip, so the user knows what an overwrite costs — e.g. "Existing `.task/task/<slug>.md` has: Description, Plan (4 steps), Tests (2)." Then pose an `AskUserQuestion`:
   - **The existing file has a `## Plan`** → an overwrite would destroy it, and `.task/` is git-excluded, so there is nothing to restore from. Recommend deepening instead: chips **Deepen it — `/task:to-plan`** *(Recommended)* / **Pick a different slug** / **Overwrite (loses the Plan)** / **Decline → stop without writing**.
   - **Description only** → the cheap case: chips **Accept overwrite** / **Edit → propose a different slug** / **Decline → stop without writing**.
2. **Read `.task/CLAUDE.md`** for Language before drafting. Step 0's gate only *tests* for the file with Bash, which does not pull it into context — the platform's auto-load fires for file-read tools only, and on this path nothing else under `.task/` is opened.
3. **Distil the chat.** Read back over the discussion in this conversation (not the codebase) and write:
   - `## Description` — the why + what, in the user's own framing, written per `.task/CLAUDE.md` → Language (the section labels themselves stay English). Use `### Problem` / `### Outcome` / `### Scope` / `### Constraints` sub-headers where the discussion gives signal for them; omit a sub-header rather than inventing content. Do not fabricate anything not actually discussed.
   - **No `## Plan` and no `## Tests`** — both are `to-plan`'s job; run `to-plan` later to add them (Tests when Testing Policy warrants).
   - **Specs (optional).** If `.task/spec/` holds a spec the discussion clearly relies on, add a `Spec: [<slug>](../spec/<slug>.md)` header line for each (ASCII, above `---`) so the executing session reads it as a fixed anchor. Only reference specs actually relevant — never invent one, and never write the spec file here (that is `to-spec`'s job).
4. **Write `$AI_DIR/task/<slug>.md` directly** (creating `$AI_DIR/task/` if needed) — no in-chat draft, no confirmation prompt. The chat discussion was the review; the written file is the deliverable, and the Step 3 digest lets the user judge whether to open it. (The Step 2.1 slug-collision guard still runs before this write.) No `Roadmap:` / `Source item:` lines in this mode; include a `Spec:` line per relevant spec, or none:

   ```markdown
   # {Short task title}
   Spec: [{spec-slug}](../spec/{spec-slug}.md)   (one line per relevant spec; omit entirely if none)
   ---
   ## Description

   {drafted body}

   ## Execution
   > Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
   ```

   The `## Execution` line is the same pointer as Step 1a's template — stamped byte-identical, never paraphrased.
5. Validate the written file: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task <slug>` — surface any WARN/ERROR in Step 3's digest.

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
