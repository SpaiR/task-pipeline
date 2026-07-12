# Usage scenarios

The [README](../README.md) covers the basic single-task flow. This page collects the larger scenarios: multi-task initiatives via a roadmap, the `/task:auto-roadmap` autopilot, several subtasks under one umbrella, and returning to a closed task.

Scenarios can be combined: some tasks via `/task:roadmap` + `--from`, small fixes directly via `/task:design`.

## A multi-stage initiative via a roadmap

```text
/task:bootstrap

/task:roadmap "migrate the public API to v2"
# → .task/roadmap/api-v2-migration.md with phases and ready-made descriptions
#   for ~10–15 tasks
# → (opt.) .task/roadmap/api-v2-migration.spec.md — if key technical decisions
#   surfaced during the brainstorm; items reference its sections via ### Spec references,
#   blueprint reads them at planning time

# One roadmap = one log umbrella (items share the roadmap-slug task-id).
/task:design --from api-v2-migration              # phase=open, auto-picks the first [ ]
/task:build                                       # implement → audit
/task:ship                                        # commit + full close; item 1 → `- [x]`
# → .task/log/api-v2-migration/0-migrate-auth-endpoints/ (with the archived task.md)

# Next item — just re-open from the same roadmap:
/task:design --from api-v2-migration              # phase=open, next un-checked item
/task:build
/task:ship                                        # item 2 → `- [x]`
# → .task/log/api-v2-migration/1-update-client-sdk/

# …repeat until every item is checked. Each ship is a full close; slug auto-derived from summary.md.
# The same bare /task:ship also cleans up after an aborted /task:auto-roadmap run
# (see the "If it failed on an item" block in the autopilot scenario below).

# If you need to skip or redo an item:
/task:design --from api-v2-migration#5
```

### Building a roadmap from a prior discussion

You don't have to brainstorm inside the skill. A common flow is to hash out an initiative in normal chat first — arguing over phases, pinning down details ("the settings button goes first in the panel") — and only then ask for the roadmap:

```text
# ...long free-chat discussion of the initiative...

/task:roadmap "build the roadmap from what we just discussed"
# Because the discussion already happened, authoring takes the HARVEST path:
# it first prints a Decision Inventory — every decision it captured, small
# details verbatim — and waits for you to confirm:
#
#   ## Roadmap Brainstorm — Decision Inventory
#   ### Decisions locked so far
#   1. Settings button is first in the panel
#   2. ...
#   ### Open forks (not yet decided)
#   - ...
#   accept / decline / edit
#
# If something you settled is missing, add it with `edit` — before the file
# is written, not after you notice it gone a week later. On `accept`, each
# decision is routed to a home in the file (an item's Outcomes / Acceptance
# criteria, the spec sidecar, or Out of scope) and the roadmap is drafted.
```

Detection is automatic — no flag. A bare `/task:roadmap "add dark mode"` with no prior discussion still takes the normal cold-start brainstorm rounds.

## Autopilot via `/task:auto-roadmap`

```text
/task:bootstrap
/task:roadmap "migrate the public API to v2"

# In a single active Claude Code session:
/task:auto-roadmap
# A wizard picks the roadmap and confirms the run; the driver then writes the
# run lock (.task/roadmap/<slug>.lock) before spawning any item.
#
# For each item, the driver spawns ONE auto-roadmap-item-runner and routes on
# its returned digest. Inside that item-runner:
#   1) spawns auto-roadmap-design-runner (parent-session model)
#      → goes through design/phases/open.md → design/phases/blueprint.md
#      → returns: "OK: item #N \"...\" — plan.md ready, awaiting implement"
#   2) reads plan.md → Implement-Model: (opus|sonnet|haiku)
#   3) spawns auto-roadmap-build-runner with Agent.model = that value
#      → goes through build/phases/implement.md
#      → returns: "OK: item #N \"...\" — diff uncommitted, ready for audit"
#   4) runs /task:build --phase audit inline
#      — audit-context.sh sees a non-trivial diff →
#        Step 2b: the item-runner spawns 3 lens agents in parallel (nested spawn)
#      — bounded auto-fix loop (≤2 iterations, touches-gate)
#      — on high-severity unfixed after 2 iterations → fail-stop
#   5) runs /task:ship inline (commit + full close; the next item re-opens fresh)
#   6) returns a compact report-card digest; the driver prints it and moves on
# On a clean finish the driver removes the run lock.

# With flags:
/task:auto-roadmap api-v2-migration --next          # only the first unclosed item
/task:auto-roadmap api-v2-migration --from #3       # start from #3
/task:auto-roadmap api-v2-migration --items 3-5     # items #3, #4, #5
/task:auto-roadmap api-v2-migration --items 1,3-5,8 # a selection

# If it failed on item #5:
/task:ship                                          # default full close; sweeps the subfolder and the active-task pointer
/task:auto-roadmap api-v2-migration --from #5       # retry from #5
```

> [!TIP]
> Run it in auto mode (auto-accept edits) — otherwise every `Edit` triggers a prompt.

> [!WARNING]
> **Limitations.**
> - Each item's cycle runs in a disposable `auto-roadmap-item-runner`, so the driver accumulates only a one-screen digest per item — the old ~15 (Sonnet 200k) / ~25 (Opus 1M) auto-compact ceiling is greatly relaxed and a long run is bounded by wall-clock, not context. Slice with `--items <range>` if you still want to bound one.
> - Live per-lens audit output shows in each item-runner's own subagent view, not the main transcript; the main thread prints the item-runner's report-card digest and the full detail stays in `.task/log/<id>/` + `git log`.
> - One session model for the whole run's orchestration — the item-runner, design-runner, audit orchestration, and ship (implement still uses each item's `plan.md → Implement-Model:`, which blueprint sets per item, leaning `haiku` for rote-class roadmap items). Set it with `/model` BEFORE starting: `/model opus` for design-heavy roadmaps, `/model sonnet` for rote-dominated ones to speed the orchestration stages.
> - The session window must stay open for the whole run.

`/task:auto-roadmap` is **not for resume**: it refuses when an active-task pointer exists for this worktree or a run lock for the roadmap is present. It skips design's refine phase — roadmap items already have a curated `Ready description`.

## Returning to a closed task

Every `/task:ship` fully closes its task and archives `task.md` under `.task/log/<task-id>/<N>-<slug>/`. To pick a closed task back up, restore `task.md` by hand from its archive and re-point the active-task pointer at it:

```text
# restore task.md from the archive:
mkdir -p .task/workspace/dt-5177
cp .task/log/dt-5177/0-feat-header-parser/task.md .task/workspace/dt-5177/task.md
echo "dt-5177" > "$(git rev-parse --path-format=absolute --git-path task-current)"

# then the standard cycle (edit the Description first if you want a fresh scope):
/task:design                                      # phase=blueprint (Description already filled)
/task:build
/task:ship                                        # full close; slug auto-derived from summary.md
```

`plan.md` / `summary.md` from the previous cycle live in `.task/log/...`.
