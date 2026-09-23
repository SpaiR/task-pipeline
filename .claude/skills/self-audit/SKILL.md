---
name: self-audit
description: Self-audit this skills repo against CLAUDE.md invariants, the artifact contract, and README/CLAUDE.md/docs/website sync via three parallel read-only subagents. Local meta-skill — independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
---

Audit **this repository** (the task-pipeline skills repo itself) for drift between skills, the artifact contract, and the docs. Three lenses run in parallel as named subagents: **Invariants**, **Contract**, **Docs-sync**.

This is a **meta-skill**. It operates on the repo's own files, not on `.task/*` artifacts. It asks one question — *does the repo obey its own declared rules?* — and each lens has an oracle: `CLAUDE.md` § "Invariants — don't break these when editing skills", `docs/contract.md`, and what is actually on disk. The skill can be invoked at any time.

**Input:** Optional scope hint: $ARGUMENTS (e.g. a single skill name to focus on; default: full repo).

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/to-task/`, `skills/validate/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** mirror the language the user writes in for all prose (headings, summaries, the final report). Findings text stays in English — it grounds in English source files and quotes them.

**Derive, never recall.** The roster of skills, `_lib/` helpers, agents and docs changes often. Neither this skill nor its agents carry a copy of it: every roster comes from the disk at run time (`ls`, Glob, frontmatter), and every rule comes from `CLAUDE.md` / `docs/contract.md` as they read today. A hardcoded list here would itself become the drift this skill exists to catch.

## Architecture

| Lens | Local agent | Oracle | What it checks |
|------|-------------|--------|---------------|
| Invariants | `self-invariants-auditor` | `CLAUDE.md` § Invariants + § Editing protocol | Skills, `_lib/` helpers, the driver, and `agents/code-reviewer.md` don't violate a declared invariant. |
| Contract   | `self-contract-auditor`   | `docs/contract.md` | Producer↔consumer artifact protocol is symmetric: `write-task.sh` / capture flows ↔ `validate.sh` / `roadmap*.sh` parsers ↔ consumer rules, plus the driver contract and the plugin manifest. |
| Docs-sync  | `self-docs-sync-auditor`  | `ls skills/`, `ls skills/_lib/`, `ls agents/`, frontmatter | `README.md`, `CLAUDE.md`, `docs/`, `CONTRIBUTING.md`, and `website/` reflect what is on disk. |

All three are **read-only** named agents at `.claude/agents/self-{invariants,contract,docs-sync}-auditor.md`, with `tools: Read, Grep, Glob, Bash` (no `Edit`/`Write` — read-only is runtime-enforced). They read the repo themselves; the main thread does not paste file contents into their prompts. Fixes happen only in the main thread (Step 4).

## Instructions

### Step 1: Gather context

In one parallel batch:
- `ls skills/ skills/_lib/ agents/ .claude/agents/` — the live roster (folder names are canonical slugs) and a sanity check that the three self-* auditor files exist.
- `git status --porcelain` — flag a dirty tree to the user before starting (findings against working state may diverge from `HEAD`).
- Read `.claude/.audit-baseline.json` if it exists (prior ratchet metrics; absent on first run — treat as no baseline).
- Read `CLAUDE.md` in full (the main thread needs it to judge skip reasons in Step 4).

Do not pre-read the skill bundle, the helpers, or the docs — each agent reads its own set, and the main thread reads a file only when merging or fixing a finding in it.

### Step 2: Run three agents in parallel

Send **one tool message** with three `Agent` calls, `subagent_type` set to:
- `self-invariants-auditor`
- `self-contract-auditor`
- `self-docs-sync-auditor`

If any of those agent files is missing under `.claude/agents/`, stop and tell the user which agent file is missing — do not fall back to inline prompts (it would lose the read-only allowlist guarantee).

#### Per-call prompt

```
Audit this repo against your lens. Read the files listed below yourself
(Read / Grep / Glob) — nothing is pasted here. Return findings in the
format defined in your agent prompt.

--- Repo root ---
{absolute path to repo root}

--- Scope hint ---
{$ARGUMENTS, or "full repo"}

--- Live roster (ls skills/ skills/_lib/ agents/) ---
{Step 1 output}

--- Your read set ---
{the lens's row from the table below}
```

Read set per lens:

| Lens | Read set |
|------|----------|
| Invariants | `CLAUDE.md`; every `skills/*/SKILL.md`; every file under `skills/_lib/` (`*.sh`, `*.md`, `roadmap-driver.js`, `templates/`); `skills/validate/validate.sh`; `agents/code-reviewer.md`. |
| Contract | `docs/contract.md` (source of truth, in full); every `skills/*/SKILL.md`; every file under `skills/_lib/`; `skills/validate/validate.sh`; `agents/code-reviewer.md`; `.claude-plugin/plugin.json`. |
| Docs-sync | `README.md`; `CLAUDE.md`; every file under `docs/`; `CONTRIBUTING.md`; `website/guide/*.md`, `website/reference/*.md` and `website/.vitepress/config.mts` (sidebar, version label); the frontmatter of every `skills/*/SKILL.md`; `.claude-plugin/plugin.json`. |

**Scope hint.** When `$ARGUMENTS` names a skill, the agent still reads its full read set (lenses cross-reference), but reports only findings located in that skill or in a file that produces for / consumes from it.

### Step 3: Merge and report

