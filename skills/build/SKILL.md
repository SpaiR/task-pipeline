---
name: build
description: 'Implement the plan, then audit the diff through three read-only lenses with a bounded auto-fix loop. Auto-resumes the phase; `--phase <implement|audit>` overrides; `--auto` runs both in one call.'
disable-model-invocation: true
user-invocable: true
---

Implement the plan, then audit code quality through 3 parallel read-only lenses with a bounded auto-fix loop. This orchestrator auto-detects which phase to run based on the current state of `.task/workspace/<task-id>/`; pass `--phase <name>` to force a specific phase.

**Input:** `$ARGUMENTS` — forwarded to the dispatched phase. Common forms:
- (empty) — auto-detect and run the next phase.
- `--phase <implement|audit>` — force a specific phase.
- `--auto` — opt-in one-shot mode: chain both phases (`implement → audit`) inside one invocation. Mutually exclusive with `--phase`. Stops on the first phase that surfaces an error or when a per-phase budget is exhausted (see Step 1b). Off by default — when absent, each call runs **one** phase and prints the chain hint.

**Phase companion files** live at `skills/build/phases/<phase>.md`. The orchestrator reads them and follows their instructions verbatim. For the audit phase, the orchestrator additionally wraps the companion's lens fanout in a bounded auto-fix loop (Step 4 below) — the loop logic stays in this SKILL.md because it controls the iteration count and the touches-gate; the companion file describes only what one pass of lens fanout does.

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-b--mcp-first-tooling) — both phases (implement, audit) are Tier B (MCP-first). Bash gates live in `audit-context.sh` and `validate.sh` (inline at Step 0).

## Step 0: Artifact gates

Run sequentially:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" plan
```

If either exits non-zero, stop and report the validator output — the artifacts are malformed and execution would silently misinterpret them. If `plan.md` is missing entirely, redirect to `/task:design` and stop.

## Step 1: Argument parsing

Parse `$ARGUMENTS` once:
- `--auto` flag present → `AUTO_MODE=1` (else `0`).
- `--phase <name>` present → `FORCE_PHASE=<name>` (else empty).
- If `AUTO_MODE=1` AND `FORCE_PHASE` is non-empty → stop with: `--auto and --phase are mutually exclusive`. Do not dispatch.
- Track `IMPLEMENT_DISPATCHED=0` for the duration of this invocation (in-memory counter used by Step 1b implement budget).

## Step 1a: Phase detection

If `FORCE_PHASE` is set → `PHASE=$FORCE_PHASE`, skip auto-detect.
Otherwise → run `PHASE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/phase-detect.sh" build)`.

