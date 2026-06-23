# Phase: audit

> **Inputs:** `$ARGUMENTS` forwarded from `/task:build` — additional context if provided.
> **Tier:** B (MCP-first tooling).
> **Workspace:** Resolved via `.task-current` → `.task/workspace/<task-id>/`.

Audit the diff for **code quality** (reuse, simplicity, clarity) and record findings. Apply fixes is governed by the orchestrator's bounded auto-fix loop (`build/SKILL.md` Step 4) — this phase file describes **one pass** of audit (load → lens fanout → write findings). The orchestrator iterates this pass up to 2 times, applies fixes in main thread between passes, and enforces `_lib/touches-gate.sh` on every fix.

**Constraint — does not touch `summary.md`.** `summary.md` is the user-facing description of what changed and is owned by the implement phase. Audit fixes are typically internal refactors that do not alter the user-facing summary; if a fix DOES change user-visible behavior, that is a sign the fix is out of scope for this phase — the `_lib/touches-gate.sh` will catch it when the change escapes planned `Touches`.

**Audit-specific language note.** When merging findings into `audit.md` (Step 3), translate the template headers (`### Findings`, `### Details`, `### Result`, table columns `Severity`/`Category`/`Location`/`Problem`) to the configured language; the `## Iteration {N}` header, `high`/`med`/`low` enum, field keys (`severity`/`category`/`location`/`problem`/`fix`) in agent output, AND the Status string values (`pending fix`, `Fixed`, `Skipped: …`) all stay English (parser-stable — `_lib/phase-detect.sh` greps for `pending fix` to route re-entry; translating would silently route to `done` with fixes still pending). Status is **emitted only in the Details block** (single source of truth) — not duplicated in the Findings table, so the auto-fix loop's status update has one anchor.

## Architecture

This phase orchestrates **lens subagents** to get a wide, multi-lens audit in one pass — addressing the failure mode of single-perspective reviewers that surface only one improvement per run.

The audit path is **adaptive** — it scales with diff size:

| Routing condition | Path | Phases |
|-------------------|------|--------|
| `trivial: true` in context (1 file, <30 lines changed) | Main-thread combined audit | (1) Context → (2a) main-thread Reuse+Simplicity+Clarity audit → (3) merge & write |
| `trivial: false` | Single-round subagent fan-out | (1) Context → (2b) one tool message: `Reuse` ‖ `Simplicity` ‖ `Clarity` → (3) merge & write |

**Where the neighborhood map comes from.** The Reuse lens needs a "what already exists in the project" map. It is built **deterministically by `audit-context.sh`** — the script extracts new top-level symbols from added diff lines, then `git grep -Fw`s each symbol over the working tree, excluding the changed files and `.task/**`. Up to 5 distinct files are kept per symbol; symbols matched in 15+ files are flagged as "too common"; symbols with no candidates are omitted.

**Subagents in the audit phase are read-only.** Each lens runs as a named agent bundled with the `task` plugin (under `agents/` in this repo) — invoked via `subagent_type` `task:audit-reuse-auditor`, `task:audit-simplicity-auditor`, `task:audit-clarity-auditor` (plugin prefix is mandatory — without it the runtime falls back to the catch-all `claude` agent and the lens prompts are silently dropped). The agents declare a read-only `tools:` allowlist in their frontmatter (no `Edit`/`Write`), so the read-only contract is enforced at the runtime level. Fixes happen in the orchestrator's main thread (build/SKILL.md Step 4) — concurrent agents editing the same files would produce conflicts.

**Per-agent context — kept lean.** Each audit agent receives only what its lens needs:

| Agent | Decisions | Plan `Touches` | Neighborhood map | Recent history | `CLAUDE.md` |
|-------|-----------|----------------|------------------|----------------|-------------|
| Reuse | ✓ | — | ✓ (from script) | — | — |
| Simplicity | ✓ | ✓ | — | ✓ (from script) | — |
| Clarity | ✓ | — | — | — | ✓ (from script) |

The diff bundle goes to all of them — that is unavoidable and the dominant cost.

## Step 1: Load context

Run the context script:

```bash
bash "${CLAUDE_SKILL_DIR}/audit-context.sh"
```

