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
/task:build                  │
  ↓                          │
/task:ship                   │
```

Phase auto-detect (`_lib/phase-detect.sh`): design → `open|blueprint|refine-prompt`; build → `implement|audit|done`. `--phase` overrides. Build audit = bounded auto-fix ≤ 2 iter, scope-gated by `_lib/touches-gate.sh`. Last item in an auto-roadmap run ships a bare `/task:ship` (default full close, slug from `summary.md`); no separate finalize.

## Spec index

| Topic | File |
|-------|------|
| Pipeline shape, phase dispatch, off-cycle skills, `/task:auto-roadmap` orchestrator | [docs/spec/pipeline.md](docs/spec/pipeline.md) |
| `.task/` layout, producer/consumer table, identifiers, `task.md` header structure | [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md) |
| `/task:auto-roadmap` mechanics (Step 0 gates, items grammar, lock invariants, failure protocol, cross-worktree) | [docs/spec/auto-roadmap.md](docs/spec/auto-roadmap.md) |
| All invariants + Shared prompt preamble (Tiers A/B/C) | [docs/spec/invariants.md](docs/spec/invariants.md) |
| Repo layout, bash helpers, agent classes, `.claude-plugin/`, skill frontmatter, editing protocol | [docs/spec/internals.md](docs/spec/internals.md) |

## Artifact contract

Full producer/consumer table, identifier rules, `task.md` header structure, `.task/` layout (`config/`, `roadmap/`, `workspace/<task-id>/`, `log/<task-id>/<N>-<slug>/`), and `WS_DIR` resolver priority: [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md). `task-id` comes from `# [TASK-ID] Title` line 1 of `task.md`; `Roadmap:` + `Source item: #<N>` headers are load-bearing for `close.sh` auto-mark. `/task:auto-roadmap` adds one driver-owned run lock `.task/roadmap/<slug>.lock`. `/task:roadmap` brainstorm may write an optional spec sidecar `.task/roadmap/<slug>.spec.md` (numbered technical-decision anchors, cited from items via `### Spec references → <slug>.spec.md §N`, read by blueprint); not `validate.sh`-enforced.

## Invariants — don't break these when editing skills

Compact one-liners; full reasoning + edge cases in [docs/spec/invariants.md](docs/spec/invariants.md). **Do not violate any of these without re-reading the linked section.**

### Universal

