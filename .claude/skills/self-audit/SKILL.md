---
name: self-audit
description: Self-audit this skills repo against CLAUDE.md invariants, the artifact contract, failure-path robustness, and README/CLAUDE.md/docs/website sync via four parallel read-only subagents. Local meta-skill — independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
argument-hint: '[skill-name]'
---

Audit **this repository** (the task-pipeline skills repo itself) for drift between skills, the artifact contract, and the docs, and for failure paths that end nowhere. Four lenses run in parallel as named subagents: **Invariants**, **Contract**, **Robustness**, **Docs-sync**.

This is a **meta-skill**. It operates on the repo's own files, not on `.task/*` artifacts. It asks one question — *does the repo obey its own declared rules?* — and each lens has an oracle: `CLAUDE.md` § "Invariants — don't break these when editing skills" and § "Editing protocol — quick rules" with the `docs/contract.md` sections their bullets link, `docs/contract.md`, the documented outputs and exit codes in `docs/contract.md` together with each skill's own declared flow, and what is actually on disk. The skill can be invoked at any time.

**Input:** Optional scope hint: $ARGUMENTS — a skill name (e.g. `to-plan`) or one or more repo paths; default: full repo.

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/to-task/`, `skills/validate/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** mirror the language the user writes in for all prose (headings, summaries, the final report). Findings text stays in English — it grounds in English source files and quotes them.

**Derive, never recall.** The roster of skills, `_lib/` helpers, agents and docs changes often. Neither this skill nor its agents carry a copy of it: every roster comes from the disk at run time (`ls`, frontmatter), and every rule comes from `CLAUDE.md` / `docs/contract.md` as they read today. A hardcoded list here would itself become the drift this skill exists to catch.

## Architecture

| Lens | Local agent | Oracle | What it checks |
|------|-------------|--------|---------------|
| Invariants | `self-invariants-auditor` | `CLAUDE.md` § Invariants + § Editing protocol, and the `docs/contract.md` sections their bullets link | Skills, `_lib/` helpers, the driver, and `agents/code-reviewer.md` don't violate a declared invariant. |
| Contract   | `self-contract-auditor`   | `docs/contract.md` | Producer↔consumer artifact protocol is symmetric: `write-task.sh` / capture flows ↔ `validate.sh` / `roadmap*.sh` parsers ↔ consumer rules, plus the driver contract and the plugin manifest. |
| Robustness | `self-robustness-auditor` | `docs/contract.md` § Bash layer (§ validate.sh, § Helpers), § Agent layer and § execution shape (driver contract), plus each skill's own declared flow | Every failure, decline, rerun and no-op path ends in a defined output; success lines only after a checked operation; documented exit codes reachable and tested; shell constructs safe on bash 3.2 and 5.x, BSD and GNU tools, any locale; no term used for two things across sibling steps. |
| Docs-sync  | `self-docs-sync-auditor`  | `ls skills/`, `ls skills/_lib/`, `ls agents/`, frontmatter | `README.md`, `CLAUDE.md`, `docs/`, `CONTRIBUTING.md`, `website/`, `evals/README.md` and any `.claude/rules/*.md` reflect what is on disk. |

All four are **read-only** named agents at `.claude/agents/self-{invariants,contract,robustness,docs-sync}-auditor.md`, with `tools: Read, Grep, Glob, Bash`. They carry no `Edit`/`Write` tools, and Bash is theirs for reading and searching only — that rule is an instruction in each agent's prompt, not a runtime guarantee: nothing stops a Bash command from writing. They read the repo themselves; the main thread does not paste file contents into their prompts. Fixes happen only in the main thread (Step 4).

## Instructions

### Step 1: Gather context

In one parallel batch:
- `ls skills/ skills/_lib/ agents/ .claude/agents/` — the live roster (folder names are canonical slugs) and a sanity check that the four self-* auditor files exist.
- `git status --porcelain` — flag a dirty tree to the user before starting (findings against working state may diverge from `HEAD`).
- `git stash create` — records the **baseline** Step 5 diffs the fixes against. It prints the SHA of a commit that snapshots the tracked working state, or nothing when the tree is clean; the baseline is that SHA, or `HEAD` when nothing was printed. Note it in the conversation — shell state does not survive between calls. It only writes objects — the snapshot's commits, trees and blobs: the stash list, which every worktree and session shares, is left untouched, so there is nothing to drop afterwards. Untracked files are not in the snapshot.
- Read `CLAUDE.md` in full (the main thread needs it to judge skip reasons in Step 4).

Do not pre-read the skill bundle, the helpers, or the docs — each agent reads its own set, and the main thread reads a file only when merging or fixing a finding in it.

### Step 2: Run four agents in parallel

Send **one tool message** with four `Agent` calls, `subagent_type` set to:
- `self-invariants-auditor`
- `self-contract-auditor`
- `self-robustness-auditor`
- `self-docs-sync-auditor`

