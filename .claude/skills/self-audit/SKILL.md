---
name: self-audit
description: Self-audit this skills repo against CLAUDE.md invariants, the artifact contract, failure-path robustness, README/CLAUDE.md/docs/website sync, and machinery that does not earn its place, via five parallel read-only subagents. Local meta-skill — independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
argument-hint: '[skill-name]'
---

Audit **this repository** (the task-pipeline skills repo itself) for drift between skills, the artifact contract, and the docs, for failure paths that end nowhere, and for machinery nothing needs. Five lenses run in parallel as named subagents: **Invariants**, **Contract**, **Robustness**, **Docs-sync**, **Leanness**.

This is a **meta-skill**. It operates on the repo's own files, not on `.task/*` artifacts. It asks one question — *does the repo obey its own declared rules?* — and each lens has an oracle: `CLAUDE.md` § "Invariants — don't break these when editing skills" and § "Editing protocol — quick rules" with the `docs/contract.md` sections their bullets link, `docs/contract.md`, the documented outputs and exit codes in `docs/contract.md` together with each skill's own declared flow, and what is actually on disk. The Leanness lens asks the inverse — *does every mechanism earn its place?* — and its oracle is proof of need: a caller on disk, a sentence in `CLAUDE.md` or `docs/contract.md` that requires it, or the fix commit that introduced it. The skill can be invoked at any time.

**Input:** Optional scope hint: $ARGUMENTS — a skill name (e.g. `to-task`) or one or more repo paths; default: full repo.

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/to-task/`, `skills/validate/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** mirror the language the user writes in for all prose (headings, summaries, the final report). Findings text stays in English — it grounds in English source files and quotes them.

**Derive, never recall.** The roster of skills, `_lib/` helpers, agents and docs changes often. Neither this skill nor its agents carry a copy of it: every roster comes from the disk at run time (`ls`, frontmatter), and every rule comes from `CLAUDE.md` / `docs/contract.md` as they read today. A hardcoded list here would itself become the drift this skill exists to catch.

## Architecture

| Lens | Local agent | Oracle | What it checks |
|------|-------------|--------|---------------|
| Invariants | `self-invariants-auditor` | `CLAUDE.md` § Invariants + § Editing protocol, and the `docs/contract.md` sections their bullets link | Skills, `_lib/` helpers, the driver, and `agents/code-reviewer.md` don't violate a declared invariant. |
| Contract   | `self-contract-auditor`   | `docs/contract.md` | Producer↔consumer artifact protocol is symmetric: `write-task.sh` / capture flows ↔ `validate.sh` / `roadmap*.sh` parsers ↔ consumer rules, plus the driver contract and the plugin manifest. |
| Robustness | `self-robustness-auditor` | `docs/contract.md` § Bash layer (§ validate.sh, § Helpers), § Agent layer and § execution shape (driver contract), plus each skill's own declared flow | Every failure, decline, rerun and no-op path ends in a defined output; success lines only after a checked operation; documented exit codes reachable and tested; shell constructs safe on bash 3.2 and 5.x, BSD and GNU tools, any locale; no term used for two things across sibling steps. |
| Docs-sync  | `self-docs-sync-auditor`  | `ls skills/`, `ls skills/_lib/`, `ls agents/`, frontmatter | `README.md`, `CLAUDE.md`, `docs/`, `CONTRIBUTING.md`, `website/` and any `.claude/rules/*.md` reflect what is on disk. |
| Leanness   | `self-leanness-auditor`   | Proof of need: `git grep` for callers, `CLAUDE.md` and `docs/contract.md` for a sentence that requires it, `git log -S` / `git blame` for the fix that introduced it | Nothing in the skills, `_lib/` helpers, the driver or `agents/code-reviewer.md` lacks a need: no branch, option or function nothing reaches, no thin wrapper with one caller, no guard for a state the callers rule out, no rule restated in full where a pointer to its owner would do, no mode that adds branches but no capability, no state or output nobody reads. |

All five are **read-only** named agents at `.claude/agents/self-{invariants,contract,robustness,docs-sync,leanness}-auditor.md`, with `tools: Read, Grep, Glob, Bash`. They carry no `Edit`/`Write` tools, and Bash is theirs for reading and searching only — that rule is an instruction in each agent's prompt, not a runtime guarantee: nothing stops a Bash command from writing. They read the repo themselves; the main thread does not paste file contents into their prompts.

