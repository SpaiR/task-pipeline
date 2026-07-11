---
name: self-improve
description: Self-improve this skills repo — surface and (safely) apply quality improvements across four parallel read-only lenses (Clarity, Leanness, Coverage, Ergonomics). Sibling of /self-audit — audit fixes rule violations, improve raises quality where no rule is broken. Local meta-skill, independent of the /task:* pipeline.
disable-model-invocation: true
user-invocable: true
---

Improve **this repository** (the task-pipeline skills repo itself) — not by fixing rule violations (that is [`/self-audit`](../self-audit/SKILL.md)), but by raising quality where nothing is broken yet. Four lenses run in parallel as named read-only subagents: **Clarity**, **Leanness**, **Coverage**, **Ergonomics**.

## improve vs audit — the split that defines this skill

`/self-audit` asks *"does the repo obey its own declared rules?"* — it has an oracle (CLAUDE.md invariants, the artifact contract, the real `skills/`/`agents/` tree), the fix direction is determined, and every gated finding is applied.

`/self-improve` asks *"nothing is violated — but where is the repo weaker than it could be?"* — there is **no oracle**. An "improvement" is a judgement call, and its direction is a design decision, not a mechanical correction. That is the literal difference between fixes (audit) and improvements (improve), and it drives the whole apply model:

- **Audit applies everything that passes its gate** — the source of truth says which way to go.
- **Improve applies only a narrow, mechanical, behavior-preserving subset automatically**, at a higher confidence bar, and **proposes** everything that changes the design for the user to greenlight. Improvements that reshape a flow, merge phases, or add a guardrail are decisions a human must nod at.

**Boundary rule (hard):** if a lens finds an actual violation of a declared rule (an invariant, a producer↔consumer mismatch, README↔code drift), that is audit's job, not improve's. The agent must set `defer: self-audit` on it and **not** propose a fix. `/self-improve` never edits under the banner of a rule violation — it only makes not-yet-broken things better.

This is a **meta-skill**. It operates on the repo's own files (`skills/*/SKILL.md`, `skills/*/phases/*.md`, `skills/*/*.sh`, `agents/*.md`, `CLAUDE.md`, `README.md`, `docs/spec/*.md`), not on `.task/*` artifacts. It is independent of the `/task:design` → `/task:build` → `/task:ship` pipeline (and `/task:auto-roadmap`) and can be invoked at any time.

**Input:**
- Optional scope hint: $ARGUMENTS (e.g. a single skill name to focus on; default: full repo).
- Optional flag `--propose-only` (alias `--dry-run`) in $ARGUMENTS: apply nothing; report both tiers only.

**Precondition (hard-stop):** This skill is local to the task-pipeline repo. Verify the working directory contains `skills/bootstrap/`, `agents/`, and `CLAUDE.md` at the repo root. If not, stop with: "This skill is local and only works inside the task-pipeline repository."

**Communication language:** Russian (per global user instructions). Findings text stays in English (it grounds in English source files and matches the existing auditor convention).

**Why a separate set of agents from self-audit?** Audit's three lenses are conformance checks (Invariants, Contract, Docs-sync) — reality-vs-declared-rule. Improve's four lenses are quality checks with no oracle. Different question, different failure modes, different apply posture — hence a separate agent set.

## Architecture

Four directions of "better" — sharper / leaner / more complete / kinder-to-the-operator. Vectors are mutually exclusive (modify in place / subtract / add internal robustness / improve human touchpoints), so cross-lens overlap is minimal.

| Lens | Local agent | Vector | Facing | What it looks for |
|------|-------------|--------|--------|-------------------|
| **Clarity** | `self-clarity-improver` | modify in place | the agent reading the prompt | Ambiguous steps, weak output templates, internal contradictions in one file — places an LLM will plausibly do the wrong thing. |
| **Leanness** | `self-leanness-improver` | subtract / link | — | Prose duplication with no single owner (→ collapse to a pointer) and over-engineering (a helper wrapping one line, a dead flag, a phase split that adds ceremony). |
| **Coverage** | `self-coverage-improver` | add robustness | the agent reading the prompt | Missing guardrails, absent worked-examples where an agent guesses, unhandled edge-cases in the flow, a missing test/doc. |
| **Ergonomics** | `self-ergonomics-improver` | modify / add | the human operator | Error / hard-stop wording, flag-name consistency across skills, next-step hints, discoverability, quality of final feedback. |

Boundaries against `/self-audit` (each agent enforces its own; `defer: self-audit` when crossed):
- **Leanness ≠ Contract auditor**: Contract flags copies that *disagree today*; Leanness flags copies that *exist and should be collapsed* even while they still agree — removing future-drift risk.
- **Leanness ≠ Docs-sync auditor**: Docs-sync flags docs that *omit/misname* a real skill; Leanness flags docs that *duplicate* something that should have one owner.
- **Coverage ≠ Invariants auditor**: Invariants flags a *declared* invariant that is *violated*; Coverage flags where *no rule exists yet* but one would help ("here is an invariant worth stating").