If any of those agent files is missing under `.claude/agents/`, stop and tell the user which agent file is missing — do not fall back to inline prompts (they would lose the agent file's tool list, which keeps `Edit`/`Write` out, and its read-only instructions).

#### Per-call prompt

```
Audit this repo against your lens. Read the files listed below yourself
— nothing is pasted here. Return findings in the schema defined in your
agent prompt.

--- Repo root ---
{absolute path to repo root}

--- Scope ---
{"full repo", or the scoped files, followed by: "Report only findings that
involve a scoped file: located in one, or in a file whose statement about
one is wrong."}

--- Checked mechanically ---
tests/xref.test.sh pins: relative links and anchors, backticked repo
paths, `<file>.md §` citations, `Step N` in SKILL.md, helper test
coverage, rule globs — do not report those.

--- Live roster (ls skills/ skills/_lib/ agents/) ---
{Step 1 output}

--- Your read set ---
{the lens's row from the table below, or on a scoped run its scoped read set}
```

Read set per lens:

| Lens | Read set |
|------|----------|
| Invariants | `CLAUDE.md`; every `docs/contract.md` section linked from a bullet in `CLAUDE.md` § Invariants or § Editing protocol; every `skills/*/SKILL.md`; every file under `skills/_lib/` (`*.sh`, `*.md`, `roadmap-driver.js`, `templates/`); `skills/validate/validate.sh`; `agents/code-reviewer.md`. |
| Contract | `docs/contract.md` (source of truth, in full); every `skills/*/SKILL.md`; every file under `skills/_lib/`; `skills/validate/validate.sh`; `agents/code-reviewer.md`; `.claude-plugin/plugin.json`. |
| Robustness | `docs/contract.md` § Bash layer, § Agent layer and § `roadmap-to-workflow` execution shape; every `skills/*/SKILL.md`; every file under `skills/_lib/`; `skills/validate/validate.sh`; `agents/code-reviewer.md`; every `tests/*.test.sh` and `tests/lib.sh`, which they source. |
| Docs-sync | `README.md`; `CLAUDE.md`; every file under `docs/`; `CONTRIBUTING.md`; `website/index.md`, `website/guide/*.md`, `website/reference/*.md` and `website/.vitepress/config.mts` (sidebar, version label); `evals/README.md`; every `.claude/rules/*.md`, when that directory exists; the frontmatter of every `skills/*/SKILL.md`; `.claude-plugin/plugin.json`. |

**Scope hint.** Empty `$ARGUMENTS` is a full-repo run: each lens gets its table row. Otherwise the main thread resolves the scope before Step 2:

- **Scoped files.** A name that is a folder in `ls skills/` means the files in `skills/<name>/`; anything else is a repo path, and every path must exist — if one does not, stop and tell the user which.
- **Scoped read set, per lens** — the lens's oracle (Invariants: `CLAUDE.md` and the contract sections its bullets link; Contract: `docs/contract.md`; Robustness: `docs/contract.md` § Bash layer, § Agent layer and § `roadmap-to-workflow` execution shape; Docs-sync: none, its oracle is the disk), plus the scoped files, plus every file of the lens's full read set that names a scoped file (`git grep -l -F` on its path, and on the bare name for a skill) or that a scoped file names (a path it cites or links).

### Step 3: Merge and report

1. Parse each agent's reply with the one finding schema every lens declares under `## Output format — strict`: required `severity`, `confidence`, `category`, `location`, `evidence`, `problem`, `fix`; optional `invariant`, `producer`, `consumer`. A finding missing a required field stays in the report but never passes the Step 4 gate. An agent that returns the literal `no findings` (its declared empty sentinel) contributes zero findings — do not parse the sentinel as a finding.
2. **Merge** cross-lens duplicates on `(location, category)`: the same `location` (same `file:line`, or the same file when one side is file-wide) and the same defect class in `category` (each lens words its labels differently — compare what they name, not the spelling) become one row. The row takes `problem`, `fix` and `confidence` from the highest-priority lens among them — Contract, then Robustness, then Docs-sync, then Invariants — and the highest `severity` of any of them; it keeps every lens's `evidence` and optional fields, and its `Lens` lists every lens that reported it (e.g. `Contract + Invariants`).
3. **Sort**: high → med → low; within severity by file, then line.
4. Render to chat as a single report, headed in the chat's language, findings in English:

   ```markdown
   ## self-audit — N findings (Hh / Mm / Ll)

   | # | Lens | Sev | Conf | Location | Problem | Fix |
   |---|------|-----|------|----------|---------|-----|
   | 1 | Invariants | high | 95 | `skills/to-plan/SKILL.md:42` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Source: <its Lens value>`, `Confidence: <0-100>`, `Evidence: <evidence>`, `Status: pending`).

5. **Do not write findings artifacts to disk.** The chat report is the deliverable; the only files this skill changes are the ones Step 4 fixes.

### Step 4: Apply fixes — confidence-gated, then proven

