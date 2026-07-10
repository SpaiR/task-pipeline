# `/task:auto-roadmap` orchestrator mechanics

Material common to the orchestrator's bash gate (`auto-roadmap-context.sh`), main-thread loop (`auto-roadmap/SKILL.md`), and the two per-item subagents (`auto-roadmap-design-runner.md` for open + blueprint, `auto-roadmap-build-runner.md` for implement — both **shared with `/task:go --auto`**; this file documents their use under auto-roadmap). Anchors here are the single source of truth for the three hard-stop preconditions, the `--items` grammar, the sentinel-file invariants, the failure protocol, the per-stage model split, and the cross-worktree contract — other spec sections ([invariants.md](invariants.md), [pipeline.md](pipeline.md)) link to anchors below instead of restating these rules.

Concrete `auto.lock` field shape is in [artifact-contract.md](artifact-contract.md) — this file references it, never duplicates it.

## Per-stage model split

A per-item cycle uses **three different LLM dispatch points**, each able to run under its own model:

| Stage | Where | Model source |
|-------|-------|--------------|
| Open + Blueprint | `auto-roadmap-design-runner` subagent | inherits parent-session model (user's `/model` choice, typically opus) |
| Implement | `auto-roadmap-build-runner` subagent | `plan.md → Implement-Model:` (`opus`, `sonnet`, or `haiku`) — passed by main thread as `Agent.model` override at spawn time |
| Audit lens fanout (×3) + ship | main thread + `audit-{clarity,reuse,simplicity}-auditor` subagents | inherits parent-session model for main-thread work; lens auditors pin `model: sonnet` in their own frontmatter |

The split exists because implement is the largest-input stage of the cycle (reads many sources, writes a diff) but the most mechanical once `plan.md` has fixed `Touches` + `Goal` per Step. Letting it run under a cheaper model than design saves significant cost on long roadmaps while keeping architectural decisions (blueprint) and code review (audit) on the parent-session model. The `Implement-Model:` rubric is in `skills/design/phases/blueprint.md` Step 3.

`auto.lock` does **not** store the per-item implement model — it captures **run** parameters at launch, not per-item plan content. The implement model is read fresh from each item's `plan.md` between Substep 3.3's OK and Substep 3.6's spawn (see `skills/auto-roadmap/SKILL.md` Substep 3.5 for the canonical regex).

## Step 0 preconditions — three hard-stop gates

`auto-roadmap-context.sh` enforces all three gates in bash, with prompt-layer reminders in `SKILL.md`. Failing any gate refuses to start the run with a specific message — no silent recovery, no rollback.

1. **`.task/config/config.md` exists** — universal pipeline precondition.
2. **`.task-current` absent at the worktree root** — no umbrella in flight in this worktree.
3. **No `.task/workspace/*/auto.lock` anywhere** — no previous orchestrator run left a per-umbrella sentinel behind, and no sibling worktree sharing this `.task/` currently owns one (the scan is glob-wide).

Beyond the three gates, the skill recommends running the session in auto mode (auto-accept edits) so implement-stage `Edit` calls don't prompt mid-run. A recommendation only — not a precondition, not enforced.

## `--items` spec grammar

The parsed include-set is captured in main-thread memory at Step 2 (variable `ITEMS_SPEC`) and recorded on disk in the `items_filter` field of the per-umbrella `auto.lock` sentinel once Substep 3.4 writes it. Mutually exclusive with `--from` at the SKILL.md layer.

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

`--next` is sugar: it resolves to a **single-item include-set** — the first unchecked item (lowest `N`) — and sets `ITEMS_SPEC=<N>`, so it travels the exact `--items <N>` path downstream (single-item run set, `auto.lock` `items_filter=<N>`, last-item `--full` ship). Mutually exclusive with `--from` / `--items` at the SKILL.md layer.

When both `items_filter` and `start_item` land in the sentinel, `items_filter` wins and `start_item` is informational only.

## Sentinel shape — anchor only

The concrete `key=value` field set, ordering, and write semantics live in [artifact-contract.md](artifact-contract.md):

- `.task/workspace/<task-id>/auto.lock` shape — see [artifact-contract.md](artifact-contract.md) § `auto.lock` shape.

Invariants:

- The file is **English regardless of `config.md` → "Language"** — parser-stable.
- Written **atomically via `set -o noclobber`** — concurrent writes fail loud.
- Carries `roadmap_mtime` as a launch-time snapshot. Race detection per loop iteration compares the live roadmap mtime to the **in-memory** `ROADMAP_MTIME` variable (refreshed by Substep 3.9 after every successful close); the on-disk value is not updated after Substep 3.4.
- Carries `orchestrator=auto-roadmap` so a sibling `/task:auto-roadmap` invocation in another worktree refuses to step on the same umbrella — the file's existence under `workspace/*/` is itself the cross-worktree mutex. `/task:go --auto` writes the same sentinel with `orchestrator=go` (a smaller field set — see [artifact-contract.md](artifact-contract.md) § `auto.lock` shape); both entry points scan the same `workspace/*/auto.lock` glob, so the two autonomous modes are mutually exclusive on a shared `.task/`.
- **Retained on failure** as the deliberate abort signal (alongside the rest of the `workspace/<task-id>/` subfolder); removed implicitly by the **last item's `/task:ship --full`** (Substep 3.9 Branch B) on clean finish — it rides with the subfolder. On a failure path the user runs `/task:ship --full chore-finalize` manually to sweep the partial umbrella; the orchestrator no longer emits `chore-finalize` on its own.
- After every successful `/task:ship` the **roadmap mtime bumps** (`close.sh:Step 1.5` flips `[ ]` → `[x]`). Main thread re-stats the roadmap and refreshes the in-memory `ROADMAP_MTIME` (Substep 3.9 Branch A) before the next iteration's race check, otherwise the legitimate close-induced bump would trip the check. Branch B (last item, `--full`) skips the refresh — there is no next iteration.

## Failure protocol — fail-stop, no rollback

The orchestrator is fail-stop with no automatic rollback. On any failure where the workspace subfolder exists, it is retained as the abort signal; the user inspects the postmortem, then explicitly cleans up with `/task:ship --full chore-finalize` (which sweeps the per-umbrella `auto.lock`, `auto-error.log`, and the whole subfolder). On failure **before** `auto-roadmap-design-runner`'s `/task:design --from` lands `.task-current` (e.g. roadmap-validate failure inside Step a, or task-id collision), no workspace subfolder was created; there is nothing to clean up, and the user reruns `/task:auto-roadmap` directly. `auto-roadmap-build-runner` always runs after design-runner OK and so always has a workspace subfolder available — its only FAIL shape is the post-open one.

Postmortem block format is standardized in `skills/_lib/fail-log.sh` — `--- FAIL <ISO> ---` for the subagent's per-stage failure, `--- ORCHESTRATOR FAIL <ISO> ---` for the main-thread block appended after a subagent's own FAIL block. The main-thread block is also used by the orchestrator-side failures that do not originate in a subagent: `Implement-Model:` extraction failure (Substep 3.5) and audit iteration-limit exhaustion (Substep 3.8) — both reuse the `subagent status line` slot for the failure reason to keep the on-disk shape uniform.

Postmortem path: `.task/workspace/<task-id>/auto-error.log` if `.task-current` exists (design-runner succeeded in landing it); otherwise **no on-disk postmortem** — the subagent's inline FAIL message in the orchestrator's main-thread output is the only record.

Failure triggers: design-runner or build-runner FAIL return, malformed status line, `Implement-Model:` extraction failure between the two subagents (Substep 3.5), audit high-severity finding unfixed (`pending fix`), commit refusal/failure, close failure, roadmap-mtime race detected at Substep 3.1, `task.md` Description body empty at the last-item `--full` ship (Substep 3.9 Branch B sanity check — implement phase produced no Description content).

## Cross-worktree safety

Two parallel git worktrees that share `.task/` (via a `.task` symlink — materialized by `/task:bootstrap` Step 0 join-mode, or placed manually) can each own a different umbrella at the same time because `.task-current` is **per-worktree**, not in `.task/`. The autopilot inherits that property:

- Two `/task:auto-roadmap` runs in different worktrees that derive **distinct** task-ids are allowed — each owns its own `workspace/<task-id>/` subfolder and `workspace/<task-id>/auto.lock` sentinel. A same-task-id collision (two worktrees targeting the same roadmap) is caught at one of two points: (a) Step 0 gate 3 refuses if the sibling worktree's design-runner has already landed `workspace/<task-id>/auto.lock`; (b) if both worktrees somehow pass Step 0 against the same target roadmap before either lands the sentinel, the loser's design-runner's `/task:design --from` refuses on `workspace/<task-id>/` mkdir collision.
- There is **no worktree-local sentinel** before Step 2's run state lands on disk in Substep 3.4 — main thread keeps that state in memory through the first iteration. The Step 2 → Substep 3.4 window in the same worktree is single-threaded by definition (interactive Claude Code processes one slash command at a time per session), so no additional file-based mutex is needed there.
