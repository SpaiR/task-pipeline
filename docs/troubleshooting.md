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

**Fix** — run `/task:bootstrap` once; it writes the config. If you already ran it elsewhere, see "A worktree can't find `.task/`" below.

### `.task/` shows up in `git status`

**Symptom** — `.task/` appears as untracked in `git status`.

**Cause** — the local git exclusion wasn't written (e.g. `.task/` was created before bootstrap, or bootstrap ran outside a git repo).

**Fix** — re-run `/task:bootstrap` (idempotent); it adds `.task` to `.git/info/exclude`. The pipeline uses `.git/info/exclude`, not `.gitignore`, on purpose — the state stays invisible to teammates. (The active-task pointer never shows up — it lives inside git's per-worktree dir, outside the work tree.)

### `validate.sh` ends with `FAIL N error(s)`

**Symptom** — an artifact check ends with `FAIL <N> error(s), <M> warning(s)`, preceded by one or more `ERROR <label>: <message>` lines.

**Cause** — a `task.md` / `plan.md` / roadmap file drifted from the expected format (bad header, missing required section, wrong separator).

**Fix** — read the `ERROR <label>:` lines (each names the file and the problem) and fix the artifact by hand — they are plain Markdown. Re-check with `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. A `WARN` on its own does not block.

### A worktree can't find `.task/`

**Symptom** — in a second git worktree, skills stop with `config.md not found` even though the repo is bootstrapped.

**Cause** — worktrees resolve the shared `.task/` through `git config task.root` (fallback `dirname(git-common-dir)`). This normally needs no setup, but the anchor can be missing (repo bootstrapped by an older version) or wrong (a bare repo whose `.task/` you put somewhere non-default).

**Fix** — run `/task:bootstrap` from any worktree; it records `task.root` and every worktree then resolves the same `.task/`. To point the pipeline at an existing `.task/` yourself (e.g. an unusual bare-repo layout), set it directly: `git config --local task.root /abs/path/containing/dot-task` (the directory that *contains* `.task`, not `.task` itself).

## Escape hatches (advanced flags)

Day-to-day you never need a flag: `/task:design`, `/task:build`, and `/task:ship` walk you through the whole cycle with a question at each phase boundary, and `/task:ship` infers its close mode. The flags below still exist — as shortcuts that **skip** the corresponding question, as a way to **force** a phase when auto-detect guessed wrong, and as the interface the non-interactive `/task:auto-roadmap` runners drive internally. They are deliberately off the everyday surface; this is where they live.

(`/task:auto-roadmap`'s own flags — `--next` / `--from #<N>` / `--items <spec>` — are **not** hidden: that command is the sanctioned batch/power surface and documents them in the [README](../README.md).)

| Flag | Skill | What it forces / skips | Interactive equivalent (the default) |
|------|-------|------------------------|--------------------------------------|
| `--phase <open\|blueprint\|refine>` | `/task:design` | Force one design phase, bypassing auto-detect. The **main recovery hatch** when the workspace state makes auto-detect pick the wrong phase. | Auto-detect from workspace state + the advance questions. |
| `--phase <implement\|audit>` | `/task:build` | Force one build phase. | Auto-detect + the implement→audit advance question. |
| `--from <path>[#<N>]` | `/task:design` | Open a specific roadmap item as the umbrella (with `#<N>`, that exact item). | Entry-fork chip **"Open from a roadmap"** → roadmap picker → item picker. |
| `--refine [<slug>]` | `/task:roadmap` | Parallel three-lens audit (Coverage / Decomposition / Clarity, ≤2 iterations) of an existing roadmap. | The inline refine offer that authoring makes when its light self-check finds enough to warrant it. |

### Repair-level: refine an existing plan

**When** — a `plan.md` is complete but you suspect it is wrong: the decomposition is off, a step's approach won't work, or a better alternative surfaced after blueprint. This is a repair capability, not part of the routine design → build → ship flow, and it is the **only** design phase with no auto/question path — you must ask for it.

**Fix** — run `/task:design --phase refine` on the active umbrella. The refine phase critically reviews the current `plan.md`, proposes alternatives, and records the chosen changes in `## Decisions` so `/task:build` implement honors them. Use it only when the plan itself needs rework; for normal progress after blueprint, just answer **"Start implementing now?"** with yes (or run `/task:build`).

> Note: this is design's plan-refine, distinct from `/task:roadmap --refine` (a roadmap audit, in the table above).

## Manual `Agent(...)` calls need the `task:` prefix

The named agents are installed as part of the plugin — nine files under `agents/`: six auditor-class (three for the `/task:build` audit phase — Reuse / Simplicity / Clarity — and three for `/task:roadmap --refine` — Coverage / Decomposition / Clarity) and three executor-class (`auto-roadmap-item-runner.md` and the two runners it spawns, `auto-roadmap-design-runner.md` and `auto-roadmap-build-runner.md`).

> [!WARNING]
> If you invoke these agents manually via `Agent(...)` from your own integrations, you **must** use the plugin prefix:
> `subagent_type: task:audit-reuse-auditor` / `task:audit-simplicity-auditor` / `task:audit-clarity-auditor` / `task:audit-roadmap-coverage-auditor` / `task:audit-roadmap-decomposition-auditor` / `task:audit-roadmap-clarity-auditor` / `task:auto-roadmap-item-runner` / `task:auto-roadmap-design-runner` / `task:auto-roadmap-build-runner`.
>
> Without the prefix the runtime silently routes to the catch-all `claude` agent — it looks like "0 tool uses Done", with no error.

## A skill's bash script fails with `No such file or directory`

Symptom — the model writes something like this in the Bash tool:

```
CLAUDE_SKILL_DIR="/.../skills/build" bash "${CLAUDE_SKILL_DIR}/audit-context.sh"
→ bash: /audit-context.sh: No such file or directory  (exit 127)
```

Cause — Claude Code substitutes `${CLAUDE_SKILL_DIR}` into the skill text **at prompt load time** (it is not a shell env var), and the model is supposed to run the command verbatim. When the model "defensively" adds an inline assignment `CLAUDE_SKILL_DIR=… bash "${CLAUDE_SKILL_DIR}/…"` on the same line, bash expands the variable in the parent shell *before* the assignment takes effect, so the path resolves to nothing → `bash "/audit-context.sh"`.

A second variant shows up in `/task:auto-roadmap`: its audit phase runs inline inside the `auto-roadmap-item-runner` — that subagent reads `skills/build/phases/audit.md` directly, no `${CLAUDE_SKILL_DIR}` substitution happens, and it guesses the path from the directory of the file it read → it wrongly puts the script in `phases/` (`.../skills/build/phases/audit-context.sh` → exit 127), even though `audit-context.sh` lives in the **root** of the build skill. On a second try it usually climbs back up to the root on its own.

Each skill that uses `${CLAUDE_SKILL_DIR}` explicitly tells the model to "run verbatim" right next to the bash block; the inline call from auto-roadmap additionally provides the ready-made absolute path `${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh`. Update the plugin: `/plugin marketplace update task-pipeline`.

Manual workaround (if you can't update):

```bash
CLAUDE_SKILL_DIR="<abs-path-to-skill-root>" bash -c 'bash "${CLAUDE_SKILL_DIR}/<script>.sh"'
```

The assignment and expansion happen in a single child shell in the right order.
