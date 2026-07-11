---
name: self-audit
description: Self-audit this skills repo against CLAUDE.md invariants, the artifact contract, and README/CLAUDE.md sync via three parallel read-only subagents. Local meta-skill — independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
---

Audit **this repository** (the task-pipeline skills repo itself) for drift between skills, the artifact contract, and the user-facing docs. Three lenses run in parallel as named subagents: **Invariants**, **Contract**, **Docs-sync**.

This is a **meta-skill**. It operates on the repo's own files (`skills/*/SKILL.md`, `skills/*/phases/*.md`, `skills/*/*.sh`, `agents/*.md`, `CLAUDE.md`, `README.md`), not on `.task/*` artifacts. It is independent of the `/task:design` → `/task:build` → `/task:ship` pipeline (and `/task:auto-roadmap`) and can be invoked at any time.

**Input:** Optional scope hint: $ARGUMENTS (e.g. a single skill name to focus on; default: full repo).

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/bootstrap/`, `agents/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** Russian (per global user instructions). Findings text stays in English (it grounds in English source files and matches the existing auditor convention).

**Why a separate set of agents?** The global `audit-{reuse,simplicity,clarity}-auditor` are tuned for code diffs (DRY, dead code, naming). This repo's content is markdown-as-prompt + a small amount of bash. The meaningful failure modes here are different — invariant drift, producer↔consumer mismatch, README↔code drift. Hence three repo-specific lenses.

## Architecture

| Lens | Local agent | What it checks |
|------|-------------|---------------|
| Invariants | `self-invariants-auditor` | Skills don't violate any bullet in `CLAUDE.md` § "Invariants — don't break these when editing skills". |
| Contract   | `self-contract-auditor`   | Producer↔consumer artifact protocol is symmetric (templates ↔ parsers ↔ consumer rules). |
| Docs-sync  | `self-docs-sync-auditor`  | `README.md` and `CLAUDE.md` reflect the actual `skills/` + `agents/` directories. |

All three are **read-only** named agents at `.claude/agents/self-{invariants,contract,docs-sync}-auditor.md`, with `tools: Read, Grep, Glob, Bash` (no `Edit`/`Write` — read-only is runtime-enforced). Fixes happen only in the main thread (Step 4).

## Instructions

### Step 1: Gather context

In one parallel batch, run:
- `ls skills/` — full skill list (folder names = canonical slugs).
- `ls agents/` — agent files at the repo level.
- `ls .claude/agents/` — local self-* agents (sanity check before fan-out).
- `git status --porcelain` — flag a dirty tree to the user before starting (audit findings against working state may diverge from `HEAD`).
- Read `.claude/.audit-baseline.json` if it exists (prior ratchet metrics; absent on first run — treat as no baseline).
- Read `CLAUDE.md` and `README.md` in full.
- Read every `skills/*/SKILL.md` (one batched call).
- Read every bash helper `skills/*/*.sh` (one batched call).
- Read every `agents/*.md` (one batched call).

If `$ARGUMENTS` names a single skill (e.g. `audit`), still load the full `CLAUDE.md` + `README.md` + agent list (lenses cross-reference), but you may narrow the SKILL.md reads to that skill plus any skill it explicitly produces/consumes for.

### Step 2: Run three agents in parallel

Send **one tool message** with three `Agent` calls, `subagent_type` set to:
- `self-invariants-auditor`
- `self-contract-auditor`
- `self-docs-sync-auditor`

If any of those agent files is missing under `.claude/agents/`, stop and tell the user which agent file is missing — do not fall back to inline prompts (it would lose the read-only allowlist guarantee, same rule as `/task:build` audit phase).

#### Per-call prompt template

Use this skeleton; fill in the lens-specific bundle below.

```
Audit this repo against your lens. Return findings in the format defined
in your agent prompt.

--- Repo root ---
{absolute path to repo root}

--- Scope hint ---
{$ARGUMENTS or "full repo"}

--- Skill list ---
{ls skills/}

--- Agent list (skills repo) ---
{ls agents/}

--- CLAUDE.md ---
{full file contents}

{lens-specific block — see table}

--- SKILL.md bundle ---
{concatenated skills/*/SKILL.md, each preceded by `=== <relative path> ===`}

--- Bash helpers ---
{lens-specific — see table}
```

Lens-specific blocks:

| Block | Invariants | Contract | Docs-sync |
|-------|-----------|----------|-----------|
| `--- README.md ---` | — | — | full file |
| `--- agents/ contents ---` (full text of each repo-level agent file) | full | full | paths + frontmatter only |
| `--- Bash helpers ---` | paths + first-line description | **full text of every `*.sh`** (parsers live there) | paths only |

