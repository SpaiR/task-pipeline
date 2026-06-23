---
name: auto-roadmap
description: '[0·drive] Roadmap autopilot — drives an approved `.task/roadmap/<slug>.md` through design → build → ship per-item inside the current session; the last item closes the umbrella via `/task:ship --full`.'
disable-model-invocation: true
user-invocable: true
---

Drive an entire approved roadmap through the full pipeline from inside the **user's currently open Claude Code session**. Per-item work splits across three pieces: (a) `auto-roadmap-design-runner` subagent — open + blueprint, runs under the parent-session model (typically opus); (b) `auto-roadmap-build-runner` subagent — implement only, runs under the model named in this item's `plan.md → Implement-Model:` (`opus|sonnet|haiku`); (c) main thread, which then runs `/task:build` (audit phase, fanout to three lens auditors works natively) and `/task:ship` (commit + close). The **last** item of the resolved run set ships with `/task:ship --full` directly (slug auto-derived from `summary.md`); the umbrella is dropped in that same close pass — no separate `chore-finalize` commit. (Slug `chore-finalize` remains the documented slug for **manual** recovery of an aborted run via `/task:ship --full chore-finalize`.)

**Input:** $ARGUMENTS — `[<roadmap-pathOrSlug>] [--next | --from #<N> | --items <spec>]`

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gates in `auto-roadmap-context.sh` remain authoritative (enforces all three Step 0 gates below).

**Runtime + orchestrator mechanics** (per-stage model split, context budget thresholds, the three Step 0 gates, `--items` grammar, sentinel invariants, failure protocol, cross-worktree safety, "inline" sub-skill execution semantics): [docs/spec/auto-roadmap.md](../../docs/spec/auto-roadmap.md). Reminders: this skill itself does not navigate or modify project code — all edits land via the two runner subagents or via `/task:build`'s audit auto-fix step; `/task:build` and `/task:ship` are `disable-model-invocation: true` and must be executed inline (read their SKILL.md + phase companion, execute Steps directly) rather than dispatched via the `Skill` tool.

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
Audit:    on  (always — auto-roadmap runs it in main thread for native lens fanout)
Filter:   <spec>                    # only shown if --items was passed; otherwise "Start at: #<N>"
Items to run (<count>):
  #<N>    — <title>
  #<N+1>  — <title>
  ...
