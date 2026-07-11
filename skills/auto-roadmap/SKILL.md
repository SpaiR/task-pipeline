---
name: auto-roadmap
description: 'Autopilot an approved `.task/roadmap/<slug>.md` — runs design → build → ship for each item inside the current session; the last item closes the umbrella.'
disable-model-invocation: true
user-invocable: true
---

Drive an entire approved roadmap through the full pipeline from inside the **user's currently open Claude Code session**. The main thread (the "driver") owns run-level orchestration only — Step 0 gates, the wizard, run-state, the per-item mtime race check and status re-check — and spawns **one `auto-roadmap-item-runner` subagent per item**. That item-runner runs the entire per-item cycle in its own isolated context: it spawns `auto-roadmap-design-runner` (open + blueprint, parent-session model), then `auto-roadmap-build-runner` (implement, under this item's `plan.md → Implement-Model:`), then the three build-audit lens auditors, then runs commit + close inline — and returns a compact report-card digest. Keeping the per-item diff bundle + lens results inside the disposable item-runner context (not the driver's) is what lets a run scale past the old ~15/~25-item auto-compact ceiling. The **last** item of the resolved run set ships a bare `/task:ship` (default full close, slug auto-derived from `summary.md`), dropping the umbrella in that same close pass — no separate finalize commit.

**Input:** $ARGUMENTS — `[<roadmap-pathOrSlug>] [--next | --from #<N> | --items <spec>]`

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gates in `auto-roadmap-context.sh` remain authoritative (enforces all three Step 0 gates below).

**Runtime + orchestrator mechanics** (per-stage model split, context budget thresholds, the three Step 0 gates, `--items` grammar, sentinel invariants, failure protocol, cross-worktree safety, "inline" sub-skill execution semantics): [docs/spec/auto-roadmap.md](../../docs/spec/auto-roadmap.md). Reminders: this skill (the driver) itself does not navigate or modify project code and spawns no lens auditors — all per-item work, including audit + ship, happens inside the `auto-roadmap-item-runner` subagent it spawns. The item-runner executes `/task:build` / `/task:ship` **inline** (reads their SKILL.md + phase companion and follows the Steps directly, since both are `disable-model-invocation: true` and the `Skill` tool refuses them) — the driver never runs them.

**Recommended:** run the session in auto mode (auto-accept edits) so implement-stage `Edit` calls don't interrupt the run with prompts.

## Step 0: Hard-stop preconditions

Three gates enforced by `auto-roadmap-context.sh` (surface its stderr verbatim on non-zero exit): `config.md` exists, `.task-current` absent, no stale `workspace/*/auto.lock`. Full rationale: [docs/spec/auto-roadmap.md § Step 0](../../docs/spec/auto-roadmap.md).

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
  - Else pick the **first** entry from `items-unchecked` (lowest `<N>`).

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

On `Launch`, **no file is written yet** — the run's parameters live only in main-thread memory until the **first item-runner** writes `.task/workspace/<task-id-lc>/auto.lock` (Step 2 of the item-runner, after its design-runner lands `.task-current`). The driver passes these captured values into every item-runner spawn; the run-level ones (below) also become the `auto.lock` field set on the first item:

- `ROADMAP` — resolved roadmap path (from `auto-roadmap-context.sh` `roadmap-resolution`).
- `ROADMAP_MTIME` — initial mtime (from the same section). Refreshed after every successful `--next` ship from the value the item-runner returns in its digest (Substep 3.4), to absorb the close-induced bump.
- `START_ITEM` — lowest item number to run.
- `ITEMS_SPEC` — raw spec when `--items` was passed, or the single resolved item number when `--next` was passed; empty string otherwise. When non-empty, it wins over `START_ITEM` as the authoritative include-set; the main-thread loop re-expands it and uses it as a strict filter.
- `STARTED` — ISO 8601 UTC timestamp.

`--next`, `--from`, and `--items` are mutually exclusive (rejected upstream in Step 1) so only one of `START_ITEM` / `ITEMS_SPEC` can be active (`--next` sets `ITEMS_SPEC`).

**Important — what is NOT created here.** This step does **not** pre-derive the umbrella task-id, does **not** write `.task-current`, does **not** create `.task/workspace/<task-id>/`, and does **not** write any sentinel file. The umbrella's task-id, workspace subfolder, and `.task-current` all land via the first item-runner's design-runner (`/task:design --from` initial-open path of `design/phases/open.md` Mode 2 → Step 4); the per-umbrella sentinel `.task/workspace/<task-id>/auto.lock` is written by that same first item-runner (its Step 2) once `.task-current` lands. The driver reads neither `.task-current` nor `auto.lock` for run state — it keeps everything in memory.

## Step 3: Per-item loop (main thread / driver)

Read the resolved run set from Step 1 into an in-memory list of `(N, title)` tuples. For each item `N` in roadmap order, do all substeps below. **Do not parallelize items** — the next item's `/task:design --from` (inside its item-runner) enters continuation mode only after the previous item's ship cleared Description; running two item-runners concurrently corrupts `task.md`.

Track two latched flags across the loop:

- `FIRST_OK_SEEN` — starts `false`; the next item-runner spawn passes `is_first = NOT FIRST_OK_SEEN`. Set it `true` the moment an item-runner returns OK. Because any FAIL fail-stops the run, `is_first` is `true` on exactly the first item-runner that succeeds — the one that must write `auto.lock`. (An item skipped at Substep 3.2 never spawns an item-runner, so it cannot consume the first-OK slot.)
- `TASK_ID` — empty until the first OK digest; assigned from each OK digest's `task_id:` field (see Substep 3.4). Step 4 reads the last value.

### Substep 3.1 — Roadmap-mtime race check

`stat` the roadmap (BSD/macOS `stat -f '%m'` or GNU `stat -c '%Y'`); compare to the in-memory `ROADMAP_MTIME` (captured at Step 2 and refreshed by Substep 3.4 from the item-runner's returned mtime after each successful `--next` ship). On mismatch:

1. Write a fail-stop record to the error log if a workspace subfolder exists (driver-level postmortem per Substep 3.4 below); otherwise rely on the inline message to the user.
2. Print to the user: "roadmap was edited mid-run (mtime <old> → <new>). Run stopped at item #<N>. Inspect .task-current (if present) and run `/task:ship` to clean up."
3. Exit. The inline message above is the user-facing report on failure; the post-run summary in Step 4 only fires after a clean finish (last item shipped a bare full close in Substep 3.4).

### Substep 3.2 — Item status re-check

Re-read the item's checkbox state from the roadmap (a manual edit between iterations may have flipped it). If it is no longer `- [ ]` (i.e. it became `[x]` / `[~]` / `[>]` / `[-]`):

- Print to the user: "Item #<N> is now [<state>] — skipping (was already done or cancelled between iterations)."
- Do not spawn the item-runner; continue to the next item. (A skipped item never consumes the `is_first` slot and is never counted as the `is_last` item — see Substep 3.3.)

### Substep 3.3 — Compute flags + spawn `auto-roadmap-item-runner`

Determine the two per-spawn flags:

- `is_first` = `NOT FIRST_OK_SEEN` (see the loop preamble — `true` only on the item-runner that will produce the run's first OK; that one writes `auto.lock`).
- `is_last` = **look-ahead over checkbox state**: `true` when **no** run-set item after `N` is still `- [ ]`. Re-read the roadmap checkbox state (same source as Substep 3.2) for the remaining run-set items; if every one of them is already `[x]`/`[~]`/`[>]`/`[-]` (or there are none), this item is the last one that will actually run → `is_last = true`. **Do not** use "last entry in the run set" — a trailing item that is already `[x]` (legal under `--items`) is skipped at Substep 3.2, so the true last *worked* item must ship a bare full close, else the umbrella is never closed and `.task-current` + `workspace/<id>/` + `auto.lock` dangle into the next run's Step 0 gate.

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-item-runner"` (plugin prefix is mandatory — unprefixed names do not resolve and the runtime silently falls back to the catch-all `claude` agent). Do **not** pass a `model:` override — the item-runner inherits the parent-session model (it re-derives the implement model per item and overrides only its own build-runner spawn). Prompt body (verbatim — keep field labels and English; parser-stable):

```
item_number: <N>
item_title: <title>
roadmap_path: <resolved roadmap path>
working_dir: <abs cwd>
is_first: <true|false>
is_last: <true|false>
roadmap: <ROADMAP>
roadmap_mtime: <ROADMAP_MTIME>
start_item: <START_ITEM>
started: <STARTED>
items_filter: <ITEMS_SPEC>

Run the FULL per-item cycle for this item: design (open + blueprint) → implement
→ audit (fan out the three lens auditors yourself) → ship. When is_first is true,
write .task/workspace/<id>/auto.lock from the run-level fields above. Ship --next
unless is_last is true, in which case ship a bare /task:ship (default full close)
to close the umbrella.

Return your report-card digest per your agent prompt's "Return format" — the last
non-empty line is a parser-stable status (OK or FAIL).
```

The run-level fields (`roadmap` … `items_filter`) are consumed only when `is_first: true` — they become the `auto.lock` field set. `items_filter` may be empty; pass it anyway (the lock writer drops empty values). The item-runner handles everything the driver used to do inline (design/build spawns, model extraction, audit lens fanout, commit + close) — proceed to Substep 3.4 to route on its reply.

### Substep 3.4 — Route on the item-runner's digest

Take the **last non-empty line** of the item-runner's reply as the status line. Match it against:

- `^OK: item #<N> shipped \((--next|full)\) — [0-9a-f]{7,}$` → **success**:
  1. Set `FIRST_OK_SEEN = true` (arms `is_first = false` for every later item).
  2. Print the item-runner's full report-card digest to the user (it is the per-item record; the details live in `.task/log/<id>/` and `git`).
  3. Grep the digest for `task_id:` and assign it to `TASK_ID` (Step 4 needs it — on the last item the full close has already removed `.task-current`).
  4. If the ship mode was `--next` (not the last item): grep the digest for `roadmap_mtime:` and assign it to the in-memory `ROADMAP_MTIME`. This absorbs the close-induced mtime bump so Substep 3.1 of the next iteration does not fail-stop on it. On `full` (last item) there is no `roadmap_mtime:` line and no next iteration — skip.
  5. Continue to the next item in the resolved run set.

- `^FAIL at <stage>: .*\. (See .*|No workspace was created — nothing to clean up\.)$` → **failure** (the item-runner already wrote its own `--- FAIL ---` / `--- ORCHESTRATOR FAIL ---` postmortem, so the driver only relays): show the user the status line + the `See <path>` postmortem path (post-open) or the inline reason (pre-open), plus recovery (`/task:ship` to sweep the partial umbrella; optional `--from #<N>` retry). Then **exit, skip Step 4**. Leave `.task/workspace/<id>/` (and its `auto.lock`) in place as the abort signal — Step 0 gate 3 of the next run trips on it until a bare `/task:ship` sweeps it.

- **Anything else** (malformed / absent status) → the item-runner misbehaved and may not have logged. Apply the two-branch postmortem resolution ([`_shared/runner-rules.md` § Postmortem path resolution](../../agents/_shared/runner-rules.md)) at the **driver level**: if `.task-current` exists (post-open), append a `--- ORCHESTRATOR FAIL <ISO> ---` block via `fail-log.sh orchestrator-fail` **directly** (do NOT use the `record_orchestrator_fail` wrapper — it hardcodes `.task-current present = yes`, wrong if the item-runner died pre-open), reason `item-runner returned malformed status: <raw last line>`; otherwise (pre-open) rely on the inline message. Then exit, skip Step 4.

A driver-level mtime race (Substep 3.1) uses the same driver-level `fail-log.sh orchestrator-fail` path when a workspace subfolder exists.

Full failure protocol: [docs/spec/auto-roadmap.md § Failure protocol](../../docs/spec/auto-roadmap.md#failure-protocol--fail-stop-no-rollback).

## Step 4: Post-run summary

Print to the user (in `config.md` Language):

```
/task:auto-roadmap finished.
  Items processed:  <count of OK iterations>
  Items skipped:    <count of "already [x]" Substep 3.2 skips>
  Roadmap:          <path>
  Archive:          .task/log/<task-id>/

The workspace subfolder and .task-current have been removed (the
per-umbrella auto.lock sentinel was swept with the subfolder).
You can run /task:auto-roadmap again immediately.
```

Substitute the literal task-id from the in-memory `TASK_ID` (assigned from each OK digest's `task_id:` field in Substep 3.4 — its last value survives the final item's full close, which has already removed `.task-current`).

## Forbidden

- Pre-deriving the umbrella task-id in Step 2 / pre-writing `.task-current` / pre-creating `.task/workspace/<task-id>/`. The first item-runner's design-runner does this via `_lib/derive-task-id.sh`; pre-creation hard-stops the initial-open path.
- Running the per-item loop with parallelism. The `/task:design --from` continuation contract requires strict serial order — one item-runner at a time.
- Spawning anything other than `auto-roadmap-item-runner` per item, or running audit / commit / close **in the driver**. The driver never spawns design/build-runners or lens auditors and never runs `/task:build` / `/task:ship` — the item-runner owns the entire per-item cycle. The driver's only per-item action is one `Agent(task:auto-roadmap-item-runner)` spawn plus digest routing.
- Passing `is_last: true` before confirming no later run-set item is still `- [ ]` (Substep 3.3 look-ahead). A premature `is_last` ships a bare full close mid-run and drops the umbrella; a missed one (last worked item shipped `--next`) leaves the umbrella dangling for the next run's Step 0 gate.
- Reading `.task-current` or `auto.lock` for run state. The driver keeps run state in memory; `.task-current` / `auto.lock` are written and read inside the item-runner. (Only the mtime race check and status re-check read the roadmap file itself.)
- Removing `workspace/<task-id>/auto.lock` mid-run — the sentinel is the cross-worktree mutex and the abort signal for failure paths; only a bare `/task:ship` (which sweeps the whole subfolder) may take it down.
