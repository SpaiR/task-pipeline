# `/task:auto-roadmap` orchestrator mechanics

Material common to the orchestrator's bash gate (`auto-roadmap-context.sh`), the main-thread driver loop (`auto-roadmap/SKILL.md`), and the per-item subagent `auto-roadmap-item-runner.md` (which itself spawns `auto-roadmap-design-runner.md` for open + blueprint and `auto-roadmap-build-runner.md` for implement, then runs audit + ship). Anchors here are the single source of truth for the three hard-stop preconditions, the `--items` grammar, the sentinel-file invariants, the failure protocol, the per-stage model split, and the cross-worktree contract — other spec sections ([invariants.md](invariants.md), [pipeline.md](pipeline.md)) link to anchors below instead of restating these rules.

Concrete `auto.lock` field shape is in [artifact-contract.md](artifact-contract.md) — this file references it, never duplicates it.

## Per-stage model split

A per-item cycle still uses a per-stage model split, now expressed as spawns **within one `auto-roadmap-item-runner`** rather than dispatch points in the driver's main thread:

| Stage | Where | Model source |
|-------|-------|--------------|
| (per-item orchestration) | `auto-roadmap-item-runner` subagent | inherits parent-session model (user's `/model` choice, typically opus) |
| Open + Blueprint | `auto-roadmap-design-runner` sub-subagent | inherits the item-runner's model (= parent-session model) |
| Implement | `auto-roadmap-build-runner` sub-subagent | `plan.md → Implement-Model:` (`opus`, `sonnet`, or `haiku`) — passed by the item-runner as `Agent.model` override at spawn time |
| Audit lens fanout (×3) | `audit-{clarity,reuse,simplicity}-auditor` sub-subagents | pin `model: sonnet` in their own frontmatter (do not inherit) |
| Audit orchestration + ship | the `auto-roadmap-item-runner` itself | its own (parent-session) model |

The split exists because implement is the largest-input stage of the cycle (reads many sources, writes a diff) but the most mechanical once `plan.md` has fixed `Touches` + `Goal` per Step. Letting it run under a cheaper model than design saves significant cost on long roadmaps while keeping architectural decisions (blueprint) and code review (audit) on the parent-session model. The `Implement-Model:` rubric is in `skills/design/phases/blueprint.md` Step 3. Depth budget: `driver(0) → item-runner(1) → {design-runner | build-runner | lens auditor}(2)`, all leaves — well under the runtime's nesting cap.

`auto.lock` does **not** store the per-item implement model — it captures **run** parameters at launch, not per-item plan content. The implement model is read fresh from each item's `plan.md` by the item-runner (its Step 3), between design-runner's OK and the build-runner spawn (see `agents/auto-roadmap-item-runner.md` Step 3 for the canonical regex).

## Step 0 preconditions — three hard-stop gates

`auto-roadmap-context.sh` enforces all three gates in bash, with prompt-layer reminders in `SKILL.md`. Failing any gate refuses to start the run with a specific message — no silent recovery, no rollback.

1. **`.task/config/config.md` exists** — universal pipeline precondition.
2. **`.task-current` absent at the worktree root** — no umbrella in flight in this worktree.
3. **No `.task/workspace/*/auto.lock` anywhere** — no previous orchestrator run left a per-umbrella sentinel behind, and no sibling worktree sharing this `.task/` currently owns one (the scan is glob-wide).

Beyond the three gates, the skill recommends running the session in auto mode (auto-accept edits) so implement-stage `Edit` calls don't prompt mid-run. A recommendation only — not a precondition, not enforced.

## `--items` spec grammar

The parsed include-set is captured in main-thread memory at Step 2 (variable `ITEMS_SPEC`), passed into every item-runner spawn, and recorded on disk in the `items_filter` field of the per-umbrella `auto.lock` sentinel once the first item-runner writes it (its Step 2). Mutually exclusive with `--from` at the SKILL.md layer.

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

`--next` is sugar: it resolves to a **single-item include-set** — the first unchecked item (lowest `N`) — and sets `ITEMS_SPEC=<N>`, so it travels the exact `--items <N>` path downstream (single-item run set, `auto.lock` `items_filter=<N>`, last-item bare full-close ship). Mutually exclusive with `--from` / `--items` at the SKILL.md layer.

When both `items_filter` and `start_item` land in the sentinel, `items_filter` wins and `start_item` is informational only.

## Sentinel shape — anchor only

The concrete `key=value` field set, ordering, and write semantics live in [artifact-contract.md](artifact-contract.md):

- `.task/workspace/<task-id>/auto.lock` shape — see [artifact-contract.md](artifact-contract.md) § `auto.lock` shape.

Invariants:

- The file is **English regardless of `config.md` → "Language"** — parser-stable.
- Written **atomically via `set -o noclobber`** — concurrent writes fail loud.
- Carries `roadmap_mtime` as a launch-time snapshot. Race detection per loop iteration compares the live roadmap mtime to the **in-memory** `ROADMAP_MTIME` variable (refreshed by the driver's Substep 3.4 from the value the item-runner returns after every successful `--next` close); the on-disk value is never updated after the first item-runner writes it.
- Carries `orchestrator=auto-roadmap` so a sibling `/task:auto-roadmap` invocation in another worktree refuses to step on the same umbrella — the file's existence under `workspace/*/` is itself the cross-worktree mutex.
- **Retained on failure** as the deliberate abort signal (alongside the rest of the `workspace/<task-id>/` subfolder); removed implicitly by the **last item-runner's bare full-close ship** on clean finish — it rides with the subfolder. On a failure path the user runs a bare `/task:ship` (default full close) manually to sweep the partial umbrella; there is no dedicated recovery slug.
- After every successful `/task:ship` the **roadmap mtime bumps** (`close.sh:Step 1.5` flips `[ ]` → `[x]`). The item-runner captures the post-close mtime and returns it in its digest; the driver assigns it to the in-memory `ROADMAP_MTIME` (Substep 3.4) before the next iteration's race check, otherwise the legitimate close-induced bump would trip the check. The last item (full close) returns no mtime — there is no next iteration.

## Failure protocol — fail-stop, no rollback

The orchestrator is fail-stop with no automatic rollback. On any failure where the workspace subfolder exists, it is retained as the abort signal; the user inspects the postmortem, then explicitly cleans up with a bare `/task:ship` (default full close, which sweeps the per-umbrella `auto.lock`, `auto-error.log`, and the whole subfolder). On failure **before** the item-runner's Step 1 design-runner lands `.task-current` (e.g. roadmap-validate failure inside open, or task-id collision), no workspace subfolder was created; there is nothing to clean up, and the user reruns `/task:auto-roadmap` directly. Every later stage — build-runner spawn, audit, ship — always has a workspace subfolder available, so its only FAIL shape is the post-open one.

Postmortem block format is standardized in `skills/_lib/fail-log.sh` — `--- FAIL <ISO> ---` for a runner's per-stage failure, `--- ORCHESTRATOR FAIL <ISO> ---` for a block appended by an orchestration layer after a child's FAIL. There are now **two** orchestration layers that can append the latter: the **item-runner** (after a design/build-runner FAIL, or for its own internal failures — `Implement-Model:` extraction miss at item-runner Step 3, audit iteration-limit exhaustion at Step 5), and the **driver** (only when the item-runner returns malformed/absent status, or on a driver-detected mtime race). All reuse the `subagent status line` slot for the failure reason to keep the on-disk shape uniform.

Postmortem path: `.task/workspace/<task-id>/auto-error.log` if `.task-current` exists (design-runner succeeded in landing it); otherwise **no on-disk postmortem** — the inline FAIL message (in the item-runner's return, relayed by the driver) is the only record.

Failure triggers: design-runner or build-runner FAIL return, malformed child status line, `Implement-Model:` extraction miss (item-runner Step 3), audit high-severity finding unfixed after 2 iterations (item-runner Step 5), commit refusal/failure, close failure, `auto.lock` collision (item-runner Step 2), `task.md` Description body empty at the last-item full close (item-runner Step 6), item-runner returned malformed/absent status (driver Substep 3.4), roadmap-mtime race detected at Substep 3.1.

## Cross-worktree safety

Two parallel git worktrees that share `.task/` (via a `.task` symlink — materialized by `/task:bootstrap` Step 0 join-mode, or placed manually) can each own a different umbrella at the same time because `.task-current` is **per-worktree**, not in `.task/`. The autopilot inherits that property:

- Two `/task:auto-roadmap` runs in different worktrees that derive **distinct** task-ids are allowed — each owns its own `workspace/<task-id>/` subfolder and `workspace/<task-id>/auto.lock` sentinel. A same-task-id collision (two worktrees targeting the same roadmap) is caught at one of two points: (a) Step 0 gate 3 refuses if the sibling worktree's first item-runner has already written `workspace/<task-id>/auto.lock`; (b) if both worktrees somehow pass Step 0 against the same target roadmap before either writes the sentinel, the loser's design-runner's `/task:design --from` refuses on `workspace/<task-id>/` mkdir collision, and the item-runner's own `auto.lock` write (`set -o noclobber`) is the final backstop.
- There is **no worktree-local sentinel** before the first item-runner writes `auto.lock` — the driver keeps run state in memory. The Step 2 → first-item-runner-lock-write window in the same worktree is single-threaded by definition (interactive Claude Code processes one slash command at a time per session), so no additional file-based mutex is needed there.