> **Run verbatim.** Don't add `CLAUDE_SKILL_DIR=…` inline before `bash` — Claude Code substitutes `${CLAUDE_SKILL_DIR}` at skill-load time, and bash same-line assignments don't take effect until *after* variable expansion (the path would resolve empty → `bash "/audit-context.sh"`). If substitution clearly failed (literal `${CLAUDE_SKILL_DIR}` visible — e.g. this phase file was read directly during an inline `/task:auto-roadmap` audit run, where no skill-load substitution happens), resolve the script at the **build skill root** `${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh` — it lives there, NOT in `phases/` next to this file. Run it via `bash -c '…'`: `CLAUDE_SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/build" bash -c 'bash "${CLAUDE_SKILL_DIR}/audit-context.sh"'`.

It outputs all context needed for the audit in one block:

- `.task/config/config.md` — tool configuration. Extract MCP priority list and the project's `CLAUDE.md` references.
- `.task/workspace/<task-id>/task.md` — extract `## Description` and `## Decisions` (if present). Decisions may explicitly justify a pattern that would otherwise look like a quality issue.
- `.task/workspace/<task-id>/plan.md` — extract `## Scope` and the `Goal`/`Touches` of each step in `## Steps`. `Touches` defines what should have changed; anything outside it is a candidate for a "scope creep" finding.
- `CLAUDE.md` (project root, if exists) — used by the Clarity agent for naming/style conventions.
- `iteration` — next iteration number (1 if `audit.md` missing, else `max(## Iteration N) + 1`).
- `diff size` — `files: N`, `lines_changed: N`, `trivial: true|false`.
- `diff bundle` — list of changed files plus per-file `git diff HEAD`, already filtered.
- `recent history` — per changed file, last 5 commit headlines (`git log -5 --oneline`). Consumed by the Simplicity lens only; surfaces "defensive check just removed, now being re-added" style churn that reads as dead code only against the historical axis.
- `neighborhood map` — for each new top-level symbol, up to 5 representative `<file>:<line>: <content>` rows where the same name already appears in the project.

If `diff bundle` says `(no changes after filtering ...)` — there is nothing to audit. Tell the user and stop.

## Step 2: Audit

Branch on the `diff size` block: take Step 2a (inline) if `trivial: true`; otherwise take Step 2b (fan-out).

### Step 2a: Inline combined audit (trivial diff)

When `trivial: true`, do the audit yourself in the main thread.

1. Read the diff bundle. For each entry in the `neighborhood map` (Reuse lens), check whether the new symbol genuinely duplicates the listed file:line.
2. Mentally apply all three lenses to the diff in one pass.
3. Build a findings list using the canonical 5-field `severity / category / location / problem / fix` schema agents return (per [`agents/_shared/audit-rules.md`](../../../agents/_shared/audit-rules.md)). Then stamp a `source` label on each finding post-hoc — one of `Reuse | Simplicity | Clarity` — by inspecting the category (e.g. `duplicates utility` → Reuse, `dead branch` → Simplicity, `misleading name` → Clarity). In the Step 2b path, `source` is supplied by which named agent returned the finding; here in the inline path you assign it yourself.
4. Skip findings that contradict an explicit decision in `task.md` / `plan.md`. **Language:** values of `category`, `problem`, `fix` are written in the language from `config.md` → "Language"; field keys and the `high`/`med`/`low` enum stay English.
5. Continue at Step 3.

### Step 2b: Non-trivial diff — single round (parallel: Reuse ‖ Simplicity ‖ Clarity)

When `trivial: false`, send **three** `Agent` calls in a **single tool-call message** so they run concurrently. Each call delegates to a **named agent** bundled with the `task` plugin (the `subagent_type` value MUST carry the `task:` plugin prefix — unprefixed names do not resolve and silently fall through to the `claude` catch-all).

| Agent | `subagent_type` | Per-call data |
|-------|-----------------|---------------|
| Reuse Auditor | `task:audit-reuse-auditor` | Decisions(task) · Decisions(plan) · **Neighborhood map** · Diff bundle |
| Simplicity Auditor | `task:audit-simplicity-auditor` | Decisions(task) · Decisions(plan) · **Plan touches (scope)** · **Recent history** · Diff bundle |
| Clarity Auditor | `task:audit-clarity-auditor` | Decisions(task) · Decisions(plan) · **CLAUDE.md** · Diff bundle |