Possible auto-detect outputs:
- `implement` — no `summary.md` OR no diff vs HEAD (work hasn't started yet).
- `audit` — `summary.md` exists, `audit.md` missing OR any `## Iteration N` block contains `pending fix` (parser greps the whole file per `_lib/phase-detect.sh:115`; the audit phase replaces every `pending fix` with `Fixed` per iteration, so practically only the last block ever holds one).
- `done` — all artifacts complete. Stop with: "Build complete. Run `/task:ship` to commit and close the umbrella, or `/task:ship --next` to transition to the next subtask."

## Step 1b: `--auto` per-phase budget gate (only when `AUTO_MODE=1`)

This gate protects the `--auto` loop from getting stuck re-entering the same phase indefinitely. It is symmetric with the audit phase's own bounded loop (Step 4) — both cap at 2 iterations.

Resolve `WS_DIR` once via the standard preamble path — shell out to a one-liner that sources `skills/_lib/preamble.sh` (which delegates to `_lib/resolve-ws.sh`, honoring the `$TASK_ID_OVERRIDE` > positional > `.task-current` priority). Do NOT construct `.task/workspace/<id>/` by hand from the pointer — the universal WS_DIR invariant forbids any path-construction shortcut.

For the dispatched `PHASE`, compute the **iteration count already on disk** and compare to the budget:

| Phase | How to count | Budget | Action when exceeded |
|-------|-------------|--------|----------------------|
| `implement` | in-memory `IMPLEMENT_DISPATCHED` (set when implement runs in Step 2 below) | 1 dispatch per `--auto` invocation | stop with `implement re-dispatched (rollback?)` |
| `audit` | max `N` across `## Iteration N` headers in `audit.md` (0 if file missing) — symmetric with `audit-context.sh`'s `max(## Iteration N) + 1` next-iteration calc, so the two consumers never drift when the producer ever emits non-contiguous numbering | 2 iterations total | stop with `audit iteration budget exhausted (2 iterations, pending fixes remain)` |

Counts are read from on-disk artifacts (not in-memory) so the budget survives a session restart: if a user aborts `--auto` and re-runs `/task:build --auto`, the limit still applies.

Stop format (English, parser-stable; the user-facing prose around it follows `config.md → Language`):

```
--auto stopped: <reason>. See $WS_DIR/<artifact>.
Run /task:build --auto again to retry after manual investigation, or
/task:design --refine to revisit scope.
```

If `AUTO_MODE=0` — skip this step entirely. Manual mode never enforces a budget; the user is expected to inspect artifacts between invocations.

## Step 2: Phase dispatch

For phase `implement`:
- Read `skills/build/phases/implement.md` and follow its instructions verbatim.
- Set `IMPLEMENT_DISPATCHED=1` after the phase completes (used by Step 1b on the next loop iteration in `--auto` mode).

For phase `audit`:
- Read `skills/build/phases/audit.md` and follow it, BUT wrap the lens fanout in the bounded auto-fix loop (Step 4 below). The companion file describes one pass; the orchestrator iterates.

If `${PHASE}` is not one of `implement`, `audit` — stop with an error.

## Step 3: Skip if not audit

If `PHASE` is `implement` — the dispatched phase completes itself (it includes its own summary update). Jump to Step 5.

If `PHASE` is `audit` — continue to Step 4.

## Step 4: Bounded auto-fix loop (audit phase only)

This loop replaces a single audit pass with up to 2 iterations of `lens fanout → apply fixes (scope-gated) → verify`. After 2 iterations any remaining high-severity findings are surfaced to the user without further auto-fixing.

```
passes_done = 0
while passes_done < 2:
    # Follow skills/build/phases/audit.md Steps 1-3 for this iteration:
    #   - Step 1: load context via audit-context.sh (yields config.md, full
    #     task.md, full plan.md, CLAUDE.md, iteration number, diff size, diff
    #     bundle, and neighborhood map; the orchestrator extracts `## Decisions`
    #     from task.md/plan.md and per-step `Touches:` from plan.md when
    #     composing the per-lens prompt template in audit.md Step 2b). The
    #     `iteration` section is the canonical N = max(## Iteration N in
    #     audit.md) + 1; use this value as the iteration header — do NOT use
    #     the local pass counter, which would collide with residual
    #     `## Iteration` blocks from a prior truncated run.
    #   - Step 2: if trivial: combined inline audit; else spawn 3 lens-agents
    #     (subagent_type: task:audit-reuse-auditor, task:audit-simplicity-auditor,
    #     task:audit-clarity-auditor — plugin prefix mandatory)
    #     in parallel via Agent(...) with context: fork.
    #   - Step 3: merge findings, dedupe, append `## Iteration <N>` (the value
    #     from audit-context.sh, NOT passes_done+1) to audit.md.

    # Apply fixes in main thread, severity order high → med → low. All
    # severities are handled identically — every fix is scope-gated.
    for each finding in current_iteration (high → med → low):
        apply fix via Edit (per config.md MCP tools, fallback Edit).
        run: bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/touches-gate.sh" "$WS_DIR/plan.md"
        if touches-gate exits non-zero:
            revert the fix (git restore the affected file).
            mark finding "Skipped: out-of-scope (touches gate — files outside plan.md Touches)".
            continue
        else:
            mark finding "Fixed".

    # After all fixes for this iteration: do ONE edit to audit.md updating each
    # affected finding's `Status:` line in the Details block (single source of
    # truth — there is no Status column in the Findings table) and the Result
    # tally in the current `## Iteration <N>` block ONLY — earlier iterations
    # are immutable per audit.md Forbidden list and the append-only invariant.
    # (Compatible with the append-only invariant: append-only applies at the
    # iteration-BLOCK level — once an iteration block is complete, it stays
    # frozen. Status flips within the CURRENT iteration block while it is
    # still being assembled are part of normal iteration composition, not a
    # rewrite of a prior iteration.)

    # Verify: run build/tests per plan.md → Verification.
    if verify fails:
        record failure as a new high-severity finding in the SAME iteration block.
        revert the fix that broke verify.
        report and stop.

    # Convergence check.
    if no "pending fix" remains AND no new high-severity findings:
        break

    passes_done += 1

if pending high-severity findings remain after 2 passes:
    surface to user with the list and stop.
    Output: "Audit hit iteration limit (2) with N high-severity findings remaining.
             Review audit.md and either fix manually or run /task:design --refine
             to revisit scope, then /task:build to retry."
```

The companion `audit.md` defines the prompt structure and lens definitions; the orchestrator owns the iteration count and the touches-gate enforcement.

## Step 5: Chain hint / `--auto` loop-back

After the dispatched phase completes successfully (no verify failure, no iteration limit surfaced):

- **Manual mode (`AUTO_MODE=0`)** — print the chain hint and stop:
  - After `implement` → `/task:build` again (auto-detects audit).
  - After `audit` (loop completed cleanly) → `/task:ship` (commit + close).
  - After `audit` (loop hit iteration limit) → user action required, no chain hint.

- **`--auto` mode (`AUTO_MODE=1`)** — instead of printing the chain hint, **loop back to Step 1a** (re-run phase-detect with the updated on-disk state). The loop terminates on:
  - Step 1a returning `done` → print `Build complete. Run /task:ship...` and stop.
  - Step 1b's per-phase budget gate firing → print `--auto stopped: ...` and stop.
  - Any dispatched phase surfacing a stop (verify failure, audit iteration limit, implement quick-fix exhausted) → propagate the phase's stop message, prefix with `--auto stopped:`, do not loop back.

  The `--auto` loop has no global iteration bound beyond the per-phase budgets in Step 1b; the worst-case execution is `implement(×1) → audit(×2)` = 3 phase dispatches before forced termination.

## Forbidden

- Inline the phase instructions in this orchestrator — always dispatch via the companion file.
- Modify any file other than what the dispatched phase's instructions specify (the audit auto-fix loop is bound to `plan.md → Touches`).
- Skip the touches-gate on any auto-fix — out-of-scope fixes must be marked Skipped, not applied.
- Run more than 2 audit iterations — the bound is the safety mechanism; surface to user instead.
- Bypass the Step 1b per-phase budget gate in `--auto` mode — the budget is the only thing keeping the loop from re-entering audit indefinitely.
- Combine `--auto` with `--phase` — they are mutually exclusive (Step 1 rejects).

## Output

After the dispatched phase completes:
- Print whatever the companion phase's "Output" section specifies (iteration counts, findings, build/test results).
- For audit: report iteration count, fixes applied, fixes skipped (touches-gate violations), and final verification status.
- In manual mode — add the chain hint (Step 5).
- In `--auto` mode — print one summary line per completed phase as the loop progresses (`[--auto] implement done`, `[--auto] audit iteration 1 done`, etc.); after the final phase or on stop, print the terminating message described in Step 5.
