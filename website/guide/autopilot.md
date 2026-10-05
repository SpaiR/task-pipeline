# Autopilot a roadmap

[`/task:roadmap-to-workflow`](/reference/roadmap-to-workflow) is the one launcher. Point it at an approved roadmap and it runs the unchecked items end to end — no babysitting each one. It's the only place in the pipeline that spawns parallel sessions, and it does so through Claude Code's own dynamic Workflow tool running a static driver script shipped with the plugin (`skills/_lib/roadmap-driver.js`) — not hand-rolled or re-generated orchestration.

## Run it

```text
/task:roadmap-to-workflow api-v2-migration
# no flags — it asks (via chips) how much to run:
#   all remaining items · just the next dependency-wave · a picked range like "1,3-5"
# and what to do if the run stops:
#   stop and ask · recover and continue
```

Launched with no argument, it asks which roadmap and how much to cover. An item that already has its task file, because an earlier run stopped after planning it, gets one more question: implement that plan, only review it, or re-plan it. [When an item fails](#when-an-item-fails) covers both.

## What it does

1. **Sorts items into dependency waves.** The skill reports each unchecked item's `**Dependencies:**`; the driver script topologically sorts them, so items with no unmet dependency land in the same wave. Nothing is spawned until that sort succeeds — a cycle, or a scope missing a dependency, stops the run with one line naming the items.
2. **Plans a wave in parallel, then implements and reviews it one item at a time.** Within a wave, every item is *planned* at once (each plan agent only writes its own `.task/task/<item-slug>.md`, so there's no collision), then each item is *implemented and reviewed* strictly one at a time in the shared working tree — the tree keeps exactly one writer, so item N never starts implementing while item N−1 is still under review. A barrier separates waves — a later wave never starts before every item it depends on has landed, and each implement sees its already-landed wave-mates' reviewed commits.
3. **Plans, implements, reviews — per item.** The default per-item shape is **opus-plans / sonnet-implements / reviewer-reviews**: a first agent plans the item from the roadmap (writing `.task/task/<item-slug>.md`), a second implements and commits, and a third is `task:code-reviewer`, which reviews that commit, fixes what it proves within the plan's **Touches**, runs your build and tests, commits those fixes on top, and ticks the item's checkbox (next step). If the item has a `**Model:**` hint, the implement agent uses it, and a `haiku` hint also scales the plan agent down to sonnet — the reviewer pins its own model, so a `haiku` item never gets a `haiku` review.
4. **Ticks the checkbox — from the review.** Once an item's review passes, `task:code-reviewer` ticks that item's checkbox as its last step; the plan and implement agents never touch it. That's deliberate: the review runs one item at a time, while parallel plan agents would otherwise race on the roadmap file. Ticking is idempotent — if the box is already checked, the reviewer treats that as the desired end state and moves on.

While it runs, the Workflow panel shows one group per item, named after the item — `W1 · #1 Migrate auth endpoints` — with its agents numbered `1/3 plan` through `3/3 review`, so you can see which item is in flight and how far along it is. The narrator lines above the panel start with the run's shape (items, waves, what waits on what) and then log each stage's digest as it lands:

```text
api-v2-migration: 2 item(s) in 2 wave(s)
  W1: #1 Migrate auth endpoints
  W2: #2 Update client SDK (after #1)
Wave 1/2 — planning #1
[W1 plan] OK #1 migrate-auth-endpoints planned
[W1 implement] OK #1 migrate-auth-endpoints implemented, committed
[W1 review] OK #1 migrate-auth-endpoints 2 fixes, tests green, fixes committed, ticked
…
```

When the run ends, the chat gets one line per item that landed and a summary:

```text
#1 migrate-auth-endpoints — implemented, committed; review: 2 fixes, tests green, fixes committed, ticked
#2 update-client-sdk — implemented, committed; review: 0 findings, tests green, ticked
Ran `api-v2-migration`: 2 of 2 items landed and ticked, 0 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
→ Done. Roadmap complete — .task/roadmap/api-v2-migration.md fully checked.
```

`→ Done.` means nothing is left unchecked. A run scoped to the next wave or a picked range ends the same way when its items land, but with the rest still unchecked the footer is `→ Next: /task:roadmap-to-workflow <slug> to run the remaining <n> item(s)` instead.

## Mixing hand-picked items with autopilot

Nothing forces one mode for a whole roadmap. A common pattern: do the first, riskiest item yourself to validate the approach, then let autopilot take the rest.

```text
/task:to-task api-v2-migration#1
implement .task/task/<item-1-slug>.md
# item 1 lands, its checkbox is ticked

/task:roadmap-to-workflow api-v2-migration
# picks up from the unchecked remainder — waves are computed over items 2..N only
```

## When an item fails

The driver is **stop-on-FAIL**: if an item's implement *or* review agent returns `FAIL`, the run prints that item's digest, lists the items that landed before it, and stops instead of starting the next wave (a later item might depend on the failed one). A red build or test run inside the review is a `FAIL`, and the reviewer leaves its fixes uncommitted in that case — the implementation commit stands as it was. So is an implementation that never got committed (a pre-commit hook rejected it, say): nothing is ticked over work no commit holds. Completed items stay checked.

```text
roadmap-to-workflow stopped in wave 2, item #3: FAIL #3 <item-slug> <what failed>
STATE recover=off scope=all attempts=none
STOPPED #3 <item-slug> stage=implement
#1 … — …; review: …
#2 … — …; review: …
Ran `api-v2-migration`: 2 of 5 items landed and ticked, 3 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
Stopped at #3 <item-slug> in wave 2. Its work is left in the working tree —
  inspect it with `git status` and `git log --oneline -3`.
→ Next: rerun `/task:roadmap-to-workflow api-v2-migration` and pick
  **Implement this plan** for #3 to continue from what is committed, or edit the
  item in `.task/roadmap/api-v2-migration.md` and pick **Re-plan from the roadmap
  item** — already-ticked items stay ticked, only the unchecked remainder reruns.
```

What happens next is the choice you made at launch, in the same prompt as the scope: *If the run stops?*

- **Stop and ask** — the skill diagnoses the stop from the driver's return and `git`, then offers the rerun it would make as a chip: **Rerun from implement** or **Rerun from review**, or **Stop here**. The footer above is what **Stop here** prints.
- **Recover and continue** — the skill makes that rerun itself and carries on with the rest of the run.

Either way the stopped item is rerun through the driver: from **implement**, with a note on what stopped and what is already committed, or from **review** when the work is committed and only the review or the checkbox is missing. A failed item never gets a repair agent the skill writes on its own, and it is never ticked without a passing review. Each item gets two recovery attempts. An item that is still failing after that, or a stop that needs your decision, comes back to you whatever the mode.

A resumed implement may depart from the plan, and from a spec it cites when none of the spec's invariants break. It declares every departure, the reviewer checks it, and the report lists it as a decision you should know about. See [Recovery](/reference/roadmap-to-workflow#recovery).

Stopping is never the end of the item. A later `/task:roadmap-to-workflow <slug>`, in this session or a fresh one, finds the stopped item's task file and asks how to take it: **Implement this plan**, **Review only**, or **Re-plan from the roadmap item**. Re-planning regenerates the task file from the roadmap item, and hand edits to that file do not survive it. To change what a re-plan produces, edit the item in the roadmap instead.

## No Workflow tool?

If the Workflow tool isn't available in your environment, `roadmap-to-workflow` hard-stops instead of running anything itself — it prints the unchecked items and tells you to run them by hand, in dependency order: `to-task` on one item in this chat, then `implement .task/task/<item-slug>.md` in a fresh session. That session's `## Execution` pointer already carries plan → commit → `task:code-reviewer`, and the reviewer ticks the roadmap checkbox once its review passes — so this is exactly the "mixing hand-picked items" pattern above, just for every item instead of the first one.

→ Next: [Specs](/guide/specs) — pinning the technical decisions a roadmap leans on.
