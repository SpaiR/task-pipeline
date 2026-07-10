# CLAUDE.md

Guidance for Claude Code when editing **this repository**. User-facing documentation lives in `README.md`; the editing-assistant spec lives in [`docs/spec/`](docs/spec/README.md).

This file carries a compact checklist of every invariant that must stay in active session context, plus pointers to the spec for full reasoning, edge cases, and contracts. **Read the relevant spec file before any non-trivial edit** to a skill, agent, or bash helper.

## Quick orient

A collection of user-invocable Claude Code skills implementing a linear "task pipeline" — design → build → ship. Skills in `skills/<name>/SKILL.md`; phase-decomposed orchestrators (`design`, `build`, `roadmap`) carry companion phase files at `skills/<name>/phases/<phase>.md` (`roadmap` only for the `--refine` mode; ship and auto-roadmap stay single-file); subagents in `agents/`; plugin manifests in `.claude-plugin/`. No build/test/lint. Work here is editing markdown (occasional bash) and reasoning about pipeline semantics.

```
/task:bootstrap
  ↓
[/task:roadmap [--refine]]            ← off-cycle, multi-task initiative
  ↓
  ├─ [/task:auto-roadmap] ──┐         ← off-cycle autopilot
  ↓                          │
/task:design [--from <roadmap>[#<N>]]
  ↓                          │
/task:build [--auto]         │
  ↓                          │
/task:ship [--next]          │
```

Phase auto-detect (`_lib/phase-detect.sh`): design → `open|idea|blueprint|refine`; build → `implement|audit`. `--phase` overrides. Build audit = bounded auto-fix ≤ 2 iter, scope-gated by `_lib/touches-gate.sh`. `--auto` chains both phases (budgets ≤ 1 / ≤ 2). Last item in an auto-roadmap run ships with `/task:ship --full` directly (slug from `summary.md`); no separate chore-finalize.

## Spec index

| Topic | File |
|-------|------|
| Pipeline shape, phase dispatch, off-cycle skills, `/task:auto-roadmap` orchestrator | [docs/spec/pipeline.md](docs/spec/pipeline.md) |
| `.task/` layout, producer/consumer table, identifiers, `task.md` header structure | [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md) |
| `/task:auto-roadmap` mechanics (Step 0 gates, items grammar, lock invariants, failure protocol, cross-worktree) | [docs/spec/auto-roadmap.md](docs/spec/auto-roadmap.md) |
| All invariants + Shared prompt preamble (Tiers A/B/C) | [docs/spec/invariants.md](docs/spec/invariants.md) |
| Repo layout, bash helpers, agent classes, `.claude-plugin/`, skill frontmatter, editing protocol | [docs/spec/internals.md](docs/spec/internals.md) |

## Artifact contract

Full producer/consumer table, identifier rules, `task.md` header structure, `.task/` layout (`config/`, `roadmap/`, `workspace/<task-id>/`, `log/<task-id>/<N>-<slug>/`), and `WS_DIR` resolver priority: [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md). `task-id` comes from `# [TASK-ID] Title` line 1 of `task.md`; `Roadmap:` + `Source item: #<N>` headers are load-bearing for `close.sh` auto-mark. `/task:auto-roadmap` adds one per-umbrella sentinel `.task/workspace/<task-id>/auto.lock`. `/task:roadmap` brainstorm may write an optional spec sidecar `.task/roadmap/<slug>.spec.md` (numbered technical-decision anchors, cited from items via `### Spec references → <slug>.spec.md §N`, read by blueprint); not `validate.sh`-enforced.

## Invariants — don't break these when editing skills

Compact one-liners; full reasoning + edge cases in [docs/spec/invariants.md](docs/spec/invariants.md). **Do not violate any of these without re-reading the linked section.**

### Universal