- Every non-bootstrap skill checks `config.md`; preconditions are duplicated **at the bash layer** (context scripts + `validate.sh` + `close.sh`) on purpose — don't DRY the bash gates away. Prompt-layer preamble is Tiers A/B/C in invariants.md; editing it does NOT relax bash gates. **Intake carve-out:** `/task:design` and `/task:roadmap` react to a config-absent gate by auto-running `/task:bootstrap` inline (prompt-layer) then re-validating, rather than hard-stopping — the bash gate is unchanged and re-checked, not relaxed; `/task:build` / `/task:ship` / `/task:auto-roadmap` keep the hard-stop redirect. The `PreToolUse` validator hook matcher is `Skill\((task:)?(build|ship|auto-roadmap)\)` — `design` is excluded alongside `bootstrap`/`roadmap` (intake phase) so its inline auto-setup is reachable; design still runs `validate.sh all` in its own Step 0.
- `validate.sh` runs after every `config.md` check (context scripts, `close.sh`) or inline at Step 0 (orchestrators `/task:design`, `/task:build`) — never bypass.
- `## Iteration N` (audit) and `## Decisions` (plan) are append-only.
- Pipeline is invisible to the project — no tracked edits outside `.task/`. `.task/` is the one sanctioned pipeline artifact at the pipeline root (git-excluded via `.git/info/exclude`, pattern `.task`). Worktree sharing is automatic: all worktrees of a repo resolve one shared `.task/` via the `task.root` git-config anchor (`/task:bootstrap` writes it; `dirname(git-common-dir)` fallback). **No `.task` symlink, no join-mode.** The per-worktree active-task pointer lives **inside git's per-worktree dir** (`git rev-parse --git-path task-current` → `.git/worktrees/<name>/task-current`, or `.git/task-current` in the main worktree) — outside the work tree, so it needs no git-exclude and can never be staged.
- `WS_DIR` always resolves through `skills/_lib/resolve-ws.sh` (priority `$TASK_ID_OVERRIDE` > positional > active-task pointer via `task_current_path`); helpers reach it via `_lib/preamble.sh` → `source_resolve_ws` (exceptions: `validate.sh` and `_lib/phase-detect.sh` source `resolve-ws.sh` directly). No helper may construct `.task/workspace/<file>.md` paths directly, and none hardcodes the pointer path — always `task_current_path`. `source_resolve_ws` self-heals a **provably-stale** pointer (empty / missing `workspace/<id>/` subfolder); a pointer whose workspace exists is never cleared, and the read-only direct sourcers never heal. Self-heal contract: invariants.md § Universal.
- `AI_DIR` (the `.task` root) is resolved by `find_ai_dir` in `resolve-ws.sh` — precedence `git config --local task.root` > `config.md`-ancestor walk > `dirname(git-common-dir)` > `$CLAUDE_PROJECT_DIR/.task` > relative `.task`; the `task.root` anchor gives every worktree the same shared `.task/` with zero setup. Re-invoked (idempotent) at each caller: `preamble.sh`, `roadmap.sh`, `validate.sh:require_config`. Only acts when `AI_DIR` is unset — never hardcode `AI_DIR=.task` ahead of it; resolve the pointer via `task_current_path`, never `dirname "$AI_DIR"`. Full precedence + export detail: internals.md § bash helpers.
- `${CLAUDE_SKILL_DIR}` is a Claude Code **load-time substitution** in skill markdown, not a shell env var. Every `bash "${CLAUDE_SKILL_DIR}/<script>.sh"` invocation in a skill file carries a `Run verbatim.` callout — preserve it. Never write the inline form `CLAUDE_SKILL_DIR=… bash "${CLAUDE_SKILL_DIR}/…"` (same-line var expansion precedes the inline assignment → empty path). Full rule in invariants.md § Universal.
- `/task:ship` stages only task-related files; never anything under `.task/` (the active-task pointer lives in the git dir and can't be staged anyway).
- Every skill carries `disable-model-invocation: true` + `user-invocable: true`. Exception: `validate` runs `user-invocable: false` (internal utility).
- Artifacts and user-facing dialog follow `config.md` → "Language"; subagent prompt skeletons + run lock / `auto-error.log` / runner return strings stay English (parser-stable).
- Every core command's user-facing output ends with the canonical next-step footer (`→ Next: <runnable command>`, or `→ Done.` when the flow is complete); every content-confirmation prompt uses the accept / decline / edit grammar; every discrete **path fork** (2–4 options) that can't be inferred is presented via `AskUserQuestion` chips — the structured-choice convention (c). All three defined once in [docs/spec/invariants.md § Interaction conventions](docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar); human-facing dialog only — parser-stable strings and artifact content untouched. (c) is **interactive-only**: the surviving flags (`--from` / `--phase`, and `/task:auto-roadmap`'s `--next` / `--items`) are the non-interactive equivalents and skip the question; the `/task:auto-roadmap` runners never reach `AskUserQuestion` because the driver always passes explicit flags. Full instance roster: invariants.md § Interaction conventions.
- **User-facing `→ Next:` footers and skill `description` frontmatter are flag-free.** The interactive question layer covers every routine fork, so the surviving advanced flags (`--from` / `--phase`) are hidden from README signatures, frontmatter, examples, and every `→ Next:` line a user sees — documented only in `docs/troubleshooting.md § Escape hatches`. **Hide ≠ remove:** they stay fully functional (the `/task:auto-roadmap` runners drive `design --from`; power users force phases). `/task:auto-roadmap`'s own flags (`--next`/`--from`/`--items`) remain a documented user interface. (The `--idea`, ship `--next`, `--auto`, and the `--refine` design-alias were **removed** outright.) Spec docs keep the surviving flags — they are the maintainer contract, not user surface.

### Code-navigation tiers

| Tier | Skills | Scope |
|------|--------|-------|
| **A — No code nav** | `/task:ship`, `validate`, `/task:auto-roadmap`, `/task:roadmap --refine` | `.task/`, `CLAUDE.md`, commit-format doc, `git` |
| **B — MCP-first** | design blueprint + refine, `/task:build` (both phases) | Tools from `config.md` priority order; built-ins fallback only |
| **C — Shallow scan** | `/task:bootstrap`, `/task:roadmap` brainstorm, design open quick-draft | Manifests, top-level dirs, `docs/`; no source files |

`/task:design` and `/task:build` orchestrator SKILL.md themselves are Tier A (config gate + phase detection + dispatch); phase tier applies inside each `phases/<phase>.md` companion. Open is Tier C (quick-draft).

### Agent classes

- **Auditor-class** — read-only `tools:` allowlist (`Read, Grep, Glob`); adding `Edit`/`Write` is a hard violation (runtime-enforced from frontmatter). Two families: build-audit lenses (`audit-{reuse,simplicity,clarity}-auditor.md`, consumed by `/task:build` audit, operate on diff) and roadmap-refine lenses (`audit-roadmap-{coverage,decomposition,clarity}-auditor.md`, consumed by `/task:roadmap --refine`, Tier A — no source nav). Shared prompt rules in `agents/_shared/audit-rules.md`; frontmatter `tools:` stays per-agent. Class declared in description; mixing roles requires redesign.
- **Executor-class** — three agents for `/task:auto-roadmap`: `auto-roadmap-item-runner.md` (spawned once per item by the driver loop; runs the whole per-item cycle in its own context) spawns `auto-roadmap-design-runner.md` (open + blueprint, parent-session model) and `auto-roadmap-build-runner.md` (implement only, per-spawn `Agent.model` from `plan.md → Implement-Model:`), fans out the three lens auditors itself, and runs audit + ship inline. Design/build runners stay leaves (scoping choice — nested spawning is supported). Shared rules in `agents/_shared/runner-rules.md`. None declares `tools:` or `model:` in frontmatter.

### Per-skill

#### bootstrap

- `/task:bootstrap` Step 0 = determine the pipeline root `ROOT` (`git config --local task.root` if set, else `dirname(git-common-dir)`; `pwd` for non-git). Step 3 creates `.task/` at `$ROOT`, records `git config --local task.root "$ROOT"` (shared across all worktrees via the repo-common config → automatic worktree sharing, no symlink/join), and Step 3a excludes `.task` via `.git/info/exclude`. For a **bare repo** the default `ROOT` is surfaced in the Step 2 accept/decline/edit confirmation so the user can redirect `.task/`. `bootstrap` is the single sanctioned writer of `.git/info/exclude` and of `task.root`.
- `/task:bootstrap` Step 2 detects language policy + testing-policy mode from the repo (commit prose/docs, test infra) and presents both as a single proposal, confirmed with the accept/decline/edit grammar (`docs/spec/invariants.md § Interaction conventions`); edit is the override path for either value, decline writes no `config.md`. Detection only seeds the proposal — it never locks a value. Besides explicit invocation, bootstrap is auto-invoked inline by the first `/task:design` or `/task:roadmap` in an unconfigured project (their Step 0 runs the full skill verbatim, then re-validates and continues); the explicit `/task:bootstrap` stays available and idempotent for re-running setup on demand.
#### design

- `/task:design` is a thin orchestrator over 3 phase companions (`open`, `blueprint`, `refine`). Its Step 0 config gate is intake-capable: on a fresh project it auto-runs `/task:bootstrap` inline then continues the original request (stops only on `decline`). Refine is a repair-level phase off the everyday surface (not advertised in the frontmatter description, README signature, pipeline diagrams, or chain hints); it never auto-enters — only `--phase refine`. Documented once as repair-level in `docs/troubleshooting.md`.
- Design's open quick-draft (**fresh open** rule): any non-empty **paraphrasable** manual context fills `## Description` in one call (no tiny-input token-count fallback). A bare ticket id with no prose to paraphrase → open elicits a one-sentence description, then quick-drafts. An empty `## Description` in an active workspace is an anomaly (no producer leaves that state) — phase-detect errors.
- Design's Step 1 presents an **entry fork** (`AskUserQuestion`: draft directly / open from a roadmap — convention (c)) only on an ambiguous fresh start (auto-detect `open`, no positional context, no flag); prose → quick-draft, a flag → that flag wins, both skip the fork. Interactive-only: the `auto-roadmap-design-runner` always gets `--from`, so the fork is unreachable non-interactively (bare no-context is an error there). `--from` without `#<N>` and >1 open item → open.md item picker (convention (c); `#<N>` skips it).
- Design's Step 3 is a **phase-advance loop**, not a passive chain hint: after each phase it re-detects and, interactive-only, asks one `AskUserQuestion` before continuing in the same call — Description-ready → "plan now?" (dispatch blueprint inline), plan-ready (`refine-prompt`) → "start implementing now?" (invoke `/task:build`, the whole skill — the design→build boundary mirrors build→ship). Decline / non-interactive → flag-free footer, stop. `auto-roadmap-design-runner` never enters the loop and never invokes build (it stops after blueprint; the item-runner spawns build-runner). Never auto-enter `refine`.
- Design's blueprint emits `## Steps` as `Goal` + `Touches` + optional `Logic` three-layer contract — build's implement + audit and design's refine all key off it.
- Design's blueprint reads pinned spec decisions (Step 1.5): when `task.md` has a `Roadmap:` header and Description cites `<slug>.spec.md §N` under `### Spec references`, it reads those `## N.` sidecar sections and honors them as fixed anchors. Missing file/section → interactive stop-and-ask, non-interactive (auto-roadmap) WARN-and-proceed (never a runner FAIL). Consumer half of the roadmap spec sidecar.
- Design's blueprint stamps `Implement-Model: <opus|sonnet|haiku>` in `plan.md`; `validate.sh` enforces presence and value (position-agnostic). Load-bearing for the `auto-roadmap-item-runner`'s build-runner spawn.
- Design's open refuses if the active-task pointer exists, with two relaxations: from-roadmap continuation (4 conditions, see spec), and provably-stale self-heal (empty / missing workspace subfolder → removed with a one-line notice, proceed as initial open). Writes the pointer (git per-worktree dir) on initial open; untouched in continuation.
- Design's open (Mode 2, from-roadmap) derives task-id via `_lib/derive-task-id.sh` — single source of truth.
- `## Tests` in `plan.md` is the single source of truth for `tests_required`.
#### build

- `/task:build` is a thin orchestrator over 2 phase companions (`implement`, `audit`) plus a bounded auto-fix loop for audit (Step 4).
- Build's Step 5 asks an **implement→audit advance question** (`AskUserQuestion`: Run audit now / Stop here — convention (c)) after a clean interactive implement — one opt-in advance that loops back to Step 1a → audit (Step 4 bounded loop). Interactive-only + clean-only: never under the item-runner (drives literal flags) or after a quick-fix-exhausted hand-off.
- Build's implement materializes plan steps as `TaskCreate` and verifies (`Identify → Run → Read → State`). At most one quick-fix on failure, then hand off.
- Build's audit auto-fix is bounded ≤ 2 iterations, runs in main thread, scope-gated by `_lib/touches-gate.sh` against `plan.md → File:`/`→ Touches:`. Out-of-scope fixes marked `Skipped: out-of-scope (touches gate)`. Gate sanitizes tokens (strips backticks / `(…)` / trailing em-/en-dash prose); stderr `WARN:` on unresolved.
- Build's audit merge runs three filter gates in Step 3 before write: **hunk-gate** (line must be inside an added/modified hunk from `diff bundle`), **claude_md_quote-gate** (Clarity-only, verbatim phrase in CLAUDE.md), **confidence-gate** (med/low scored 0–100 by merger, drop <75; high bypass). Drops land in optional `### Filtered (low confidence)` block — no `Status:`, ignored by auto-fix; `### Result` line tallies `— filtered: K`. Empty kept-list still writes a valid Iteration without `pending fix` (parser-stable `done`).
- Build's audit orchestration is adaptive: trivial (1 file, <30 lines changed) → main thread; otherwise three lens agents in parallel. Don't fall back to inline if lens agents missing. `audit-context.sh` emits a `recent history` section (`git log -5 --oneline` per changed file) for Simplicity ONLY — the orchestrator must drop it from Reuse and Clarity prompts (lensed-context contract).
- `subagent_type` for plugin-bundled agents MUST carry the `task:` prefix — unprefixed silently routes to the catch-all `claude` agent (0 tool uses, lens prompts dropped).
- Build's audit does not touch `summary.md` (owned by implement).
- Build's audit default human-facing output is the one-line `### Result` summary (found / fixed / filtered); full `### Findings`/`### Details` detail stays retrievable in `audit.md`; blocking (iteration-limit / verify-failure) findings are always surfaced in full. The `### Result` format string is parser-stable — unchanged.
- A clean interactive build proposes ship: at each clean endpoint (phase-detect `done`, audit-clean) it flows into ship's single accept/decline/edit confirmation (confirm-gated, interactive-only — decline holds and prints the manual footer; blocking paths never propose; item-runner byte-stable).
#### ship

- `/task:ship` has one mode: full close. It commits (single Step 3 accept/decline/edit confirmation; item-runner auto-accepts), then `close.sh` archives `plan/audit/summary.md` **plus `task.md`** to `.task/log/<task-id>/<N>-<slug>/`, sweeps `workspace/<task-id>/`, and removes the active-task pointer. Full close allows empty Description; archiving `task.md` on every close is what keeps a task's Description in `.task/log/`. Slug is always auto-derived (no hand-supplied slug), kebab-case English regardless of language. Removed forms (`--full`, `--next`, a positional slug) fail loud with a "removed — use X" message.
- `/task:ship` auto-marks source roadmap when `Roadmap:` + `Source item:` headers present — loud failure on stale paths. Only roadmap mutation in the pipeline.
- `/task:ship` reads commit format from `config.md` → "Commit Format" `**Source:** <path>`; `skills/_lib/templates/conventional-commits.md` is fallback only.
- `/task:ship` composes the commit header+body from `summary.md` artifacts (fallback `task.md`; no free-text authoring) and presents it once for an accept/decline/edit confirmation before committing; the `auto-roadmap-item-runner` auto-accepts (non-interactive). See `docs/spec/invariants.md § Interaction conventions (b)`.
#### roadmap

- `/task:roadmap` blockquote sub-headings stay English (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / optional `### Contracts` / `### Acceptance criteria` / optional `### Spec references`). Outcomes/Goal/Invariants/Contracts are **behavioral** — observable properties only, no project-specific file/symbol names (normative names from spec or this `CLAUDE.md` are fine). `### Context` mandatory, precedes `### Goal` — propagates into `task.md` via `/task:design --from` as the "why" field, distinct from Goal's target-state framing. Legacy `### Changes` is a hard cutover (validator rejects it). `**Class:**` is a best-effort **inferred** hint (closed list, user-overridable in-file, `validate.sh`-tolerated — not enforced); `Size` is **computed** from the `### Outcomes` count (small 1–2 / medium 3–6 / large 7+), never asked — a mismatch is drift the decomposition auditor flags. Class enum values + `### Changes` migration: invariants.md § roadmap.
- `/task:roadmap` optional spec sidecar `<slug>.spec.md` is brainstorm-owned (Step 5–7, only when load-bearing tech decisions surfaced; no anchors → no file) — the pressure-release valve that keeps the roadmap behavioral. Numbered `## N.` sections (`Decision`/`Rationale`/`Constrains`), cited via `### Spec references → <slug>.spec.md §N`. **Boundary test:** a decision belongs in the sidecar iff blueprint could re-derive it differently AND that would break cross-item consistency; file layouts/signatures/per-step lists stay in `plan.md`. `### Contracts` (behavioral) and sidecar (technical decision behind it) are complementary. Structural labels English, prose config-language. Refine never writes it; Clarity auditor flags dangling `§N` (`broken spec ref`).
- `/task:roadmap` Step 0 config gate is intake-capable (like design): on a fresh project it auto-runs `/task:bootstrap` inline then proceeds with the brainstorm/refine (stops only on `decline`). roadmap is already outside the PreToolUse hook matcher, so no hook change was needed for it — only `design` had to be dropped from the matcher.
- `/task:roadmap` brainstorm has two input paths converging on one pre-draft confirmed decision list; detection is heuristic in Step 3 (not the `--refine` token parse): **harvest** when the prior conversation already settled decisions for this initiative (prefer when unsure), else **cold start**. Harvest surfaces a **Decision Inventory** (every captured decision at full specificity) confirmed via accept/decline/edit before drafting; cold start reaches the same list at Step 4's final-round sign-off. The Inventory is chat-only — an *input* confirmation, never written to a file. Step 5 routes each confirmed decision to a home and Step 6 verifies none is silently dropped — routing rules + sidecar boundary test: invariants.md § roadmap. Does not subsume slug-collision / too-small preconditions, nor lower Step 8's escalation threshold.
- `/task:roadmap` brainstorm authoring closes with a **report-only** light three-lens self-check (Coverage / Decomposition / Clarity, Step 8) over the just-saved file — a self-run checklist, never a subagent fanout, and it never rewrites the saved roadmap silently. It offers `--refine` inline via the accept/decline/edit grammar only when findings warrant escalation (≥1 high-severity or ≥3 total); otherwise it reports and moves straight to the next-step footer.
- `/task:roadmap --refine` is opt-in lens audit over existing roadmap (single-file dispatch in `roadmap/SKILL.md` Step 0a, never auto-entered — an accepted inline offer from the light pass above is still an explicit invocation, not an automatic entry). Three read-only auditors fan out in parallel; findings → `.task/roadmap/<slug>.refine.md` as append-only `## Iteration N`. Bounded ≤ 2; only `severity: high` auto-applied; med/low surfaced for manual review.

### `/task:auto-roadmap`

Shared mechanics (three Step 0 gates, `--items` grammar, lock shapes, failure protocol, cross-worktree safety): [docs/spec/auto-roadmap.md](docs/spec/auto-roadmap.md).

- All LLM work runs in the user's interactive session — the driver's main thread, the `auto-roadmap-item-runner` it spawns per item, or their sub-subagents. No background execution, no `claude -p` subprocess.
- Per-stage model split: the item-runner (+ its design-runner), audit orchestration, and ship use the parent-session model (set via `/model` before invoking); implement uses per-item `plan.md → Implement-Model:` passed by the item-runner as `Agent.model` override; the three audit lens auditors pin `model: sonnet` in their own frontmatter regardless of parent.
- Per item: the driver spawns ONE `auto-roadmap-item-runner` (no `is_first`/`is_last` flags — every item is identical), then routes on its returned digest. The item-runner spawns `auto-roadmap-design-runner` → reads `plan.md → Implement-Model:` (fail-stop on miss/malformed) → spawns `auto-roadmap-build-runner` with `Agent.model: <value>` → runs audit (fanning out the three lens auditors itself) + ship inline (full close) → returns a compact report-card digest (last line parser-stable; carries `task_id:` and `roadmap_mtime:` on every OK). "Inline" = the item-runner reads each skill's `SKILL.md` (and phase file) and executes Steps directly. The driver never spawns runners/auditors or runs `/task:build` / `/task:ship` itself.
- Single driver-owned run lock `.task/roadmap/<slug>.lock` (atomic `set -o noclobber`, keyed on the roadmap slug, in the shared `.task/roadmap/` → cross-worktree mutex + crash sentinel). Driver keeps run state in memory (never re-reads the lock) and removes it on every handled exit; only an unhandled crash leaves it (Step 0 gate 3 reports it for manual `rm`). A failed item leaves its partial `workspace/<id>/` + `.task-current` as the dirty-state signal, swept by a bare `/task:ship`. Lock lifecycle: auto-roadmap.md § Run lock.
- Item count effectively unbounded: per-item diff + 3 lens results live in the disposable item-runner context, so the driver accumulates only one digest per item — the old ~15 (Sonnet 200k) / ~25 (Opus 1M) auto-compact ceiling is greatly relaxed. User can still narrow with `--items <range>`.
- `/task:auto-roadmap` Step 1 launch is interactive: the roadmap picker (`AskUserQuestion` from `roadmaps-available`) is the precedent instance of convention (c); when no `--items`/`--next`/`--from` is given and >1 item is unchecked it also asks an **item-scope question** (All remaining [default, = prior no-flag behavior] / Only next [= `--next`] / Pick range [= `--items`, free-text via the "Other" option]). One unchecked item or a flag skips it. The driver then hands runners literal `ITEMS_SPEC`/`START_ITEM` — the question never reaches a runner.
- Two-level failure protocol: the item-runner logs child FAILs + its own internal failures (`--- ORCHESTRATOR FAIL ---`); the driver appends its own block only on malformed/absent item-runner status or a mtime race, and otherwise relays. `ROADMAP_MTIME` is refreshed in the driver's Substep 3.4 from the mtime the item-runner returns on every OK (every item full-closes and auto-marks, bumping it).

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
- Types: `feat | fix | refactor | perf | docs | test | chore | revert`. **Do not invent types.**
- Scopes (optional but strongly preferred): skill names without `task:` prefix (`bootstrap`, `roadmap`, `auto`, `open`, `blueprint`, `refine`, `implement`, `audit`, `commit`, `close`, `validate`), agent names (`audit-reuse`, `audit-simplicity`, `audit-clarity`, `audit-roadmap-coverage`, `audit-roadmap-decomposition`, `audit-roadmap-clarity`), or cross-cutting keys (`skills`, `agents`, `runners`, `lib`, `hooks`, `plugin`, `github`, `readme`, `claudemd`, `changelog`, `contributing`, `spec`). **Do not invent scopes.**
- Body: mandatory for all non-trivial commits; explain **why**, not what; 2–5 bullet list, imperative tense.
- Footer: `BREAKING CHANGE:` when header carries `!`; `Fixes #N` / `Closes #N` for issues/PRs.
- AI attribution: every Claude-assisted commit must carry `Co-Authored-By: Claude <noreply@anthropic.com>` as the last footer line.

## Pull requests

Source of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md#pull-request-title) (the Pull Request Title / Body / Labels subsections). When opening a PR (`gh pr create`), follow it — do NOT default to `gh`'s commit-derived title/body:

- **Title**: short descriptive prose for the whole change. **Not** the first commit's header, and **no** `type(scope):` prefix — the type is carried by the label. Sentence case, no trailing period, under ~72 chars.
- **Body**: use `.github/pull_request_template.md`. Only `## What` is mandatory; fill `Why` / `Changes` / `Verification` / `Notes for reviewer` when they apply, delete the rest. End with `Closes #N` / `Fixes #N` when relevant, then the `🤖 Generated with [Claude Code]` attribution line.
- **Label**: apply exactly one type label mapped from the commit type — `feat`→`enhancement`, `fix`→`fix`, `docs`→`documentation`, `refactor`→`refactor`, `perf`→`performance`, `test`/`chore`→`chore`. Add `breaking-change` on top when the header carries `!` / a `BREAKING CHANGE:` footer. Set it with `gh pr create --label <name>`. **Do not invent labels.**

## Release procedure

Triggered only when the user explicitly requests a release. Execute in this exact order — do not reorder or merge steps:

1. **Release commit** — in a single commit: rename `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] — YYYY-MM-DD` (no fresh empty `## [Unreleased]` left above) **and** bump `"version"` in `.claude-plugin/plugin.json` to match. Commit message: `chore(changelog): release vX.Y.Z`.
2. **Version sentinel commit** — `git commit --allow-empty -m "vX.Y.Z"`.
3. **Tag** — `git tag vX.Y.Z` on the sentinel commit. Then confirm with the user before running `git push --tags`.
