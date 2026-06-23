# Phase: implement

> **Inputs:** `$ARGUMENTS` forwarded from `/task:build` — additional context if provided.
> **Tier:** B (MCP-first tooling).
> **Workspace:** Resolved via `.task-current` → `.task/workspace/<task-id>/`.

Implement the task strictly according to the prepared plan.

## Step 1: Load context

Validate pipeline artifacts before reading them:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" plan
```

If either exits non-zero, **stop** and report the validator output; the plan is malformed and execution would silently misinterpret it.

1. Read `.task/config/config.md` — tool configuration. Use the MCP tools described there for code navigation and editing. Build/test commands — from this file.
2. Read `.task/workspace/<task-id>/task.md` — task description. Use it as the source of truth for *why* the work is being done; fall back to it when the plan is ambiguous. Also extract its `## Decisions` section if present — Socratic-mode idea phase records umbrella-level decisions there; follow them when the plan does not mention a constraint they impose.
3. Read `.task/workspace/<task-id>/plan.md` — implementation plan. This is your primary source of actions. Each step in `## Steps` has three layers:
   - **Goal** — detailed description of intent and the expected end state. This is what you must achieve; read it in full.
   - **Touches** — the concrete symbols (classes, functions, methods, interfaces, exports) the step affects. Treat this as the bounded scope of what the step is allowed to modify.
   - **Logic** (optional, not always present) — pseudocode sketch clarifying non-obvious branching or conditions. Treat it as guidance, **not a literal template**. If `Logic` conflicts with `Goal` — `Goal` wins (the pseudocode is a sketch and can drift from intent).

   Also extract the `## Decisions` section of `plan.md` if present — the refine phase records there the choices that override the original plan; follow them when a step's `Goal`/`Logic` conflicts with the recorded decision. Plan-level decisions take precedence over task-level decisions when both speak to the same point.
4. Resolve `tests_required`: `plan.md` has a non-empty `## Tests` section. This is the **only** signal — do not re-read `Testing Policy`. If the blueprint phase did not emit `## Tests`, tests are out of scope for this task.

## Step 2: Materialize plan steps as tracked tasks

Before executing, create one `TaskCreate` per `### Step N` in `plan.md` so progress is visible in the runtime task tracker and the run is **auto-resumable** (a re-invocation of `/task:build` after interruption can read `TaskList` to see which steps are still `in_progress`).

For each step:

- `subject` = `Step N: {short title from plan}` (truncate at ~70 chars)
- `description` = the step's `Goal:` text verbatim (the executor will read this to recall intent without re-loading plan.md every step)
- `activeForm` = `Working on Step N`

Do not yet set status — they all start `pending`.

If `TaskList` already contains tasks named `Step N: ...` from a prior `/task:build` run on the same `plan.md`, **reuse them**: do not create duplicates. Skip already-`completed` steps; resume `in_progress` ones.

## Step 3: Sequential execution

For each step in `## Steps` order (skipping `completed` ones from Step 2):

1. **Mark in_progress.** `TaskUpdate` the corresponding tracked task to `in_progress`.
2. **Execute the step.** Branch on `tests_required`:

   **If `tests_required` is true and the step is referenced by a `### Test K`** — run the TDD micro-loop for that test:
   a. Create or update the test file exactly as specified (file path, framework, arrange/act/assert).
   b. Run the test command from `config.md` → `Testing Policy` → `Test command`, scoped to the new test if the runner supports it; otherwise run the whole suite.
   c. Expect **RED** — failure matching the "Expected failure before implementation" line. If the test unexpectedly passes → stop and report: the test does not actually exercise the target behavior; ask the user how to proceed.
   d. Apply the implementation changes confined to the step's `Touches`.
   e. Re-run the affected test(s). Expect **GREEN**. If still RED — invoke the **Errors** protocol below.
   f. Refactor only when tests are green. Re-run after each refactor.

   **If `tests_required` is false** — execute the step directly:
   - Use `Goal` as the primary anchor — what must be true after the step is done.
   - Restrict edits to the symbols listed in `Touches`. Do not modify unrelated symbols in the same file unless the `Goal` explicitly requires it.
   - If `Logic` is present — use it as a sketch, not a literal template. Prefer idiomatic code that matches the file's neighboring style over verbatim transcription of pseudocode.
   - When creating a file — check neighboring files for style consistency.
   - After modification — ensure the file is syntactically correct.

3. **Verification-before-completion (mandatory).** Before marking the tracked task `completed`:
   - **Identify** what to check: the `Touches` symbols (must be present in the diff), and any step-local invariant from `Goal` (e.g. "registered in DI container", "exported from index").
   - **Run** the verification: `git diff -- <files>` to confirm `Touches` symbols actually changed; if `tests_required` and a test references this step, confirm it transitioned RED → GREEN.
   - **Read** the full output, not just exit code. Skim the diff hunk to confirm the change matches `Goal`, not just the symbol name.
   - **State** the result internally before transitioning. If verification fails — keep the task `in_progress`, **stop**, report what was checked and what failed, and ask the user to inspect the diff and rerun the skill after manual investigation, or run `/task:design --refine` if scope needs revisiting.
   - Only on a passed verification: `TaskUpdate` the tracked task to `completed`.

4. **Move to the next step.** Loop until all steps are `completed` or a verification stops the run.

## Step 4: Build and tests

After all steps are `completed`, run the verification commands from the "Verification" section in `plan.md`.

## Step 5: Update summary

After all steps and verification, create or overwrite `.task/workspace/<task-id>/summary.md` using the shared template + rules in [`../../_lib/templates/summary.md`](../../_lib/templates/summary.md). Render in the language of `task.md` Description; always overwrite (old content is irrelevant).

## Errors

If build or tests fail mid-execution, do **one** quick attempt grounded in a clear root cause:

1. Read the **full** error output (not just exit code or last line).
2. If the cause is obvious from the output (typo, missing import, wrong symbol name in `Touches`) — apply **one** targeted fix and re-run.
3. If the fix succeeds — continue execution.
4. If the fix fails, or the cause is not obvious from the output — **stop** and tell the user:
   > Step {N} failed. One quick-fix attempt did not resolve it (or the root cause is not obvious from one pass). Inspect the diff and rerun `/task:build` after manual investigation, or run `/task:design --refine` if the scope needs revisiting.

Do **not** try shotgun fixes ("try this and see"). When the root cause is not obvious — stop and hand off to the user.

## Forbidden

- Modify files outside the plan — only files listed in the "Scope" or "Steps" sections of plan.md.
- Remove existing functionality unless explicitly specified in the plan.

## Output

After completion, output:
- List of completed steps.
- List of modified/created files.
- Build and test results.

Note that the next `/task:build` call will auto-detect audit phase.
