# Autopilot a roadmap

[`/task:roadmap-to-workflow`](/reference/roadmap-to-workflow) is the one launcher. Point it at an approved roadmap and it runs the unchecked items end to end — no babysitting each one. It's the only place in the pipeline that spawns parallel sessions, and it does so through Claude Code's own dynamic Workflow tool, not hand-rolled orchestration.

## Run it

```text
/task:roadmap-to-workflow api-v2-migration
# no flags — it asks (via chips) how much to run:
#   all remaining items · just the next dependency-wave · a picked range like "1,3-5"
```

Launched with no argument, it asks which roadmap and how much to cover.

## What it does

1. **Sorts items into dependency waves.** It reads each unchecked item's `**Dependencies:**` and topologically sorts them: items with no unmet dependency land in the same wave.
2. **Plans a wave in parallel, then implements it one at a time.** Within a wave, every item is *planned* at once (each plan agent only writes its own `.task/task/<item-slug>.md`, so there's no collision), then the items are *implemented* strictly one at a time in the shared working tree. A barrier separates waves — a later wave never starts before every item it depends on has landed, and each implement sees its already-landed wave-mates' commits.
3. **Plans then implements, per item.** The default per-item shape is **opus-plans / sonnet-implements**: a first agent runs `to-plan` for the item (writing `.task/task/<item-slug>.md`), a second implements + `/verify` + `/code-review` + commits. If the item has a `**Model:**` hint, the implement agent uses it.
4. **Ticks the checkbox — from the driver.** After an item's agent returns OK, the **driver** ticks that item's checkbox, never the per-item agent. That's deliberate: parallel wave-mates would otherwise race on the roadmap file.

Output is one digest line per item as each wave lands:

```text
OK #1 migrate-auth-endpoints implemented, verified, reviewed, committed
OK #2 update-client-sdk implemented, verified, reviewed, committed
→ Done. Roadmap complete — .task/roadmap/api-v2-migration.md fully checked.
```

## Mixing hand-picked items with autopilot

Nothing forces one mode for a whole roadmap. A common pattern: do the first, riskiest item yourself to validate the approach, then let autopilot take the rest.

```text
/task:to-plan api-v2-migration#1
implement .task/task/<item-1-slug>.md
# item 1 lands, its checkbox is ticked

/task:roadmap-to-workflow api-v2-migration
# picks up from the unchecked remainder — waves are computed over items 2..N only
```

## When an item fails

The run is **stop-on-FAIL**: if an item's agent returns `FAIL`, the run prints that item's digest and stops instead of starting the next wave (a later item might depend on the failed one). Completed items stay checked.

```text
FAIL #3 <item-slug> <what failed>
→ Next: fix the item, then rerun `/task:roadmap-to-workflow` —
  completed items stay checked, only the unchecked remainder reruns.
```

Fix the failing item (edit its task file, or re-implement it by hand), tick its box, then rerun — it only picks up the unchecked remainder.

## No Workflow tool?

If the Workflow tool isn't available in your environment, `roadmap-to-workflow` falls back to the same hand-picked pattern: `to-plan` on one item at a time, then a plain `implement` session, ticking the checkbox before moving on. Same order, same result — just serial.

→ Next: [Specs](/guide/specs) — pinning the technical decisions a roadmap leans on.
