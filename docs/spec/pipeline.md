# Pipeline shape

```
/task:bootstrap
  ↓
[/task:roadmap [--refine]]                               ← off-cycle, multi-task initiative
  ↓                                                        (--refine: parallel three-lens audit
                                                            over an existing roadmap)
  ├─ [/task:auto-roadmap] ─────────────┐                ← off-cycle autopilot
  ↓                                     │                   (main-thread loop;
/task:go  [--auto]                      │                ← one-verb entry (see below)
  ↓  (or the explicit verbs)            │
/task:design [--from <roadmap>[#<N>]]   │                    per-stage model split:
  ↓                                     │                    design/audit/ship use session model,
/task:build [--auto]                    │                    implement uses plan.md → Implement-Model;
  ↓                                     │                    session stays open)
/task:ship [--full]                     │                Last item ships with /task:ship --full
                                        │                directly (slug from summary.md); no
                                        │                separate chore-finalize commit.
                                        │                /task:build --auto chains both phases.
```

The three operational skills (`design`, `build`, `ship`) auto-detect their current phase from `.task/workspace/<task-id>/` state. Pass `--phase <name>` to force a specific phase (override auto-detect).

## Phase dispatch

`/task:design` covers 4 phases — `open`, `idea`, `blueprint`, `refine`:

- `open` — fresh task or roadmap continuation. Auto-detected when no `.task-current` or no `task.md`. In manual mode (no `--from`), Step 2a writes `## Description` via **quick-draft** (paraphrase of the provided context into `### Problem` / `### Outcome` / `### Scope` / `### Constraints`) for any non-empty **paraphrasable** context — a filled `task.md` in one call. Quick-draft is skipped (Description left empty) on two paths: `--idea` (explicit opt-out → orchestrator continues into the idea phase, architect, in the same call) and input with no prose to paraphrase (e.g. a bare ticket id → next `/task:design` enters the idea phase). An empty `/task:design` with no task in flight is treated as `--idea`.
- `idea` — brainstorm / refine `## Description`. Reached via `--idea`, an empty `/task:design` call with no task in flight (orchestrator opens a header-only umbrella first), or auto-detect when `task.md` exists with empty Description (post-`/task:ship` continuation slot). Mode is a function of Description content: empty → architect-style brainstorm; non-empty → Socratic refinement.
- `blueprint` — MCP discovery + plan composition. Auto-detected when Description is filled and `plan.md` doesn't exist.
- `refine` — critically review the plan, propose alternatives. **Never auto-entered** — only on explicit `--phase refine` or `--refine` shorthand.

`/task:build` covers 2 phases — `implement`, `audit`:

- `implement` — execute plan steps with TDD-loop (if `## Tests` present) + verification before TaskUpdate(completed). Auto-detected when `summary.md` is missing (its presence is the implement-complete marker; a present `summary.md` with no diff vs HEAD warns on stderr but does not re-route back to implement).
- `audit` — code-quality lens fanout (Reuse / Simplicity / Clarity) with **bounded auto-fix loop** (≤2 iterations, scope-gated). Three merge-time gates filter findings before write — hunk-gate (location must be in an added/modified hunk), CLAUDE.md quote-gate (Clarity citations must carry a verbatim phrase), confidence-gate (med/low must score ≥75 on a 0–100 rubric). Drops land in `### Filtered (low confidence)` inside the iteration — surfaced for review, ignored by auto-fix. Auto-detected when `summary.md` exists and `audit.md` is missing or has pending fixes.

Default semantics: one phase per invocation, then a chain hint. `--auto` (opt-in, mutually exclusive with `--phase`) chains both phases in a single invocation, guarded by per-phase budgets (≤1 `implement`, ≤2 `audit`) — symmetric with audit's own bounded loop. Not auto-detected; the flag must be passed explicitly. See [invariants.md § `/task:build`](invariants.md) for the full stop-condition matrix.

`/task:ship` has two modes:

- **default** (umbrella close) — commit, then archive everything including `task.md`; remove `.task/workspace/<task-id>/` and `.task-current`. `--full` is accepted as a backward-compatible alias of this default.
- **`--next`** (subtask transition) — commit, then archive per-subtask artifacts; keep `task.md` with Description body cleared, ready for the next subtask of the same umbrella.

## `/task:go` — one-verb entry

`/task:go` is a state-aware dispatcher: it inspects `.task/workspace/<task-id>/` and runs the **next** pipeline phase, so a user need not remember whether `design`, `build`, or `ship` comes next. It owns no phase logic — it reads the two detectors (`phase-detect.sh design`, then `phase-detect.sh build` once the first returns `refine-prompt`) and runs the resolved phase by executing the owning skill's Steps **inline** (the three operational skills are `disable-model-invocation: true`, so the `Skill` tool cannot dispatch them — same posture as `/task:auto-roadmap`). Two modes off one `--auto` flag:

- **Interactive** (`/task:go`) — run the next phase, then an `AskUserQuestion` checkpoint (Continue / Edit artifact / Stop) before advancing. The design side is delegated whole to inline `/task:design` (auto-detect, incl. the open→idea chain); go crosses to build only when the design detector returns `refine-prompt`. The blueprint→build checkpoint also offers `--refine` (surfaced, never auto-entered). No subagents; tolerates a stray `auto.lock` (resumes a stopped autonomous run).
- **Autonomous** (`/task:go --auto`) — an N=1 `/task:auto-roadmap`: the main thread opens + quick-drafts the Description (one confirmation), then delegates blueprint and implement to the shared executor runners (`auto-roadmap-{design,build}-runner`, the design half spawned with `from: current` for blueprint-only) and runs audit + ship inline. Always closes `--full` (no roadmap to auto-mark); on failure it hands back a resumable task — no `chore-finalize`. Pre-gated by `skills/go/go-context.sh` (config / `.task-current` absent / no stale `auto.lock`, sharing the cross-worktree mutex with `/task:auto-roadmap`).

