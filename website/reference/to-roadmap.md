# to-roadmap

Fixes a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items, each with optional `**Dependencies:**` and `**Model:**` hints.

See the [roadmaps guide](/guide/roadmaps) for the end-to-end flow.

## Usage

```text
/task:to-roadmap <idea>
```

**Input** — `$ARGUMENTS`: a rough description of the initiative, or a reference back to a prior discussion (`"build a roadmap from what we discussed"`).

## When to use it

For work with phases, inter-task dependencies, or more than ~3 atomic steps. If the initiative is smaller than that, `to-roadmap` **stops and redirects** you to `to-task` / `to-plan` — one file per task is the better fit.

## What it writes

An item backlog, each item shaped like:

```markdown
### - [ ] 1. <Task title>

**Dependencies:** — / 1, 2, …
**Model:** haiku | sonnet | opus      (optional per-item hint)

**Ready description:**

> ### Context
> ### Goal
> ### Outcomes
> ### Invariants          (optional)
> ### Acceptance criteria
```

Items describe **observable behavior** — no project-specific file or symbol names; those are decided when the item is picked up in [`to-plan`](/reference/to-plan).

## Specs

If a load-bearing cross-item technical decision surfaces, `to-roadmap` does **not** inline it — it surfaces a recommendation to capture it via [`/task:to-spec`](/reference/to-spec), then the roadmap references it with a `Spec: [<slug>](../spec/<slug>.md)` header directly under its `# <Title>`, and items cite `### Spec references → [<slug>](../spec/<slug>.md) §N`. Both are Markdown links, so the reference is clickable in a viewer; the link text is the slug that carries the identity.

## Architecture

If the discussion also settles the initiative's **technical shape** — which components it builds, what one item hands another — `to-roadmap` doesn't inline that either: it flags the shape in the digest and recommends a [`/task:to-architecture <slug>`](/reference/to-architecture) follow-up, which adds a `## Architecture` section to the file this run just wrote. Re-running `to-roadmap` on an existing slug that already carries that section warns you first, before the overwrite prompt — an overwrite destroys the section, and `.task/` is git-excluded, so it isn't recoverable.

## Output

A digest, a report-only self-check (coverage / decomposition / clarity — findings surfaced, never silently rewritten into the file), then:

```text
Wrote `.task/roadmap/api-v2-migration.md`
API v2 migration
Items: 5 tasks across 2 phases — recommended order: 1 → 2 → 4 → 3 → 5
- 1. {item title}
- 2. …
Specs referenced: event-envelope
Technical shape: flagged for a /task:to-architecture follow-up
validate: OK — 0 errors, 0 warnings

→ Next: `/task:roadmap-to-workflow api-v2-migration` (run the whole roadmap),
  `/task:to-task api-v2-migration#1` (pick up the first item by hand — any item
  number works), or `/task:to-architecture api-v2-migration` (add the technical
  layer first — components, interfaces between items, per-item sketches — for
  every planner to follow)
```

## Does not

- Name project-specific files/symbols in `### Outcomes` / `### Goal` / `### Invariants`.
- Plan implementation details — that's [`to-plan`](/reference/to-plan)'s job when the item is picked up.
- Auto-check / auto-uncheck item checkboxes — that happens in the executing session (or the [`roadmap-to-workflow`](/reference/roadmap-to-workflow) driver in an autopilot run), never here.
- Modify any file other than the roadmap — specs are authored only by `to-spec`.
- Write the `## Architecture` section — that's [`to-architecture`](/reference/to-architecture)'s job, never this skill's.
- Hold more than one initiative per file.