Mode:     interactive (session must stay open for the run's duration)
```

`AskUserQuestion` shape: single-select, question `"Launch /task:auto-roadmap for these <count> items?"`, options `Launch` / `Cancel`. On `Cancel` — exit without changes.

On `Launch`, **no file is written yet** — the run's parameters live only in main-thread memory until Substep 3.4 lands them in `.task/workspace/<task-id-lc>/auto.lock` (after the first subagent's `/task:design --from` lands `.task-current` and the workspace subfolder). Capture the following in main-thread variables; they are read on every iteration:

- `ROADMAP` — resolved roadmap path (from `auto-roadmap-context.sh` `roadmap-resolution`).
- `ROADMAP_MTIME` — initial mtime (from the same section). Updated after every successful `/task:ship` in Substep 3.9 to absorb the close-induced bump.
- `START_ITEM` — lowest item number to run.
- `ITEMS_SPEC` — raw spec when `--items` was passed, or the single resolved item number when `--next` was passed; empty string otherwise. When non-empty, it wins over `START_ITEM` as the authoritative include-set; the main-thread loop re-expands it and uses it as a strict filter.
- `STARTED` — ISO 8601 UTC timestamp.

`--next`, `--from`, and `--items` are mutually exclusive (rejected upstream in Step 1) so only one of `START_ITEM` / `ITEMS_SPEC` can be active (`--next` sets `ITEMS_SPEC`).

**Important — what is NOT created here.** This step does **not** pre-derive the umbrella task-id, does **not** write `.task-current`, does **not** create `.task/workspace/<task-id>/`, and does **not** write any sentinel file. The umbrella's task-id, workspace subfolder, and `.task-current` all land via the first subagent's `/task:design --from` execution (initial-open path of `design/phases/open.md` Mode 2 → Step 4); the per-umbrella sentinel `.task/workspace/<task-id>/auto.lock` lands in Substep 3.4 once that succeeds.

## Step 3: Per-item loop (main thread)

Read the resolved run set from Step 1 into an in-memory list of `(N, title)` tuples. For each item `N` in roadmap order, do all substeps below. **Do not parallelize items** — the next item's `/task:design --from` enters continuation mode only after the previous item's `/task:ship` cleared Description; running two items concurrently corrupts `task.md`.

### Substep 3.1 — Roadmap-mtime race check

`stat` the roadmap (BSD/macOS `stat -f '%m'` or GNU `stat -c '%Y'`); compare to the in-memory `ROADMAP_MTIME` (captured at Step 2 and refreshed by Substep 3.9 after each successful ship). On mismatch:

1. Write a fail-stop record to the error log if a workspace subfolder exists (path resolution per Substep 3.7 below); otherwise rely on the inline message to the user.
2. Print to the user: "roadmap was edited mid-run (mtime <old> → <new>). Run stopped at item #<N>. Inspect .task-current (if present) and run `/task:ship --full` to clean up."
3. Exit. The inline message above is the user-facing report on failure; the post-run summary in Step 4 only fires after a clean finish via Substep 3.9 Branch B.

### Substep 3.2 — Item status re-check

Re-read the item's checkbox state from the roadmap (a manual edit between iterations may have flipped it). If it is no longer `- [ ]` (i.e. it became `[x]` / `[~]` / `[>]` / `[-]`):

- Print to the user: "Item #<N> is now [<state>] — skipping (was already done or cancelled between iterations)."
- Do not spawn the subagent; continue to the next item.

### Substep 3.3 — Spawn `auto-roadmap-design-runner`

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-design-runner"` (plugin prefix is mandatory — unprefixed names do not resolve and the runtime silently falls back to the catch-all `claude` agent). Do **not** pass a `model:` override here — the design-runner inherits the parent-session model (typically the user's `/model` choice — usually opus). Prompt body (verbatim — keep field labels and English; parser-stable):

```
roadmap_path: <resolved roadmap path>
item_number: <N>
working_dir: <abs cwd>

Run the design half of the per-item cycle through Step b (Open → Blueprint).
Do NOT run implement / audit / commit / close — the orchestrator runs implement
via auto-roadmap-build-runner after you return, then audit + ship inline.

Before any code navigation in blueprint, read `.task/config/config.md` and use
the MCP tools listed under "Code Navigation" / "Code Editing" in the priority
order given there. Fall back to built-in Read / Grep / Glob only when config.md
explicitly lists them as fallback, or when the listed MCP server is unreachable.

Return your one-line status (OK or FAIL) per your agent prompt's "Return format".
```

Wait for the subagent's reply. Take the **last non-empty line** of its message as the status line. Match it against:

- `^OK: item #<N> ".*" — plan\.md ready, awaiting implement$` → success path. On the **first** OK of the run, fall through to Substep 3.4 (auto.lock) before continuing; on subsequent iterations skip 3.4 and proceed directly to Substep 3.5.
- `^FAIL at <stage>: .*\. (See .*|No workspace was created — nothing to clean up\.)$` → failure path (Substep 3.7). The `See <path>` tail is the post-open shape (postmortem on disk); the `No workspace was created` tail is the pre-open shape (no postmortem written — the inline reason is the record).
- Anything else → treat as malformed status; failure path with reason `design-runner returned malformed status: <raw last line>`.

### Substep 3.4 — First-item-only: read `.task-current`, write `auto.lock`

Only on the **first** successful design-runner OK of the run (i.e. when this iteration's OK is the first OK so far). Runs **between** Substep 3.3's OK and Substep 3.5 — the `.task-current` and `workspace/<task-id>/` that design-runner's `/task:design --from` just landed are needed both for the lock path and for the upcoming `plan.md` read.

1. Read `.task-current` (the subagent's `/task:design --from` initial path wrote it). Expect a single line: the lowercase umbrella task-id.
2. Atomically write `.task/workspace/<task-id>/auto.lock` so any concurrent `/task:auto-roadmap` (e.g. another worktree sharing `.task/`) refuses to launch on the same umbrella. Mirror every captured field from Step 2's in-memory state, plus `orchestrator=auto-roadmap`. The shared `_lib/auto-locks.sh write` helper is the canonical writer — it uses `set -o noclobber` + truncate-or-fail (`: > "$path" || exit 1`) so a real sentinel collision exits non-zero and `|| { … exit 1; }` fires. It also skips empty values automatically, so `items_filter=$ITEMS_SPEC` can be passed unconditionally (empty `ITEMS_SPEC` → the line is dropped from the lock file, disabling include-set semantics downstream):

   ```bash
   TASK_ID=$(head -n 1 .task-current | tr -d '[:space:]')
   LOCK_PATH=".task/workspace/$TASK_ID/auto.lock"
   bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/auto-locks.sh" write "$LOCK_PATH" \
     "roadmap=$ROADMAP" \
     "roadmap_mtime=$ROADMAP_MTIME" \
     "start_item=$START_ITEM" \
     "started=$STARTED" \
     "orchestrator=auto-roadmap" \
     "items_filter=$ITEMS_SPEC" \
     || { echo "auto.lock collision in workspace/$TASK_ID — another orchestrator is active. Aborting auto-roadmap run."; exit 1; }
   ```

   Do **not** hand-roll `(set -o noclobber; cat > FILE <<EOF; ...; printf >> FILE) 2>/dev/null || abort` inline — without an unconditional truncate-or-fail primitive immediately after `set -o noclobber`, a real collision falls through to the `if`/`printf` lines (append is not blocked by noclobber) and the `|| abort` branch silently never fires.

On subsequent iterations skip this substep entirely — the sentinel is already in place. Main thread keeps using its in-memory state for the loop; the on-disk sentinel is a launch-time snapshot for diagnostics + cross-worktree mutex, not a re-read source.

### Substep 3.5 — Read `Implement-Model:` from `plan.md`

Between the two subagent spawns, main thread reads `.task/workspace/<task-id>/plan.md` and extracts the model name. `.task-current` is guaranteed to exist here — design-runner's `/task:design --from` landed it either on the first iteration (initial-open path) or it persisted from a prior iteration (continuation mode):

```bash
TASK_ID=$(head -n 1 .task-current | tr -d '[:space:]')
IMPLEMENT_MODEL=$(bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" \
                    extract_implement_model ".task/workspace/$TASK_ID/plan.md")
```

`extract_implement_model` uses the same regex `validate.sh` validates with, and exits 1 with a stderr message on miss / malformed / multiple matches. Substep 3.5 is the **first** place `Implement-Model:` is parsed in the auto-roadmap flow — `validate.sh plan` only runs later inside build-runner's implement phase Step 0, so a miss here means design-runner emitted `plan.md` without the stamp (bug in blueprint Step 3, or design-runner skipped the rubric). Surface rather than silently default:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" record_orchestrator_fail \
  ".task/workspace/$TASK_ID/auto-error.log" "#$N" \
  "MODEL_EXTRACT: design-runner emitted plan.md without Implement-Model: stamp — bug in blueprint Step 3 or design-runner skipped the rubric"
```

Print to the user: "item #<N>: plan.md Implement-Model header missing/malformed — design-runner skipped the blueprint rubric. See `.task/workspace/<id>/auto-error.log`. Recovery same as Substep 3.7." Exit. The inline message + on-disk postmortem are the user-facing record; the post-run summary in Step 4 does not fire on failure.

When the regex matched, capture `IMPLEMENT_MODEL` for Substep 3.6's `Agent.model` argument.

### Substep 3.6 — Spawn `auto-roadmap-build-runner`

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-build-runner"` and **`model: <IMPLEMENT_MODEL>`** (the value extracted in Substep 3.5). The per-spawn `model:` override takes precedence over the agent's frontmatter and is the mechanism by which implement runs under a different model than design / audit / ship. Prompt body (verbatim — keep field labels and English; parser-stable):

```
roadmap_path: <resolved roadmap path>
item_number: <N>
working_dir: <abs cwd>
implement_model: <IMPLEMENT_MODEL>

Run the implement phase for this item (Step c only).
Do NOT run audit / commit / close — the orchestrator runs those after you return.

Before any code navigation or editing, read `.task/config/config.md` and use
the MCP tools listed under "Code Navigation" / "Code Editing" in the priority
order given there. Fall back to built-in Read / Edit / Grep / Glob only when
config.md explicitly lists them as fallback, or when the listed MCP server is
unreachable.

Return your one-line status (OK or FAIL) per your agent prompt's "Return format".
```

Wait for the subagent's reply. Take the **last non-empty line** of its message as the status line. Match it against:

- `^OK: item #<N> ".*" — diff uncommitted, ready for audit$` → success path (continue to Substep 3.8 audit; auto.lock already written by Substep 3.4 earlier in this iteration on the first item).
- `^FAIL at implement: .*\. See .*\.$` → failure path (Substep 3.7). Only the **post-open** shape is valid here — by the time build-runner is spawned, the workspace subfolder exists.
- Anything else → treat as malformed status; failure path with reason `build-runner returned malformed status: <raw last line>`.

### Substep 3.7 — Failure handling (on FAIL or malformed status)

The recovery flow keys off the subagent's status shape, not its identity. Resolve postmortem path per [`_shared/runner-rules.md` § Postmortem path resolution](../../agents/_shared/runner-rules.md) (same logic for both runners):

| Status shape                                           | On-disk postmortem | Orchestrator action                                                                                                                                                                                                                              |
|--------------------------------------------------------|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `… See <path>.` (post-open)                            | yes — `<path>`     | Append `--- ORCHESTRATOR FAIL <ISO> ---` block (fields: `item`, `subagent status line` verbatim, `resolved error-log path`, `.task-current present`). Show user: status line + path + recovery (`/task:ship --full chore-finalize`, optional `--from #<N>` retry). |
| `… No workspace was created — nothing to clean up.` (pre-open) | no                 | Show subagent's inline FAIL + one-line hint: nothing to clean up; rerun after fixing root cause.                                                                                                                                                  |
| malformed last line                                    | maybe              | Treat as post-open if `.task-current` exists, else pre-open; reason = `malformed status: <raw last line>`.                                                                                                                                       |

Then **exit. Skip Step 4** — the inline message + on-disk postmortem are the user-facing record. Leave `.task/workspace/<id>/` (and its `auto.lock` sentinel) in place as the abort signal when one exists; Step 0 gate 3 of the next run trips on it until `/task:ship --full chore-finalize` sweeps it. Full failure protocol: [docs/spec/auto-roadmap.md § Failure protocol](../../docs/spec/auto-roadmap.md#failure-protocol--fail-stop-no-rollback).

### Substep 3.8 — Audit (main thread, only on subagent OK)

Run `/task:build`'s audit phase inline in main thread — read `${CLAUDE_PLUGIN_ROOT}/skills/build/SKILL.md` and execute its Steps directly with `PHASE=audit` (the skill is `disable-model-invocation: true`; the `Skill` tool cannot dispatch it). The build orchestrator dispatches to `${CLAUDE_PLUGIN_ROOT}/skills/build/phases/audit.md`, which runs the context script — invoke it by its **absolute path at the build skill root**, `bash "${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh"` (NOT `phases/audit-context.sh`; reading the phase file inline gives no `${CLAUDE_SKILL_DIR}` substitution, so don't guess the path from where `audit.md` sits). It gates `task.md` + `plan.md` (both written by the subagent), then the phase performs lens fanout (`Agent(audit-{clarity,reuse,simplicity}-auditor)` in parallel — works natively because you are the main thread). The build orchestrator wraps this in its bounded auto-fix loop (≤2 iterations, scope-gated by `_lib/touches-gate.sh` against `plan.md → Touches`).

Branch on result:

- **No findings** or all findings `Fixed` or `Skipped` after ≤2 iterations → continue to Substep 3.9.
- **Iteration limit hit with pending high-severity finding** (build's auto-fix loop surfaced after 2 iterations) → fail-stop:
  1. Append `--- ORCHESTRATOR FAIL <ISO> ---` block to the error log via `record_orchestrator_fail`: the reason text rides in the `subagent_status` slot — no subagent failed here (the main-thread audit loop did), but reusing that field keeps the on-disk shape identical to Substep 3.7 so postmortem readers parse one format. Concretely:

     ```bash
     TASK_ID=$(head -n 1 .task-current | tr -d '[:space:]')
     bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" record_orchestrator_fail \
       ".task/workspace/$TASK_ID/auto-error.log" "#$N" \
       "AUDIT_LIMIT: build audit hit iteration limit with high-severity unfixed finding — see audit.md"
     ```
  2. Print: "Audit blocked item #<N> — high-severity finding remains unfixed after 2 iterations. See `.task/workspace/<id>/audit.md`. Recovery same as Substep 3.7."
  3. Exit. Skip Step 4 (post-run summary) — the audit-blocked message is the user-facing record.

Medium and low findings do not block. The auto-fix loop's applied edits land in the same uncommitted diff that `/task:ship` is about to stage.

### Substep 3.9 — Ship (main thread, mode depends on IS_LAST)

Determine `IS_LAST`: `true` when item `N` is the **last** entry in the resolved run set (no items remain to process after this one); `false` otherwise. Track in main-thread memory.

Run `/task:ship`'s logic inline in main thread (read `${CLAUDE_PLUGIN_ROOT}/skills/ship/SKILL.md` and execute its Steps directly — same pattern as Substep 3.8). The flag passed to ship is the only difference between the two branches:

**Branch A — `IS_LAST == false` (per-item transition case).** Pass `--next` to ship — bare ship (and `--full`) now fully closes the umbrella, which would break continuation. The skill performs commit + close in one pass:

1. **Commit step** (ship/SKILL.md Steps 1-3): reads `.task/workspace/<id>/summary.md` (written by the subagent's implement step), composes a commit message per `config.md` → "Commit Format", stages only project code (never `.task/*` or `.task-current`), and creates the commit.
2. **Close step** (ship/SKILL.md Steps 4-5): auto-derives the slug from `summary.md`, calls `close.sh` (relocated to `skills/ship/close.sh`), which:
   - Auto-marks the source roadmap (`### - [ ] <N>.` → `### - [x] <N>.`) — load-bearing for the next iteration's roadmap-mtime check; note that mtime will change as a result of this auto-mark, so **refresh the in-memory `ROADMAP_MTIME` variable after each successful ship** before Substep 3.1 fires for the next item:

      ```bash
      ROADMAP_MTIME=$(bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" \
                        refresh_roadmap_mtime "$ROADMAP")
      ```

     Without this refresh, Substep 3.1 of the next iteration would fail-stop immediately on the legitimate close-induced mtime bump. The on-disk `auto.lock` (a launch-time snapshot written once in Substep 3.4) is intentionally not updated.

   - Archives `plan/audit/summary.md` to `.task/log/<id>/<K>-<slug>/`.
   - Clears the body of `## Description` in `task.md`; leaves header, `Roadmap:`, `Source item:` (will be rewritten by next item's open), `.task-current`, any `## Decisions`.

Continue to the next item in the resolved run set.

**Branch B — `IS_LAST == true` (final iteration).** Pass `--full` to ship. Pre-flight sanity: confirm `.task/workspace/<id>/task.md` exists and Description body is **non-empty** (the just-completed implement + audit step wrote it). An empty body here means the cycle produced no Description content — fail-stop per Substep 3.7 with reason `task.md Description body empty at last-item --full ship — implement phase produced no Description content`. Do **not** pass an explicit slug — the last-item commit's slug should describe the item itself (derived from `summary.md`), not the legacy `chore-finalize` chore. Ship then performs:

1. **Commit step**: same as Branch A — `summary.md`-driven commit with project-code-only staging.
2. **Close step** (`close.sh --full`): auto-derives the slug from `summary.md`, then:
   - Auto-marks the source roadmap (same condition as Branch A — Description non-empty gates the auto-mark in `close.sh:Step 1.5` regardless of `FULL`).
   - Archives `plan/audit/summary.md` **and** `task.md` to `.task/log/<id>/<K>-<slug>/`.
   - Removes the entire `.task/workspace/<id>/` subfolder (taking the per-umbrella `auto.lock` written in Substep 3.4 with it).
   - Removes `.task-current`.

   No `ROADMAP_MTIME` refresh — there is no next iteration. Proceed directly to Step 4 (post-run summary) and skip back to Substep 3.1 is impossible because `.task-current` is gone.

On any failure (commit refused, no diff, summary.md missing, close error) → fail-stop per Substep 3.7 with reason `ship failed for item #<N>: <message>` (Branch A) or `ship --full failed for last item #<N>: <message>` (Branch B).

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

Substitute the literal task-id from the (now-removed) `.task-current` (capture it earlier in Substep 3.4 when you wrote `auto.lock`).

## Forbidden

- Pre-deriving the umbrella task-id in Step 2 / pre-writing `.task-current` / pre-creating `.task/workspace/<task-id>/`. The first subagent's `/task:design --from` does this via `_lib/derive-task-id.sh`; pre-creation hard-stops the initial-open path.
- Running the per-item loop with parallelism. The `/task:design --from` continuation contract requires strict serial order.
- Shipping items **other than the last** without `--next`. Bare `/task:ship` (and its `--full` alias) fully closes the umbrella — on any non-last item that drops it mid-run and breaks continuation. Non-last items (Substep 3.9 Branch A) **must** pass `--next`; full close belongs to Branch B (last-item ship) only. The slug `chore-finalize` is reserved for **manual** recovery of an aborted run via `/task:ship --full chore-finalize`.
- Removing `workspace/<task-id>/auto.lock` mid-run — the sentinel is the cross-worktree mutex and the abort signal for failure paths; only `/task:ship --full chore-finalize` (which sweeps the whole subfolder) may take it down.
- Attempting to dispatch `/task:build` / `/task:ship` via the `Skill` tool. They are `disable-model-invocation: true` by invariant; the tool will refuse. Execute their SKILL.md Steps inline in main thread instead (see Substeps 3.6 / 3.7).
