# Artifact contract — the inter-skill protocol

`.task/` has four role-specific subdirectories:

- `config/` — settings.
- `roadmap/` — multi-task initiative backlog (`<slug>.md`, optional `<slug>.spec.md` technical-decision sidecar, optional `<slug>.refine.md` audit sidecar).
- **`workspace/`** — container of per-task subfolders. Each active task owns `workspace/<task-id>/` with its working artifacts (`task.md`, `plan.md`, `audit.md`, `summary.md`) and (during a `/task:auto-roadmap` run, on failure) `auto-error.log`. Multiple subfolders can coexist when separate git worktrees share `.task/` (one active task per worktree).
- `log/` — immutable history. Archive layout `log/<task-id>/<N>-<slug>/` keeps the same per-subtask files **flat** (no `workspace/` subdir there) — archives are immutable history, not active state.

Two things live outside the `.task/` tree:

- **`.task/` itself** sits once at the **pipeline root**, shared by every worktree of the repo. The root is recorded in `git config --local task.root` by `/task:bootstrap` (fallback `dirname(git-common-dir)`), so all worktrees — nested (`<repo>/.claude/worktrees/<name>`), sibling (`git worktree add ../foo`), or a bare repo's worktrees — resolve the same `.task/` with **zero setup**. There is no `.task` symlink and no "join" step; the old symlink + `/task:bootstrap` join-mode are gone. `.task/` is git-excluded through `.git/info/exclude` (pattern `.task`, configured by `/task:bootstrap`).
- **the active-task pointer** — per-worktree, one line: the lowercase task-id of the active umbrella in this worktree. It lives **inside git's per-worktree dir**, resolved via `git rev-parse --path-format=absolute --git-path task-current` (`.git/worktrees/<name>/task-current` in a linked worktree, `.git/task-current` in the main one). Being inside the git dir, it is per-worktree by construction, is never part of any work tree, and needs no git-exclude entry. Written by `/task:design`'s open phase (initial mode) and (transitively, under `/task:auto-roadmap`, via the first item-runner's design-runner `/task:design --from`); removed by a default `/task:ship` full close. Downstream skills resolve `WS_DIR=.task/workspace/<task-id>/` through it via `skills/_lib/resolve-ws.sh` (priority: `$TASK_ID_OVERRIDE` env > positional argument > pointer contents via `task_current_path`). A **provably-stale** pointer (empty, or naming a task-id whose `workspace/<id>/` subfolder is gone) is **self-healed** rather than requiring manual removal: the resolver's preamble path (`source_resolve_ws` → `heal_stale_pointer`) and design's open phase both clear it with a one-line notice and continue as "no active task", while a **valid** pointer (workspace present) is never touched. **Note:** neither the `/task:auto-roadmap` driver's own Step 2 nor the item-runner writes the pointer directly — each item-runner's design-runner (`/task:design --from` initial-open path) does it.

One `.task/`-internal sentinel is used by the autopilot:

- **`.task/roadmap/<slug>.lock`** — the autopilot **run lock**, written by the **driver** at its Step 2 (launch, before any item-runner), keyed on the roadmap slug and living in the shared `.task/roadmap/` so it is visible cross-worktree. Carries the run's parameters and an `orchestrator=auto-roadmap` discriminator. The driver removes it on every handled exit (clean finish and handled failures); it survives only an unhandled crash, where Step 0 gate 3 reports it for a manual `rm`. It is the run's cross-worktree mutex — a sibling `/task:auto-roadmap` on the same roadmap trips Step 0 gate 3 (or the atomic `set -o noclobber` write). Distinct from the per-task `workspace/<task-id>/` subfolders, which each item's full-close ship sweeps.

## Producer/consumer table

| File | Produced by | Consumed by |
|------|-------------|-------------|
| active-task pointer (git per-worktree dir — `git rev-parse --git-path task-current`) | `/task:design`'s open phase (initial mode); under `/task:auto-roadmap`, the **first item-runner's design-runner** (its `/task:design --from` initial path — neither the driver SKILL.md nor the item-runner writes it directly); removed by a `/task:ship` full close, or **self-healed** (removed with a one-line notice) when provably stale by `_lib/resolve-ws.sh`'s `heal_stale_pointer` on the `source_resolve_ws` path and by design's open phase. Single line: lowercase task-id of the active task in this worktree. | `_lib/resolve-ws.sh` via `task_current_path` (resolves WS_DIR for every context script and bash helper; `source_resolve_ws` self-heals a provably-stale pointer — empty / missing workspace subfolder — never a valid one); design's open phase stale-pointer self-heal; `/task:auto-roadmap` Step 0 precondition (refuses if present); `/task:ship` full-close precondition |
| `.task/roadmap/<slug>.md` | `/task:roadmap` (initial); user-edited thereafter; `/task:ship` flips `- [ ]` → `- [x]` (auto-mark via `close.sh`); `/task:roadmap --refine` rewrites item bodies on high-severity auto-applied fixes (never flips checkboxes) | design's open phase (`--from`); `/task:ship` (auto-mark lookup); `/task:roadmap --refine` (R3 lens input) |
| `.task/roadmap/<slug>.refine.md` | `/task:roadmap --refine` appends `## Iteration N` (Step R4) — append-only sidecar carrying lens findings (`severity / category / location / problem / fix`) with per-finding `Status:` (`pending fix` / `Fixed` / `Skipped: <reason>`). Lifecycle independent of the roadmap proper (`<slug>.md`); never produced by brainstorm mode | `/task:roadmap --refine` re-entry (R3 reads prior `## Iteration N` blocks for the `Decisions (prior iterations)` prompt block; R6 reads the iteration count for the bound check); user (manual review of med/low findings — those are not auto-applied) |
| `.task/roadmap/<slug>.spec.md` | `/task:roadmap` **brainstorm mode only**, written at Step 5–7 when the brainstorm surfaced load-bearing technical anchors (no anchors → no file); user-edited thereafter. **Never** produced or modified by refine mode. Numbered `## N.` decision sections (`**Decision:**` / `**Rationale:**` / `**Constrains:**`), referenced from roadmap items via `### Spec references` → `<slug>.spec.md §N`. Not enforced by `validate.sh` | design's blueprint phase (Step 1.5 — best-effort read of the cited `## N.` sections to ground `## Steps` in pinned decisions; interactive stop-and-ask / non-interactive WARN-and-proceed on a missing file or section); `/task:roadmap --refine` Clarity auditor (resolves `<slug>.spec.md §N` references — dangling → `broken spec ref`) |
| `.task/workspace/<task-id>/task.md` | design's open phase (header + body — body is written by Step 2a quick-draft on the manual path for any non-empty context, or by `--from` mode directly from the roadmap blockquote; `--from` mode also writes `Roadmap:` + `Source item:`) | design's blueprint + refine phases; build's implement + audit phases; `/task:ship` (also reads `Roadmap:` + `Source item:` for auto-mark, then archives the whole file on full close) |
| `.task/workspace/<task-id>/plan.md` | design's blueprint phase; design's refine phase appends `## Decisions`. `## Tests` only iff `tests_required`. Header line `Implement-Model: <opus\|sonnet\|haiku>` between `# Plan:` and `## Scope` is parser-validated by `validate.sh` and **load-bearing for `/task:auto-roadmap`** (the `auto-roadmap-item-runner` reads it at its Step 3 and passes the value as `Agent.model` override to `auto-roadmap-build-runner`); harmless in manual flows. | build's implement + audit phases; `_lib/touches-gate.sh` reads `File:` and `Touches:` lines for audit auto-fix scope (token sanitization strips backticks / `(…)` / trailing em-/en-dash prose; unresolvable tokens emit stderr `WARN:`); `/task:auto-roadmap`'s item-runner reads `Implement-Model:` between its design-runner OK and build-runner spawn |
| `.task/workspace/<task-id>/audit.md` | build's audit phase appends `## Iteration N` | build's audit phase re-entry; orchestrator auto-fix loop reads pending fixes |
| `.task/workspace/<task-id>/summary.md` | build's implement phase. **Never** written by build's audit phase | `/task:ship`'s commit step (primary); `/task:ship`'s close step (slug source) |
| `.task/log/<task-id>/<N>-<slug>/` | `/task:ship` (via `close.sh`) archives plan/audit/summary.md **plus `task.md`** — flat layout; the full close then removes the entire `workspace/<task-id>/` subfolder | history; user (recovery: manual `cp` from `.task/log/<id>/<latest>/task.md` back into `.task/workspace/<id>/` if reviving a closed umbrella) |
| `.task/roadmap/<slug>.lock` | `/task:auto-roadmap` **driver** (its Step 2, at launch, before any item-runner). Field set: `roadmap=`, `roadmap_mtime=`, `start_item=`, optional `items_filter=`, `started=`, plus `orchestrator=auto-roadmap` for cross-worktree handover. Launch-time snapshot — never updated after write (the driver keeps its own in-memory `ROADMAP_MTIME`, refreshed at Substep 3.4 from the value each item-runner returns). Removed by the driver on clean finish (Step 4) and on every handled failure (Substep 3.1 / 3.4); survives only an unhandled crash. | `/task:auto-roadmap` Step 0 gate 3 (hard-stop precondition — scans `.task/roadmap/*.lock`); never re-read for run state by the loop itself. Its existence in the shared `.task/roadmap/` is the cross-worktree mutex. |
| `.task/workspace/<task-id>/auto-error.log` (no fallback when failure precedes the first `/task:design --from`, i.e. `.task-current` does not yet exist) | `auto-roadmap-design-runner` / `auto-roadmap-build-runner` on FAIL append `--- FAIL <ISO> ---` via `_lib/fail-log.sh` (item, stage, reason, stage-log tail, `<dir>` snapshot); the **item-runner** appends `--- ORCHESTRATOR FAIL <ISO> ---` on a child FAIL or its own internal failure; the **driver** appends one only when the item-runner returns malformed/absent status or on a mtime race. Path resolution: if `.task-current` exists and the workspace subfolder is in place, write to `.task/workspace/<task-id>/auto-error.log`; otherwise no postmortem is written — the inline FAIL message (relayed by the driver) is the only record. | user (postmortem); never read by any skill; never archived through `/task:ship`. Lives in `<task-id>/` until a bare `/task:ship` (default full close) sweeps the subfolder. |

## Identifiers

- `task-id` is extracted from `# [TASK-ID] Title` (line 1 of `task.md`), lowercased.
- `N` = next free numeric prefix in `.task/log/<task-id>/`.
- In from-roadmap mode `Title` is the **initiative title** (roadmap H1, with `Implementation roadmap: ` prefix stripped); per-subtask context lives in the `Source item: #<N> — <item title>` header line.
- The `--from` form may omit `#<N>` — design's open phase then auto-picks the first heading matching `^### - \[ \] [0-9]+\. ` (after a `--next` ship + auto-mark, that's naturally the next un-checked item).

