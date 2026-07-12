# `/task:auto-roadmap` orchestrator mechanics

Material common to the orchestrator's bash gate (`auto-roadmap-context.sh`), the main-thread driver loop (`auto-roadmap/SKILL.md`), and the per-item subagent `auto-roadmap-item-runner.md` (which itself spawns `auto-roadmap-design-runner.md` for open + blueprint and `auto-roadmap-build-runner.md` for implement, then runs audit + ship). Anchors here are the single source of truth for the three hard-stop preconditions, the `--items` grammar, the sentinel-file invariants, the failure protocol, the per-stage model split, and the cross-worktree contract — other spec sections ([invariants.md](invariants.md), [pipeline.md](pipeline.md)) link to anchors below instead of restating these rules.

Concrete run-lock field shape is in [artifact-contract.md](artifact-contract.md) — this file references it, never duplicates it.

## Per-stage model split

A per-item cycle still uses a per-stage model split, now expressed as spawns **within one `auto-roadmap-item-runner`** rather than dispatch points in the driver's main thread:

| Stage | Where | Model source |
|-------|-------|--------------|
| (per-item orchestration) | `auto-roadmap-item-runner` subagent | inherits parent-session model (user's `/model` choice, typically opus) |
| Open + Blueprint | `auto-roadmap-design-runner` sub-subagent | inherits the item-runner's model (= parent-session model) |
| Implement | `auto-roadmap-build-runner` sub-subagent | `plan.md → Implement-Model:` (`opus`, `sonnet`, or `haiku`) — passed by the item-runner as `Agent.model` override at spawn time |
| Audit lens fanout (×3, non-trivial diffs only) | `audit-{clarity,reuse,simplicity}-auditor` sub-subagents | pin `model: sonnet` in their own frontmatter (do not inherit) |
| Audit orchestration + ship | the `auto-roadmap-item-runner` itself | its own (parent-session) model |

Audit is **adaptive** (honoring `build/SKILL.md` Step 4): a trivial diff (1 file AND <30 changed lines) is audited inline in the item-runner's own context with no lens sub-subagents; only a non-trivial diff triggers the ×3 fanout above. The gate is size-based (`audit-context.sh` `trivial` flag), never `Class`-based.

The split exists because implement is the largest-input stage of the cycle (reads many sources, writes a diff) but the most mechanical once `plan.md` has fixed `Touches` + `Goal` per Step. Letting it run under a cheaper model than design saves significant cost on long roadmaps while keeping architectural decisions (blueprint) and code review (audit) on the parent-session model. The `Implement-Model:` rubric is in `skills/design/phases/blueprint.md` Step 3. Depth budget: `driver(0) → item-runner(1) → {design-runner | build-runner | lens auditor}(2)`, all leaves — well under the runtime's nesting cap.

The run lock does **not** store the per-item implement model — it captures **run** parameters at launch, not per-item plan content. The implement model is read fresh from each item's `plan.md` by the item-runner (its Step 2), between design-runner's OK and the build-runner spawn (see `agents/auto-roadmap-item-runner.md` Step 2 for the canonical regex).

Ship has **one mode — full close** (the `--next` subtask-transition mode was removed). Every item full-closes: commit, archive `plan/audit/summary.md` + `task.md`, sweep `workspace/<task-id>/` + `.task-current`. The next item re-opens fresh via `/task:design --from`. The item-runner runs ship non-interactively (auto-accepts the commit confirmation).

## Step 0 preconditions — three hard-stop gates

`auto-roadmap-context.sh` enforces all three gates in bash, with prompt-layer reminders in `SKILL.md`. Failing any gate refuses to start the run with a specific message — no silent recovery, no rollback.

1. **`.task/config/config.md` exists** — universal pipeline precondition.
2. **no active-task pointer for this worktree** (git per-worktree dir) — no task in flight in this worktree. This is also the dirty-state signal after a handled failure: a partial task's `.task-current` blocks re-entry until a bare `/task:ship` sweeps it.
3. **No `.task/roadmap/*.lock`** — no `/task:auto-roadmap` run lock is present, either from a run currently active (possibly in a sibling worktree sharing this `.task/`) or one left by a crashed run.

Beyond the three gates, the skill recommends running the session in auto mode (auto-accept edits) so implement-stage `Edit` calls don't prompt mid-run. A recommendation only — not a precondition, not enforced.

## `--items` spec grammar

The parsed include-set is captured in main-thread memory at Step 2 (variable `ITEMS_SPEC`) and recorded on disk in the `items_filter` field of the run lock the driver writes at launch (Step 2). Mutually exclusive with `--from` at the SKILL.md layer.

```
spec    := part ( ',' part )*
part    := N | N '-' M | N '-'
N, M    := positive integer (1-based item numbers)
```

- `N` — single item.
- `N-M` — inclusive range (`N ≤ M`).
- `N-` — open-ended tail (from `N` to last roadmap item).
- Comma-separated parts union into a strict include-set.

Items not in the resolved set are skipped during iteration regardless of their `[ ]` / `[x]` state. Expansion happens inline in main thread.

`--next` is sugar: it resolves to a **single-item include-set** — the first unchecked item (lowest `N`) — and sets `ITEMS_SPEC=<N>`, so it travels the exact `--items <N>` path downstream (single-item run set, lock `items_filter=<N>`, full-close ship like every item). Mutually exclusive with `--from` / `--items` at the SKILL.md layer.

When both `items_filter` and `start_item` land in the lock, `items_filter` wins and `start_item` is informational only.

## Run lock — anchor only

The concrete `key=value` field set, ordering, and write semantics live in [artifact-contract.md](artifact-contract.md):

- `.task/roadmap/<slug>.lock` shape — see [artifact-contract.md](artifact-contract.md) § run lock shape.

Invariants:

- The lock is **driver-owned**, keyed on the roadmap slug (the unit of a run), at `.task/roadmap/<slug>.lock`. The driver writes it once at Step 2 (launch, before any item-runner) and owns its whole lifecycle — item-runners never touch it.
- The file is **English regardless of `config.md` → "Language"** — parser-stable.
- Written **atomically via `set -o noclobber`** — a concurrent run racing past Step 0 gate 3 fails the write loud rather than clobbering.
- Carries `roadmap_mtime` as a launch-time snapshot. Race detection per loop iteration compares the live roadmap mtime to the **in-memory** `ROADMAP_MTIME` variable (refreshed by the driver's Substep 3.4 from the value the item-runner returns after every successful close); the on-disk value is never updated after launch.
- Carries `orchestrator=auto-roadmap`; its existence under `.task/roadmap/` (shared across all worktrees) is the **cross-worktree mutex** for that roadmap — a sibling `/task:auto-roadmap` on the same roadmap trips Step 0 gate 3 (or the `set -o noclobber` write, as the atomic backstop).
- **Removed by the driver on every handled exit** — clean finish (Step 4) and every handled failure (mtime race at Substep 3.1, item-runner FAIL / malformed status at Substep 3.4). It survives **only** an unhandled driver crash, where it correctly signals a stuck run for a manual `rm` (Step 0 gate 3 reports the path). The abort signal for a partial task is the retained `workspace/<task-id>/` + `.task-current` (Step 0 gate 2), swept by a bare `/task:ship`.
- After every successful `/task:ship` the **roadmap mtime bumps** (`close.sh:Step 1.5` flips `[ ]` → `[x]`). The item-runner captures the post-close mtime and returns it in its digest; the driver assigns it to the in-memory `ROADMAP_MTIME` (Substep 3.4) before the next iteration's race check, otherwise the legitimate close-induced bump would trip the check. Every item returns a mtime (every item full-closes); on the final item the refresh is harmless (no next race check).

## Failure protocol — fail-stop, no rollback

The orchestrator is fail-stop with no automatic rollback. On any handled failure the driver **removes the run lock** (releasing the roadmap mutex), then leaves any partial `workspace/<task-id>/` + `.task-current` in place as the abort signal; the user inspects the postmortem, then explicitly cleans up with a bare `/task:ship` (full close, which sweeps `auto-error.log` and the whole subfolder). Step 0 gate 2 (`.task-current` absent) blocks a fresh `/task:auto-roadmap` until that sweep. On failure **before** the item-runner's Step 1 design-runner lands `.task-current` (e.g. roadmap-validate failure inside open, or task-id collision), no workspace subfolder was created; there is nothing to clean up, and the user reruns `/task:auto-roadmap` directly. Every later stage — build-runner spawn, audit, ship — always has a workspace subfolder available, so its only FAIL shape is the post-open one. (Only an unhandled driver crash leaves the run lock behind; then Step 0 gate 3 reports it for a manual `rm` on top of the `/task:ship` sweep.)

Postmortem block format is standardized in `skills/_lib/fail-log.sh` — `--- FAIL <ISO> ---` for a runner's per-stage failure, `--- ORCHESTRATOR FAIL <ISO> ---` for a block appended by an orchestration layer after a child's FAIL. There are **two** orchestration layers that can append the latter: the **item-runner** (after a design/build-runner FAIL, or for its own internal failures — `Implement-Model:` extraction miss at item-runner Step 2, audit iteration-limit exhaustion at Step 4), and the **driver** (only when the item-runner returns malformed/absent status, or on a driver-detected mtime race). All reuse the `subagent status line` slot for the failure reason to keep the on-disk shape uniform.

Postmortem path: `.task/workspace/<task-id>/auto-error.log` if `.task-current` exists (design-runner succeeded in landing it); otherwise **no on-disk postmortem** — the inline FAIL message (in the item-runner's return, relayed by the driver) is the only record.

Failure triggers: design-runner or build-runner FAIL return, malformed child status line, `Implement-Model:` extraction miss (item-runner Step 2), audit high-severity finding unfixed after 2 iterations (item-runner Step 4), commit refusal/failure, close failure, run-lock collision at launch (driver Step 2), `task.md` Description body empty at close (item-runner Step 5), item-runner returned malformed/absent status (driver Substep 3.4), roadmap-mtime race detected at Substep 3.1.

## Cross-worktree safety

Two parallel git worktrees of one repo automatically share the same `.task/` (resolved via the `task.root` anchor — no symlink, no join step) yet can each own a different task at the same time, because the active-task pointer lives **per-worktree** inside git's per-worktree dir (`git rev-parse --git-path task-current`), not in the shared `.task/`. The autopilot inherits that property:

- Two `/task:auto-roadmap` runs in different worktrees over **different roadmaps** are allowed — each writes its own `.task/roadmap/<slug>.lock` and owns its own per-item `workspace/<task-id>/` subfolders (which come and go as each item full-closes). Two runs over the **same roadmap** collide on the shared `.task/roadmap/<slug>.lock`: whichever worktree launches second trips Step 0 gate 3 (lock present), and if both somehow pass Step 0 before either writes, the `set -o noclobber` write at driver Step 2 fails the loser loud. The lock is keyed on the roadmap slug and written **once at launch** (before any item-runner), so the mutex covers the whole run continuously — there is no inter-item window where a sibling could slip in (unlike the old per-item workspace sentinel, which vanished between items).
- The lock lives in the **shared** `.task/roadmap/` (not the per-worktree git dir), so it is visible to every worktree — that shared visibility is exactly what makes it the cross-worktree mutex.