- Every non-bootstrap skill checks `config.md`; preconditions are duplicated **at the bash layer** (context scripts + `validate.sh` + `close.sh`) on purpose — don't DRY the bash gates away. Prompt-layer preamble is Tiers A/B/C in invariants.md; editing it does NOT relax bash gates.
- `validate.sh` runs after every `config.md` check (context scripts, `close.sh`) or inline at Step 0 (orchestrators `/task:design`, `/task:build`) — never bypass.
- `## Iteration N` (audit) and `## Decisions` (task/plan) are append-only.
- Pipeline is invisible to the project — no tracked edits outside `.task/`. Two sanctioned outside-`.task/` artifacts: `.task-current` (per-worktree pointer, gitignored) and a `.task` **symlink** to the main worktree's `.task/` (linked worktrees only; materialized solely by `/task:bootstrap` Step 0 join-mode; passive, no code). Both git-excluded via `.git/info/exclude` with the pattern `.task` **without trailing slash** (slash misses the symlink). `.task-current` is never symlinked.
- `WS_DIR` is always resolved through `skills/_lib/resolve-ws.sh` (priority `$TASK_ID_OVERRIDE` > positional > `.task-current`); bash helpers go through `_lib/preamble.sh` → `source_resolve_ws` (exceptions: `validate.sh` and `_lib/phase-detect.sh` source `resolve-ws.sh` directly). No helper may construct `.task/workspace/<file>.md` paths directly.
- `AI_DIR` (the `.task` root) is resolved by `find_ai_dir` in `resolve-ws.sh` — a git-style upward walk from `$PWD` (config.md ancestor > `.task-current` ancestor > `$CLAUDE_PROJECT_DIR/.task` > relative `.task`), so helpers work from any subdir, not just the project root. It exports an **absolute** `<root>/.task` with the `.task` component appended literally (symlink preserved, so `dirname "$AI_DIR"` is where the local `.task-current` lives). Runs at `resolve-ws.sh` source time and is re-invoked (idempotent) by `preamble.sh`, `roadmap.sh`, and `validate.sh:require_config`. `.task-current` reads/removals in helpers key off `dirname "$AI_DIR"`, never cwd. Only acts when `AI_DIR` is unset — never hardcode `AI_DIR=.task` ahead of it.
- `${CLAUDE_SKILL_DIR}` is a Claude Code **load-time substitution** in skill markdown, not a shell env var. Every `bash "${CLAUDE_SKILL_DIR}/<script>.sh"` invocation in a skill file carries a `Run verbatim.` callout — preserve it. Never write the inline form `CLAUDE_SKILL_DIR=… bash "${CLAUDE_SKILL_DIR}/…"` (same-line var expansion precedes the inline assignment → empty path). Full rule in invariants.md § Universal.
- `/task:ship` stages only task-related files; never anything under `.task/` and never `.task-current`.
- Every skill carries `disable-model-invocation: true` + `user-invocable: true`. Exception: `validate` runs `user-invocable: false` (internal utility).
- Artifacts and user-facing dialog follow `config.md` → "Language"; subagent prompt skeletons + `auto.lock` / `auto-error.log` / runner return strings stay English (parser-stable).

### Code-navigation tiers

| Tier | Skills | Scope |
|------|--------|-------|
| **A — No code nav** | `/task:ship`, `validate`, `/task:auto-roadmap`, design open header-only path (`--idea` / empty fresh call), `/task:roadmap --refine` | `.task/`, `CLAUDE.md`, commit-format doc, `git` |
| **B — MCP-first** | design blueprint + refine, `/task:build` (both phases) | Tools from `config.md` priority order; built-ins fallback only |
| **C — Shallow scan** | `/task:bootstrap`, `/task:roadmap` brainstorm, design idea, design open quick-draft | Manifests, top-level dirs, `docs/`; no source files |

`/task:design` and `/task:build` orchestrator SKILL.md themselves are Tier A (config gate + phase detection + dispatch; design additionally runs a bounded idea-phase elicitation + open→idea chain on a fresh brainstorm start); phase tier applies inside each `phases/<phase>.md` companion. Open is internally mixed-tier (header-only → A; quick-draft → C).

### Agent classes