**Outcome enum (closed — do not invent tokens):** `pending` | `fixed` | `skipped-not-reproduced` | `skipped-out-of-scope` | `skipped-underspecified`.

After rendering the report, consider for auto-apply only findings that pass the gate: **severity ∈ {high, med} AND confidence ≥ 80**. Findings below the gate (low severity, or confidence < 80) stay `pending` — surfaced in the report for manual review, never auto-edited. Work through gate-passing findings in severity order (high → med), editing via `Edit` in the main thread.

For each gate-passing finding, in order:

1. **Prove it.** The agent's confidence is self-reported. Read the anchor in the current file and confirm the problem exists as stated — the quoted text is there, the roster claim matches `ls`, the parser really rejects the template. When proving it means running a helper or `validate.sh`, do it in a temp dir with `AI_DIR` exported to a `.task/` inside it (holding a minimal `CLAUDE.md`) and `CLAUDE_PROJECT_DIR` unset, never from inside the repo — its `git config task.root` points at the live dogfood `.task/`. If it does not reproduce, mark `skipped-not-reproduced` and move on.
2. **Check the fix is whole.** This repo's editing protocol ties some edits to others; a half-applied fix creates the next drift. Mark `skipped-underspecified` instead of applying when:
   - it edits a `skills/*/SKILL.md` and the `Fix` does not also cover the matching `README.md` / `docs/contract.md` (and `website/` page, when user-facing behavior changes) — `CLAUDE.md` § Editing protocol requires them in the same commit;
   - it edits a bash helper or the driver and does not also update its case file under `tests/`;
   - it changes a producer template without the matching parser side, or vice versa (Contract findings are paired by definition);
   - the `Fix` field is too vague to act on without guessing.
3. **Check for conflict.** If the fix contradicts an explicit decision elsewhere in `CLAUDE.md` or `docs/contract.md`, mark `skipped-out-of-scope` (do not skip merely because a fix looks risky).
4. **Apply** and mark `fixed` (in memory only), noting the files it edited — Step 5 scopes its re-audit to them; do **not** rewrite the chat report between fixes.

Never touch `CHANGELOG.md` or `.claude-plugin/plugin.json`'s `version` — both need explicit user confirmation per `CLAUDE.md`. A finding that requires either stays `pending`.

**Never** stage or commit. Leave the working tree dirty for the user to review.

### Step 5: Verification

If no fix was applied, skip this step.

Otherwise:

1. **Suite and re-read**, in one parallel batch:
   - Run `bash tests/run.sh` — the repo's own suite. It covers every bash helper, the driver, and `tests/skill-injections.test.sh`, which catches a stray `!`-injection an edited `SKILL.md` might have gained. A red suite means the offending edit is reverted and its finding re-marked `pending`.
   - Re-read each edited file once (Read, not `cat`) and confirm the change landed cleanly.
2. **Re-audit — one round.** After the suite, send one tool message re-running each lens that reported a `fixed` finding (every lens in a merged row's `Lens`), plus Docs-sync whenever a fix edited a doc (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `evals/README.md`, anything under `docs/` or `website/`). Same agents and per-call prompt as Step 2, scoped (Step 2 § Scope hint) to the files Step 4 edited.
   - `git diff <baseline> -- <edited files>` shows the text the fixes introduced (its `+` lines), without what was already in the tree when the run began. A file that was untracked at Step 1 is not in the baseline — compare it against the edit you made instead.
   - A new finding whose `evidence` quotes text a fix introduced is a **regression**: undo that fix with the inverse `Edit` (its new text back to its old text) and set its finding back to `pending`. If the inverse no longer applies — a later fix changed the same text — leave the file as it is and say so in the report.
   - Any other new finding does not trace to a fix: add it to the report as `pending`, never auto-applied.
   - If a fix was undone, run `bash tests/run.sh` once more. Do not re-audit the undos — one round only.
3. Re-emit a one-line summary: `Verified: K/K fixes intact, tests <pass|fail>, re-audit: R regression(s) undone.`

### Step 6: Final report

In the chat's language, terse:

- `Findings`: total (h/m/l).
- `Fixed`: K, `Skipped`: M (with reasons), `Pending`: P (below gate — manual review).
- `Verification`: pass / fail / n/a.
- `Re-audit`: R regressions undone (naming any whose inverse no longer applied), N new findings added as `pending` — or n/a when nothing was fixed.
- Reminder: files were edited; review with `git diff` before commit.

## Notes

- This skill is **local** (`.claude/skills/self-audit/` + `.claude/agents/self-*-auditor.md`). It is not installed globally and not bundled into the public skill set. To remove: delete those two paths.
- It keeps no state between runs: no file is written except by the Step 4 fixes. Step 1's `git stash create` adds a few unreferenced objects under `.git/`, which git's own garbage collection removes.
- Findings about `.task/` are **out of scope** (working artifacts; git history is their record — there is no archive).
- This skill must not modify `.task/` or the project's `.gitignore`.
