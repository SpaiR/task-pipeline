# Usage scenarios

The [README](../README.md) covers the basic single-task flow: discuss in chat, run `to-task` or `to-plan`, then tell any session `implement .task/task/<slug>.md`. This page collects the larger scenarios: a multi-task initiative via a roadmap, the `roadmap-to-workflow` autopilot, mixing hand-picked items with autopilot, and returning to a task later.

Every scenario below builds on the same flat `.task/` layout — `.task/config/config.md`, `.task/task/<slug>.md` (one file per task, the slug is both filename and identity), `.task/roadmap/<slug>.md`, `.task/spec/<slug>.md` (standalone technical-decision specs, referenced via `Spec:` headers). There is no workspace, no log, no active-task pointer — the artifact's path is the only handle there is. Full shapes: [docs/contract.md](contract.md).

## A multi-task initiative, picked up by hand

```text
# talk through the initiative in chat — phases, dependencies, open questions — then:

/task:to-roadmap "migrate the public API to v2"
# → .task/roadmap/api-v2-migration.md — a phase-grouped backlog of ready-to-pick-up
#   items, each with a Ready description (Context/Goal/Outcomes/Invariants/
#   Acceptance criteria) and optional **Dependencies:** / **Model:** hints
# → if a load-bearing technical decision surfaces, capture it separately with
#   /task:to-spec (writes .task/spec/<slug>.md) and reference it from the roadmap
#   (and its items) via a Spec: header
# → footer: → Next: `/task:roadmap-to-workflow` or `/task:to-task api-v2-migration#1`

# Pick up item 1 directly — to-task/to-plan can open a roadmap item as their input:
/task:to-plan api-v2-migration#1
# → drafts .task/task/migrate-auth-endpoints.md, stamped with
#   Roadmap: api-v2-migration / Source item: #1
# → footer: implement it now, or in a fresh session run:
#   `implement .task/task/migrate-auth-endpoints.md`

"implement .task/task/migrate-auth-endpoints.md"
# → follows ## Execution: implement the plan, /verify, /code-review, commit
# → because Roadmap:/Source item: are present, the executing session also
#   ticks item #1's checkbox in .task/roadmap/api-v2-migration.md

# Next item — same pattern, no need to remember anything:
/task:to-plan api-v2-migration#2
"implement .task/task/<item-2-slug>.md"
# …repeat until every item is checked.
```

`to-task api-v2-migration#3` works the same way when you want a lighter capture (Description only, no Plan) before deciding on an approach.

## Autopilot via `roadmap-to-workflow`

For a roadmap you're ready to run end to end without babysitting each item:

```text
/task:to-roadmap "migrate the public API to v2"
# … as above …

/task:roadmap-to-workflow api-v2-migration
# no flags — it asks (via chips) how much to run: all remaining items,
# just the next dependency-wave, or a picked range like "1,3-5"

# It topologically sorts the unchecked items on **Dependencies:** into waves,
# then authors and invokes a dynamic Workflow:
#   - items in the same wave run in PARALLEL, each in its own isolated
#     git worktree, sharing the one .task/ (via `git config task.root`)
#   - default per-item shape is opus-plans / sonnet-implements: a first
#     agent runs to-plan for the item (writes .task/task/<item-slug>.md),
#     a second implements + /verify + /code-review + commits, using the
#     item's **Model:** hint if present
#   - the DRIVER ticks each item's roadmap checkbox after its agent returns
#     OK — never the per-item agent, so parallel wave-mates never race on
#     the roadmap file
#   - a barrier separates waves; a later wave never starts before every
#     item it depends on has landed

# Output as it runs — one digest line per item as each wave lands:
#   OK #1 migrate-auth-endpoints implemented, verified, reviewed, committed
#   OK #2 update-client-sdk implemented, verified, reviewed, committed
# → Done. Roadmap complete — .task/roadmap/api-v2-migration.md fully checked.
```

If the Workflow tool isn't available in your environment, `roadmap-to-workflow` falls back to the same hand-picked pattern shown above: `to-plan` on one item at a time, then a plain `implement .task/task/<item-slug>.md` session, ticking the checkbox by hand before moving on.

## Mixing hand-picked items with autopilot

Nothing forces one mode for a whole roadmap. A common pattern: do the first, riskiest item yourself to validate the approach, then let `roadmap-to-workflow` take the rest.

```text
/task:to-plan api-v2-migration#1
"implement .task/task/<item-1-slug>.md"
# item 1 lands, its checkbox is ticked

/task:roadmap-to-workflow api-v2-migration
# picks up from the unchecked remainder automatically — item 1 is
# already checked, so waves are computed over items 2..N only
```

If `roadmap-to-workflow` stops partway (one item's agent returns `FAIL`), completed items stay checked. Fix the failing item, then rerun `roadmap-to-workflow api-v2-migration` — it only reruns the unchecked remainder.

## Returning to a task later

There's no pointer to re-point. A task file is just a file — pick it back up in this session or a brand-new one:

```text
ls .task/task/
# every task ever captured that you haven't deleted — closed tasks are
# just files that stay put; git history is the record, there's no archive

"implement .task/task/http-retry-backoff.md"
# any session, any time — the artifact path is the handle
```

Want to change scope before re-running it? Edit the Description (and `## Plan`, if present) by hand, or run `/task:to-plan http-retry-backoff` again — on a file that already has `## Plan`, this **revises** it in place (shows the new Plan next to a one-line note of what changed) rather than starting over. On a `to-task`-only file with no `## Plan` yet, the same command **promotes** it in place instead.

To find where a roadmap stands, grep its checkboxes directly:

```text
grep '^### - \[ \]' .task/roadmap/api-v2-migration.md
# every item still unchecked
```

## Combining scenarios

These aren't exclusive: capture a couple of small fixes directly with `to-task`, run a larger one through `to-plan`, and reserve `to-roadmap` + `roadmap-to-workflow` for the initiative-sized work — all sharing the same flat `.task/`, all invisible to `git status`.
