# Usage scenarios

The [README](../README.md) covers the basic single-task flow. This page collects the larger scenarios: the one-verb `/task:go` entry, multi-task initiatives via a roadmap, the `/task:auto-roadmap` autopilot, several subtasks under one umbrella, and returning to a closed task.

Scenarios can be combined: some tasks via `/task:roadmap` + `--from`, small fixes directly via `/task:design` (or just `/task:go`).

## One verb, start to finish — `/task:go`

`/task:go` is the front door when you don't want to remember which stage comes next. It looks at `.task/` state and runs the next phase, then pauses for your OK before advancing.

```text
/task:bootstrap

/task:go "fix the flaky retry logic"   # opens the task + drafts the Description,
                                       # then asks: plan it now? [Continue / Edit / Stop]
/task:go                               # → blueprint; then asks: build? (or refine the plan)
/task:go                               # → implement; then asks: audit?
/task:go                               # → audit; then asks: ship?
/task:go                               # → ship (choose full close or --next)
```

Each call resumes from wherever you left off — stop after any checkpoint, hand-edit an artifact (`task.md` / `plan.md`), and run `/task:go` again to continue. You never have to know whether the next step is `design`, `build`, or `ship`.

**Hands-off single task — `/task:go --auto`.** When a task is well-specified and you want it done without babysitting:

```text
/task:go --auto "add exponential backoff to the retry executor"
#   1) main thread opens + drafts the Description
#   2) confirms once: "proceed autonomously?"           ← the only checkpoint
#   3) spawns the design runner (blueprint) in a subagent
#   4) spawns the build runner (implement) with the plan's Implement-Model
#   5) audits (3 lenses) + ships --full inline
```

This is an N=1 `/task:auto-roadmap`: same executor runners, no roadmap file. On any failure it stops and hands back a resumable task — just run `/task:go` to take over interactively. It is opt-in: plain `/task:go` never runs the whole pipeline unattended.

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
/task:ship --full                                  # slug auto-generated from summary.md
# → .task/log/api-v2-migration/{N}-feat-...-finalize/ with the archived task.md
# The chore-finalize slug isn't used in a clean finish of a manual run —
# it's reserved for manual recovery of an aborted /task:auto-roadmap
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
# For each item:
#   1) main thread spawns auto-roadmap-design-runner (parent-session model)
#      → goes through design/phases/open.md → design/phases/blueprint.md
#      → returns: "OK: item #N \"...\" — plan.md ready, awaiting implement"
#   2) main thread reads plan.md → Implement-Model: (opus|sonnet|haiku)
#   3) main thread spawns auto-roadmap-build-runner with Agent.model = that value
#      → goes through build/phases/implement.md
#      → returns: "OK: item #N \"...\" — diff uncommitted, ready for audit"
#   4) main thread → /task:build --phase audit inline
#      — audit-context.sh sees a non-trivial diff →
#        Step 2b spawns 3 lens agents in parallel (the main thread can Agent(...))
#      — bounded auto-fix loop (≤2 iterations, touches-gate)
#      — on high-severity unfixed after 2 iterations → fail-stop
#   5) main thread → /task:ship inline (commit + close: --next on intermediate items, --full on the last)

# With flags:
/task:auto-roadmap api-v2-migration --next          # only the first unclosed item
/task:auto-roadmap api-v2-migration --from #3       # start from #3
/task:auto-roadmap api-v2-migration --items 3-5     # items #3, #4, #5
/task:auto-roadmap api-v2-migration --items 1,3-5,8 # a selection

# If it failed on item #5:
/task:ship --full chore-finalize                    # sweeps the subfolder and .task-current
/task:auto-roadmap api-v2-migration --from #5       # retry from #5
```

> [!TIP]
> Run it in auto mode (auto-accept edits) — otherwise every `Edit` triggers a prompt.

> [!WARNING]
> **Limitations.**
> - The main thread's context accumulates. Rough auto-compact thresholds: ~15 items on Sonnet 200k, ~25 on Opus 1M. Slice with `--items <range>` as needed.
> - One session model for the whole run. For opus, run `/model opus` BEFORE starting.
> - The session window must stay open for the whole run.

`/task:auto-roadmap` is **not for resume**: it refuses when `.task-current` exists or any `workspace/*/auto.lock` is present. It skips design's idea + refine phases — roadmap items already have a curated `Ready description`.

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
/task:ship chore-cleanup                          # default = full close (--full is an alias)
# → .task/log/dt-5177/2-chore-cleanup/  (with task.md)
```

## Returning to a closed umbrella task

To pick a closed umbrella back up, restore `task.md` by hand from the latest full-close archive and re-point `.task-current` at it:

```text
# restore task.md from the latest full-close archive:
mkdir -p .task/workspace/dt-5177
cp .task/log/dt-5177/2-chore-cleanup/task.md .task/workspace/dt-5177/task.md
echo "dt-5177" > .task-current

# (opt.) clear everything from ## Description down if you want a clean start
# then the standard cycle:
/task:design "a new subtask"                      # Description empty → phase=idea (architect)
/task:build
/task:ship fix-edge-case                          # default = full close of the umbrella
```

`plan.md` / `summary.md` are left with the previous subtask — look in `.task/log/...`.
