---
name: self-audit
description: Self-audit this skills repo against CLAUDE.md invariants, the v3 artifact contract, and README/CLAUDE.md/docs sync via three parallel read-only subagents. Local meta-skill — independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
---

Audit **this repository** (the task-pipeline skills repo itself) for drift between skills, the artifact contract, and the user-facing docs. Three lenses run in parallel as named subagents: **Invariants**, **Contract**, **Docs-sync**.

This is a **meta-skill**. It operates on the repo's own files (`skills/*/SKILL.md`, `skills/_lib/*.sh`, `skills/validate/validate.sh`, `CLAUDE.md`, `README.md`, `docs/contract.md`), not on `.task/*` artifacts. The pipeline it audits is the v3 chat-first protocol — capture in chat, then `to-task` / `to-plan` / `to-roadmap` fix the discussion into a `.task/` artifact that a plain session (or `roadmap-to-workflow`) executes directly. There is no `design` / `build` / `ship` / `auto-roadmap` pipeline any more, and no repo-level `agents/` directory. The skill can be invoked at any time.

**Input:** Optional scope hint: $ARGUMENTS (e.g. a single skill name to focus on; default: full repo).

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/to-task/`, `skills/validate/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** Russian (per global user instructions). Findings text stays in English (it grounds in English source files and matches the existing auditor convention).

**Why a separate set of agents?** The global `audit-{reuse,simplicity,clarity}-auditor` are tuned for code diffs (DRY, dead code, naming). This repo's content is markdown-as-prompt plus a thin `skills/_lib/` bash layer. The meaningful failure modes here are different — invariant drift, producer↔consumer mismatch, README↔code drift. Hence three repo-specific lenses.

## Architecture

| Lens | Local agent | What it checks |
|------|-------------|---------------|
| Invariants | `self-invariants-auditor` | Skills don't violate any bullet in `CLAUDE.md` § "Invariants — don't break these when editing skills". |
| Contract   | `self-contract-auditor`   | Producer↔consumer artifact protocol is symmetric (templates ↔ `validate.sh`/`roadmap.sh` parsers ↔ consumer rules), per `docs/contract.md`. |
| Docs-sync  | `self-docs-sync-auditor`  | `README.md`, `CLAUDE.md`, and `docs/contract.md` reflect the actual `skills/` directory (four user skills + `validate`). |

All three are **read-only** named agents at `.claude/agents/self-{invariants,contract,docs-sync}-auditor.md`, with `tools: Read, Grep, Glob, Bash` (no `Edit`/`Write` — read-only is runtime-enforced). Fixes happen only in the main thread (Step 4).

## Instructions

### Step 1: Gather context

In one parallel batch, run:
- `ls skills/` — full skill list (folder names = canonical slugs; expect `to-task`, `to-plan`, `to-roadmap`, `roadmap-to-workflow`, `validate`, `_lib`).
- `ls .claude/agents/` — local self-* agents (sanity check before fan-out).
- `git status --porcelain` — flag a dirty tree to the user before starting (audit findings against working state may diverge from `HEAD`).
- Read `.claude/.audit-baseline.json` if it exists (prior ratchet metrics; absent on first run — treat as no baseline).
- Read `CLAUDE.md`, `README.md`, and `docs/contract.md` in full.
- Read every `skills/*/SKILL.md` (one batched call).
- Read every bash helper `skills/_lib/*.sh` plus `skills/validate/validate.sh` (one batched call).

There is **no repo-level `agents/` directory** and **no `docs/spec/`** in v3 — do not attempt to read them. If `$ARGUMENTS` names a single skill (e.g. `to-plan`), still load the full `CLAUDE.md` + `README.md` + `docs/contract.md` (lenses cross-reference), but you may narrow the SKILL.md reads to that skill plus any skill it explicitly produces/consumes for.

### Step 2: Run three agents in parallel

Send **one tool message** with three `Agent` calls, `subagent_type` set to:
- `self-invariants-auditor`
- `self-contract-auditor`
- `self-docs-sync-auditor`

If any of those agent files is missing under `.claude/agents/`, stop and tell the user which agent file is missing — do not fall back to inline prompts (it would lose the read-only allowlist guarantee).

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
| `--- docs/contract.md ---` | — | **full file** (the contract source of truth) | full file |
| `--- Bash helpers ---` | paths + first-line description | **full text of every `skills/_lib/*.sh` + `validate.sh`** (parsers live there) | paths only |

### Step 3: Merge and report

1. Parse each agent's reply into a list of findings using its declared schema.
2. **Deduplicate** cross-lens overlap: same `(file, anchor)` with overlapping `problem` text → keep the more specific lens (Contract beats Docs-sync beats Invariants when they collide on the same anchor).
3. **Sort**: high → med → low; within severity by file, then line.
4. Render to chat as a single Russian-headed report with English findings:

   ```markdown
   ## self-audit — N findings (Hh / Mm / Ll)

   | # | Lens | Sev | Conf | Location | Problem | Fix |
   |---|------|-----|------|----------|---------|-----|
   | 1 | Invariants | high | 95 | `skills/to-plan/SKILL.md:42` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Source: Invariants | Contract | Docs-sync`, `Confidence: <0-100>`, `Status: pending`).

5. **Do not write findings artifacts to disk.** The chat report is the deliverable. The one sanctioned on-disk write is the ratchet baseline (Step 6) — a single gitignored metrics file, not a parallel artifact tree.

### Step 4: Apply fixes — confidence-gated

**Outcome enum (closed — do not invent tokens):** `pending` | `fixed` | `skipped-out-of-scope` | `skipped-underspecified`.

After rendering the report, auto-apply only findings that pass the gate: **severity ∈ {high, med} AND confidence ≥ 80**. Edit the touched files via `Edit` in the main thread, in severity order (high → med → low). Findings below the gate (low severity, or confidence < 80) stay `pending` — surfaced in the report for manual review, never auto-edited.

- After each applied fix, mark the finding `fixed` (in memory only); do **not** rewrite the chat report between fixes.
- If a fix would change a producer template, sanity-check the matching parser side (or vice versa) before applying — Contract findings are paired by definition.
- If a fix conflicts with an explicit decision elsewhere in `CLAUDE.md` or `docs/contract.md`, mark `skipped-out-of-scope` and move on (only legitimate skip reason — do not skip merely because a fix looks risky).
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
- Reminder: docs (`README.md`, `CLAUDE.md`, `docs/contract.md`) and skill files were edited; review with `git diff` before commit.

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
- Findings about `.task/` are **out of scope** (working artifacts; git history is their record — there is no archive in v3).
- This skill must not modify `.task/` or the project's `.gitignore`.
