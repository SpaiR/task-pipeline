# Shared rules for the `/task:auto-roadmap` runners

Rules inherited by the three roadmap runners (`auto-roadmap-item-runner`, `auto-roadmap-design-runner`, `auto-roadmap-build-runner`) from their nested phase files (`skills/design/phases/{open,blueprint}.md`, `skills/build/phases/{implement,audit}.md`, `skills/ship/SKILL.md`) and from project invariants. Centralized here so editors of any side see a single registry of cross-cutting constraints — a misread of a nested phase file in autopilot cannot silently degrade behavior if the rule is also restated here.

The per-item cycle runs inside one `auto-roadmap-item-runner` per item (spawned by the `/task:auto-roadmap` driver loop). The item-runner spawns `auto-roadmap-design-runner` (Steps a + b — open + blueprint), reads `plan.md → Implement-Model:`, spawns `auto-roadmap-build-runner` with the matching `Agent.model` override (`opus`, `sonnet`, or `haiku`) for Step c (implement), then runs the audit + ship stages itself (fanning out the three build-audit lens auditors). Rules below apply to whichever runner enters the corresponding nested phase; the "Applies to" column names it.

When editing any rule below, **also update its source-of-truth file** — drift between this list and the source is itself a bug:

| Rule | Applies to | Source of truth |
|------|------------|------------------|
| One quick-fix max during implement | `auto-roadmap-build-runner` | `skills/build/phases/implement.md` |
| Append-only artifacts | all runners (`## Decisions`; `## Iteration N` in `audit.md` for item-runner) | `docs/spec/invariants.md` § Universal |
| Mandatory verification before `TaskUpdate(completed)` | `auto-roadmap-build-runner` | `skills/build/phases/implement.md` |
| MCP-first tooling in nested phases | all runners (blueprint / implement / audit) | `docs/spec/invariants.md` § Code-navigation tiers + `.task/config/config.md` |
| Implement-Model rubric stamp in `plan.md` | `auto-roadmap-design-runner` | `skills/design/phases/blueprint.md` § Step 3 |
| Never call `AskUserQuestion` — pass explicit flags | all runners | `docs/spec/invariants.md` § Interaction conventions (c) |

## Rules

- **One quick-fix max during implement.** On a single obvious failure (typo, missing import, wrong symbol name in `Touches`) apply one targeted fix and re-run. Further failure → stop. No shotgun fixes. (Build-runner only.)
- **Append-only artifacts.** `## Decisions` in `task.md` / `plan.md` is append-only. (Both runners.)
- **Mandatory verification before `TaskUpdate(completed)`** for each step in implement: Identify → Run → Read → State. `Touches` symbols must be visible in `git diff`; if `## Tests` is present, RED→GREEN must be observed. (Build-runner only.)
- **MCP-first tooling.** For code navigation and editing inside any nested phase (`blueprint`, `implement`, `audit`), use MCP tools from `.task/config/config.md` → "Code Navigation" / "Code Editing" in the priority order listed there. Built-in `Read`/`Edit`/`Grep`/`Glob`/`ls` are allowed only when `config.md` explicitly lists them as fallback; otherwise justify the choice in one line before calling. **Read `config.md` once at the start of your run** — all three runners are interactive-session subagents, so `config.md` is available throughout their context.
- **Never call `AskUserQuestion`; never enter design's advance loop.** The interactive structured-choice forks (`docs/spec/invariants.md` § Interaction conventions (c) — design's entry fork, `--from` item picker, design's Step 3 phase-advance loop, build's implement→audit advance, auto-roadmap's item-scope question) are **interactive-only**. A runner has no user to answer and must never reach one: always drive the nested skill with the explicit flag the driver captured (`--from <path>#<N>`, `--items`/`--next`, `--auto` or literal phase dispatch). In particular, `auto-roadmap-design-runner` runs open + blueprint explicitly and **stops after blueprint** — it does not ask "start implementing now?" and does not invoke `/task:build` (the item-runner spawns `auto-roadmap-build-runner` separately). A blocked question would deadlock the unattended run. (All runners.)
- **Implement-Model rubric.** Design-runner MUST apply `blueprint.md` § Step 3's rubric honestly (`opus` for cross-cutting / >5 steps / >3 modules / subtle invariants; `sonnet` for typical isolated changes; `haiku` for ≤2-step single-module mechanical edits; `sonnet` when uncertain). The stamp is load-bearing — the item-runner reads `plan.md → Implement-Model:` after design-runner OK and passes the value as the `Agent.model` override when spawning build-runner. Too cheap → implement may flap on verification; too dear → the run pays opus rates for trivial work. (Design-runner only — build-runner just echoes the chosen value in its `implement_model` input field.)