- **Auditor-class** — read-only `tools:` allowlist (`Read, Grep, Glob`); adding `Edit`/`Write` is a hard violation (runtime-enforced from frontmatter). Two families: build-audit lenses (`audit-{reuse,simplicity,clarity}-auditor.md`, consumed by `/task:build` audit, operate on diff) and roadmap-refine lenses (`audit-roadmap-{coverage,decomposition,clarity}-auditor.md`, consumed by `/task:roadmap --refine`, Tier A — no source nav). Shared prompt rules in `agents/_shared/audit-rules.md`; frontmatter `tools:` stays per-agent. Class declared in description; mixing roles requires redesign.
- **Executor-class** — split: `auto-roadmap-design-runner.md` (open + blueprint, parent-session model) and `auto-roadmap-build-runner.md` (implement only, per-spawn `Agent.model` from `plan.md → Implement-Model:`). Both called from `/task:auto-roadmap` main thread; audit + ship stay in orchestrator main thread for lens fanout. Shared rules in `agents/_shared/runner-rules.md`. Neither declares `tools:` or `model:` in frontmatter.

### Per-skill

- `/task:bootstrap` Step 0 = worktree join-mode: in a *linked* worktree (`git rev-parse --git-common-dir` ≠ `--git-dir`) without a local `.task`, it symlinks `.task` → main worktree's `.task/` (absolute `pwd -P` target), updates `.git/info/exclude`, and short-circuits Steps 1–4. Decision tree never overwrites a broken/foreign symlink or a real `.task` (refuses instead). Step 3a exclude writes `.task` (no slash) + `.task-current`. `bootstrap` is the single sanctioned writer of `.git/info/exclude`.
- `/task:design` is a thin orchestrator over 4 phase companions (`open`, `idea`, `blueprint`, `refine`). Refine never auto-enters — only `--phase refine` or `--refine`.
- Design's open quick-draft (**fresh open** rule): any non-empty **paraphrasable** manual context fills `## Description` in one call (no tiny-input token-count fallback). Two paths leave Description empty for the idea phase: `--idea` (mutually exclusive with `--from` / `--phase` / `--refine`) and input with no prose to paraphrase (bare ticket id). An empty `/task:design` with no task in flight is treated as `--idea` (orchestrator elicits the idea, opens a header-only umbrella, enters idea phase). This is fresh-open only — **between subtasks** (Description cleared by a `--next` ship) a call routes to the idea phase, not quick-draft.
- Design's idea mode = function of `## Description` content (empty → architect, non-empty → Socratic); roadmap-mode short-circuit redirects to `/task:design --from`. On a fresh `--idea`/empty-call start the orchestrator chains open(header-only) → idea(architect) in one call; open stays the sole owner of header + `.task-current` creation.
- Design's blueprint emits `## Steps` as `Goal` + `Touches` + optional `Logic` three-layer contract — build's implement, audit, refine all key off it.
- Design's blueprint reads pinned spec decisions (Step 1.5): when `task.md` has a `Roadmap:` header and Description cites `<slug>.spec.md §N` under `### Spec references`, it reads those `## N.` sidecar sections and honors them as fixed anchors. Missing file/section → interactive stop-and-ask, non-interactive (`--auto`/auto-roadmap) WARN-and-proceed (never a runner FAIL). Consumer half of the roadmap spec sidecar.
- Design's blueprint stamps `Implement-Model: <opus|sonnet|haiku>` in `plan.md`; `validate.sh` enforces presence and value (position-agnostic). Load-bearing for `/task:auto-roadmap` build-runner spawn.
- Design's open refuses if `.task-current` exists, with one relaxation for from-roadmap continuation (4 conditions, see spec). Writes `.task-current` on initial open; untouched in continuation.
- Design's open (Mode 2, from-roadmap) derives task-id via `_lib/derive-task-id.sh` — single source of truth.
- `## Tests` in `plan.md` is the single source of truth for `tests_required`.
- `/task:build` is a thin orchestrator over 2 phase companions (`implement`, `audit`) plus a bounded auto-fix loop for audit (Step 4).
- Build's `--auto` is opt-in one-shot: chains `implement → audit` (Step 5 loop-back); mutually exclusive with `--phase`. Per-phase budgets: implement ≤ 1 (in-memory counter), audit ≤ 2 (max `N` across `^## Iteration N` headers in audit.md). Exhaustion → `--auto stopped: <reason>` (English, parser-stable).
- Build's implement materializes plan steps as `TaskCreate` and verifies (`Identify → Run → Read → State`). At most one quick-fix on failure, then hand off.
- Build's audit auto-fix is bounded ≤ 2 iterations, runs in main thread, scope-gated by `_lib/touches-gate.sh` against `plan.md → File:`/`→ Touches:`. Out-of-scope fixes marked `Skipped: out-of-scope (touches gate)`. Gate sanitizes tokens (strips backticks / `(…)` / trailing em-/en-dash prose); stderr `WARN:` on unresolved.
- Build's audit merge runs three filter gates in Step 3 before write: **hunk-gate** (line must be inside an added/modified hunk from `diff bundle`), **claude_md_quote-gate** (Clarity-only, verbatim phrase in CLAUDE.md), **confidence-gate** (med/low scored 0–100 by merger, drop <75; high bypass). Drops land in optional `### Filtered (low confidence)` block — no `Status:`, ignored by auto-fix; `### Result` line tallies `— filtered: K`. Empty kept-list still writes a valid Iteration without `pending fix` (parser-stable `done`).
- Build's audit orchestration is adaptive: trivial (1 file, <30 lines changed) → main thread; otherwise three lens agents in parallel. Don't fall back to inline if lens agents missing. `audit-context.sh` emits a `recent history` section (`git log -5 --oneline` per changed file) for Simplicity ONLY — the orchestrator must drop it from Reuse and Clarity prompts (lensed-context contract).
- `subagent_type` for plugin-bundled agents MUST carry the `task:` prefix — unprefixed silently routes to the catch-all `claude` agent (0 tool uses, lens prompts dropped).
- Build's audit does not touch `summary.md` (owned by implement).
- `/task:ship` has two modes: default umbrella close (also via the `--full` alias) / `--next` subtask transition. Slug kebab-case English regardless of language. Default full close sweeps `workspace/<task-id>/` and removes `.task-current`; `--next` keeps `task.md` (Description body cleared).
- `/task:ship` auto-marks source roadmap when `Roadmap:` + `Source item:` headers present — loud failure on stale paths. Only roadmap mutation in the pipeline.
- `/task:ship` reads commit format from `config.md` → "Commit Format" `**Source:** <path>`; `skills/_lib/templates/conventional-commits.md` is fallback only.
- `/task:roadmap` blockquote sub-headings stay English (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / optional `### Contracts` / `### Acceptance criteria` / optional `### Spec references`). Outcomes/Goal/Invariants/Contracts are **behavioral** — observable properties only, no project-specific file/symbol names (normative names from spec or this `CLAUDE.md` are fine). `### Context` mandatory, precedes `### Goal` — propagates into `task.md` via `/task:design --from` as the "why" field, distinct from Goal's target-state framing. Hard cutover from legacy `### Changes`: validator no longer accepts it; one-line migration `sed -i 's/^> ### Changes$/> ### Outcomes/'`. `**Class:**` per-task field is best-effort hint (closed list: `rote-refactor | new-substrate | cross-module-migration | product-feature | content-vocabulary | tooling`); empty values tolerated. Sizing by `### Outcomes` bullet count: small = 1–2, medium = 3–6, large = 7+.
- `/task:roadmap` optional spec sidecar `<slug>.spec.md` is brainstorm-owned (Step 5–7, only when load-bearing tech decisions surfaced; no anchors → no file) — the pressure-release valve that keeps the roadmap behavioral. Numbered `## N.` sections (`Decision`/`Rationale`/`Constrains`), cited via `### Spec references → <slug>.spec.md §N`. **Boundary test:** a decision belongs in the sidecar iff blueprint could re-derive it differently AND that would break cross-item consistency; file layouts/signatures/per-step lists stay in `plan.md`. `### Contracts` (behavioral) and sidecar (technical decision behind it) are complementary. Structural labels English, prose config-language. Refine never writes it; Clarity auditor flags dangling `§N` (`broken spec ref`).
- `/task:roadmap --refine` is opt-in lens audit over existing roadmap (single-file dispatch in `roadmap/SKILL.md` Step 0a, never auto-entered). Three read-only auditors fan out in parallel; findings → `.task/roadmap/<slug>.refine.md` as append-only `## Iteration N`. Bounded ≤ 2; only `severity: high` auto-applied; med/low surfaced for manual review.

