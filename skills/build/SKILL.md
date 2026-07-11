---
name: build
description: 'Implement the plan, then audit the diff through three read-only lenses with a bounded auto-fix loop. Auto-resumes the phase and asks before advancing from implement to audit.'
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
- `done` — all artifacts complete. Print "Build complete." (The `done` phase-detect token itself is parser-facing — do not alter it; only the human-facing message changes.) Then branch on the run: an **interactive run** is clean here, so proceed into the **Clean-build ship proposal** (shared note before Step 5) instead of the passive footer; a **non-interactive run** (the item-runner executing inline) stops here and lets the item-runner drive ship. On a declined proposal (interactive), fall back to the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)) — flag-free: `→ Next: \`/task:ship\``. (Ship then infers close-vs-transition and proposes it; the user never has to name the mode.)

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
             Review audit.md and either fix manually or revisit scope with
             /task:design --refine.
             → Next: /task:build   (retry the audit after addressing findings)"
```

The companion `audit.md` defines the prompt structure and lens definitions; the orchestrator owns the iteration count and the touches-gate enforcement.

## Clean-build ship proposal (interactive only)

A build is **clean** when phase-detect returns `done`, OR the audit auto-fix loop converged with no `pending fix` remaining and no unresolved high-severity finding. This is the *same* signal the existing clean endpoints already reach — it adds no new detector.

On a clean build **in an interactive run**, the orchestrator does not stop at a passive `→ Next: \`/task:ship\`` footer — it **proposes the ship** by flowing directly into the ship flow: compose the commit from artifacts → resolve the close mode → present ship's single **accept / decline / edit** confirmation (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)). That single ship confirmation **is** the confirm-gate for the auto-ship — do NOT stack a separate "ship now?" prompt in front of it (§2's single explicit confirmation; one prompt, no second checkpoint):

- **accept** → commit + close (ship runs its normal close/transition).
- **decline** → nothing is committed (safe default); the build then prints the manual `→ Next: \`/task:ship\`` footer so the user can ship later.
- **edit** → ship's normal edit branch, then commit + close.

On a **non-interactive run** — the `auto-roadmap-item-runner` executing these Steps inline (the *same* non-interactive detector ship's SKILL.md Steps 2.5/3 use) — the orchestrator does **not** propose: it completes silently and the item-runner drives ship itself with literal flags. This interactive-only gate is what keeps the item-runner and the driver byte-stable. This is a confirm-gated default (always-on for interactive builds), not an opt-in flag or config toggle — per `simplify-pipeline-surface.spec.md §2`.

**Blocking completions never propose.** The Step 4 verify-failure path, the Step 4 / Step 5 audit iteration-limit path, and the implement quick-fix-exhausted hand-off are not clean — they keep their full blocking-finding surfacing and their own `→ Next:` lines, with no ship proposal added.

## Step 5: Chain hint / `--auto` loop-back

After the dispatched phase completes successfully (no verify failure, no iteration limit surfaced):

- **Manual mode (`AUTO_MODE=0`)** — print the chain hint as the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)) and stop:
  - After a clean `implement` (completed, no quick-fix-exhausted hand-off) → **advance question.** On an **interactive** run, instead of printing the passive footer, ask one `AskUserQuestion` (single-select) — "Implement done. Run the audit now?" — with **Run audit now** / **Stop here** (structured-choice convention (c) in [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar); the two-option advance folds `--auto`'s implement→audit chaining into one interactive opt-in). **Run audit now** → loop back to Step 1a exactly as `--auto` would (re-run phase-detect → `audit`, run the Step 4 bounded loop), then apply the normal clean-build outcome. **Stop here** → print `→ Next: \`/task:build\`` (auto-detects audit). This reuses the existing `--auto` machinery for a single opt-in advance — it does **not** flip the run into full `--auto` mode (no multi-phase budget loop beyond the one audit the user asked for). **Non-interactive carve-out:** the `auto-roadmap-item-runner` running build inline never asks — it drives phases with literal flags; print no question and let it proceed. On a non-interactive run print `→ Next: \`/task:build\``.
  - After `audit` (loop completed cleanly) → print the compact one-line summary first — `Audit: <total> found · <fixed> fixed · <filtered> filtered — full detail in \`audit.md\``, with the three numbers read from the just-written iteration's `### Result` line. Do not re-print the Findings/Details tables; they stay in `audit.md`. The build is now clean: on an **interactive run**, follow the compact summary with the **Clean-build ship proposal** (flow into ship's single confirmation) instead of the passive footer; on a **non-interactive run**, or when the proposal is declined, print `→ Next: \`/task:ship\`` (commit + close).
  - After `audit` (loop hit iteration limit) → user action required; print the Step 4 iteration-limit message (which ends with its own `→ Next:` line), no chain hint and **no ship proposal** — the build is not clean.

