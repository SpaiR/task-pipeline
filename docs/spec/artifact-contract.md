# Artifact contract — the inter-skill protocol

`.task/` has four role-specific subdirectories:

- `config/` — settings.
- `roadmap/` — multi-task initiative backlog (`<slug>.md`, optional `<slug>.spec.md` technical-decision sidecar, optional `<slug>.refine.md` audit sidecar).
- **`workspace/`** — container of per-umbrella subfolders. Each active umbrella owns `workspace/<task-id>/` with its working artifacts (`task.md`, `plan.md`, `audit.md`, `summary.md`) and (during a `/task:auto-roadmap` run) orchestrator state (`auto.lock`, `auto-error.log`). Multiple subfolders can coexist when separate git worktrees share `.task/` (one umbrella per worktree).
- `log/` — immutable history. Archive layout `log/<task-id>/<N>-<slug>/` keeps the same per-subtask files **flat** (no `workspace/` subdir there) — archives are immutable history, not active state.

Outside `.task/`, two sanctioned artifacts may live at the worktree root:

- **`.task-current`** — per-worktree pointer. One line: the lowercase task-id of the active umbrella in this worktree. Written by `/task:design`'s open phase (initial mode) and (transitively, under `/task:auto-roadmap`, via the first item-runner's design-runner `/task:design --from`); removed by a default `/task:ship` full close. Gitignored through `.git/info/exclude` (configured by `/task:bootstrap`). Downstream skills resolve `WS_DIR=.task/workspace/<task-id>/` through this file via `skills/_lib/resolve-ws.sh` (priority order: `$TASK_ID_OVERRIDE` env > positional argument > `.task-current` contents). A **provably-stale** pointer (empty, or naming a task-id whose `workspace/<id>/` subfolder is gone) is **self-healed** rather than requiring manual removal: the resolver's preamble path (`source_resolve_ws` → `heal_stale_pointer`) and design's open phase both clear it with a one-line notice and continue as "no active task", while a **valid** pointer (workspace present) is never touched. **Note:** neither the `/task:auto-roadmap` driver's own Step 2 nor the item-runner writes `.task-current` directly — the first item-runner's design-runner (`/task:design --from` initial-open path) does it. `.task-current` is **never** symlinked — it stays a real per-worktree file.
- **`.task` (symlink)** — present only in a *linked* git worktree: a symlink to the main worktree's `.task/`, materialized by `/task:bootstrap` Step 0 join-mode (in the main worktree `.task` is the real directory, not a symlink). This is the sanctioned mechanism by which separate worktrees share one `.task/` (see the `workspace/` bullet above) while each keeps its own `.task-current`. Passive artifact — no executable code. Git-excluded through `.git/info/exclude` via the pattern `.task` **without a trailing slash**: a slash (`.task/`) matches only a directory and would let the symlink surface in `git status`; the slash-less form covers both the real directory (main) and the symlink (linked worktree).

One `.task/`-internal sentinel is used by the autopilot:

- **`.task/workspace/<task-id>/auto.lock`** — per-umbrella autopilot sentinel written by the **first `auto-roadmap-item-runner`** (its Step 2, gated on `is_first`, after its design-runner lands `.task-current` and the workspace subfolder). Carries the run's parameters and an `orchestrator=auto-roadmap` discriminator. Removed implicitly when the last item-runner's bare full-close ship deletes the workspace subfolder on success; retained on failure as abort signal. Serves both as launch-time diagnostic snapshot and as the cross-worktree mutex — a sibling `/task:auto-roadmap` in another worktree that shares this `.task/` sees the sentinel under `workspace/*/` and refuses to step on the same umbrella.

## Producer/consumer table

