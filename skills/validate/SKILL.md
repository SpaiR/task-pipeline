---
name: validate
description: Validate the format of task-pipeline artifacts (task.md, plan.md, .task/roadmap/*.md). Internal utility — invoked from context scripts and the PreToolUse hook; not user-invocable.
disable-model-invocation: true
user-invocable: false
model: inherit
---

Validate the format of task-pipeline artifacts. This skill is a thin wrapper around `validate.sh` — it produces a structured pass/fail report so the pipeline can fail closed on malformed artifacts before a downstream skill (`/task:design`, `/task:build`, `/task:ship`) parses them and silently misbehaves. **Not user-invocable**: the bash script is dispatched directly from context scripts and the plugin's PreToolUse hook.

**Input (when invoked manually via bash):** one of: `task [<task-id>]`, `plan [<task-id>]`, `roadmap <path|slug>`, `all`. For `task` / `plan` the workspace subfolder is resolved through `_lib/resolve-ws.sh` (priority: `$TASK_ID_OVERRIDE` > positional > `.task-current`); `all` tolerates a missing `.task-current` and skips workspace validation in that case.

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gate in `validate.sh` itself is authoritative (the script enforces the `.task/config/config.md` precondition and exits 2 on miss). Internal utility — not user-invocable; the language pointer is informational only (validator output is fixed English by design, parser-stable).

## What gets validated

| Artifact | Checks |
|----------|--------|
| `.task/workspace/<task-id>/task.md` | line 1 matches `# [task-id] <title>`; `---` separator present; `## Description` heading present |
| `.task/workspace/<task-id>/plan.md` | line 1 matches `# Plan: <title>`; `## Steps` present with ≥1 `### Step N:` block; each step has non-empty `Goal:` and `Touches:`; `Touches` contains no `...` placeholder; `## Verification` present; if `## Tests` is present, ≥1 `### Test N:` block must exist (`## Risks` is optional and not validated) |
| `.task/roadmap/<slug>.md` | ≥1 `### N. <title>` heading (with optional `- [ ]`/`- [x]` checkbox); each task block has `**Ready description:**` and the English sub-headings `### Context`, `### Goal`, `### Outcomes`, `### Acceptance criteria` (mandatory contract with `/task:design --from`) |

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

Context scripts (`audit-context.sh`, `commit-context.sh`) and `close.sh` invoke `validate.sh` directly as a precondition gate after the `config.md` check. A failure aborts the script with a non-zero exit code, which stops the calling skill before it parses an invalid artifact. Orchestrator skills (`/task:design`, `/task:build`) call the validator inline at Step 0.

## PreToolUse hook (shipped with the plugin)

The plugin includes a PreToolUse hook (`hooks/hooks.json`) that runs `validate.sh all` before any `Skill(task:design|build|ship|auto-roadmap)` invocation. The hook tolerates the absence of `.task-current` (so it does not block `/task:bootstrap` or design's open phase or `/task:auto-roadmap` from running before an umbrella exists). This turns the in-skill checks into runtime-enforced gates that survive prompt injection and accidental skill-prompt edits. The hook activates automatically with the plugin.

## Output

- Subcommand executed.
- Full issue list from the script.
- Exit summary.
- (On failure) one-line suggestion for the next remedial skill.