## Off-cycle skills

- `/task:roadmap` — brainstorm a multi-task roadmap (default mode). Long-lived `.task/roadmap/<slug>.md`. When the brainstorm surfaces load-bearing technical decisions, also writes an optional `.task/roadmap/<slug>.spec.md` sidecar — numbered decision anchors that roadmap items cite via `### Spec references` and design's blueprint phase reads to stay aligned with what was agreed. Supports `--refine [<slug>]` to run a parallel three-lens audit (Coverage / Decomposition / Clarity) over an existing roadmap, bounded ≤ 2 iterations; findings land in sidecar `.task/roadmap/<slug>.refine.md` (high-severity auto-applied, med/low surfaced for manual review).
- `/task:auto-roadmap` — drive an approved roadmap through the pipeline item-by-item.
- `validate` — internal-only (not user-invocable). Run as PreToolUse hook + inline at Step 0 of orchestrators.

## `/task:auto-roadmap` orchestrator

Drives an approved roadmap through the full pipeline item-by-item. The common shape — three Step 0 preconditions, `--items` grammar, lock-file invariants, failure protocol, cross-worktree safety — is centralized in [auto-roadmap.md](auto-roadmap.md). Per-skill specifics below.

`/task:auto-roadmap` runs the per-item loop **inside the user's interactive Claude Code main thread**. The runtime cascades into three observable properties: per-stage model split (see below), foreground-only, inline observability.

- **`skills/auto-roadmap/SKILL.md` owns the entire run**, Steps 0–5: hard-stop preconditions (three gates), wizard (roadmap / `--next` / `--from #N` / `--items <spec>`), the per-item loop itself, umbrella close. Step 2 captures the run's parameters in main-thread memory only; the first on-disk record lands in Substep 3.4 as `workspace/<task-id>/auto.lock`.
- **Two subagents per item, narrow scope.**
  - `auto-roadmap-design-runner` (`agents/auto-roadmap-design-runner.md`) reads design's open + blueprint phase files (`from: <roadmap>#N`) and returns `OK: design done — plan.md ready, awaiting implement` or `FAIL at <stage>: ...`. Runs under the parent-session model. (Shared with `/task:go --auto`, which spawns it `from: current` for blueprint only.)
  - `auto-roadmap-build-runner` (`agents/auto-roadmap-build-runner.md`) reads build's implement phase file and returns `OK: implement done — diff uncommitted, ready for audit` or `FAIL at implement: ...`. Spawned with `Agent.model` override set to `plan.md → Implement-Model:` (`opus|sonnet|haiku`). The OK line is orchestrator-agnostic (parsers key on the em-dash clause, not the log prefix).
  - Neither runs audit or ship — those are the orchestrator's.
- **Main thread runs `/task:build` audit phase + `/task:ship` inline** after build-runner OK. "Inline" = main thread reads each skill's `SKILL.md` (and relevant `phases/<phase>.md` companion) and executes its Steps directly — see [`invariants.md` § `/task:auto-roadmap`](invariants.md). Build's audit Step 2b fans out to `audit-{reuse,simplicity,clarity}-auditor` natively (main thread can spawn subagents); ship's commit step reads the uncommitted diff the build-runner produced; ship's close step auto-marks the roadmap item and clears Description for the next iteration.
- **Single sentinel — per-umbrella lifecycle.** Only one autopilot file exists on disk: `workspace/<task-id>/auto.lock` (with `orchestrator=auto-roadmap`), written by Substep 3.4 after design-runner's open lands `.task-current` and the workspace subfolder. It is both the launch-time snapshot of the run's parameters and the cross-worktree mutex — Step 0 gate 3 scans `workspace/*/auto.lock` and refuses on any match. Clean finish removes the sentinel with the workspace subfolder (via the **last** item's `/task:ship --full` inside Substep 3.9 Branch B — no separate `chore-finalize` commit).
- **Per-stage model split.** Design (open + blueprint), audit orchestration (Step 1 trivial-check, Step 3 merge, Step 4 auto-fix loop), and ship run under the parent-session model (user sets it via `/model` before invoking). Implement runs under each item's `plan.md → Implement-Model:` (`opus|sonnet|haiku`), passed by main thread as `Agent.model` override when spawning `auto-roadmap-build-runner`. The three audit lens auditors (`audit-{reuse,simplicity,clarity}-auditor`) spawned in Step 2b pin `model: sonnet` in their own frontmatter — they do **not** inherit the parent-session model. To force a specific implement model, edit `Implement-Model:` in `plan.md` (or adjust the blueprint rubric); to change the lens-auditor model, edit the agents' frontmatter.
- **Item count is unbounded; context budget is the user's call.** Past ~15 items on Sonnet 200k (or ~25 on Opus 1M), auto-compact can drop items mid-run and corrupt the `.task-current` → continuation chain. No hard cap is enforced — if approaching the budget, slice with `--items <range>` and run back-to-back.
- **Skips design's idea + refine phases always** — curated `Ready description:` (Context / Goal / Outcomes / Acceptance criteria) on each roadmap item is sufficient; Socratic refinement is unnecessary and refine requires a human in the loop.
- **Recovery procedure.** On failure (triggers and postmortem path in [auto-roadmap.md § Failure protocol](auto-roadmap.md#failure-protocol--fail-stop-no-rollback)): manually inspect postmortem; run `/task:ship --full chore-finalize` to sweep the partial umbrella. Optionally `/task:auto-roadmap <roadmap> --from #<N>` to retry from the failed item.

## Universal precondition

Every non-`bootstrap` skill refuses to run without `.task/config/config.md`.