- **`--auto` mode (`AUTO_MODE=1`)** — instead of printing the chain hint, **loop back to Step 1a** (re-run phase-detect with the updated on-disk state). The loop terminates on:
  - Step 1a returning `done` → the build is clean; apply the **Clean-build ship proposal** via the Step 1a `done` branch (interactive: flow into ship's single confirmation; non-interactive / declined: print `Build complete.` + the `→ Next:` footer) and stop.
  - Step 1b's per-phase budget gate firing → print `--auto stopped: ...` and stop. This path is not clean — no ship proposal.
  - Any dispatched phase surfacing a stop (verify failure, audit iteration limit, implement quick-fix exhausted) → propagate the phase's stop message, prefix with `--auto stopped:`, do not loop back.

  The `--auto` loop has no global iteration bound beyond the per-phase budgets in Step 1b; the worst-case execution is `implement(×1) → audit(×2)` = 3 phase dispatches before forced termination.

## Forbidden

- Inline the phase instructions in this orchestrator — always dispatch via the companion file.
- Modify any file other than what the dispatched phase's instructions specify (the audit auto-fix loop is bound to `plan.md → Touches`).
- Skip the touches-gate on any auto-fix — out-of-scope fixes must be marked Skipped, not applied.
- Run more than 2 audit iterations — the bound is the safety mechanism; surface to user instead.
- Bypass the Step 1b per-phase budget gate in `--auto` mode — the budget is the only thing keeping the loop from re-entering audit indefinitely.
- Combine `--auto` with `--phase` — they are mutually exclusive (Step 1 rejects).
- Propose the ship on a non-clean build (any blocking path — verify failure, audit iteration limit, implement quick-fix exhausted) or under non-interactive (item-runner inline) execution — the Clean-build ship proposal is interactive-only and clean-only.
- Ask the manual-mode implement→audit advance question (Step 5) under non-interactive (item-runner inline) execution, or after a non-clean implement (quick-fix-exhausted hand-off) — the advance question is interactive-only and clean-only; the item-runner drives phases with literal flags.
- Add a second confirmation on top of ship's single Step 3 accept/decline/edit confirmation — the clean-build proposal reuses that one prompt, it does not stack another.

## Output

After the dispatched phase completes:
- Print whatever the companion phase's "Output" section specifies (iteration counts, findings, build/test results).
- For audit (clean/converged case): the **default** human-facing output is a single compact line — `Audit: <total> found · <fixed> fixed · <filtered> filtered — full detail in \`audit.md\`` — where the three numbers come from the just-written iteration's `### Result` line. Do NOT re-print the Findings/Details tables by default; they remain retrievable from `audit.md` on request. The Step 4 iteration-limit and verify-failure paths keep their existing full blocking-finding surfacing — the compact summary never replaces those.
- On a **clean interactive build** (both clean endpoints — Step 1a `done` and Step 5 audit-clean — plus the `--auto` `done` termination): after the applicable completion / compact-summary line, surface the **Clean-build ship proposal** (see the shared note before Step 5) — flow into ship's single accept/decline/edit confirmation (accept → commit + close; decline → no commit, print the manual `→ Next: \`/task:ship\`` footer; edit → ship's edit branch). Non-interactive runs and every blocking path never propose.
- In manual mode — add the chain hint (Step 5).
- In `--auto` mode — print one summary line per completed phase as the loop progresses (`[--auto] implement done`, `[--auto] audit iteration 1 done`, etc.); after the final phase or on stop, print the terminating message described in Step 5.