| File | Produced by | Consumed by |
|------|-------------|-------------|
| `.task-current` (worktree root) | `/task:design`'s open phase (initial mode); under `/task:auto-roadmap`, the **first item-runner's design-runner** (its `/task:design --from` initial path — neither the driver SKILL.md nor the item-runner writes it directly); removed by a default `/task:ship` full close, or **self-healed** (removed with a one-line notice) when provably stale by `_lib/resolve-ws.sh`'s `heal_stale_pointer` on the `source_resolve_ws` path and by design's open phase. Single line: lowercase task-id of the active umbrella in this worktree. | `_lib/resolve-ws.sh` (resolves WS_DIR for every context script and bash helper; `source_resolve_ws` self-heals a provably-stale pointer first — empty / missing workspace subfolder — never a valid one); design's open phase `--from` continuation check (matches against line-1 task-id of `task.md`) and its stale-pointer self-heal; `/task:auto-roadmap` Step 0 precondition (refuses if present); `/task:ship` full-close precondition |
| `.task/roadmap/<slug>.md` | `/task:roadmap` (initial); user-edited thereafter; `/task:ship` flips `- [ ]` → `- [x]` (auto-mark via `close.sh`); `/task:roadmap --refine` rewrites item bodies on high-severity auto-applied fixes (never flips checkboxes) | design's open phase (`--from`); `/task:ship` (auto-mark lookup); `/task:roadmap --refine` (R3 lens input) |
| `.task/roadmap/<slug>.refine.md` | `/task:roadmap --refine` appends `## Iteration N` (Step R4) — append-only sidecar carrying lens findings (`severity / category / location / problem / fix`) with per-finding `Status:` (`pending fix` / `Fixed` / `Skipped: <reason>`). Lifecycle independent of the roadmap proper (`<slug>.md`); never produced by brainstorm mode | `/task:roadmap --refine` re-entry (R3 reads prior `## Iteration N` blocks for the `Decisions (prior iterations)` prompt block; R6 reads the iteration count for the bound check); user (manual review of med/low findings — those are not auto-applied) |
| `.task/roadmap/<slug>.spec.md` | `/task:roadmap` **brainstorm mode only**, written at Step 5–7 when the brainstorm surfaced load-bearing technical anchors (no anchors → no file); user-edited thereafter. **Never** produced or modified by refine mode. Numbered `## N.` decision sections (`**Decision:**` / `**Rationale:**` / `**Constrains:**`), referenced from roadmap items via `### Spec references` → `<slug>.spec.md §N`. Not enforced by `validate.sh` | design's blueprint phase (Step 1.5 — best-effort read of the cited `## N.` sections to ground `## Steps` in pinned decisions; interactive stop-and-ask / non-interactive WARN-and-proceed on a missing file or section); `/task:roadmap --refine` Clarity auditor (resolves `<slug>.spec.md §N` references — dangling → `broken spec ref`) |
| `.task/workspace/<task-id>/task.md` | design's open phase (header + body — body is written by Step 2a quick-draft on the manual path for any non-empty context, by `--from` mode directly from the roadmap blockquote, or left empty when `--idea` opts out so the idea phase brainstorms it; `--from` mode also writes `Roadmap:` + `Source item:`; continuation mode rewrites only per-subtask header lines and Description body, preserving line 1, `Roadmap:`, and any `## Decisions`); design's idea phase (Description; architect + Socratic modes also append `## Decisions`); `/task:ship --next` (clears Description body in place via `close.sh`; preserves any `## Decisions`) | design's blueprint + refine phases; build's implement + audit phases; `/task:ship` (also reads `Roadmap:` + `Source item:` for auto-mark) |
| `.task/workspace/<task-id>/plan.md` | design's blueprint phase; design's refine phase appends `## Decisions`. `## Tests` only iff `tests_required`. Header line `Implement-Model: <opus\|sonnet\|haiku>` between `# Plan:` and `## Scope` is parser-validated by `validate.sh` and **load-bearing for `/task:auto-roadmap`** (the `auto-roadmap-item-runner` reads it at its Step 3 and passes the value as `Agent.model` override to `auto-roadmap-build-runner`); harmless in manual flows. | build's implement + audit phases; `_lib/touches-gate.sh` reads `File:` and `Touches:` lines for audit auto-fix scope (token sanitization strips backticks / `(…)` / trailing em-/en-dash prose; unresolvable tokens emit stderr `WARN:`); `/task:auto-roadmap`'s item-runner reads `Implement-Model:` between its design-runner OK and build-runner spawn |
| `.task/workspace/<task-id>/audit.md` | build's audit phase appends `## Iteration N` | build's audit phase re-entry; orchestrator auto-fix loop reads pending fixes |
| `.task/workspace/<task-id>/summary.md` | build's implement phase. **Never** written by build's audit phase | `/task:ship`'s commit step (primary); `/task:ship`'s close step (slug source) |
| `.task/log/<task-id>/<N>-<slug>/` | `/task:ship` (via `close.sh`) archives plan/audit/summary.md (and `task.md` only on a full close — the default) — flat layout; the default full close removes the entire `workspace/<task-id>/` subfolder; `--next` removes only the archived files from `workspace/<task-id>/` and keeps `task.md` with Description cleared | history; user (recovery: manual `cp` from `.task/log/<id>/<latest>/task.md` back into `.task/workspace/<id>/` if reviving a closed umbrella) |
| `.task/workspace/<task-id>/auto.lock` | first `auto-roadmap-item-runner` (its Step 2): created **after** its design-runner's `/task:design --from` lands `.task-current` and the workspace subfolder, from run-level fields the driver passes in the spawn prompt. Field set: `roadmap=`, `roadmap_mtime=`, `start_item=`, optional `items_filter=`, `started=`, plus `orchestrator=auto-roadmap` for cross-worktree handover. Launch-time snapshot — never updated after it is written (the driver keeps its own in-memory `ROADMAP_MTIME`, refreshed at Substep 3.4 from the value each item-runner returns). Removed implicitly when the umbrella's default full close (`close.sh <slug>`) deletes the whole `<task-id>/` subfolder on success; **kept on failure** (alongside the subfolder) as deliberate abort signal. | `/task:auto-roadmap` Step 0 (hard-stop precondition — scans `workspace/*/auto.lock`); never re-read for run state by the loop itself. Existence under another worktree's umbrella is the cross-worktree mutex. |
| `.task/workspace/<task-id>/auto-error.log` (no fallback when failure precedes the first `/task:design --from`, i.e. `.task-current` does not yet exist) | `auto-roadmap-design-runner` / `auto-roadmap-build-runner` on FAIL append `--- FAIL <ISO> ---` via `_lib/fail-log.sh` (item, stage, reason, stage-log tail, `<dir>` snapshot); the **item-runner** appends `--- ORCHESTRATOR FAIL <ISO> ---` on a child FAIL or its own internal failure; the **driver** appends one only when the item-runner returns malformed/absent status or on a mtime race. Path resolution: if `.task-current` exists and the workspace subfolder is in place, write to `.task/workspace/<task-id>/auto-error.log`; otherwise no postmortem is written — the inline FAIL message (relayed by the driver) is the only record. | user (postmortem); never read by any skill; never archived through `/task:ship`. Lives in `<task-id>/` until a bare `/task:ship` (default full close) sweeps the subfolder. |

