---
name: auto-roadmap
description: 'Autopilot an approved `.task/roadmap/<slug>.md` — runs design → build → ship (full close) for each item inside the current session.'
disable-model-invocation: true
user-invocable: true
---

Drive an entire approved roadmap through the full pipeline from inside the **user's currently open Claude Code session**. The main thread (the "driver") owns run-level orchestration only — Step 0 gates, the wizard, the run lock, run-state, the per-item mtime race check and status re-check — and spawns **one `auto-roadmap-item-runner` subagent per item**. That item-runner runs the entire per-item cycle in its own isolated context: it spawns `auto-roadmap-design-runner` (open + blueprint, parent-session model), then `auto-roadmap-build-runner` (implement, under this item's `plan.md → Implement-Model:`), then the three build-audit lens auditors, then runs commit + close inline — and returns a compact report-card digest. Keeping the per-item diff bundle + lens results inside the disposable item-runner context (not the driver's) is what lets a run scale past the old ~15/~25-item auto-compact ceiling. **Every item ships a full `/task:ship` close** (slug auto-derived from `summary.md`), archiving its own `task.md` and re-opening fresh for the next item — there is no transition mode and no separate finalize commit.

**Input:** $ARGUMENTS — `[<roadmap-pathOrSlug>] [--next | --from #<N> | --items <spec>]`

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gates in `auto-roadmap-context.sh` remain authoritative (enforces all three Step 0 gates below).

**Runtime + orchestrator mechanics** (per-stage model split, context budget thresholds, the three Step 0 gates, `--items` grammar, sentinel invariants, failure protocol, cross-worktree safety, "inline" sub-skill execution semantics): [docs/spec/auto-roadmap.md](../../docs/spec/auto-roadmap.md). Reminders: this skill (the driver) itself does not navigate or modify project code and spawns no lens auditors — all per-item work, including audit + ship, happens inside the `auto-roadmap-item-runner` subagent it spawns. The item-runner executes `/task:build` / `/task:ship` **inline** (reads their SKILL.md + phase companion and follows the Steps directly, since both are `disable-model-invocation: true` and the `Skill` tool refuses them) — the driver never runs them.

**Recommended:** run the session in auto mode (auto-accept edits) so implement-stage `Edit` calls don't interrupt the run with prompts. The **parent-session model** (set via `/model` before launching) governs the item-runner, its design-runner, audit orchestration, and ship — implement alone is governed per-item by `plan.md → Implement-Model:`. For a roadmap dominated by rote items, launching under `/model sonnet` speeds those non-implement stages; reach for `/model opus` when the items carry genuine design difficulty. Recommendation only — not a precondition, not enforced.

## Step 0: Hard-stop preconditions

Three gates enforced by `auto-roadmap-context.sh` (surface its stderr verbatim on non-zero exit): `config.md` exists, `.task-current` absent, no stale `.task/roadmap/*.lock`. Full rationale: [docs/spec/auto-roadmap.md § Step 0](../../docs/spec/auto-roadmap.md).

## Step 1: Wizard / argument parsing

Parse `$ARGUMENTS` for:
- `<roadmap-pathOrSlug>` — first non-flag positional;
- `--next` — run **only** the first unchecked item (lowest `<N>`); sugar for `--items <N>` where `<N>` is auto-resolved from `items-unchecked` in Step 1's wizard branch;
- `--from #<N>` — explicit start item (run **every unchecked** item from `<N>` onwards);
- `--items <spec>` — explicit include-set (run **only** items in `<spec>`). Mutually exclusive with `--next` / `--from` (see below). Spec grammar (comma-separated parts, optional whitespace):
  - `N` — single item `#N`;
  - `N-M` — inclusive range `#N..#M` (requires `N ≤ M`);
  - `N-` — open range from `#N` to the last item in the roadmap;
  - combinations: `1,3-5,8` / `3-5,7-` / etc.

`--next`, `--from`, and `--items` are mutually exclusive — at most one may be passed. If more than one is present — **stop** with: "`--next`, `--from`, and `--items` are mutually exclusive. Use `--next` (or `--items <N>`) for a single item, or `--items <N>-` / `--from #<N>` to run from `<N>` onwards."

Run the context script:

```bash
bash "${CLAUDE_SKILL_DIR}/auto-roadmap-context.sh" [<roadmap-pathOrSlug>]
```

> **Run verbatim.** Don't add `CLAUDE_SKILL_DIR=…` inline before `bash` — Claude Code substitutes `${CLAUDE_SKILL_DIR}` at skill-load time, and bash same-line assignments don't take effect until *after* variable expansion (the path would resolve empty → `bash "/auto-roadmap-context.sh"`). If substitution clearly failed (literal `${CLAUDE_SKILL_DIR}` visible), use `bash -c '…'`: `CLAUDE_SKILL_DIR="<abs-skill-dir>" bash -c 'bash "${CLAUDE_SKILL_DIR}/auto-roadmap-context.sh" [arg]'`.

It re-enforces the hard-stop preconditions and, when an arg is passed, validates the roadmap (exit 1 on validation errors). When no arg is passed, it lists available roadmaps with `<slug>\t<done>/<total>\t<path>` per line — use that for the wizard.

**Wizard branches** (only when not pre-supplied via args) — use `AskUserQuestion` for any interactive choice, never free-text prompts:

- **Roadmap.** If `<roadmap-pathOrSlug>` was not given, build options from the `roadmaps-available` section. Each row is `<slug>\t<done>/<total>\t<path>` (malformed rows substitute `[malformed — …]` for `<done>/<total>`). Compute completeness in the wizard: a roadmap is *complete* when `<done> == <total>` (and `> 0`), *partial* otherwise. Sort: partial roadmaps first by `<done>/<total>`, complete ones last with the wizard-rendered `(complete)` suffix; malformed rows surfaced as their literal `[malformed …]` text. Refuse to proceed if a fully-complete roadmap is chosen. After selection, re-run the context script with the chosen slug to get `roadmap-resolution` and `items-unchecked`.
- **Start item / items filter.**
  - If `--items <spec>` was given, validate the spec (each expanded item number must exist in the roadmap; ranges where `N > M` are rejected). Allow expanded items to be already `[x]` — the main-thread loop will skip them with a progress note. If **every** expanded item is already `[x]`, stop with "All items in `--items` spec are already marked done; nothing to run."
  - Else if `--next` was given, take the **first** entry from `items-unchecked` (lowest `<N>`) and treat it as `--items <N>` — set `ITEMS_SPEC` to that single number (single-item include-set; run set is exactly `{N}`). If `items-unchecked` is empty, fall through to the empty-roadmap stop below.
  - Else if `--from #<N>` was given, validate that item `<N>` is currently `- [ ]` (hard-stop with "item #N is already [x]" otherwise).
  - Else (no `--items` / `--next` / `--from` given) → **item-scope question.** If `items-unchecked` has more than one entry, present a single `AskUserQuestion` (single-select) — "How much of `<roadmap>` should this run cover?" — with the options below (structured-choice convention (c) in [docs/spec/invariants.md § Interaction conventions](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar); the flags stay as the explicit non-interactive equivalents and skip this question when passed). If only **one** entry is unchecked, skip the question — the fork is degenerate — and pick that entry. Non-interactive carve-out: default to **All remaining** without asking.
    - **All remaining** (default / first option) → pick the first entry from `items-unchecked` (lowest `<N>`); leave `ITEMS_SPEC` empty so the driver runs every unchecked item from there onward. Identical to the prior no-flag behavior.
    - **Only next** → equivalent to `--next`: take the first `items-unchecked` entry and set `ITEMS_SPEC` to that single number (run set `{N}`).
    - **Pick range** → equivalent to `--items <spec>`: collect the spec via the `AskUserQuestion` free-text ("Other") option and validate it exactly as a passed `--items` (each expanded item must exist; `N > M` ranges rejected).

If `items-unchecked` is empty (and no `--items` filter was given): stop with "All items in `<roadmap>` are already marked done/cancelled (`[x]`/`[~]`/`[>]`/`[-]`); nothing to run."

## Step 2: Confirm + capture run state

Print the summary block, then ask for confirmation via `AskUserQuestion`:

```
Roadmap:  <path>
Audit:    on  (always — each item-runner fans out to the three lens auditors)
Filter:   <spec>                    # only shown if --items was passed; otherwise "Start at: #<N>"
Items to run (<count>):
  #<N>    — <title>
  #<N+1>  — <title>
  ...
Mode:     interactive (session must stay open for the run's duration)
```

`AskUserQuestion` shape: single-select, question `"Launch /task:auto-roadmap for these <count> items?"`, options `Launch` / `Cancel`. On `Cancel` — exit without changes.

On `Launch`, capture the run parameters into main-thread memory and **write the run lock** (the run's only sentinel):

- `ROADMAP` — resolved roadmap path (from `auto-roadmap-context.sh` `roadmap-resolution`).
- `ROADMAP_MTIME` — initial mtime (from the same section). Refreshed after every successful ship from the value the item-runner returns in its digest (Substep 3.4), to absorb the close-induced bump.
- `START_ITEM` — lowest item number to run.
- `ITEMS_SPEC` — raw spec when `--items` was passed, or the single resolved item number when `--next` was passed; empty string otherwise. When non-empty, it wins over `START_ITEM` as the authoritative include-set; the main-thread loop re-expands it and uses it as a strict filter.
- `STARTED` — ISO 8601 UTC timestamp.

`--next`, `--from`, and `--items` are mutually exclusive (rejected upstream in Step 1) so only one of `START_ITEM` / `ITEMS_SPEC` can be active (`--next` sets `ITEMS_SPEC`).

**Write the run lock.** The lock is keyed on the roadmap slug (the unit of a run), lives at `.task/roadmap/<slug>.lock`, and is the cross-worktree mutex + crash sentinel for the whole run. Write it now, before spawning any item-runner, via the shared `_lib/auto-locks.sh write` helper (atomic `set -o noclobber` + truncate-or-fail; it skips empty values so `items_filter` can be passed unconditionally):

```bash
ROADMAP_SLUG=$(basename "$ROADMAP" .md)
LOCK_PATH=".task/roadmap/$ROADMAP_SLUG.lock"
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/auto-locks.sh" write "$LOCK_PATH" \
  "roadmap=$ROADMAP" \
  "roadmap_mtime=$ROADMAP_MTIME" \
  "start_item=$START_ITEM" \
  "started=$STARTED" \
  "orchestrator=auto-roadmap" \
  "items_filter=$ITEMS_SPEC"
```

If the helper exits non-zero, a concurrent `/task:auto-roadmap` already owns this roadmap (Step 0 gate 3 should have caught it, but this is the atomic backstop) — **stop** with "a run lock already exists for `<slug>` — another orchestrator is active, or a prior run crashed. Remove `.task/roadmap/<slug>.lock` if you are sure no run is active." Keep `LOCK_PATH` in memory; the driver removes it on clean finish (Step 4) and on any handled failure (Substep 3.1 / 3.4).

**Important — what is NOT created here.** This step does **not** pre-derive the task-id, does **not** write `.task-current`, and does **not** create `.task/workspace/<task-id>/`. The task-id, workspace subfolder, and `.task-current` all land via each item-runner's design-runner (`/task:design --from` initial-open path of `design/phases/open.md` Mode 2 → Step 3). The driver reads neither `.task-current` nor the run lock for run state — it keeps everything in memory.

## Step 3: Per-item loop (main thread / driver)

Read the resolved run set from Step 1 into an in-memory list of `(N, title)` tuples. For each item `N` in roadmap order, do all substeps below. **Do not parallelize items** — each item's `/task:design --from` (inside its item-runner) does a fresh initial open that requires no active-task pointer; the previous item's ship must have fully closed and removed `.task-current` first, so running two item-runners concurrently corrupts state.

Track one latched value across the loop:

- `TASK_ID` — empty until the first OK digest; assigned from each OK digest's `task_id:` field (see Substep 3.4). Step 4 reads the last value.

### Substep 3.1 — Roadmap-mtime race check

`stat` the roadmap (BSD/macOS `stat -f '%m'` or GNU `stat -c '%Y'`); compare to the in-memory `ROADMAP_MTIME` (captured at Step 2 and refreshed by Substep 3.4 from the item-runner's returned mtime after each successful ship). On mismatch:

1. **Remove the run lock** (`rm -f "$LOCK_PATH"`).
2. Write a fail-stop record to the error log if a workspace subfolder exists (driver-level postmortem per Substep 3.4 below); otherwise rely on the inline message to the user.
3. Print to the user: "roadmap was edited mid-run (mtime <old> → <new>). Run stopped at item #<N>. Inspect .task-current (if present) and run `/task:ship` to clean up."
4. Exit. The inline message above is the user-facing report on failure; the post-run summary in Step 4 only fires after a clean finish.

### Substep 3.2 — Item status re-check

Re-read the item's checkbox state from the roadmap (a manual edit between iterations may have flipped it). If it is no longer `- [ ]` (i.e. it became `[x]` / `[~]` / `[>]` / `[-]`):

- Print to the user: "Item #<N> is now [<state>] — skipping (was already done or cancelled between iterations)."
- Do not spawn the item-runner; continue to the next item.

### Substep 3.3 — Spawn `auto-roadmap-item-runner`

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-item-runner"` (plugin prefix is mandatory — unprefixed names do not resolve and the runtime silently falls back to the catch-all `claude` agent). Do **not** pass a `model:` override — the item-runner inherits the parent-session model (it re-derives the implement model per item and overrides only its own build-runner spawn). Prompt body (verbatim — keep field labels and English; parser-stable):

```
item_number: <N>
item_title: <title>
roadmap_path: <resolved roadmap path>
working_dir: <abs cwd>

Run the FULL per-item cycle for this item: design (open + blueprint) → implement
→ audit (fan out the three lens auditors yourself) → ship (full close).

Return your report-card digest per your agent prompt's "Return format" — the last
non-empty line is a parser-stable status (OK or FAIL).
```

The item-runner handles everything the driver used to do inline (design/build spawns, model extraction, audit lens fanout, commit + full close) — proceed to Substep 3.4 to route on its reply. It needs no run-level flags: the driver owns the run lock (written at Step 2), and every item ships identically (full close).

### Substep 3.4 — Route on the item-runner's digest

Take the **last non-empty line** of the item-runner's reply as the status line. Match it against:

- `^OK: item #<N> shipped — [0-9a-f]{7,}$` → **success**:
  1. Print the item-runner's full report-card digest to the user (it is the per-item record; the details live in `.task/log/<id>/` and `git`).
  2. Grep the digest for `task_id:` and assign it to `TASK_ID` (Step 4 needs it — the full close has already removed `.task-current`).
  3. Grep the digest for `roadmap_mtime:` and assign it to the in-memory `ROADMAP_MTIME`. Every item full-closes and auto-marks, bumping the mtime; this refresh absorbs the bump so Substep 3.1 of the next iteration does not fail-stop on it. (On the final item there is no next race check — the refresh is harmless.)
  4. Continue to the next item in the resolved run set.

- `^FAIL at <stage>: .*\. (See .*|No workspace was created — nothing to clean up\.)$` → **failure** (the item-runner already wrote its own `--- FAIL ---` / `--- ORCHESTRATOR FAIL ---` postmortem, so the driver only relays): **remove the run lock** (`rm -f "$LOCK_PATH"` — release the mutex), then show the user the status line + the `See <path>` postmortem path (post-open) or the inline reason (pre-open), plus recovery (`/task:ship` to sweep the partial task; optional `--from #<N>` retry). Then **exit, skip Step 4**. Leave `.task/workspace/<id>/` + `.task-current` in place as the dirty-state signal — Step 0 gate 2 (`.task-current` absent) blocks re-entry until a bare `/task:ship` sweeps them.

- **Anything else** (malformed / absent status) → the item-runner misbehaved and may not have logged. **Remove the run lock** (`rm -f "$LOCK_PATH"`), then apply the two-branch postmortem resolution ([`_shared/runner-rules.md` § Postmortem path resolution](../../agents/_shared/runner-rules.md)) at the **driver level**: if `.task-current` exists (post-open), append a `--- ORCHESTRATOR FAIL <ISO> ---` block via `fail-log.sh orchestrator-fail` **directly** (do NOT use the `record_orchestrator_fail` wrapper — it hardcodes `.task-current present = yes`, wrong if the item-runner died pre-open), reason `item-runner returned malformed status: <raw last line>`; otherwise (pre-open) rely on the inline message. Then exit, skip Step 4.

A driver-level mtime race (Substep 3.1) also removes the run lock and uses the same driver-level `fail-log.sh orchestrator-fail` path when a workspace subfolder exists.

Full failure protocol: [docs/spec/auto-roadmap.md § Failure protocol](../../docs/spec/auto-roadmap.md#failure-protocol--fail-stop-no-rollback).

## Step 4: Post-run summary

The run finished cleanly (every run-set item shipped OK). **Remove the run lock** (`rm -f "$LOCK_PATH"`) — it is the driver's to clean up; the final item's full close already swept its workspace subfolder and `.task-current`. Then print to the user (in `config.md` Language):

```
/task:auto-roadmap finished.
  Items processed:  <count of OK iterations>
  Items skipped:    <count of "already [x]" Substep 3.2 skips>
  Roadmap:          <path>
  Archive:          .task/log/<task-id>/

The last item's full close removed its workspace subfolder and .task-current;
the run lock (.task/roadmap/<slug>.lock) has been removed.
You can run /task:auto-roadmap again immediately.
```

Substitute the literal task-id from the in-memory `TASK_ID` (assigned from each OK digest's `task_id:` field in Substep 3.4 — its last value survives the final item's full close, which has already removed `.task-current`).

## Forbidden

- Pre-deriving the task-id in Step 2 / pre-writing `.task-current` / pre-creating `.task/workspace/<task-id>/`. Each item-runner's design-runner does this via `_lib/derive-task-id.sh`; pre-creation hard-stops the initial-open path.
- Running the per-item loop with parallelism. Each item's `/task:design --from` is a fresh initial open that requires no active-task pointer — the previous item must have fully closed and removed `.task-current` first, so items run strictly serially, one item-runner at a time.
- Spawning anything other than `auto-roadmap-item-runner` per item, or running audit / commit / close **in the driver**. The driver never spawns design/build-runners or lens auditors and never runs `/task:build` / `/task:ship` — the item-runner owns the entire per-item cycle. The driver's only per-item action is one `Agent(task:auto-roadmap-item-runner)` spawn plus digest routing.
- Reading `.task-current` for run state, or reading the run lock at all after writing it. The driver keeps run state in memory; `.task-current` is written and read inside the item-runner. (Only the mtime race check and status re-check read the roadmap file itself.)
- Leaving the run lock (`.task/roadmap/<slug>.lock`) behind on a handled exit. The driver owns its whole lifecycle: written at Step 2, removed on clean finish (Step 4) **and** on every handled failure (Substep 3.1 / 3.4). Only an unhandled crash leaves it stuck — Step 0 gate 3 then reports it for a manual `rm`.