### `/task:auto-roadmap`

Shared mechanics (three Step 0 gates, `--items` grammar, lock shapes, failure protocol, cross-worktree safety): [docs/spec/auto-roadmap.md](docs/spec/auto-roadmap.md).

- All LLM work runs in the user's interactive main thread (or subagents spawned from it). No background execution, no `claude -p` subprocess.
- Per-stage model split: design + audit orchestration + ship use parent-session model (set via `/model` before invoking); implement uses per-item `plan.md → Implement-Model:` passed as `Agent.model` override; the three audit lens auditors pin `model: sonnet` in their own frontmatter regardless of parent.
- Per-item: main thread spawns `auto-roadmap-design-runner` → reads `plan.md → Implement-Model:` (fail-stop on miss/malformed) → spawns `auto-roadmap-build-runner` with `Agent.model: <value>` → runs audit + ship inline. "Inline" = main thread reads each skill's `SKILL.md` (and phase file) and executes Steps directly.
- Single per-umbrella sentinel `.task/workspace/<task-id>/auto.lock` (atomic `set -o noclobber`, written by Substep 3.4 after `.task-current` lands). Step 2 keeps run state in main-thread memory only. Step 0 gate 3 scans `workspace/*/auto.lock`. Clean finish → last item ships `--full` inline (Substep 3.9 Branch B, slug from `summary.md`) which removes sentinel with workspace subfolder; failure → subfolder + sentinel retained as abort signal; user runs `/task:ship --full chore-finalize` manually.
- No hard cap on items. Auto-compact may start dropping items around ~15 on Sonnet 200k (~25 on Opus 1M). User narrows with `--items <range>`.
- `ROADMAP_MTIME` refreshed in memory after every successful `--next` ship (Substep 3.9 Branch A) before next iteration's Substep 3.1; Branch B (last item, `--full`) skips the refresh.