### Step 3: Merge and report

1. Parse each agent's reply into a list of findings using its declared schema.
2. **Deduplicate** cross-lens overlap: same `(file, anchor)` with overlapping `problem` text → keep the more specific lens (Contract beats Docs-sync beats Invariants when they collide on the same anchor).
3. **Sort**: high → med → low; within severity by file, then line.
4. Render to chat as a single Russian-headed report with English findings:

   ```markdown
   ## self-audit — N findings (Hh / Mm / Ll)

   | # | Lens | Sev | Conf | Location | Problem | Fix |
   |---|------|-----|------|----------|---------|-----|
   | 1 | Invariants | high | 95 | `skills/implement/SKILL.md:42` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Source: Invariants | Contract | Docs-sync`, `Confidence: <0-100>`, `Status: pending`).

5. **Do not write findings artifacts to disk.** The chat report is the deliverable. The one sanctioned on-disk write is the ratchet baseline (Step 6) — a single gitignored metrics file, not a parallel artifact tree.

### Step 4: Apply fixes — confidence-gated

**Outcome enum (closed — do not invent tokens):** `pending` | `fixed` | `skipped-out-of-scope` | `skipped-underspecified`.

After rendering the report, auto-apply only findings that pass the gate: **severity ∈ {high, med} AND confidence ≥ 80**. Edit the touched files via `Edit` in the main thread, in severity order (high → med → low). Findings below the gate (low severity, or confidence < 80) stay `pending` — surfaced in the report for manual review, never auto-edited.

- After each applied fix, mark the finding `fixed` (in memory only); do **not** rewrite the chat report between fixes.
- If a fix would change a producer template, sanity-check the matching parser side (or vice versa) before applying — Contract findings are paired by definition.
- If a fix conflicts with an explicit decision elsewhere in `CLAUDE.md`, mark `skipped-out-of-scope` and move on (only legitimate skip reason — do not skip merely because a fix looks risky).
- If a gate-passing finding's `Fix` field is too vague to act on safely, mark `skipped-underspecified` and move on rather than guessing.

**Never** stage or commit. Leave the working tree dirty for the user to review.

### Step 5: Verification

If no fix was applied, skip this step.

Otherwise, in one parallel batch:
- Run `bash skills/validate/validate.sh --help 2>&1 | head -5` to confirm the validator still parses (any syntax break is high-severity).
- For each fix that touched a producer template, re-read the file once (Read, no `cat`) and confirm the change landed cleanly.
- Re-emit a one-line summary: `Verified: K/K fixes intact.`

### Step 6: Final report

English, terse:

- `Iteration`: ad-hoc (this skill does not maintain iterations).
- `Findings`: total (h/m/l).
- `Fixed`: K, `Skipped`: M (with reasons), `Pending`: P (below gate — manual review).
- `Verification`: pass / fail / n/a.
- Reminder: docs (`README.md`, `CLAUDE.md`) and skill files were edited; review with `git diff` before commit.

#### Ratchet

Compare against the baseline read in Step 1 and render a trend block:

```
Ratchet (previous → current):
  findings_total: <p> → <c>  <▪ flat | ↓ improved | ↑ regressed>
  findings_high:  <p> → <c>  <…>
  findings_med:   <p> → <c>  <…>
  findings_low:   <p> → <c>  <…>
```

First run (no baseline read in Step 1) → render `Ratchet: baseline initialised (no prior run).`

Then **write** the new baseline to `.claude/.audit-baseline.json` (the only sanctioned on-disk write of this skill; the file is gitignored). Counts are the Step 3 totals (**pre-fix**), so the trend reflects drift caught per run, not residual:

```json
{ "version": 1, "last_run": "<ISO8601 UTC>", "metrics": { "findings_total": N, "findings_high": N, "findings_med": N, "findings_low": N } }
```

## Notes

- This skill is **local** (`.claude/skills/self-audit/` + `.claude/agents/self-*-auditor.md`). It is not installed globally and not bundled into the public skill set. To remove: delete those two paths (and the gitignored `.claude/.audit-baseline.json`).
- The ratchet baseline `.claude/.audit-baseline.json` is the **sole** on-disk artifact this skill writes (gitignored, per-clone). The skill must not modify `.gitignore` at runtime — the baseline entry is added once at bootstrap.
- Findings about `agents/audit-*-auditor.md` themselves **are** in scope — they are part of the pipeline contract.
- Findings about `.task/` are **out of scope** (working artifacts, archived by `/task:ship`).
- This skill must not modify `.task/` or the project's `.gitignore`.
