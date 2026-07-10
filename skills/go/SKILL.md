---
name: go
description: 'One-verb pipeline entry — inspect .task/ state and run the next phase (open → blueprint → implement → audit → ship), checkpointing between each so you decide when to advance. `--auto` runs the whole task hands-off via plan + implement subagents.'
disable-model-invocation: true
user-invocable: true
---

Drive a single task through the pipeline with one command. `/task:go` inspects the state of `.task/workspace/<task-id>/` and runs the **next** phase, then stops at a checkpoint and asks whether to advance — so newcomers never have to remember which of `design` / `build` / `ship` comes next, and power users keep those explicit verbs for finer control. `--auto` turns the same walk into a hands-off run: the main thread opens + drafts the Description (one confirmation), then delegates blueprint and implement to subagents and runs audit + ship inline.

**Input:** `$ARGUMENTS` — `[<context>] [--auto]`
- `<context>` — free-form task context (ticket id / title / a sentence), used only when opening a fresh task. Ignored when a task is already in flight.
- `--auto` — autonomous mode (Step 3). Without it, `/task:go` is interactive (Step 2).

**This skill dispatches other skills inline.** `/task:design`, `/task:build`, and `/task:ship` are all `disable-model-invocation: true` — the `Skill` tool **cannot** invoke them. Wherever a Step below says "run `/task:<x>` inline", it means: read `${CLAUDE_PLUGIN_ROOT}/skills/<x>/SKILL.md` (and any phase companion it dispatches) and execute its Steps directly in this thread, exactly as `/task:auto-roadmap` does. Never re-implement a phase's logic here — always defer to the owning phase file.

