# Open a roadmap item

The shared from-roadmap block: resolve the roadmap, pick the item, read its
ready description, collect the specs it cites, and derive the task slug. Read by
`to-task` (Step 1a) and the driver's plan agent (`plan-driver.md` § Driver mode) —
one copy, so the item-picking rules cannot drift between them. Both are planners,
so both run steps 3–6, step 6 included; steps 1–2 are `to-task`'s — the driver's
plan agent receives their results in its prompt.

[docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd)
is the item grammar; [§ Cross-artifact references](../../docs/contract.md#cross-artifact-references)
is the one rule for every link-shaped header and citation below: **the label
carries the identity, the href is for viewers** — take the slug from the link
text and rebuild `$AI_DIR/<kind>/<slug>.md` yourself, and read a hand-edited
bare slug the same way.

## 1. Resolve the roadmap

The `ROADMAPS:` line for `<slug>` from the caller's Step 0 block names the file:
`$AI_DIR/roadmap/<slug>.md`. No such line means no such roadmap — **stop**, name
the slugs that are listed, and close with a runnable footer that carries one of
them, never a literal `<slug>`.

## 2. Pick the item

- `#<N>` given → use it.
- Otherwise → the roadmap's `unchecked=` list is the open items; read their
  titles from the file. More than one: ask via `AskUserQuestion` (one chip per
  `#<N> — <title>`, lowest number the default). Exactly one: take it.
- `0/0 unchecked=none` → **stop**: no item heading in `$AI_DIR/roadmap/<slug>.md`
  parses — this is not a finished roadmap. Footer: `→ Next: \`bash
  "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>\`, fix the
  headings, rerun \`<the caller's command> <slug>\`.`
- Any other `unchecked=none` → **stop**: every item is already checked off. Footer:
  `→ Next: \`<the caller's command> <slug>#<a real item number from the file>\`
  to redo a specific item, or describe new work in chat.`
- `unchecked=unreadable` → **stop**: the roadmap file could not be read. Name
  `$AI_DIR/roadmap/<slug>.md`. Footer: `→ Next: fix the file's permissions, then
  rerun \`<the caller's command> <slug>\`.`

## 3. Read the ready description

Read the item's `**Ready description:**` blockquote. Its sub-headings are
quoted bold lines — `> **Context**` / `> **Goal**` / `> **Outcomes**` / `> **Invariants**` /
`> **Acceptance criteria**` — so strip the `> ` prefix as you read. `**Context**`
becomes the Description's "why"; the rest folds into the "what".
`**Acceptance criteria**` entries carry into `## Tests` verbatim as test intents
when tests are required.

`validate.sh` makes both the label and the blockquote a hard ERROR, so a bare
unquoted `**Context**` means the roadmap is malformed — not that the shape is
optional.

## 4. Collect the specs

Two sources, both slugs: the item's own `> **Spec references:** [<slug>](../spec/<slug>.md) §N`
citations, and the roadmap's own `Spec:` header lines. Hold the distinct slugs —
they become the task's `Spec:` headers, and each `$AI_DIR/spec/<slug>.md` is read
as a fixed anchor before drafting.

## 5. Derive the slug, and check whose file it is

`<item-slug>` is kebab-case English, 2–4 words, from the **item's** title (not the
roadmap's). It is the filename and the identity — no task-id, no bracket.

If it is already in the caller's `TASKS:` list — or, for a caller that has no
`TASKS:` list (the driver's plan agent), if `$AI_DIR/task/<item-slug>.md`
exists — do not assume that file is this item's. Read its header:

- `Roadmap:` label matches this roadmap's slug **and** `Source item: #N` matches
  this item → it **is** this item's earlier capture. The interactive caller
  (`to-task`) asks before replacing it — its slug-collision chip, never a silent
  `--force`; the driver's plan agent, which has nobody to ask, regenerates it
  per `plan-driver.md` D2 — this header match is the guard that earns its `--force`.
- Different headers, or none → an unrelated task that merely kebab-cases the same
  title. Disambiguate `<item-slug>` with a short qualifier — append a second
  distinguishing word — and **never** overwrite it. Then run this same check on
  the new slug: a rerun derives the same qualifier, so the file there may be this
  item's own earlier capture (the first bullet) or another namesake (this one,
  again). Repeat until the slug is free or is this item's own file.

## 6. Note the architecture

If the roadmap carries an `## Architecture` section, note it and this item's
`#<N>` bullet under `### Item sketches`: `plan-driver.md` § Core step 1 reads them
as the intended shape before drafting the Plan. Hold nothing for the write — the
section stays in the roadmap, and the task file gains no header for it. The
Description stays behavioral all the same: technical shape enters only through
the Plan.
