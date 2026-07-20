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

If a load-bearing cross-item technical decision surfaces, `to-roadmap` does **not** inline it — it surfaces a recommendation to capture it via [`/task:to-spec`](/reference/to-spec), then the roadmap references it with a `Spec:` header and items cite `### Spec references → <slug> §N`.

## Output

A digest, a report-only self-check (coverage / decomposition / clarity — findings surfaced, never silently rewritten into the file), then:

```text
Wrote `.task/roadmap/api-v2-migration.md`
API v2 migration
Items: 5 tasks across 2 phases — recommended order: 1 → 2 → 4 → 3 → 5
- 1. {item title}
- 2. …
Specs referenced: event-envelope
validate: OK — 0 errors, 0 warnings

→ Next: `/task:roadmap-to-workflow` or `/task:to-task api-v2-migration#1`
```

## Does not

- Name project-specific files/symbols in `### Outcomes` / `### Goal` / `### Invariants`.
- Plan implementation details — that's [`to-plan`](/reference/to-plan)'s job when the item is picked up.
- Auto-check / auto-uncheck item checkboxes — that's the [`roadmap-to-workflow`](/reference/roadmap-to-workflow) driver's exclusive job.
- Modify any file other than the roadmap — specs are authored only by `to-spec`.
- Hold more than one initiative per file.