**Preconditions, tool tier, language:** `/task:go` is [Tier A](../../docs/spec/invariants.md#tier-a--no-code-navigation) — it only gates, detects state, and dispatches. Each phase it runs (or subagent it spawns) applies its own tier internally. User-facing dialog follows `.task/config/config.md` → "Language"; the phase-detector outputs, runner return strings, and `auto.lock` fields stay English (parser-stable).

## Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. If it exits non-zero with a `config.md not found` message, redirect the user to `/task:bootstrap` and stop. The `all` subcommand tolerates a missing `.task-current` (the fresh-start path).

## Step 1: Parse arguments

- If `$ARGUMENTS` contains `--auto` → **autonomous mode**: go to Step 3. Everything else in `$ARGUMENTS` (minus the flag) is the fresh-task context.
- Otherwise → **interactive mode**: go to Step 2.

`/task:go` takes no other flags. If the user wants to force a specific phase, that is what `/task:design --phase` / `/task:build --phase` are for — say so and stop only if they passed an unrecognized flag.

## Step 2: Interactive loop

Repeat the following until the task ships or the user stops. Never hand-parse workspace files — always route via the detectors and defer phase work to the owning phase files.

### 2a. Detect the current pipeline stage

Run the design-scope detector:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/phase-detect.sh" design
```

> **Run verbatim.** `${CLAUDE_PLUGIN_ROOT}` is a Claude Code load-time substitution — never prefix an inline `CLAUDE_PLUGIN_ROOT=…` assignment (it expands empty). If substitution clearly failed (literal `${CLAUDE_PLUGIN_ROOT}` visible), fall back to `bash -c '…'` with the absolute plugin path.

Map the output to a **stage**:
- `open` / `idea` / `blueprint` → the design side is not done; stage = that value.
- `refine-prompt` → the design side is complete (`plan.md` exists). Run the build-scope detector `bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/phase-detect.sh" build` and map:
  - `implement` / `audit` → stage = that value.
  - `done` → stage = `ship`.

### 2b. Run the stage inline

- **`open` / `idea` / `blueprint`** — run `/task:design` inline (let its own Step 1 auto-detect land the phase; do not force one — this preserves the fresh-start open→idea chain). On the **first** design-side dispatch of the run, forward the user's `<context>` as `/task:design`'s `$ARGUMENTS` (so open's quick-draft has material); on later dispatches pass no extra arguments — the phase reads state.
- **`implement` / `audit`** — run `/task:build` inline, forcing the phase (equivalent to `/task:build --phase <stage>`): read `skills/build/SKILL.md` and execute its Steps with `PHASE=<stage>` (build's Step 1a takes the forced value and skips auto-detect). For `audit`, this includes build's Step 4 bounded auto-fix loop (≤2 iterations, scope-gated by `_lib/touches-gate.sh`).
- **`ship`** — do not run anything yet; go straight to the ship checkpoint in 2c.

### 2c. Checkpoint (AskUserQuestion)

After the stage completes, present a single-select `AskUserQuestion` (never a free-text prompt) whose options depend on what just ran. "Continue" loops back to 2a; "Edit …" and "Stop" both print the relevant artifact path plus the resume hint `→ Next: /task:go` and then stop.

- After `open` or `idea` (Description written) → **Continue to plan** / **Edit `task.md` first** / **Stop**.
- After `blueprint` (plan written) → **Continue to build** / **Refine the plan (`--refine`)** / **Edit `plan.md` first** / **Stop**. On *Refine*, run `/task:design --refine` inline, then loop back to 2a (the plan still detects as `refine-prompt`, re-presenting this checkpoint).
- After `implement` → **Continue to audit** / **Stop**.
- After `audit`:
  - Loop finished cleanly (no pending high-severity finding) → **Ship now** / **Stop**.
  - Loop hit its iteration limit with a pending finding → do **not** offer Ship. Report the `audit.md` path and stop (the user resolves it, then reruns `/task:go`).
- Stage `ship` → **Close the umbrella (`--full`)** / **Next subtask (`--next`)** / **Stop**. On a ship choice, run `/task:ship` inline with the chosen flag (`--full` for the default full close, or `--next`), then stop — the loop is terminal at ship.

### 2d. Stray-lock tolerance

If, at any 2a detection, the resolved workspace also contains an `auto.lock`, this task was left behind by a stopped autonomous run (`/task:go --auto` or `/task:auto-roadmap`). Interactive `/task:go` **resumes it anyway** — note "resuming a stopped autonomous run" to the user and proceed. A subsequent `--full` ship removes the workspace subfolder, sweeping the lock with it.

## Step 3: Autonomous mode (`--auto`)

An N=1 mini-auto-roadmap: one human checkpoint (the drafted Description), then hands-off through ship. Blueprint and implement run in subagents (their code-navigation noise stays out of this thread); audit and ship run inline (the audit lens fanout must spawn subagents, which only the main thread can do). This mirrors `/task:auto-roadmap`'s per-item loop with the roadmap replaced by one confirmed Description.

### 3.1 — Pre-gate (fresh start required)

```bash
bash "${CLAUDE_SKILL_DIR}/go-context.sh"
```

> **Run verbatim.** Same `${CLAUDE_SKILL_DIR}` load-time-substitution rule as elsewhere — no inline `CLAUDE_SKILL_DIR=…` prefix; if substitution failed (literal token visible), use `CLAUDE_SKILL_DIR="<abs-skill-dir>" bash -c 'bash "${CLAUDE_SKILL_DIR}/go-context.sh"'`.

Surface the script's stderr verbatim and stop on any non-zero exit. It enforces three gates: `config.md` present, `.task-current` absent (else resume interactively with `/task:go`), and no stale/active `workspace/*/auto.lock` (cross-worktree mutex, shared with `/task:auto-roadmap`).

### 3.2 — Open + draft the Description (main thread)

Run `/task:design` inline, forwarding the user's `<context>` as its `$ARGUMENTS` — this lands `task.md` + `.task-current` via `open.md` Mode 1 quick-draft. If the context had no paraphrasable prose (a bare ticket id) and open leaves `## Description` empty, ask the user **once** (`AskUserQuestion` or a single prompt) for a one-sentence description, write it into `## Description`, and proceed. Do **not** enter the multi-round idea phase — `--auto` allows exactly this one elicitation.

### 3.3 — Confirm (the one checkpoint)

Print the drafted `## Description`, then `AskUserQuestion` single-select: **Proceed autonomously** / **Edit first** / **Stop**. On *Edit first* / *Stop*, print the `task.md` path and the resume hint (`/task:go` to continue interactively) and stop. Only *Proceed* continues.

### 3.4 — Write the sentinel `auto.lock`

`.task-current` now exists (3.2 landed it). Write the per-umbrella sentinel so a concurrent `/task:auto-roadmap` (or another worktree) refuses to launch on the same shared `.task/`:

```bash
TASK_ID=$(head -n 1 .task-current | tr -d '[:space:]')
LOCK_PATH=".task/workspace/$TASK_ID/auto.lock"
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/auto-locks.sh" write "$LOCK_PATH" \
  "orchestrator=go" \
  "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "working_dir=$PWD" \
  || { echo "auto.lock collision in workspace/$TASK_ID — another orchestrator is active. Aborting."; exit 1; }
```

The `auto-locks.sh write` helper skips empty values and uses `set -o noclobber` + truncate-or-fail so a real collision exits non-zero (see auto-roadmap SKILL.md Substep 3.4 for the rationale — do not hand-roll the noclobber logic). Fields stay English/parser-stable, matching the `orchestrator=go` variant documented in `docs/spec/artifact-contract.md` § `auto.lock` shape.

### 3.5 — Blueprint subagent

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-design-runner"` (the plugin prefix is mandatory — unprefixed names silently fall back to the catch-all `claude` agent). Do **not** pass a `model:` override — the runner inherits the parent-session model. Prompt body (verbatim — keep field labels and English; parser-stable):

```
from: current
working_dir: <abs cwd>

The task is already open (task.md + .task-current exist with a populated
Description). Run blueprint only — do NOT open, and do NOT run implement /
audit / commit / close. The orchestrator runs implement via
auto-roadmap-build-runner after you return, then audit + ship inline.

Before any code navigation in blueprint, read `.task/config/config.md` and use
the MCP tools listed under "Code Navigation" / "Code Editing" in the priority
order given there. Fall back to built-in Read / Grep / Glob only when config.md
explicitly lists them as fallback, or when the listed MCP server is unreachable.

Return your one-line status (OK or FAIL) per your agent prompt's "Return format".
```

Take the **last non-empty line** of the reply as the status line and match:
- `^OK: .* — plan\.md ready, awaiting implement$` → success; continue to 3.6.
- `^FAIL at .*` → failure; go to 3.10.
- anything else → malformed; go to 3.10 with reason `design-runner returned malformed status: <raw last line>`.

### 3.6 — Read `Implement-Model:` from `plan.md`

```bash
TASK_ID=$(head -n 1 .task-current | tr -d '[:space:]')
IMPLEMENT_MODEL=$(bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" \
                    extract_implement_model ".task/workspace/$TASK_ID/plan.md")
```

`extract_implement_model` exits non-zero on a missing / malformed / multi-match stamp. On failure, treat it as an audit-class failure (go to 3.10) with reason `MODEL_EXTRACT: blueprint produced plan.md without a valid Implement-Model: stamp`. On success, capture `IMPLEMENT_MODEL` for 3.7.

### 3.7 — Implement subagent

Use the `Agent` tool with `subagent_type: "task:auto-roadmap-build-runner"` and **`model: <IMPLEMENT_MODEL>`** (from 3.6). Prompt body (verbatim — keep field labels and English; parser-stable):

```
working_dir: <abs cwd>
implement_model: <IMPLEMENT_MODEL>

Run the implement phase only (build/phases/implement.md) for the task in
.task-current. Do NOT run audit / commit / close — the orchestrator runs those
after you return.

Before any code navigation or editing, read `.task/config/config.md` and use
the MCP tools listed under "Code Navigation" / "Code Editing" in the priority
order given there. Fall back to built-in Read / Edit / Grep / Glob only when
config.md explicitly lists them as fallback, or when the listed MCP server is
unreachable.

Return your one-line status (OK or FAIL) per your agent prompt's "Return format".
```

Match the last non-empty line:
- `^OK: .* — diff uncommitted, ready for audit$` → success; continue to 3.8.
- `^FAIL at implement: .*` → failure; go to 3.10.
- anything else → malformed; go to 3.10 with reason `build-runner returned malformed status: <raw last line>`.

### 3.8 — Audit (inline, main thread)

Run `/task:build`'s audit phase inline — read `${CLAUDE_PLUGIN_ROOT}/skills/build/SKILL.md` and execute its Steps with `PHASE=audit`. The audit phase runs its context script by its **absolute path at the build skill root**, `bash "${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh"` (NOT `phases/audit-context.sh`). Lens fanout (`Agent(task:audit-{clarity,reuse,simplicity}-auditor)` in parallel) works natively because you are the main thread. Build's bounded auto-fix loop applies (≤2 iterations, scope-gated by `_lib/touches-gate.sh` against `plan.md → Touches`).

- No findings, or all findings `Fixed` / `Skipped` after ≤2 iterations → continue to 3.9.
- Iteration limit hit with a pending high-severity finding → go to 3.10 with reason `AUDIT_LIMIT: build audit hit iteration limit with high-severity unfixed finding — see audit.md`.

### 3.9 — Ship `--full` (inline, main thread)

Run `/task:ship`'s logic inline (read `${CLAUDE_PLUGIN_ROOT}/skills/ship/SKILL.md` and execute its Steps). Pass **`--full`** — a `--auto` run is always a single umbrella closed in one pass (no `--next` transition, no roadmap to auto-mark). Do **not** pass an explicit slug; ship derives it from `summary.md`. Ship's `close.sh --full` archives `plan/audit/summary.md` + `task.md` to `.task/log/<task-id>/<N>-<slug>/`, removes the whole `workspace/<task-id>/` subfolder (sweeping `auto.lock` with it) and removes `.task-current`.

On any ship failure (commit refused, no diff, `summary.md` missing, close error) → go to 3.10 with reason `ship --full failed: <message>`.

### 3.10 — Failure hand-back

On any FAIL / malformed status / audit-limit above: **stop. Do not ship, do not clean up.** The workspace subfolder, its artifacts, and the `auto.lock` are left in place as the abort signal and the resumable state. Print to the user (in `config.md` Language):

- what failed and where (the reason string; the subagent's postmortem lives at `.task/workspace/<task-id>/auto-error.log` when one was written);
- **resume**: `/task:go` — resumes interactively at the failed phase (it tolerates the stray `auto.lock`); a clean run through to a `--full` ship then sweeps the lock;
- **discard**: `/task:ship --full` to close/clean up without finishing, or remove `.task/workspace/<task-id>/` + `.task-current` by hand.

There is no `chore-finalize` machinery here — that is `/task:auto-roadmap`'s multi-item recovery; an N=1 run just hands back a resumable task.

### 3.11 — Post-run summary

On a clean finish, print (in `config.md` Language): the task-id, the commit hash + message, the archive path `.task/log/<task-id>/<N>-<slug>/`, and a note that the workspace + `.task-current` were removed (so `/task:go` is ready for a new task).

## Forbidden

- Dispatching `/task:design` / `/task:build` / `/task:ship` via the `Skill` tool — they are `disable-model-invocation: true`; the tool refuses. Execute their SKILL.md Steps inline.
- Re-implementing any phase's logic in this file — always defer to the owning phase companion / SKILL.md.
- Constructing `.task/workspace/<task-id>/` paths by hand — resolve `<task-id>` via `head -n 1 .task-current` (as the substeps show) or the standard resolver; never assume a layout.
- Skipping the config gate (Step 0), even mid-pipeline — `validate.sh all` is cheap and catches corrupt state early.
- Auto-advancing past a checkpoint in interactive mode. Interactive `/task:go` stops at every `AskUserQuestion`; only `--auto` runs hands-off (and even it keeps the 3.3 confirmation).
- Running `--auto` when a task is in flight (3.1 refuses) — autonomy is fresh-start only.

## Output

- **Interactive:** after each stage, whatever the dispatched phase printed, plus the checkpoint. On stop, the resume hint `→ Next: /task:go`.
- **`--auto`:** a one-line progress note per stage (`[--auto] blueprint … ok`, `[--auto] implement … ok`, `[--auto] audit iteration N done`, `[--auto] shipped`), then the 3.11 summary — or the 3.10 hand-back on failure.