## Editing protocol — quick rules

Full detail in [docs/spec/internals.md § Editing protocol](docs/spec/internals.md#editing-protocol).

- Treat each `SKILL.md` (and `phases/<phase>.md`) as a prompt contract — output templates, section headers, step numbering are load-bearing.
- Changing `task.md` template/separator coordinates three files: `ship/close.sh`, `validate.sh`, `design/phases/open.md` template.
- Prefer Markdown + **bold** over XML.
- Every skill change updates `README.md` (humans) and the relevant `docs/spec/*.md` in the same commit.
- **Never** update `CHANGELOG.md` autonomously. Edit it only when the user explicitly requests it.
- **Never change `.claude-plugin/plugin.json`'s `version` without explicit user confirmation.** Same rule for cutting `## [Unreleased]` into a numbered release.
- **Before committing anything in this repo**, read [`CONTRIBUTING.md`](CONTRIBUTING.md) — it is the source of truth for commit format, scope list, and versioning policy.

## Commit format

Source of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md). Summary:

- Header: `<type>(<scope>): <short summary>` — under 72 chars, imperative, lowercase first letter, no trailing period.
- Types: `feat | fix | refactor | docs | chore`. **Do not invent types.**
- Scopes (optional but strongly preferred): skill names without `task:` prefix (`bootstrap`, `roadmap`, `auto`, `open`, `idea`, `blueprint`, `refine`, `implement`, `audit`, `commit`, `close`, `validate`), agent names (`audit-reuse`, `audit-simplicity`, `audit-clarity`), or cross-cutting keys (`skills`, `hooks`, `plugin`, `readme`, `claudemd`, `changelog`). **Do not invent scopes.**
- Body: mandatory for all non-trivial commits; explain **why**, not what; 2–5 bullet list, imperative tense.
- Footer: `BREAKING CHANGE:` when header carries `!`; `Fixes #N` / `Closes #N` for issues/PRs.
- AI attribution: every Claude-assisted commit must carry `Co-Authored-By: Claude <noreply@anthropic.com>` as the last footer line.

## Release procedure

Triggered only when the user explicitly requests a release. Execute in this exact order — do not reorder or merge steps:

1. **Release commit** — in a single commit: rename `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] — YYYY-MM-DD` (no fresh empty `## [Unreleased]` left above) **and** bump `"version"` in `.claude-plugin/plugin.json` to match. Commit message: `chore(changelog): release vX.Y.Z`.
2. **Version sentinel commit** — `git commit --allow-empty -m "vX.Y.Z"`.
3. **Tag** — `git tag vX.Y.Z` on the sentinel commit. Then confirm with the user before running `git push --tags`.
