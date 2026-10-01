# to-roadmap

Fixes a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items, each with optional `**Dependencies:**` and `**Model:**` hints, **together with its `## Architecture`**: components, interfaces between items, a module-level sketch per item, and technical ordering.

See the [roadmaps guide](/guide/roadmaps) for the end-to-end flow.

## Usage

```text
/task:to-roadmap [initiative]
```

**Input** — `$ARGUMENTS`: a rough description of the initiative, or a reference back to a prior discussion (`"build a roadmap from what we discussed"`).

## When to use it

For work with phases, inter-task dependencies, or more than ~3 atomic steps. For a single task, `to-task` is usually the better fit — but the choice is yours: `to-roadmap` captures whatever you hand it.

## The flow

Behavioral decomposition first — items, phases, dependencies, settled with no source reading — then a module-level read of the code over the fixed items, then the architecture, drafted the same way (harvested from the discussion, or worked out in rounds), and finally **one write**: items and `## Architecture` land in the same file together. Always a new file; there is no enrich or revise mode — to change an existing roadmap's architecture, edit it in chat.

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

Items describe **observable behavior** — no project-specific file or symbol names; those are decided when the item is picked up in [`to-task`](/reference/to-task).

## Specs

If a load-bearing cross-item technical decision surfaces, `to-roadmap` does **not** inline it — it surfaces a recommendation to capture it via [`/task:to-spec`](/reference/to-spec), then the roadmap references it with a `Spec: [<slug>](../spec/<slug>.md)` header directly under its `# <Title>`, and items cite `### Spec references → [<slug>](../spec/<slug>.md) §N`. Both are Markdown links, so the reference is clickable in a viewer; the link text is the slug that carries the identity.

## Architecture

Every roadmap `to-roadmap` writes carries an `## Architecture` section — there's no separate command and no follow-up step:

```markdown
## Architecture

> Intended technical shape of this initiative — planners follow it and state a
> reason where the code forces a deviation. Decisions with rationale live in specs.

### Components
- `<name>` — new | existing · `<module path>` — role in this initiative.

### Interfaces between items       (omit when none)
- #2 → #4, #5 — `<name>`: what crosses the boundary; form pinned in [<slug>](../spec/<slug>.md) §N.

### Item sketches                  (one bullet per item)
- #1 — module-level sketch: which components it touches and how.

### Technical ordering             (omit when none)
- #3 before #6 — reason. Mirrored in item #6's `**Dependencies:**`.
```

Real module paths and symbol names are expected here — the behavioral discipline binds only an item's `### Outcomes` / `### Goal` / `### Invariants`. A choice whose **reasoning** must survive re-derivation still belongs in a spec; this section cites it as `[<slug>](../spec/<slug>.md) §N` rather than restating it. From then on, `to-task` on an item — interactive or through `roadmap-to-workflow`'s per-item plan agent — reads the section as the **intended shape**: its Plan follows the named components and interfaces by default, and a step is free to depart when the real code disagrees, as long as it says why.

**Specs vs. architecture** — the two divide cleanly. A spec says *why this form over that one*; the architecture section says *what goes where*. A component map that drifts into a spec is really architecture wearing the wrong hat.

## Output

A digest, a report-only self-check (coverage / decomposition / clarity / architecture — findings surfaced, never silently rewritten into the file), then:

```text
Wrote `.task/roadmap/api-v2-migration.md`
API v2 migration
Items: 5 tasks across 2 phases — recommended order: 1 → 2 → 4 → 3 → 5
1. {item title}
2. …

Architecture: 3 components, 2 interfaces, 5 item sketches
- `AuthGateway` — new, terminates the v2 auth handshake
- `LegacyAuthAdapter` — existing, bridges v1 sessions during the migration
- `SessionStore` — existing, holds tokens both adapters read

Interfaces: #2 → #4 `SessionToken`

Specs referenced: event-envelope

validate: OK — 0 errors, 0 warnings

→ Next: `/task:roadmap-to-workflow api-v2-migration` (run the whole roadmap —
  every item's planner follows this architecture) or `/task:to-task
  api-v2-migration#1` (pick up one item by hand — any item number works).
```

## Does not

- Name project-specific files/symbols in `### Outcomes` / `### Goal` / `### Invariants`.
- Plan implementation details — that's [`to-task`](/reference/to-task)'s job when the item is picked up.
- Auto-check / auto-uncheck item checkboxes — `task:code-reviewer` ticks an item once its review passes, whether in a plain session or a [`roadmap-to-workflow`](/reference/roadmap-to-workflow) run, never here.
- Modify any file other than the roadmap — specs are authored only by `to-spec`.
- Write plan-level detail in `## Architecture` — no `file:line` references, no step lists, no code block over 5 lines.
- Restate the items' behavioral outcomes as architecture.
- Edit an existing roadmap in place — this skill only writes new files; to change an existing roadmap's items or architecture, edit it in chat.
- Hold more than one initiative per file, or more than one `## Architecture` section in a file.