## Identifiers

- `task-id` is extracted from `# [TASK-ID] Title` (line 1 of `task.md`), lowercased.
- `N` = next free numeric prefix in `.task/log/<task-id>/`.
- In from-roadmap mode `Title` is the **initiative title** (roadmap H1, with `Implementation roadmap: ` prefix stripped); per-subtask context lives in the `Source item: #<N> — <item title>` header line.
- The `--from` form may omit `#<N>` — design's open phase then auto-picks the first heading matching `^### - \[ \] [0-9]+\. ` (after a `--next` ship + auto-mark, that's naturally the next un-checked item).

## `/task:design --from` task-id priority

1. ticket in `[extra context]` args
2. ticket embedded in item title
3. roadmap basename without `.md` (default)

So all subtasks of one roadmap share an umbrella `.task/log/<roadmap-slug>/{N}-<slug>/` folder. Same priority applies to both explicit-`#N` and no-`#N` (auto-pick) forms.

## `auto.lock` shape

Written by the first `auto-roadmap-item-runner` at its Step 2 (atomically via `set -o noclobber`) into `.task/workspace/<task-id-lc>/auto.lock` — that is, **inside** the umbrella's workspace subfolder, after its design-runner's `/task:design --from` has landed `.task-current` and the workspace subfolder. The autopilot's run parameters live in the driver's main-thread memory (captured at Step 2, passed into every item-runner spawn); this file is the first on-disk record of the run. Read by Step 0 (existence-check via `workspace/*/auto.lock` glob) of subsequent invocations and (in another worktree's case) as the cross-worktree handover signal. Five required `key=value` lines plus one optional (`items_filter` when `--items` or `--next`), English regardless of `config.md` → "Language" (parser-stable):

```
roadmap=.task/roadmap/api-v2-migration.md
roadmap_mtime=1746810000
start_item=3
started=2026-05-11T12:34:56Z
orchestrator=auto-roadmap
items_filter=3-5,7
```

Field order in the sample mirrors the `auto-locks.sh write` argument order in `auto-roadmap-item-runner.md` Step 2 (optional `items_filter=` last — the writer drops it when empty). Parsers key on the `<key>=` prefix; position is not significant.

- `roadmap_mtime` — Unix epoch from `stat` (`-f '%m'` on BSD/macOS, `-c '%Y'` on GNU/Linux); the **launch-time** mtime captured at the driver's Step 2 wizard run and passed into the first item-runner. Substep 3.1 compares the live roadmap mtime against the driver's **in-memory** `ROADMAP_MTIME` (refreshed at Substep 3.4 from the value each item-runner returns after a `--next` close); the on-disk value is the launch snapshot and is intentionally not updated.
- `start_item` — lowest item number to run (from `--from #N` or the auto-picked first un-checked item). When `items_filter` is also present, `items_filter` wins and `start_item` is informational only.
- `items_filter` — **optional**; written **only** when `/task:auto-roadmap --items <spec>` **or** `--next` was passed. Value is the raw spec (`N`, `N-M`, `N-`, or comma-separated combinations); `--next` resolves to a single-item `<N>` (the first unchecked item).
- `started` — ISO 8601 UTC timestamp.
- `orchestrator=auto-roadmap` — discriminator field; identifies the owning skill for cross-worktree refusal.

**No `impl_model_override`** — the per-item implement model is sourced from each item's `plan.md → Implement-Model:` (read fresh by the item-runner at its Step 3, between its design-runner and build-runner spawns), not stored on the lock. The lock captures the **run** parameters, not per-item plan content.

Removed implicitly when the **last item-runner's bare full-close ship** (its Step 6, Branch B) deletes the whole `workspace/<task-id>/` subfolder on a clean finish — no separate finalize commit is emitted. Retained on failure (together with the subfolder) as the deliberate abort signal — Step 0 then refuses re-entry by scanning `workspace/*/auto.lock` until the user runs a bare `/task:ship` (default full close) manually to clean up.

## `task.md` header structure (above the first `---`)

- Line 1: `# [task-id] Title`.
- Optional `Roadmap: <path>` and `Source item: #<N> — <title>` for from-roadmap umbrellas — **load-bearing for `close.sh:Step 1.5` auto-mark**. Renaming/translating either label, or moving below `---`, silently disables auto-mark — keep them ASCII and above the separator, and update `close.sh`'s awk in the same change. Within the `Source item:` line, only the `#<N>` token is parser-required — `close.sh` matches on `^Source item: #[0-9]+` and ignores the ` — <title>` tail; the title is the audit trail back to the roadmap item, surfaced by `validate.sh` as a WARN-only when missing (not a hard error).
- Optional `Modules:` / `Packages:` / `Key files:`.