The deliverable is the **report**. The skill edits nothing on its own: after the report it asks the user what to fix (Step 4), and only the findings the user picked are fixed — by Sonnet subagents, never by the lenses or the main thread (Step 5). The main thread's only edits undo a fix that breaks the suite or the re-audit (Step 6).

## Instructions

### Step 1: Gather context

In one parallel batch:
- `ls skills/ skills/_lib/ agents/ .claude/agents/` — the live roster (folder names are canonical slugs) and a sanity check that the five self-* auditor files exist.
- `git status --porcelain` — flag a dirty tree to the user before starting (findings against working state may diverge from `HEAD`).
- Read `CLAUDE.md` in full (the main thread needs it to merge findings, and in Step 5 to batch each fix with the files its Editing protocol ties to it).

Do not pre-read the skill bundle, the helpers, or the docs — each agent reads its own set, and the main thread reads a file only when merging a finding in it, or after the fixes, to check or undo one.

### Step 2: Run five agents in parallel

Send **one tool message** with five `Agent` calls, `subagent_type` set to:
- `self-invariants-auditor`
- `self-contract-auditor`
- `self-robustness-auditor`
- `self-docs-sync-auditor`
- `self-leanness-auditor`

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
| Docs-sync | `README.md`; `CLAUDE.md`; every file under `docs/`; `CONTRIBUTING.md`; `website/index.md`, `website/guide/*.md`, `website/reference/*.md` and `website/.vitepress/config.mts` (sidebar, version label); every `.claude/rules/*.md`, when that directory exists; the frontmatter of every `skills/*/SKILL.md`; `.claude-plugin/plugin.json`. |
| Leanness | `CLAUDE.md`; `docs/contract.md` (in full — it is where a mechanism's need is stated); every `skills/*/SKILL.md`; every file under `skills/_lib/`; `skills/validate/validate.sh`; `agents/code-reviewer.md`; every `tests/*.test.sh`, read as evidence of what is exercised, not as audit targets. |

**Scope hint.** Empty `$ARGUMENTS` is a full-repo run: each lens gets its table row. Otherwise the main thread resolves the scope before Step 2:

- **Scoped files.** A name that is a folder in `ls skills/` means the files in `skills/<name>/`; anything else is a repo path, and every path must exist — if one does not, stop and tell the user which.
- **Scoped read set, per lens** — the lens's oracle (Invariants: `CLAUDE.md` and the contract sections its bullets link; Contract: `docs/contract.md`; Robustness: `docs/contract.md` § Bash layer, § Agent layer and § `roadmap-to-workflow` execution shape; Docs-sync: none, its oracle is the disk; Leanness: `CLAUDE.md` and `docs/contract.md`), plus the scoped files, plus every file of the lens's full read set that names a scoped file (`git grep -l -F` on its path, and on the bare name for a skill) or that a scoped file names (a path it cites or links).

### Step 3: Merge and report

1. Parse each agent's reply with the one finding schema every lens declares under `## Output format — strict`: required `severity`, `confidence`, `category`, `location`, `evidence`, `problem`, `fix`; optional `invariant`, `producer`, `consumer`. A finding missing a required field stays in the report but is never dispatched to a fixer in Step 5. An agent that returns the literal `no findings` (its declared empty sentinel) contributes zero findings — do not parse the sentinel as a finding.
2. **Merge** cross-lens duplicates on `(location, category)`: the same `location` (same `file:line`, or the same file when one side is file-wide) and the same defect class in `category` (each lens words its labels differently — compare what they name, not the spelling) become one row. The row takes `problem`, `fix` and `confidence` from the highest-priority lens among them — Contract, then Robustness, then Docs-sync, then Invariants, then Leanness — and the highest `severity` of any of them; it keeps every lens's `evidence` and optional fields, and its `Lens` lists every lens that reported it (e.g. `Contract + Invariants`).
3. **Sort**: high → med → low; within severity by file, then line.
4. Render to chat as a single report, headed in the chat's language, findings in English:

   ```markdown
   ## self-audit — N findings (Hh / Mm / Ll)

   | # | Lens | Sev | Conf | Location | Problem | Fix |
   |---|------|-----|------|----------|---------|-----|
   | 1 | Invariants | high | 95 | `skills/to-task/SKILL.md:42` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Source: <its Lens value>`, `Confidence: <0-100>`, `Evidence: <evidence>`, `Status: pending`).

### Step 4: Ask what to fix

A finding is **dispatchable** unless it misses a required field (Step 3) or its fix needs `CHANGELOG.md` or the `version` in `.claude-plugin/plugin.json` — `CLAUDE.md` wants an explicit request for those, and picking a whole set is not one. The others stay `pending`. With no dispatchable finding, skip to Step 7.

