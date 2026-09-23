# to-architecture

Fixes an initiative's **technical shape** — components, interfaces between items, a module-level sketch per item, technical ordering — into a roadmap's `## Architecture` section. Writes the roadmap itself, through the shared capture flow, when none exists yet.

See the [roadmaps guide](/guide/roadmaps) for when to run it and how planners use the section.

## Usage

```text
/task:to-architecture [<roadmap-slug> | <idea>]
```

**Input** — `$ARGUMENTS`, optional. Recognized forms:

| Form | Behavior |
|---|---|
| `<roadmap-slug>` or a path to an existing roadmap | Add the section to that roadmap (enrich), or replace the one it has (revise). |
| *(empty)* | The roadmap this conversation is clearly about, or a fresh capture from the discussion. |
| anything else | A rough description of the initiative, or a reference back to prior discussion. |

## When to use it

Run it once a roadmap's items exist and their technical shape is worth pinning — right after `to-roadmap` in the same chat, or standalone against a roadmap captured earlier. It's the initiative-level counterpart to `to-plan`: as `to-plan` adds `## Plan` to one task, this adds `## Architecture` to a roadmap.

Three stops worth knowing:

- **Too small for a roadmap** — with no roadmap yet, a discussion that is really one task (no phases, no cross-item dependencies) → it **stops without writing** and points you at [`to-plan`](/reference/to-plan) or [`to-task`](/reference/to-task): one task's technical shape is a `## Plan`, not this section.
- **Nothing left to plan** — every item on the target roadmap is already checked off → it **stops without writing**; no planner would read the section.
- **A `/task:roadmap-to-workflow` run is active on the target roadmap** → it **stops without writing**. The run's mark stage rewrites the file as items land and would drop the edit, and its waves were already computed at launch, so an added dependency wouldn't apply anyway.

## What it writes

```markdown
## Architecture

> Intended technical shape of this initiative — planners follow it and state a
> reason where the code forces a deviation. Decisions with rationale live in specs.

### Components
- `<name>` — new | existing · `<module path>` — role in this initiative.

### Interfaces between items       (omit when none)
- #2 → #4, #5 — `<name>`: what crosses the boundary; form pinned in [<slug>](../spec/<slug>.md) §N.

### Item sketches                  (one bullet per unchecked item)
- #1 — module-level sketch: which components it touches and how.

### Technical ordering             (omit when none)
- #3 before #6 — reason. Mirrored in item #6's `**Dependencies:**`.
```

Real module paths and symbol names are expected here — the behavioral discipline binds only an item's `### Outcomes` / `### Goal` / `### Invariants`. A choice whose **reasoning** must survive re-derivation still belongs in a spec; this section cites it as `[<slug>](../spec/<slug>.md) §N` rather than restating it.

## Output

```text
Wrote `.task/roadmap/api-v2-migration.md`  (fresh)
API v2 migration
Items: 5 tasks across 2 phases — recommended order: 1 → 2 → 4 → 3 → 5
Architecture: 3 components, 2 interfaces, 5 item sketches
- `AuthGateway` — new, terminates the v2 auth handshake
- `LegacyAuthAdapter` — existing, bridges v1 sessions during the migration
- `SessionStore` — existing, holds tokens both adapters read
Interfaces: #2 → #4 `SessionToken`
Dependencies added: #4 ← 2
Spec headers added: none
Specs referenced: none
validate: OK — 0 errors, 0 warnings

→ Next: `/task:roadmap-to-workflow api-v2-migration` (run it — every item's planner
  now follows this architecture) or `/task:to-plan api-v2-migration#1` (plan one
  item by hand — any item number works).
```

The first line's `(fresh | enrich | revise)` tag names the mode; a revise run also reports any `Stale dependencies:` an edited ordering left behind, and a fresh run prints the same self-check summary `to-roadmap` does.

## Does not

- Write plan-level detail — no `file:line` references, no step lists, no code block over 5 lines.
- Restate the items' behavioral outcomes as architecture.
- Edit anything on the roadmap beyond the section itself, `**Dependencies:**` additions on unchecked items, and missing `Spec:` header lines — no item titles, ready descriptions, `**Model:**` hints, phases, or checkboxes.
- Remove a dependency, or add one to an already-checked item.
- Write or edit a spec — it only cites one and wires the `Spec:` header; authorship stays [`to-spec`](/reference/to-spec)'s.
- Hold more than one `## Architecture` section in a file.