#### Per-call prompt template

Use the same template for all three; include the lens-specific block only where the table above marks it.

```
Audit this diff against your lens. Return findings in the format defined
in your agent prompt.

--- Language ---
{paste config.md → "Language" value verbatim}

--- Decisions (task) ---
{paste task.md ## Decisions, or "none"}

--- Decisions (plan) ---
{paste plan.md ## Decisions, or "none"}

--- Plan touches (scope) ---       # Simplicity ONLY
{paste each step's Touches list}

--- Recent history ---             # Simplicity ONLY
{paste recent history block from audit-context.sh}

--- Neighborhood map ---           # Reuse ONLY
{paste neighborhood_map}

--- CLAUDE.md ---                  # Clarity ONLY
{paste CLAUDE.md content from audit-context.sh, or "(missing)" if absent}

--- Diff bundle ---
{paste diff bundle}
```

Note: do NOT include a `--- Tools available ---` section. The lens agents are runtime-locked to `Read, Grep, Glob` via their frontmatter `tools:` allowlist (see `agents/_shared/audit-rules.md`); listing MCP code-navigation tools from `config.md` would be dead emission and risks the lens attempting calls that will fail.

If the `task` plugin is not installed (the `Agent` call returns `subagent_type not found` for `task:audit-*-auditor`), surface that error with: "Install the `task` plugin so `task:audit-reuse-auditor` / `-simplicity-auditor` / `-clarity-auditor` are available." Then stop — do not fall back to inline prompts.

## Step 3: Merge, prioritize, write `audit.md`

Three gates fire in order before the surviving findings reach the iteration block: existing filter (3) → hunk-gate (3a) → claude_md_quote-gate (3b, Clarity only) → confidence-gate (3c). Findings dropped at gates 3a–3c go to `### Filtered (low confidence)` with a one-line note — they are not lost, just demoted out of the auto-fix queue.

1. Parse each agent's reply (or your own findings list, if Step 2a) into a list of findings.
2. **Deduplicate**: same `(file, line)` with overlapping `problem` text → keep the most specific entry, discard the rest.
3. **Filter**: drop findings that
   - reference symbols not present in the diff;
   - contradict an explicit decision in `task.md` / `plan.md`.

3a. **Hunk-gate** — drop findings whose `location` line is not inside an added or modified hunk.

   The `diff bundle` from Step 1 contains the per-file diff with hunk headers `@@ -<old> +<new_start>,<new_count> @@`. For each file, collect the set of ranges `[new_start, new_start + new_count - 1]` (use `new_count = 1` if absent). A finding survives the gate iff its `<line>` falls inside at least one range for its `<file>`. The merger can do this inline (no extra script — `awk '/^\+\+\+ b\// {f=…} /^@@/ {match($0, /\+([0-9]+),?([0-9]*)/, m); …}'` over the bundle is enough).

   File-wide findings (no `:line` in `location`) bypass this gate — they were intentionally emitted without a specific line.

   Dropped findings → `### Filtered (low confidence)` with note `(line not in diff hunks)`.

3b. **CLAUDE.md quote-gate** (Clarity findings only) — drop findings claiming a CLAUDE.md convention if the quote is not verbatim in the CLAUDE.md block.

   Clarity findings whose category implies a project convention (`naming inconsistency`, or any category whose `problem` text mentions CLAUDE.md / project convention) MUST carry a `claude_md_quote: "<phrase>"` field (see `agents/audit-clarity-auditor.md`). The merger normalizes both the quote and the CLAUDE.md block (case-insensitive, collapse whitespace, strip trailing punctuation) and substring-matches the quote against the block. No match → drop.

   Dropped findings → `### Filtered (low confidence)` with note `(claude_md_quote not found)`.