Otherwise count **N**, the dispatchable findings, and **H**, the `high` ones among them, then ask one single-select `AskUserQuestion` in the chat's language:

- **Fix all (N)**: every dispatchable finding.
- **Fix critical (H)**: only the dispatchable `high` findings.
- **Fix nothing**: keep the report as it is.

Drop the critical option when H = 0 or H = N: it would repeat one of the other two, and two options remain. A free-text answer that names findings by `#` picks the dispatchable ones among them; any other free text counts as **Fix nothing**.

**Fix nothing** goes to Step 7 with every finding `pending`. Otherwise the picked set goes to Step 5.

### Step 5: Apply fixes with Sonnet subagents

**Outcome enum (closed — do not invent tokens):** `pending` | `fixed` | `skipped-not-reproduced` | `skipped-out-of-scope` | `skipped-underspecified`.

1. **Baseline.** In one parallel batch, run `git stash create` and `git status --porcelain`. The first records the **baseline** Step 6 diffs the fixes against: it prints the SHA of a commit that snapshots the tracked working state, or nothing when the tree is clean; the baseline is that SHA, or `HEAD` when nothing was printed. It only writes objects — the snapshot's commits, trees and blobs: the stash list, which every worktree and session shares, is left untouched, so there is nothing to drop afterwards. Untracked files are not in the snapshot; the second call lists them (`??`). Note both in the conversation — shell state does not survive between calls. The baseline is taken here, after the pick, so edits made while the audit ran or the question waited are not blamed on a fixer.
2. **Batch by file.** A picked finding claims the file in its `location`, every file its `fix` names, and the files `CLAUDE.md` § Editing protocol ties to those: `README.md` and `docs/contract.md` for a `skills/*/SKILL.md`, and its case file under `tests/` for a bash helper or the driver. Two findings share a batch when they claim a file in common, followed transitively. Batches then share no claimed file, so no two fixers edit the same claimed file. Within a batch, order high → med → low, then by file and line.
3. **Dispatch.** Send **one tool message** with one `Agent` call per batch: `subagent_type: general-purpose`, `model: sonnet`, and no `isolation` — the fixes must land in this working tree, where Step 6 checks them.
4. **Record.** When every fixer has returned, parse each reply and set each finding's outcome in memory, with its changes: Step 6 undoes a fix with them. A finding the reply does not cover stays `pending`. Take the edited files from git, not from the replies: `git diff --name-only <baseline>`, plus every untracked path `git status --porcelain` shows now and did not show in item 1. Step 6 scopes its re-audit to those files. The Step 7 report names a file a fixer edited outside its batch (listed under `outside:`, which keeps the edit), and any edited file no reply accounts for — a fixer that failed mid-run leaves those. Do **not** rewrite the chat report between batches.

The fixers never stage or commit: the working tree stays dirty for the user to review.

#### Per-call prompt

```
You fix findings from a /self-audit run over this repository. Work through
your findings in the order given, editing with Edit, one occurrence per
call (no replace_all); use Write only to create a file and rm only to
delete one. Never stage or commit. Never run tests/run.sh: other fixers
are editing in parallel, and the suite runs once after all of you. Never
touch CHANGELOG.md, the "version" in .claude-plugin/plugin.json, anything
under .task/, or .gitignore: a fix that needs one is skipped-out-of-scope.

--- Repo root ---
{absolute path to repo root}

--- Read first ---
CLAUDE.md in full: its Editing protocol ties some edits to others.

--- Your findings ---
{the batch's findings, each with its #, its Lens and every field it carries}

--- Your files ---
{every file the batch claims}
Edit only these. When a fix is not whole without another file, edit that
file too and list it under outside:, unless another fixer owns it:
{every file the other batches claim, or none}

--- The whole report (context only, not yours to fix) ---
{the merged table}

--- For each finding, in order ---
1. Prove it. Confidence is self-reported. Read the anchor in the current
   file and confirm the problem exists as stated: the quoted text is there,
   the roster claim matches ls, the parser really rejects the template.
   When proving it means running a helper or validate.sh, do it in a temp
   dir with AI_DIR exported to a .task/ inside it (holding a minimal
   CLAUDE.md) and CLAUDE_PROJECT_DIR unset, never from inside the repo: its
   git config task.root points at the live dogfood .task/. If it does not
   reproduce: skipped-not-reproduced.
   A Leanness finding removes rather than repairs, so its proof goes
   further: re-run git grep for callers and git log -S on the text it would
   remove. When a fix commit introduced that text, or another finding in
   the whole report relies on it: skipped-out-of-scope.
2. Check the fix is whole. A half-applied fix creates the next drift.
   skipped-underspecified, instead of editing, when the files you may
   edit cannot make it whole:
   - it edits a skills/*/SKILL.md and cannot also cover the matching
     README.md and docs/contract.md (and the website/ page, when
     user-facing behavior changes);
   - it edits a bash helper or the driver and cannot also update its
     case file under tests/;
   - it changes a producer template and cannot change the matching parser
     side, or the reverse;
   - the fix is too vague to act on without guessing.
3. Check for conflict. If the fix contradicts an explicit decision in
   CLAUDE.md or docs/contract.md: skipped-out-of-scope. Do not skip merely
   because a fix looks risky.
4. Apply it: fixed.

--- Reply format — strict ---
One entry per finding, then the outside: line, nothing else:

- id: <#>
  outcome: fixed | skipped-not-reproduced | skipped-out-of-scope | skipped-underspecified
  reason: <one sentence; omit when fixed>
  edits:            (only when fixed; one per change, verbatim, in order)
    - file: <path>
      old: <exact old_string>
      new: <exact new_string>
    - file: <path>
      whole: created | deleted      (a file made with Write or removed)
outside: <files edited outside "Your files", or none>
```