All four are **read-only** named agents at `.claude/agents/self-{clarity,leanness,coverage,ergonomics}-improver.md`, with `tools: Read, Grep, Glob, Bash` — no `Edit`/`Write` in the allowlist (that part is runtime-enforced); `Bash` is present only for read navigation (`git`/`ls`/`grep`), and the agent prompts forbid using it to write. Edits happen only in the main thread (Step 4).

## Instructions

### Step 1: Gather context

In one parallel batch, run:
- `ls skills/` — full skill list (folder names = canonical slugs).
- `ls agents/` — agent files at the repo level.
- `ls .claude/agents/` — local self-* agents (sanity check before fan-out).
- `git status --porcelain` — flag a dirty tree to the user before starting (proposals against working state may diverge from `HEAD`).
- Read `.claude/.improve-baseline.json` if it exists (prior ratchet metrics; absent on first run — treat as no baseline).
- Read `CLAUDE.md` and `README.md` in full.
- Read every `docs/spec/*.md` (one batched call) — Leanness and Coverage receive these; dedup targets and spec-level coverage gaps live here.
- Read every `skills/*/SKILL.md` and `skills/*/phases/*.md` (one batched call).
- Read every bash helper `skills/*/*.sh` (one batched call).
- Read every `agents/*.md` (one batched call).

If `$ARGUMENTS` names a single skill (e.g. `audit`), still load the full `CLAUDE.md` + `README.md` + agent list (lenses cross-reference), but you may narrow the SKILL.md / phase reads to that skill plus any skill it explicitly produces/consumes for.

### Step 2: Run four agents in parallel

Send **one tool message** with four `Agent` calls, `subagent_type` set to:
- `self-clarity-improver`
- `self-leanness-improver`
- `self-coverage-improver`
- `self-ergonomics-improver`

If any of those agent files is missing under `.claude/agents/`, stop and tell the user which agent file is missing — do not fall back to inline prompts (it would lose the read-only allowlist guarantee, same rule as `/task:build` audit phase and `/self-audit`).

#### Per-call prompt template

Use this skeleton; fill in the lens-specific bundle below.

```
Improve this repo along your lens. Return findings in the format defined
in your agent prompt. Remember: actual rule violations are NOT yours —
set `defer: self-audit` on them and do not propose a fix.

--- Repo root ---
{absolute path to repo root}

--- Scope hint ---
{$ARGUMENTS minus flags, or "full repo"}

--- Skill list ---
{ls skills/}

--- Agent list (skills repo) ---
{ls agents/}

--- CLAUDE.md ---
{full file contents}

{lens-specific block — see table}

--- SKILL.md + phases bundle ---
{concatenated skills/*/SKILL.md and skills/*/phases/*.md, each preceded by `=== <relative path> ===`}

--- Bash helpers ---
{lens-specific — see table}
```

Lens-specific blocks:

| Block | Clarity | Leanness | Coverage | Ergonomics |
|-------|---------|----------|----------|------------|
| `--- README.md ---` | — | full file | — | full file |
| `--- docs/spec/*.md ---` | — | full (dedup targets live here) | full | — |
| `--- agents/ contents ---` (full text of each repo-level agent file) | full | full | full | paths + frontmatter only |
| `--- Bash helpers ---` | paths + first-line description | **full text of every `*.sh`** (over-engineering lives there) | **full text of every `*.sh`** (missing guards live there) | paths + any user-facing `echo`/error strings |

### Step 3: Merge and report

1. Parse each agent's reply into a list of findings using the declared schema. An agent that returns the literal `no findings` (its declared empty sentinel) contributes zero findings — do not parse the sentinel as a finding.
2. **Drop deferred findings from the improve report**: any finding with `defer: self-audit` is not improve's to act on — collect them into a short tail block "→ These are audit findings; run `/self-audit`" (location + one-line problem only), and remove them from the main tables.
3. **Deduplicate** cross-lens overlap: same `(file, anchor)` with overlapping `problem` text → keep the more specific lens (Clarity beats Coverage beats Leanness beats Ergonomics when they collide on the same anchor).
4. **Re-derive the tier — do not trust the agent's self-label.** A finding is **Tier 1 (auto-apply)** only if **all** hold: `behavior_preserving: true` **AND** `confidence ≥ 90` **AND** `category ∈ {clarity-wording, dedup-to-pointer, dead-flag-removal}`. Everything else is **Tier 2 (propose)**. The **entire Ergonomics lens is Tier 2** regardless of its fields (human-facing text is always the user's call).
5. **Sort** each tier: value high → low; within value by file, then line.
6. Render to chat as a single Russian-headed report with English findings — two tables:

   ```markdown
   ## self-improve — N improvements (Tier1 auto: A / Tier2 propose: B)

   ### Applied (Tier 1 — mechanical, behavior-preserving)
   | # | Lens | Val | Conf | Location | Improvement |
   |---|------|-----|------|----------|-------------|
   | 1 | Clarity | med | 94 | `skills/build/phases/audit.md:88` | … |

   ### Proposed (Tier 2 — needs your greenlight; reply e.g. "apply 2, 5")
   | # | Lens | Val | Conf | Location | Improvement | Blast radius |
   |---|------|-----|------|----------|-------------|--------------|
   | 2 | Ergonomics | high | — | `skills/bootstrap/SKILL.md:31` | … | … |
   ```

   Then a `Details` list (one entry per finding with `Lens`, `Confidence`, `Behavior-preserving: yes/no`, `Status: pending`).