1. Parse each agent's reply into findings using its declared schema. An agent that returns the literal `no findings` (its declared empty sentinel) contributes zero findings — do not parse the sentinel as a finding.
2. **Deduplicate** cross-lens overlap on the shared `location` field: same `file:line` (or same file when one side is file-wide) with overlapping `problem` text → keep the more specific lens (Contract beats Docs-sync beats Invariants when they collide on the same anchor).
3. **Sort**: high → med → low; within severity by file, then line.
4. Render to chat as a single report, headed in the chat's language, findings in English:

   ```markdown
   ## self-audit — N findings (Hh / Mm / Ll)

   | # | Lens | Sev | Conf | Location | Problem | Fix |
   |---|------|-----|------|----------|---------|-----|
   | 1 | Invariants | high | 95 | `skills/to-plan/SKILL.md:42` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Source: Invariants | Contract | Docs-sync`, `Confidence: <0-100>`, `Status: pending`).

5. **Do not write findings artifacts to disk.** The chat report is the deliverable. The one sanctioned on-disk write is the ratchet baseline (Step 6) — a single gitignored metrics file, not a parallel artifact tree.

### Step 4: Apply fixes — confidence-gated, then proven

**Outcome enum (closed — do not invent tokens):** `pending` | `fixed` | `skipped-not-reproduced` | `skipped-out-of-scope` | `skipped-underspecified`.

After rendering the report, consider for auto-apply only findings that pass the gate: **severity ∈ {high, med} AND confidence ≥ 80**. Findings below the gate (low severity, or confidence < 80) stay `pending` — surfaced in the report for manual review, never auto-edited. Work through gate-passing findings in severity order (high → med), editing via `Edit` in the main thread.

For each gate-passing finding, in order:

1. **Prove it.** The agent's confidence is self-reported. Read the anchor in the current file and confirm the problem exists as stated — the quoted text is there, the roster claim matches `ls`, the parser really rejects the template. If it does not reproduce, mark `skipped-not-reproduced` and move on.
2. **Check the fix is whole.** This repo's editing protocol ties some edits to others; a half-applied fix creates the next drift. Mark `skipped-underspecified` instead of applying when:
   - it edits a `skills/*/SKILL.md` and the `Fix` does not also cover the matching `README.md` / `docs/contract.md` (and `website/` page, when user-facing behavior changes) — `CLAUDE.md` § Editing protocol requires them in the same commit;
   - it edits a bash helper or the driver and does not also update its case file under `tests/`;
   - it changes a producer template without the matching parser side, or vice versa (Contract findings are paired by definition);
   - the `Fix` field is too vague to act on without guessing.
3. **Check for conflict.** If the fix contradicts an explicit decision elsewhere in `CLAUDE.md` or `docs/contract.md`, mark `skipped-out-of-scope` (do not skip merely because a fix looks risky).
4. **Apply** and mark `fixed` (in memory only); do **not** rewrite the chat report between fixes.

Never touch `CHANGELOG.md` or `.claude-plugin/plugin.json`'s `version` — both need explicit user confirmation per `CLAUDE.md`. A finding that requires either stays `pending`.

**Never** stage or commit. Leave the working tree dirty for the user to review.

### Step 5: Verification

If no fix was applied, skip this step.

Otherwise, in one parallel batch:
- Run `bash tests/run.sh` — the repo's own suite. It covers every bash helper, the driver, and `tests/skill-injections.test.sh`, which catches a stray `!`-injection an edited `SKILL.md` might have gained. A red suite means the offending edit is reverted and its finding re-marked `pending`.
- Re-read each edited file once (Read, not `cat`) and confirm the change landed cleanly.
- Re-emit a one-line summary: `Verified: K/K fixes intact, tests <pass|fail>.`

### Step 6: Final report

In the chat's language, terse:

- `Findings`: total (h/m/l).
- `Fixed`: K, `Skipped`: M (with reasons), `Pending`: P (below gate — manual review).
- `Verification`: pass / fail / n/a.
- Reminder: files were edited; review with `git diff` before commit.

#### Ratchet

**Only on a full-repo run.** A scoped run (non-empty `$ARGUMENTS`) sees a fraction of the repo, so comparing it against a full-repo baseline — or overwriting that baseline with it — would fake a trend. On a scoped run render `Ratchet: skipped (scoped run).` and do not write the file.

On a full-repo run, compare against the baseline read in Step 1 and render a trend block:

```
Ratchet (previous → current):
  findings_total: <p> → <c>  <▪ flat | ↓ improved | ↑ regressed>
  findings_high:  <p> → <c>  <…>
  findings_med:   <p> → <c>  <…>
  findings_low:   <p> → <c>  <…>
```

First run (no baseline read in Step 1) → render `Ratchet: baseline initialised (no prior run).`

The counts come from LLM agents and vary somewhat run to run — read the trend as a signal, not a gate.

Then **write** the new baseline to `.claude/.audit-baseline.json` (the only sanctioned on-disk write of this skill; the file is gitignored). Counts are the Step 3 totals (**pre-fix**), so the trend reflects drift caught per run, not residual:

```json
{ "version": 1, "last_run": "<ISO8601 UTC>", "metrics": { "findings_total": N, "findings_high": N, "findings_med": N, "findings_low": N } }
```

## Notes

- This skill is **local** (`.claude/skills/self-audit/` + `.claude/agents/self-*-auditor.md`). It is not installed globally and not bundled into the public skill set. To remove: delete those two paths (and the gitignored `.claude/.audit-baseline.json`).
- The ratchet baseline `.claude/.audit-baseline.json` is the **sole** on-disk artifact this skill writes (gitignored, per-clone). The skill must not modify `.gitignore` at runtime — the baseline entry is added once at bootstrap.
- Findings about `.task/` are **out of scope** (working artifacts; git history is their record — there is no archive).
- This skill must not modify `.task/` or the project's `.gitignore`.
