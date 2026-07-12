---
name: validate
description: Validate the format of task-pipeline artifacts (.task/task/<slug>.md, .task/roadmap/*.md). Internal utility — an optional self-check the intake skills run at Step 0; not user-invocable.
disable-model-invocation: true
user-invocable: false
model: inherit
---

Validate the format of task-pipeline artifacts. This skill is a thin wrapper around `validate.sh` — it produces a structured pass/fail report so a skill can catch a malformed artifact before it is parsed downstream. **Not user-invocable**: the bash script is dispatched directly by the intake skills. In v3 this is an **optional self-check, not a gate** — there is no PreToolUse hook; a WARN/ERROR is reported, and only a genuinely absent `.task/config/config.md` hard-stops (the setup case the intake skills handle inline).

**Input (when invoked manually via bash):** one of: `task <slug>`, `roadmap <slug|path>`, `all`. `task <slug>` validates `.task/task/<slug>.md`; `all` validates every `.task/task/*.md` and every `.task/roadmap/*.md`, tolerating an empty `.task/task/`.

**Format contract, preconditions:** see [docs/contract.md](../../docs/contract.md) — the bash gate in `validate.sh` itself is authoritative (the script enforces the `.task/config/config.md` precondition and exits 2 on miss). Validator output is fixed English by design, parser-stable.

## What gets validated

| Artifact | Checks |
|----------|--------|
| `.task/task/<slug>.md` | line 1 matches `# <Title>` (`^# .+`, no `[TASK-ID]` bracket); `---` separator present; `## Description` heading present. `## Plan` is **optional** — if present, must contain ≥1 `### Step N:` block. `## Tests` is **optional** — if present, must contain ≥1 `### Test N:` block. |
| `.task/roadmap/<slug>.md` | ≥1 `### N. <title>` heading (with optional `- [ ]`/`- [x]` checkbox); each task block carries the English sub-headings `### Context`, `### Goal`, `### Outcomes`, `### Acceptance criteria` (the contract consumed by `/task:to-task` / `/task:to-plan` when opening from an item) |

The slug is the identifier and the filename — there is no task-id, no workspace subfolder, and no active-task pointer to resolve. There is no `plan` subcommand (the plan lives inside `task.md` under `## Plan`) and no `Implement-Model:` check (the per-item model hint lives on roadmap items, not in `task.md`).

## How the script is invoked

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" <subcommand> [arg]
```

The script prints one issue per line in the format `ERROR <artifact>: <message>` or `WARN <artifact>: <message>` to stderr, followed by a final summary line `OK 0 errors, N warning(s)` or `FAIL X error(s), N warning(s)`.

Exit codes:

- `0` — all checks passed
- `1` — at least one validation error
- `2` — usage error or missing `.task/config/config.md`

## How other skills use the validator

The intake skills (`/task:to-task`, `/task:to-plan`, `/task:to-roadmap`) call `validate.sh all` at their Step 0 as an optional self-check after the config precondition: a WARN/ERROR is surfaced alongside the rest of the output, but only the config-absent case hard-stops (and that triggers the inline setup, not an abort). There is no execution skill (`build`/`ship` were removed in v3) and no hook — an executing session or `roadmap-to-workflow` simply reads the artifact directly.

## Output

- Subcommand executed.
- Full issue list from the script.
- Exit summary.
- (On failure) one-line suggestion for the next remedial skill.