7. **Do not write findings artifacts to disk.** The chat report is the deliverable. The one sanctioned on-disk write is the ratchet baseline (Step 6).

### Step 4: Apply

**Outcome enum (closed — do not invent tokens):** `pending` | `applied` | `proposed` | `skipped-out-of-scope` | `skipped-underspecified`.

**Tier 1 — auto-apply.** Unless `--propose-only` was passed, edit each Tier 1 finding via `Edit` in the main thread, value order (high → low). These are behavior-preserving by construction — wording clarifications, exact-duplicate → pointer collapses, provably-dead flag removals.
- After each applied edit, mark `applied` (in memory only); do **not** rewrite the chat report between edits.
- For a `dedup-to-pointer` edit, sanity-check the pointer target exists and the collapsed copy carried no unique content before deleting it.
- For a `dead-flag-removal` edit, first `grep -rn` the flag token across `skills/`, `agents/`, `README.md`, `CLAUDE.md`, and `docs/` — the removal is only safe if it appears nowhere but the definition being deleted. Any other hit (a doc, another skill, a user-facing mention) means the flag is not dead → downgrade to `proposed` instead of applying.
- If a Tier 1 finding's `improvement` is too vague to act on safely, mark `skipped-underspecified` and move on rather than guessing.
- If applying it would contradict an explicit decision elsewhere in `CLAUDE.md`/spec, mark `skipped-out-of-scope`.

**Tier 2 — propose only.** Never auto-applied. They stay `proposed` in the report. When the user replies naming numbers (e.g. "apply 2 and 5"), apply exactly those in the main thread **in the same session** — re-checking each against the current file before editing. A Tier 2 finding the user does not pick is left untouched.

**Never** stage or commit. Leave the working tree dirty for the user to review.

### Step 5: Verification

If nothing was applied (`--propose-only`, or Tier 1 empty and no user picks yet), skip this step.

Otherwise, in one parallel batch:
- Run `bash skills/validate/validate.sh --help 2>&1 | head -5` to confirm the validator still parses (any syntax break is a regression — revert the offending edit).
- For each edit that touched a producer template or a bash helper, re-read the file once (Read, no `cat`) and confirm the change landed cleanly and behavior is preserved.
- Re-emit a one-line summary: `Verified: K/K edits intact.`

### Step 6: Final report

English, terse:

- `Improvements`: total (Tier1 / Tier2).
- `Applied`: A, `Proposed`: B (awaiting greenlight), `Skipped`: M (with reasons), `Deferred to audit`: D.
- `Verification`: pass / fail / n/a.
- Reminder: docs and skill files were edited; review with `git diff` before commit.

#### Ratchet (informational)

Improve has no oracle, and the opportunity pool grows with the repo — so the ratchet is a **trend signal, not a quality gate**. Compare against the baseline read in Step 1 and render:

```
Ratchet (previous → current):
  improvements_total: <p> → <c>  <▪ flat | ↓ fewer opportunities (more polished) | ↑ more>
  tier1_auto:         <p> → <c>  <…>
  tier2_propose:      <p> → <c>  <…>
  deferred_audit:     <p> → <c>  <…>
```

First run (no baseline read in Step 1) → render `Ratchet: baseline initialised (no prior run).`

Then **write** the new baseline to `.claude/.improve-baseline.json` (the only sanctioned on-disk write of this skill; gitignored). Counts are the Step 3 totals **before applying** (so the trend reflects opportunities surfaced per run, not residual):

```json
{ "version": 1, "last_run": "<ISO8601 UTC>", "metrics": { "improvements_total": N, "tier1_auto": N, "tier2_propose": N, "deferred_audit": N } }
```

## Notes

- This skill is **local** (`.claude/skills/self-improve/` + `.claude/agents/self-*-improver.md`). It is not installed globally and not bundled into the public skill set. To remove: delete those paths (and the gitignored `.claude/.improve-baseline.json`).
- The ratchet baseline `.claude/.improve-baseline.json` is the **sole** on-disk artifact this skill writes (gitignored, per-clone). The skill must not modify `.gitignore` at runtime — the baseline entry is added once at bootstrap.
- Findings about `agents/*.md` and `docs/spec/*.md` themselves **are** in scope — they are part of the prompt contract.
- Findings about `.task/` are **out of scope** (working artifacts, archived by `/task:ship`).
- This skill must not modify `.task/` or the project's `.gitignore`.
- Sibling skill: [`/self-audit`](../self-audit/SKILL.md) — run it for rule-violation fixes; `/self-improve` defers all violations to it.
