# Troubleshooting

First-run problems you may hit as a new user, then edge cases when integrating with the pipeline or invoking its agents by hand.

## First run

### `/task:` commands don't appear after installing

**Symptom** — typing `/task:` shows nothing; no `/task:bootstrap`, `/task:design`, etc.

**Cause** — the `task` plugin isn't installed/enabled in this session, or the marketplace was never added.

**Fix** —

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

Then reopen the `/` menu. If it was already installed, make sure it isn't disabled (`/plugin`).

### `ERROR precondition: …/config.md not found. Run /task:bootstrap first.`

**Symptom** — a skill stops immediately with `ERROR precondition: …/.task/config/config.md not found. Run /task:bootstrap first.`

**Cause** — every skill except `/task:bootstrap` needs `.task/config/config.md`, and it hasn't been created in this project yet.

**Fix** — run `/task:bootstrap` once; it writes the config. If you already ran it, you may be in a different git worktree — see "A linked worktree has no `.task/`" below.

### `.task/` shows up in `git status`

**Symptom** — `.task/` or `.task-current` appears as untracked in `git status`.

**Cause** — the local git exclusion wasn't written (e.g. `.task/` was created before bootstrap, or bootstrap ran outside a git repo).

**Fix** — re-run `/task:bootstrap` (idempotent); it adds `.task` and `.task-current` to `.git/info/exclude`. The pipeline uses `.git/info/exclude`, not `.gitignore`, on purpose — the state stays invisible to teammates.

### `validate.sh` ends with `FAIL N error(s)`

**Symptom** — an artifact check ends with `FAIL <N> error(s), <M> warning(s)`, preceded by one or more `ERROR <label>: <message>` lines.

**Cause** — a `task.md` / `plan.md` / roadmap file drifted from the expected format (bad header, missing required section, wrong separator).

**Fix** — read the `ERROR <label>:` lines (each names the file and the problem) and fix the artifact by hand — they are plain Markdown. Re-check with `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. A `WARN` on its own does not block.

### A linked worktree has no `.task/`

**Symptom** — in a second git worktree, skills can't find the config or `.task-current`, or `.task` is missing.

**Cause** — `.task/` lives in the main worktree and is git-excluded, so a fresh linked worktree doesn't inherit it.

**Fix** — run `/task:bootstrap` in the linked worktree; in join-mode it symlinks `.task` → the main worktree's `.task/` and wires the exclusion. (Set up the main worktree first if it never was.)

### `--auto stopped: <reason>`

**Symptom** — `/task:build --auto` (or `/task:auto-roadmap`) prints `--auto stopped: <reason>. See <path>.` and halts.

**Cause** — expected, not a crash: a per-phase budget was reached (implement runs once; audit stops after 2 non-converging iterations).

**Fix** — open the named artifact (`audit.md` / `summary.md`), finish what's left by hand or with a plain `/task:build`, then continue. `--auto` is intentionally one-shot.

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
