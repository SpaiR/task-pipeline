# Roadmaps

A **roadmap** groups several tasks into one initiative. Where [`to-task`](/reference/to-task) / [`to-plan`](/reference/to-plan) each capture one task, [`/task:to-roadmap`](/reference/to-roadmap) captures a whole phase-grouped backlog of ready-to-pick-up items into `.task/roadmap/<slug>.md`.

Reach for it when the work has phases, inter-task dependencies, or more than a couple of atomic steps. For anything smaller, a single task is the better fit — `to-roadmap` will actually stop and redirect you if the initiative is too small.

## Capture the initiative

Talk through the initiative in chat — phases, dependencies, open questions — then:

```text
/task:to-roadmap "migrate the public API to v2"
# → .task/roadmap/api-v2-migration.md — a phase-grouped backlog where each item
#   carries a Ready description (Context / Goal / Outcomes / Invariants /
#   Acceptance criteria) and optional **Dependencies:** and **Model:** hints
```

Each item is written so a reader who hasn't seen the discussion could pick it up cold. Items describe **observable behavior** — no project-specific file or symbol names; those are decided when the item is picked up in `to-plan`.

If a load-bearing technical decision surfaces during the discussion, capture it separately with [`/task:to-spec`](/guide/specs) and reference it from the roadmap via a `Spec: [<slug>](../spec/<slug>.md)` header, directly under the roadmap's `# <Title>` — roadmaps don't inline cross-item technical decisions.

## Add the technical layer

Once the items exist, the initiative usually has a technical shape too: which components it builds or changes, what one item hands another, a module-level sketch per item, and a technical ordering between them. That's neither an item (items stay behavioral, no project names) nor a spec (a spec pins a decision's *reasoning*, not a layout) — it's a roadmap's own `## Architecture` section, and [`/task:to-architecture`](/reference/to-architecture) is what writes it:

```text
/task:to-architecture api-v2-migration
# → adds ## Architecture to .task/roadmap/api-v2-migration.md: components with
#   real module paths, interfaces between items (#2 → #4), one module-level
#   sketch per unchecked item, and a technical ordering mirrored into the
#   dependent items' **Dependencies:**
```

Run it right after `to-roadmap`, in the same chat, or on its own against a roadmap you captured earlier. With no roadmap yet, it captures one first — through the same flow `to-roadmap` uses — and then adds the section, so one command covers both. From then on, `to-plan` on an item — interactive or through `roadmap-to-workflow`'s per-item plan agent — reads the section as the **intended shape**: its Plan follows the named components and interfaces by default, and a step is free to depart when the real code disagrees, as long as it says why. The executing session and `task:code-reviewer` never read it directly; by the time they run, the shape is already embodied in the Plan.

**Specs vs. architecture** — the two divide cleanly. A spec says *why this form over that one*: a protocol, a data shape, a "we picked X over Y because…" whose reasoning would otherwise be re-litigated. The architecture section says *what goes where*: which module owns which behavior, and what crosses the boundary between two items. A component map that drifts into a spec is really architecture wearing the wrong hat; the section cites a spec inline wherever a shape it describes is pinned by one.

## Pick up items by hand

`to-task` / `to-plan` can open a roadmap item directly as their input:

```text
/task:to-plan api-v2-migration#1
# → drafts .task/task/migrate-auth-endpoints.md, stamped with
#   Roadmap: [api-v2-migration](../roadmap/api-v2-migration.md) / Source item: #1
# → footer: implement it now, or in a fresh session run:
#   `implement .task/task/migrate-auth-endpoints.md`

implement .task/task/migrate-auth-endpoints.md
# → follows ## Execution: implement → commit → task:code-reviewer reviews,
#   fixes what it proves, runs your build and tests, commits the fixes
# → because Roadmap: / Source item: are present, the executing session also
#   ticks item #1's checkbox in the roadmap file once the review comes back OK
```

The `Roadmap:` and `Source item:` headers on the task file are what let the executing session tick the right checkbox automatically. Then repeat for the next item — no state to remember between them:

```text
/task:to-plan api-v2-migration#2
implement .task/task/<item-2-slug>.md
# …until every item is checked.
```

`to-task api-v2-migration#3` works the same way when you want a lighter capture (Description only) before deciding an approach.

## Where does the roadmap stand?

The checkboxes are the source of truth. To see what's left:

```text
grep '^### - \[ \]' .task/roadmap/api-v2-migration.md
# every item still unchecked
```

## Ready to run it hands-off?

If you don't want to pick up each item by hand, [`/task:roadmap-to-workflow`](/guide/autopilot) fans the whole unchecked backlog out to parallel sessions in dependency order.

→ Next: [Autopilot a roadmap](/guide/autopilot).