## `/task:design --from` task-id priority

1. ticket in `[extra context]` args (the only override — opts one item out)
2. roadmap basename without `.md` (default)

A ticket in the item *title* does **not** override the slug, so all items of one roadmap share an umbrella `.task/log/<roadmap-slug>/{N}-<slug>/` folder. Same priority applies to both explicit-`#N` and no-`#N` (auto-pick) forms.

## Run lock shape

Written by the **driver** at its Step 2 (launch, atomically via `set -o noclobber`) into `.task/roadmap/<slug>.lock` — keyed on the roadmap slug, in the shared `.task/roadmap/` so it is visible cross-worktree. It is the run's cross-worktree mutex + crash sentinel; the driver keeps the run's parameters in main-thread memory and this file is their on-disk record. Read by Step 0 gate 3 (existence-check via `.task/roadmap/*.lock`) of subsequent invocations (including a sibling worktree). Five required `key=value` lines plus one optional (`items_filter` when `--items` or `--next`), English regardless of `config.md` → "Language" (parser-stable):

```
roadmap=.task/roadmap/api-v2-migration.md
roadmap_mtime=1746810000
start_item=3
started=2026-05-11T12:34:56Z
orchestrator=auto-roadmap
items_filter=3-5,7
```

Field order in the sample mirrors the `auto-locks.sh write` argument order in `auto-roadmap/SKILL.md` Step 2 (optional `items_filter=` last — the writer drops it when empty). Parsers key on the `<key>=` prefix; position is not significant.