3c. **Confidence-gate** — post-hoc score each surviving med/low finding, drop below threshold.

   The merger (main thread) assigns each `med` or `low` finding a `confidence` value from `{0, 25, 50, 75, 100}` using this rubric:

   - **0** — false positive that does not survive light scrutiny, or a pre-existing issue.
   - **25** — might be real, might be false positive; could not verify either way. For style: not explicitly called out in the relevant CLAUDE.md.
   - **50** — verified real, but a nitpick or rarely hit; not very important relative to the rest of the diff.
   - **75** — double-checked, very likely real and will be hit in practice; the current approach is insufficient, OR the issue is directly mentioned in the relevant CLAUDE.md.
   - **100** — directly confirmed by the evidence; will happen frequently.

   **High-severity findings bypass this gate** — they are always kept.

   **Threshold: drop findings with confidence < 75.** (Calibration: stricter than the built-in `/code-review`'s 80 — that threshold is tuned for 5 overlapping agents with broad mandates; our 3 lens-specific agents emit less noise, so 75 catches the same class without over-pruning.)

   Dropped findings → `### Filtered (low confidence)` with note `(confidence: <N>)`.

4. **Sort**: high → med → low; within a severity — by file, then line.
5. Build the iteration block and **append** to `.task/workspace/<task-id>/audit.md` (create the file if iteration 1). Initial statuses are all `pending fix`.

**Language for the rendered file:** translate the section headers and table column names per `config.md` → "Language". Keep the `## Iteration {N}` header English regardless. Keep the `high`/`med`/`low` enum values, file paths, line numbers, Status strings (`pending fix`, `Fixed`, `Skipped: …`), and the `Source:` label/values (`Reuse` / `Simplicity` / `Clarity`) as-is — they are parser-stable identifiers (Status strings are read by `_lib/phase-detect.sh` and by the orchestrator's auto-fix loop; Source labels are how the orchestrator routes findings).

Template for each iteration:

```markdown
## Iteration {N}

### Findings

| # | Severity | Category | Location | Problem |
|---|----------|----------|----------|---------|
| 1 | high | duplicates utility | `path/Foo.ts:42` | re-implements `formatDate` from `utils/date.ts` |
| 2 | med  | dead branch        | `path/Bar.ts:88` | `if (x === null)` after non-null assertion above |

### Details

1. **{Brief title}** — `{path}:{line}` — {problem in one sentence}
   - Fix: {concrete change}
   - Source: Reuse | Simplicity | Clarity
   - Status: pending fix

### Filtered (low confidence)

- redundant comment at `path/Foo.ts:42`: restates what the loop already says (confidence: 25)
- naming inconsistency at `path/Bar.ts:88`: function uses snake_case (claude_md_quote not found)
- dead branch at `path/Baz.ts:120`: unreachable after early-return (line not in diff hunks)

### Result: {fixed}/{total} fixed — high: X / med: Y / low: Z — filtered: K
```

`Status` lives only on each Details bullet — there is no `Status` column in the Findings table. The orchestrator's auto-fix loop (`build/SKILL.md` Step 4) flips that single bullet from `pending fix` to `Fixed` / `Skipped: …`; `phase-detect.sh` greps the whole file for `pending fix` to decide re-entry, so a single anchor per finding is enough.

**`### Filtered (low confidence)` is optional.** Emit the section only when at least one finding was dropped at gate 3a/3b/3c. The section carries one bullet per dropped finding (`- <category> at <location>: <problem> (<reason>)`) and **no `Status:` lines** — the auto-fix loop treats it as inert. The `filtered: K` count in the `### Result` line tallies these. If every finding is filtered, `### Findings` keeps only the header row, `### Details` is omitted entirely, and `### Result` reads `0/0 fixed — filtered: K`; the absence of `pending fix` makes `phase-detect.sh` correctly classify the phase as `done`.

Return control to the orchestrator (`build/SKILL.md` Step 4) which will apply fixes in main thread with `_lib/touches-gate.sh` enforcement and may invoke this phase again for iteration 2 if pending high-severity findings remain.

## Forbidden

- Apply fixes in this phase — fixes are the orchestrator's responsibility (main thread, scope-gated).
- Modify `summary.md` — it is owned by the implement phase.
- Rewrite previous iterations of `audit.md` — append-only.
- Spawn subagents recursively (this phase already runs lens-agents; agents can't spawn agents).
