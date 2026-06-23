# Phase: refine (`--refine` mode)

> **Inputs:** `$ARGUMENTS` forwarded from `/task:roadmap` with `--refine` somewhere in it, optionally followed by a roadmap slug or path.
> **Tier:** A (no code nav). Lens auditors read `.task/roadmap/<slug>.md` + `CLAUDE.md`; the Clarity auditor additionally `Glob`/`Read`s the spec sidecar `.task/roadmap/<slug>.spec.md` when an item cites it, to resolve `<slug>.spec.md §N` references.
> **Workspace:** N/A. Operates directly on `.task/roadmap/<slug>.md` and its sidecar `.task/roadmap/<slug>.refine.md` (the spec sidecar `.task/roadmap/<slug>.spec.md` is read-only here — never created or modified by refine).

Source-of-truth for `/task:roadmap --refine`. Dispatched from `skills/roadmap/SKILL.md` Step 0a when `$ARGUMENTS` contains the literal token `--refine`. Runs **after** a roadmap exists: dispatches a parallel three-lens audit (Coverage / Decomposition / Clarity), merges findings into a sidecar log, and applies high-severity fixes to the roadmap inline — a roadmap-level analog of `/task:build` audit phase, bounded ≤ 2 iterations.

**Never auto-entered** — only on explicit `--refine` in `$ARGUMENTS`, mirroring how design's refine phase is opt-in. Steps run sequentially in main thread; lens auditors are read-only subagents.

## Step R1: Resolve slug

Parse `$ARGUMENTS` (with `--refine` stripped) for an optional slug positional. Two paths:

1. **Explicit slug.** If a slug or roadmap path was passed (e.g. `--refine api-v2-migration` or `--refine .task/roadmap/api-v2-migration.md`), resolve it to `.task/roadmap/<slug>.md` via `_lib/roadmap.sh:resolve_roadmap_path`. If the file does not exist — stop with `ERROR: roadmap '<slug>' not found in .task/roadmap/. Existing roadmaps: <list>`.
2. **No slug.** List `.task/roadmap/*.md`. If exactly one file exists — use it. Otherwise present them via `AskUserQuestion` (single-select, options = filenames with `<done>/<total>` progress; cancel option exits). Sort: incomplete first, complete last.

Capture `ROADMAP_PATH`, `ROADMAP_SLUG` (basename without `.md`), and `REFINE_LOG_PATH := ".task/roadmap/<slug>.refine.md"` for the rest of the steps.

## Step R2: Validate structure

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap "$ROADMAP_SLUG"`. On non-zero exit — relay the validator's stderr verbatim and stop. A roadmap with structural breakage (missing `### - [ ]` checkbox, missing mandatory `### Context` / `### Goal` / `### Outcomes` / `### Acceptance criteria` sub-headings, blockquote violations) cannot be audited meaningfully — the user must fix the structure first. `### Invariants` and optional `### Contracts` are part of the item template but are not validator-enforced — the clarity auditor flags absence where it matters (e.g. `missing contracts` on substrate-class items).

## Step R3: Lens fanout

Send **three** `Agent` calls in a **single tool-call message** so they run concurrently. Each call delegates to a named auditor bundled with the `task` plugin (the `subagent_type` value MUST carry the `task:` plugin prefix — unprefixed names do not resolve and silently fall through to the `claude` catch-all).

| Agent | `subagent_type` | Per-call extra block |
|-------|-----------------|----------------------|
| Coverage Auditor | `task:audit-roadmap-coverage-auditor` | — |
| Decomposition Auditor | `task:audit-roadmap-decomposition-auditor` | — |
| Clarity Auditor | `task:audit-roadmap-clarity-auditor` | `CLAUDE.md` |

### Per-call prompt template

Use the same template for all three; include the lens-specific block only where the table marks it.

```
Audit this roadmap against your lens. Return findings in the format defined
in your agent prompt.

--- Language ---
{paste config.md → "Language" value verbatim}

--- Roadmap file (full) ---
{paste the entire .task/roadmap/<slug>.md content; line-prefix with the
 roadmap path for traceability is optional. The head of this file
 (prose intro + Summary + Prerequisites, up to the first `## Phase
 summary` heading) IS the Initiative summary — lenses extract it from
 this single block; no separate `--- Initiative summary ---` is sent.}

--- Decisions (prior iterations) ---
{paste accumulated `Status: …` / fix notes from prior `## Iteration N`
 blocks in <slug>.refine.md, or "none"}

--- CLAUDE.md ---                                # Clarity ONLY
{paste CLAUDE.md content from disk, or "(missing)" if absent}
```

Note: do NOT include a `--- Tools available ---` section. The lens agents are runtime-locked to `Read, Grep, Glob` via their frontmatter `tools:` allowlist; listing MCP code-navigation tools would be dead emission.

If the `task` plugin is not installed (the `Agent` call returns `subagent_type not found` for `task:audit-roadmap-*-auditor`), surface that error with: "Install the `task` plugin so `task:audit-roadmap-coverage-auditor` / `-decomposition-auditor` / `-clarity-auditor` are available." Then stop — do not fall back to inline prompts.

## Step R4: Merge, prioritize, write `<slug>.refine.md`

1. Parse each agent's reply into a list of findings using the canonical 5-field `severity / category / location / problem / fix` schema (per [`agents/_shared/audit-rules.md`](../../../agents/_shared/audit-rules.md)).
2. Stamp `source` on each finding: which agent returned it (`Coverage` / `Decomposition` / `Clarity`).
3. **Deduplicate**: same `(location, problem)` overlap → keep the most specific finding, discard the rest. Cross-lens dups (e.g. both Coverage and Decomposition flag the same item) keep the higher-severity one and merge the fix notes.
4. **Filter**: drop findings that contradict an explicit `## Decisions` block in the roadmap (rare — most roadmaps have none).
5. **Sort**: high → med → low; within severity — by item number, then by sub-section.
6. Determine `N` — the next iteration number — using the canonical max-based recipe (mirrors `skills/build/audit-context.sh:76`): `MAX_N=$(grep -oE '^## Iteration [0-9]+' "$REFINE_LOG_PATH" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true); N=$(( ${MAX_N:-0} + 1 ))`. Counting blocks (`grep -c`) is fragile to manual edits that produce non-contiguous numbering; max-based is robust.
7. **Append** the iteration block to `$REFINE_LOG_PATH` (create file if iteration 1). Initial statuses are all `pending fix`.