### Step 6: Verification

If Step 5 found no edited file, skip this step.

Otherwise:

1. **Suite and re-read**, in one parallel batch:
   - Run `bash tests/run.sh` — the repo's own suite. It covers every bash helper, the driver, and `tests/skill-injections.test.sh`, which catches a stray `!`-injection an edited `SKILL.md` might have gained. A red suite means the offending fix is undone the way item 2 undoes a regression, and its finding re-marked `pending`.
   - Re-read each edited file once (Read, not `cat`) and confirm the change landed cleanly.
2. **Re-audit — one round.** After the suite, send one tool message re-running each lens that reported a `fixed` finding (every lens in a merged row's `Lens`), plus Docs-sync whenever an edited file is a doc (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, anything under `docs/` or `website/`). Same agents and per-call prompt as Step 2, scoped (Step 2 § Scope hint) to the edited files Step 5 listed.
   - `git diff <baseline> -- <edited files>` shows the text the fixes introduced (its `+` lines), without what was already in the tree when the fixers started. A file untracked when the baseline was taken is not in it — compare it against the fixer's reported edits instead.
   - A new finding whose `evidence` quotes text a fix introduced is a **regression**. Undo that fix in the main thread, last change first: one inverse `Edit` per replacement its fixer reported, `new` back to `old`; a file it created is removed, and one it deleted restored with `git show <baseline>:<path> > <path>`. Set its finding back to `pending`. If an inverse no longer applies — a later fix changed the same text — leave the file as it is and say so in the report.
   - Any other new finding does not trace to a fix: add it to the report as `pending`, never fixed in this run.
   - If a fix was undone, run `bash tests/run.sh` once more. Do not re-audit the undos — one round only.
3. Re-emit a one-line summary: `Verified: K/K fixes intact, tests <pass|fail>, re-audit: R regression(s) undone.`

### Step 7: Final report

In the chat's language, terse:

- `Findings`: total (h/m/l).
- `Picked`: the Step 4 answer, or n/a when Step 4 asked nothing.
- `Fixed`: K, `Skipped`: M (with reasons), `Pending`: P (not picked, not dispatchable, not covered by a fixer's reply, or undone).
- `Outside edits`: the files a fixer edited beyond its batch, and any edited file no reply accounts for — omit when none.
- `Verification`: pass / fail / n/a.
- `Re-audit`: R regressions undone (naming any whose inverse no longer applied), N new findings added as `pending` — or n/a when nothing was fixed.
- Only when a file was edited: review with `git diff` before commit.

## Notes

- This skill is **local** (`.claude/skills/self-audit/` + `.claude/agents/self-*-auditor.md`). It is not installed globally and not bundled into the public skill set. To remove: delete those two paths.
- It keeps no state between runs: the report lives only in chat, and no file is written except by the Step 5 fixes, which run only on the user's pick. Step 5's `git stash create` adds a few unreferenced objects under `.git/`, which git's own garbage collection removes.
- Findings about `.task/` are **out of scope** (working artifacts; git history is their record — there is no archive).
- This skill must not modify `.task/` or the project's `.gitignore`.