## Postmortem path resolution

When a runner fails it dumps a postmortem to the error log via the shared formatter (`skills/_lib/fail-log.sh`). Path resolution is gated on whether the workspace subfolder exists:

1. **`.task-current` exists at the worktree root and `.task/workspace/<id>/` exists** (where `<id>` = `cat .task-current`) → write `.task/workspace/<id>/auto-error.log`. This is the post-open path.
2. **Otherwise** (design-runner failed in Step a before `/task:design --from` landed `.task-current`) → **no on-disk postmortem**. Return the FAIL status line with the inline reason as the only record; the user reads it directly in the orchestrator's output. There is no worktree-local fallback file.

`auto-roadmap-build-runner` always sees branch 1 (build-runner is only spawned after design-runner OK, so the subfolder is guaranteed). `auto-roadmap-design-runner` may hit either branch depending on where in Step a the failure occurred. `auto-roadmap-item-runner` inherits whichever branch its failing stage implies — pre-open only if its own Step 1 design-runner failed before `.task-current` landed; post-open for every later stage.

The two-branch resolution is applied at **two levels** on a failure:

1. **Item-runner level** — when the item-runner catches a child FAIL or fails in a stage it runs itself, it appends its own `--- ORCHESTRATOR FAIL ---` block (via `record_orchestrator_fail`, or `fail-log.sh orchestrator-fail` directly when it must set `task_current_present` itself for a pre-open design failure).
2. **Driver level** (`auto-roadmap/SKILL.md` Substep 3.4) — the driver appends its own `--- ORCHESTRATOR FAIL ---` block **only** when the item-runner returned a malformed/absent status, or on a driver-detected mtime race (Substep 3.1). For a well-formed item-runner FAIL the driver just relays — the item-runner already logged. The driver uses `fail-log.sh orchestrator-fail` **directly** (never `record_orchestrator_fail`, whose hardcoded `task_current_present = yes` is wrong if the item-runner died pre-open).

## Return format (shared rules)

Every runner ends its reply with exactly one status line — the **last non-empty line** of the reply. The consumer scans bottom-up and routes off that line; anything above it is log output (for `auto-roadmap-item-runner`, that "log output" is the report-card digest — see below) and is not used for routing. The consumer differs per runner: the **item-runner** consumes design-runner's and build-runner's status lines; the **driver** (`auto-roadmap/SKILL.md` Substep 3.4) consumes the item-runner's.

Rules common to all runners (per-runner OK/FAIL grammars live in each agent's own `## Return format` section):

- **Stands alone.** No trailing prose, no Markdown decoration around the status line, no blank lines after it that contain anything but whitespace.
- **English regardless of `config.md` → "Language".** The status lines are parser-stable identifiers, not user-facing prose.
- **The trailing clause is part of the status string** (`"— plan.md ready, awaiting implement"` for design-runner; `"— diff uncommitted, ready for audit"` for build-runner; `"shipped (--next|full) — <sha>"` for item-runner). Load-bearing — the consumer pattern-matches on it to know which producer/stage it is reading. Do not omit it.
- **Closed enum for `<stage>`** — each runner's `## Return format` lists the exact accepted values. Never emit any other.
- **Never improvise a third shape.** If you cannot construct a valid `OK:`, emit `FAIL at <stage>: …` instead. Anything else is malformed and the consumer follows the fail-stop protocol with reason `runner returned malformed status`.
- **Error-log path naming.** On failure with an on-disk postmortem, name the actual path you wrote to (so the user can `cat` it directly).

**Item-runner digest (extra rule).** `auto-roadmap-item-runner` prefixes its status line with a compact multi-line **report card** (item title, model, audit tally, commit, `task_id:`, and — only on `--next` — `roadmap_mtime:`). The driver prints the whole card and greps it for the `task_id:` / `roadmap_mtime:` fields. The card MUST stay compact — never echo the diff bundle or verbatim lens findings (they live in `audit.md` + `git`); its size is what keeps a long run under the context ceiling. The final `OK:` / `FAIL at <stage>:` line still obeys every rule above.