**Language for the rendered file:** translate the section headers and table column names per `config.md` → "Language". Keep the `## Iteration {N}` header English regardless. Keep the `high`/`med`/`low` enum values, item numbers, Status strings (`pending fix`, `Fixed`, `Skipped: …`), and the `Source:` label/values (`Coverage` / `Decomposition` / `Clarity`) as-is — parser-stable identifiers.

Template for each iteration:

```markdown
## Iteration {N}

### Findings

| # | Severity | Category | Location | Problem |
|---|----------|----------|----------|---------|
| 1 | high | broken dependency  | `<roadmap>:#5` | depends on `#9` but file has 7 items |
| 2 | high | technical leak     | `<roadmap>:#3:### Outcomes` | bullet names `pools/selection.rs` — implementation choice belongs in blueprint, not roadmap |
| 3 | med  | missing contracts  | `<roadmap>:#7` | `Class: new-substrate` but `### Contracts` sub-heading absent |

### Details

1. **{Brief title}** — `{location}` — {problem in one sentence}
   - Fix: {concrete change}
   - Source: Coverage | Decomposition | Clarity
   - Status: pending fix

### Result: {fixed}/{total} fixed — high: X / med: Y / low: Z
```

`Status` lives only on each Details bullet — there is no `Status` column in the Findings table.

## Step R5: Apply high-severity fixes

For each finding with `severity: high` and `Status: pending fix` in iteration N:

1. Read `.task/roadmap/<slug>.md` and locate the item / sub-section named in `location`.
2. Apply the fix described in the finding (rewrite a vague bullet, split a compound task into two consecutive items, correct a `Dependencies:` reference, etc.). When splitting an item, renumber subsequent items and update every `Dependencies:` line that referenced the old numbering.
3. Update the corresponding Details bullet's `Status:` line in `$REFINE_LOG_PATH` from `pending fix` to `Fixed` (or `Skipped: <reason>` if applying the fix is impossible without user input — e.g. the fix requires a content decision the auditor could not make).
4. Update the `### Result:` line of iteration N with the new counts.

Medium and low findings stay `pending fix` in the log — they are surfaced to the user at Step R7 but not auto-applied (decomposition / clarity calls at med severity often warrant a human decision).

After fixes are applied, re-run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap "$ROADMAP_SLUG"`. If structural validation now fails — relay the validator output, mark this iteration's `### Result:` with `(structure broken after fix — manual repair required)`, and stop without iterating further.

## Step R6: Bounded re-run

**Re-compute** `MAX_N` from `$REFINE_LOG_PATH` after R4.7 has appended iteration N (do NOT reuse the pre-write capture from R4.6 — that value is off by one and would let the loop run a third iteration):

```bash
MAX_N=$(grep -oE '^## Iteration [0-9]+' "$REFINE_LOG_PATH" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)
MAX_N=${MAX_N:-0}
```

After R4.7's append, `MAX_N` equals the count of iterations now on disk (1 after iter 1, 2 after iter 2). Then:

- If `MAX_N < 2` **and** at least one high-severity finding in iteration N landed `Skipped:` rather than `Fixed` (or the model believes another lens pass on the updated roadmap would surface new high findings) — return to Step R3 for iteration N+1. The lens auditors will see the updated `.task/roadmap/<slug>.md` plus the accumulated `Decisions (prior iterations)` block built from the prior iteration's Details.
- If `MAX_N >= 2` and high-severity findings remain `Skipped:` — stop with the parser-stable English line `--refine stopped: iteration limit (high-severity still pending — see <slug>.refine.md)`.
- Otherwise (no high-severity remaining after the latest iteration) — stop with `--refine stopped: no high-severity remaining`.

These two terminal strings are English regardless of `config.md` → "Language" — they are parser-stable so future tooling can pattern-match them.

## Step R7: Output

Print to the user (in `config.md` Language):

```
/task:roadmap --refine finished (<terminal status>).
  Roadmap:      <roadmap path>
  Refine log:   <refine log path>
  Iterations:   <N>
  High:  Fixed <fix-count> / Skipped <skip-count>
  Med:   <count> pending fix (see log)
  Low:   <count> pending fix (see log)

Open the refine log to review med/low findings; apply them by hand or
re-run /task:roadmap --refine after editing.
```

Then stop. Do **not** chain into brainstorm mode or any other skill.

## Forbidden (refine mode)

- Apply medium-/low-severity fixes automatically — sidecar-surface only; only high-severity is auto-applied (Step R5).
- Spawn lens auditors recursively; rewrite previous `## Iteration N` blocks (append-only).
- Create or modify the spec sidecar `.task/roadmap/<slug>.spec.md` — it is owned exclusively by brainstorm mode. Refine may read it (Clarity reference-resolution) but never writes it; a dangling `<slug>.spec.md §N` is surfaced as a `broken spec ref` finding for the user to fix, not auto-repaired.
