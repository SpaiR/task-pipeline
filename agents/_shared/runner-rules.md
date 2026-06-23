# Shared rules for `auto-roadmap-{design,build}-runner`

Rules inherited by the two roadmap runners from their nested phase files (`skills/design/phases/{open,blueprint}.md`, `skills/build/phases/implement.md`) and from project invariants. Centralized here so editors of either side see a single registry of cross-cutting constraints — a misread of a nested phase file in autopilot cannot silently degrade behavior if the rule is also restated here.

The per-item cycle is split: `auto-roadmap-design-runner` runs Steps a + b (open + blueprint), then returns; the orchestrator's main thread reads `plan.md → Implement-Model:` and spawns `auto-roadmap-build-runner` with the matching `Agent.model` override (`opus`, `sonnet`, or `haiku`) to run Step c (implement). Rules below apply to whichever runner enters the corresponding nested phase.

When editing any rule below, **also update its source-of-truth file** — drift between this list and the source is itself a bug:

| Rule | Applies to | Source of truth |
|------|------------|------------------|
| One quick-fix max during implement | `auto-roadmap-build-runner` | `skills/build/phases/implement.md` |
| Append-only artifacts | both runners | `docs/spec/invariants.md` § Universal |
| Mandatory verification before `TaskUpdate(completed)` | `auto-roadmap-build-runner` | `skills/build/phases/implement.md` |
| MCP-first tooling in nested phases | both runners (within blueprint / implement) | `docs/spec/invariants.md` § Code-navigation tiers + `.task/config/config.md` |
| Implement-Model rubric stamp in `plan.md` | `auto-roadmap-design-runner` | `skills/design/phases/blueprint.md` § Step 3 |

## Rules

- **One quick-fix max during implement.** On a single obvious failure (typo, missing import, wrong symbol name in `Touches`) apply one targeted fix and re-run. Further failure → stop. No shotgun fixes. (Build-runner only.)
- **Append-only artifacts.** `## Decisions` in `task.md` / `plan.md` is append-only. (Both runners.)
- **Mandatory verification before `TaskUpdate(completed)`** for each step in implement: Identify → Run → Read → State. `Touches` symbols must be visible in `git diff`; if `## Tests` is present, RED→GREEN must be observed. (Build-runner only.)
- **MCP-first tooling.** For code navigation and editing inside any nested phase (`blueprint`, `implement`), use MCP tools from `.task/config/config.md` → "Code Navigation" / "Code Editing" in the priority order listed there. Built-in `Read`/`Edit`/`Grep`/`Glob`/`ls` are allowed only when `config.md` explicitly lists them as fallback; otherwise justify the choice in one line before calling. **Read `config.md` once at the start of your run** — both runners are interactive-session subagents, so `config.md` is available throughout their context.
- **Implement-Model rubric.** Design-runner MUST apply `blueprint.md` § Step 3's rubric honestly (`opus` for cross-cutting / >5 steps / >3 modules / subtle invariants; `sonnet` for typical isolated changes; `haiku` for ≤2-step single-module mechanical edits; `sonnet` when uncertain). The stamp is load-bearing — the orchestrator reads `plan.md → Implement-Model:` between design-runner OK and build-runner spawn, and passes the value as the `Agent.model` override. Too cheap → implement may flap on verification; too dear → the run pays opus rates for trivial work. (Design-runner only — build-runner just echoes the chosen value in its `implement_model` input field.)

## Postmortem path resolution

When a runner fails it dumps a postmortem to the error log via the shared formatter (`skills/_lib/fail-log.sh`). Path resolution is gated on whether the workspace subfolder exists:

1. **`.task-current` exists at the worktree root and `.task/workspace/<id>/` exists** (where `<id>` = `cat .task-current`) → write `.task/workspace/<id>/auto-error.log`. This is the post-open path.
2. **Otherwise** (design-runner failed in Step a before `/task:design --from` landed `.task-current`) → **no on-disk postmortem**. Return the FAIL status line with the inline reason as the only record; the user reads it directly in the orchestrator's output. There is no worktree-local fallback file.

`auto-roadmap-build-runner` always sees branch 1 (build-runner is only spawned after design-runner OK, so the subfolder is guaranteed). `auto-roadmap-design-runner` may hit either branch depending on where in Step a the failure occurred. The orchestrator (`auto-roadmap/SKILL.md` Substep 3.7) applies the same two-branch resolution when appending its own `--- ORCHESTRATOR FAIL ---` block.

## Return format (shared rules)

Both runners end their reply with exactly one status line — the **last non-empty line** of the reply. The orchestrator scans bottom-up and routes off that line; anything above it is log output and is not used for routing.

Rules common to both runners (per-runner OK/FAIL grammars live in each agent's own `## Return format` section):

- **Stands alone.** No trailing prose, no Markdown decoration around the status line, no blank lines after it that contain anything but whitespace.
- **English regardless of `config.md` → "Language".** The status lines are parser-stable identifiers, not user-facing prose.
- **The trailing clause is part of the status string** (`"— plan.md ready, awaiting implement"` for design-runner; `"— diff uncommitted, ready for audit"` for build-runner). Load-bearing — the orchestrator pattern-matches on it to distinguish the two runners. Do not omit it.
- **Closed enum for `<stage>`** — each runner's `## Return format` lists the exact accepted values. Never emit any other.
- **Never improvise a third shape.** If you cannot construct a valid `OK:`, emit `FAIL at <stage>: …` instead. Anything else is malformed and the orchestrator follows the fail-stop protocol with reason `runner returned malformed status`.
- **Error-log path naming.** On failure with an on-disk postmortem, name the actual path you wrote to (so the user can `cat` it directly).
