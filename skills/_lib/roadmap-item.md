# Open a roadmap item

The shared from-roadmap block: resolve the roadmap, pick the item, read its
ready description, collect the specs it cites, and derive the task slug. Read by
`to-task` (Step 1a), `to-plan` (Step 2a) and the driver's plan agent
(`plan-driver.md` § Driver mode) — one copy, so the item-picking rules cannot
drift between them.

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
them, never a literal `<slug>`. In driver mode the roadmap path arrives in the
prompt instead, already resolved.

## 2. Pick the item

- `#<N>` given → use it.
- Otherwise → the roadmap's `unchecked=` list is the open items; read their
  titles from the file. More than one: ask via `AskUserQuestion` (one chip per
  `#<N> — <title>`, lowest number the default). Exactly one: take it.
- `unchecked=none` → **stop**: every item is already checked off. Footer:
  `→ Next: \`<the caller's command> <slug>#<a real item number from the file>\`
  to redo a specific item, or describe new work in chat.`
- Driver mode never picks: `#N` and the title arrive in the prompt.

## 3. Read the ready description

Read the item's `**Ready description:**` blockquote. Its sub-headings are
quoted — `> ### Context` / `> ### Goal` / `> ### Outcomes` / `> ### Invariants` /
`> ### Acceptance criteria` — so strip the `> ` prefix as you read. `### Context`
becomes the Description's "why"; the rest folds into the "what".
`### Acceptance criteria` entries carry into `## Tests` verbatim as test intents
when tests are required.

`validate.sh` makes both the label and the blockquote a hard ERROR, so a bare
unquoted `### Context` means the roadmap is malformed — not that the shape is
optional.

## 4. Collect the specs

Two sources, both slugs: the item's own `### Spec references → [<slug>](../spec/<slug>.md) §N`
citations, and the roadmap's own `Spec:` header lines. Hold the distinct slugs —
they become the task's `Spec:` headers, and each `$AI_DIR/spec/<slug>.md` is read
as a fixed anchor before drafting.

## 5. Derive the slug, and check whose file it is

`<item-slug>` is kebab-case English, 2–4 words, from the **item's** title (not the
roadmap's). It is the filename and the identity — no task-id, no bracket.

If it is already in the caller's `TASKS:` list, do not assume that file is this
item's. Read its header:

- `Roadmap:` label matches this roadmap's slug **and** `Source item: #N` matches
  this item → it **is** this item's earlier capture. Extend it in place
  (promote / revise), never as a fresh write.
- Different headers, or none → an unrelated task that merely kebab-cases the same
  title. Disambiguate `<item-slug>` with a short qualifier — append a second
  distinguishing word — and **never** overwrite it.
