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

# One roadmap = one umbrella task. Items are sequential subtasks.
/task:design --from api-v2-migration              # phase=open, auto-picks the first [ ]
/task:build                                       # implement → audit
/task:ship --next                                 # transition to the next item (umbrella alive)
# → .task/log/api-v2-migration/0-migrate-auth-endpoints/
# Auto-mark: item 1 in the roadmap → `- [x]`. task.md stays (Description cleared).
# Without --next a bare /task:ship would have closed the umbrella entirely.

# Next item:
/task:design --from api-v2-migration              # phase=open continuation
/task:build
/task:ship --next                                 # transition again (this isn't the last item)
# → .task/log/api-v2-migration/1-update-client-sdk/, item 2 → `- [x]`

# At the end (the last roadmap item):
/task:ship                                         # default full close; slug auto-generated from summary.md
# → .task/log/api-v2-migration/{N}-feat-.../ with the archived task.md
# The same bare /task:ship also cleans up after an aborted /task:auto-roadmap run
# (see the "If it failed on an item" block in the autopilot scenario below).

# If you need to skip or redo an item:
/task:design --from api-v2-migration#5
```

## Autopilot via `/task:auto-roadmap`

```text
/task:bootstrap
/task:roadmap "migrate the public API to v2"

# In a single active Claude Code session:
/task:auto-roadmap
# A wizard picks the roadmap and confirms the run.
#
# For each item, the driver spawns ONE auto-roadmap-item-runner and routes on
# its returned digest. Inside that item-runner:
#   1) spawns auto-roadmap-design-runner (parent-session model)
#      → goes through design/phases/open.md → design/phases/blueprint.md
#      → returns: "OK: item #N \"...\" — plan.md ready, awaiting implement"
#      (first item only: writes workspace/<id>/auto.lock right after the active-task pointer lands)
#   2) reads plan.md → Implement-Model: (opus|sonnet|haiku)
#   3) spawns auto-roadmap-build-runner with Agent.model = that value
#      → goes through build/phases/implement.md
#      → returns: "OK: item #N \"...\" — diff uncommitted, ready for audit"
#   4) runs /task:build --phase audit inline
#      — audit-context.sh sees a non-trivial diff →
#        Step 2b: the item-runner spawns 3 lens agents in parallel (nested spawn)
#      — bounded auto-fix loop (≤2 iterations, touches-gate)
#      — on high-severity unfixed after 2 iterations → fail-stop
#   5) runs /task:ship inline (commit + close: --next on intermediate items, a bare /task:ship (default full close) on the last)
#   6) returns a compact report-card digest; the driver prints it and moves on

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
> - One session model for the whole run's orchestration (implement still uses each item's `plan.md → Implement-Model:`). For opus, run `/model opus` BEFORE starting.
> - The session window must stay open for the whole run.

`/task:auto-roadmap` is **not for resume**: it refuses when an active-task pointer exists for this worktree or any `workspace/*/auto.lock` is present. It skips design's idea + refine phases — roadmap items already have a curated `Ready description`.

## Several subtasks in one umbrella task

```text
/task:design DT-5177 export refactor             # phase=open + quick-draft:
                                                  # task.md with a Description in one call
                                                  # (need a brainstorm — add --idea)
/task:design                                      # phase=blueprint
/task:build                                       # implement → audit
/task:ship --next                                 # transition: subtask to archive, umbrella alive
# → .task/log/dt-5177/0-feat-header-parser/

# the same task.md, a new Description (Description cleared by ship):
# IMPORTANT: between subtasks quick-draft is NOT applied — an empty Description
# in an active umbrella always goes to idea (architect), even if context is passed
# (the context isn't lost: it becomes the seed of round zero of the brainstorm).
/task:design "what we're doing in the new subtask" # Description empty → phase=idea (architect)
/task:build
/task:ship --next
# → .task/log/dt-5177/1-feat-body-emitter/

# finally (the last subtask — closing the umbrella entirely):
/task:ship                                        # default = full close; slug auto-derived from summary.md
# → .task/log/dt-5177/2-feat-schema-guard/  (slug auto-derived; with task.md)
```

## Returning to a closed umbrella task

To pick a closed umbrella back up, restore `task.md` by hand from the latest full-close archive and re-point the active-task pointer at it:

```text
# restore task.md from the latest full-close archive:
mkdir -p .task/workspace/dt-5177
cp .task/log/dt-5177/2-feat-schema-guard/task.md .task/workspace/dt-5177/task.md
echo "dt-5177" > "$(git rev-parse --path-format=absolute --git-path task-current)"

# (opt.) clear everything from ## Description down if you want a clean start
# then the standard cycle:
/task:design "a new subtask"                      # Description empty → phase=idea (architect)
/task:build
/task:ship fix-edge-case                          # default = full close of the umbrella
```

`plan.md` / `summary.md` are left with the previous subtask — look in `.task/log/...`.