- `roadmap_mtime` — Unix epoch from `stat` (`-f '%m'` on BSD/macOS, `-c '%Y'` on GNU/Linux); the **launch-time** mtime captured at the driver's Step 2. Substep 3.1 compares the live roadmap mtime against the driver's **in-memory** `ROADMAP_MTIME` (refreshed at Substep 3.4 from the value each item-runner returns after its close); the on-disk value is the launch snapshot and is intentionally not updated.
- `start_item` — lowest item number to run (from `--from #N` or the auto-picked first un-checked item). When `items_filter` is also present, `items_filter` wins and `start_item` is informational only.
- `items_filter` — **optional**; written **only** when `/task:auto-roadmap --items <spec>` **or** `--next` was passed. Value is the raw spec (`N`, `N-M`, `N-`, or comma-separated combinations); `--next` resolves to a single-item `<N>` (the first unchecked item).
- `started` — ISO 8601 UTC timestamp.
- `orchestrator=auto-roadmap` — discriminator field; identifies the owning skill for cross-worktree refusal.

**No `impl_model_override`** — the per-item implement model is sourced from each item's `plan.md → Implement-Model:` (read fresh by the item-runner at its Step 2, between its design-runner and build-runner spawns), not stored on the lock. The lock captures the **run** parameters, not per-item plan content.

The driver removes it on every handled exit — clean finish (Step 4) and every handled failure (Substep 3.1 / 3.4). It survives only an unhandled driver crash, where Step 0 gate 3 reports the path for a manual `rm`. Per-item `workspace/<task-id>/` subfolders are separate: each item's full-close ship sweeps its own subfolder + `.task-current`; a partial subfolder retained after a failure is the dirty-state signal Step 0 gate 2 blocks on until a bare `/task:ship` sweeps it.

## `task.md` header structure (above the first `---`)

- Line 1: `# [task-id] Title`.
- Optional `Roadmap: <path>` and `Source item: #<N> — <title>` for from-roadmap umbrellas — **load-bearing for `close.sh:Step 1.5` auto-mark**. Renaming/translating either label, or moving below `---`, silently disables auto-mark — keep them ASCII and above the separator, and update `close.sh`'s awk in the same change. Within the `Source item:` line, only the `#<N>` token is parser-required — `close.sh` matches on `^Source item: #[0-9]+` and ignores the ` — <title>` tail; the title is the audit trail back to the roadmap item, surfaced by `validate.sh` as a WARN-only when missing (not a hard error).
- Optional `Modules:` / `Packages:` / `Key files:`.
