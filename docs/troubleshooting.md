# Troubleshooting

Edge cases you may hit when integrating with the pipeline or invoking its agents by hand.

## Manual `Agent(...)` calls need the `task:` prefix

The named agents are installed as part of the plugin — eight files under `agents/`: six auditor-class (three for the `/task:build` audit phase — Reuse / Simplicity / Clarity — and three for `/task:roadmap --refine` — Coverage / Decomposition / Clarity) and two executor-class (`auto-roadmap-design-runner.md` and `auto-roadmap-build-runner.md`).

> [!WARNING]
> If you invoke these agents manually via `Agent(...)` from your own integrations, you **must** use the plugin prefix:
> `subagent_type: task:audit-reuse-auditor` / `task:audit-simplicity-auditor` / `task:audit-clarity-auditor` / `task:audit-roadmap-coverage-auditor` / `task:audit-roadmap-decomposition-auditor` / `task:audit-roadmap-clarity-auditor` / `task:auto-roadmap-design-runner` / `task:auto-roadmap-build-runner`.
>
> Without the prefix the runtime silently routes to the catch-all `claude` agent — it looks like "0 tool uses Done", with no error.

## A skill's bash script fails with `No such file or directory`

Symptom — the model writes something like this in the Bash tool:

```
CLAUDE_SKILL_DIR="/.../skills/build" bash "${CLAUDE_SKILL_DIR}/audit-context.sh"
→ bash: /audit-context.sh: No such file or directory  (exit 127)
```

Cause — Claude Code substitutes `${CLAUDE_SKILL_DIR}` into the skill text **at prompt load time** (it is not a shell env var), and the model is supposed to run the command verbatim. When the model "defensively" adds an inline assignment `CLAUDE_SKILL_DIR=… bash "${CLAUDE_SKILL_DIR}/…"` on the same line, bash expands the variable in the parent shell *before* the assignment takes effect, so the path resolves to nothing → `bash "/audit-context.sh"`.

A second variant shows up in `/task:auto-roadmap`: its audit phase runs inline — the main thread reads `skills/build/phases/audit.md` directly, no `${CLAUDE_SKILL_DIR}` substitution happens, and the model guesses the path from the directory of the file it read → it wrongly puts the script in `phases/` (`.../skills/build/phases/audit-context.sh` → exit 127), even though `audit-context.sh` lives in the **root** of the build skill. On a second try the model usually climbs back up to the root on its own.

Each skill that uses `${CLAUDE_SKILL_DIR}` explicitly tells the model to "run verbatim" right next to the bash block; the inline call from auto-roadmap additionally provides the ready-made absolute path `${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh`. Update the plugin: `/plugin marketplace update task-pipeline`.

Manual workaround (if you can't update):

```bash
CLAUDE_SKILL_DIR="<abs-path-to-skill-root>" bash -c 'bash "${CLAUDE_SKILL_DIR}/<script>.sh"'
```

The assignment and expansion happen in a single child shell in the right order.
