# task-pipeline

A linear task workflow for Claude Code: from intake to commit, through explicit checkpoints, on your terms.

## TL;DR

```text
/task:bootstrap                # once per project
/task:design "what we're doing" # open a task and write a plan
/task:build   →   /task:ship   # implement, review, commit
```

## Why

If you've ever tried to cram Claude into one big "do everything in this ticket" session, you know how it ends: the model starts writing code before it understands the task; it "fixes" one bug and breaks three others; it reports "done" while half the acceptance criteria are still stubs. `task-pipeline` solves this not with magic but with boring discipline: each stage of a task is a separate slash command with an explicit contract, artifacts live as files in `.task/`, and nothing runs "by itself."

Concretely, you get:

- **Three explicit checkpoints.** `/task:design` (plan), `/task:build` (implementation + checks), `/task:ship` (commit + close). You decide when to move on. You can stop, fix an artifact by hand, and continue.
- **A paper trail.** `task.md` (what and why), `plan.md` (how), `audit.md` (what the audit found), `summary.md` (the result). All plain Markdown, readable without an agent, reviewable by eye.
- **Project-aware.** A single `/task:bootstrap` pins down the stack, the MCP tool priority (Serena, context7, ast-grep…), and the commit format. Every step follows it afterward — no "how do you do it here?" round-trips.
- **Multilingual.** Task descriptions and discussion happen in your language (English, Russian, anything). The plan, audit, and commits follow the policy in `config.md`.
- **Invisible to the project.** All pipeline state lives in `.task/`, excluded via `.git/info/exclude` (not `.gitignore`). A colleague who clones the repo without the pipeline sees no trace of it.
- **Bounded auto-fix + filters.** `/task:build` automatically applies the problems it finds (≤2 iterations), but only within the declared `Touches` scope from the plan. Weak or out-of-scope findings are not applied — they land in `### Filtered (low confidence)` for manual review.
- **An archive.** `/task:ship` files completed subtasks under `.task/log/{task-id}/{N}-{slug}/`. Six months later you can still see what was done, and when, for each ticket.

## Quick start

```
/task:bootstrap  — once per project; creates .task/config/config.md
  ↓
[/task:roadmap [--refine]]  — optional; roadmap for a large initiative → .task/roadmap/<slug>.md
  ↓                          --refine: parallel audit of an existing roadmap
                              (Coverage / Decomposition / Clarity, ≤2 iterations)
  ├─→ [/task:auto-roadmap] — optional; autopilot over an approved roadmap
  ↓                         in the current interactive session.
/task:design  — open a task, write the Description, plan it out
  ↓             (phase auto-detect: open(quick-draft) → blueprint; [--idea] brainstorm, [--refine] opt.)
/task:build [--auto] — implementation + audit with an auto-fix loop
  ↓             (phase auto-detect: implement → audit;
                 --auto — opt-in: both phases in one call)
/task:ship [--next]  — commit + close
                        default → full close of the umbrella task (--full is an alias)
                        --next  → transition to the next subtask (task.md stays)
```

Re-entry semantics: `/task:design` and `/task:build` look at the state of `.task/workspace/<task-id>/` and automatically resume from the right phase. To override: `--phase <open|idea|blueprint|refine|implement|audit>`. `/task:build` additionally accepts `--auto` (opt-in one-shot: runs `implement → audit` in a single call, mutually exclusive with `--phase`).

`validate` is an internal utility: the pipeline invokes it as a precondition gate. It is not called via a slash command; for a manual check run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`.

### Umbrella task vs subtask

In this pipeline, `task.md` is an **umbrella task**: a task with one `task-id` and a shared title, under which there may be several subtasks. Each `/task:design → /task:build → /task:ship` cycle is one subtask. By default `/task:ship` closes the umbrella task entirely (`--full` is a backward-compatible alias). `/task:ship --next` clears the Description and keeps the title — the next cycle starts from the same umbrella task.

## Installation

The pipeline ships as a Claude Code plugin (`task`) inside the `task-pipeline` marketplace. The recommended path is through the marketplace:

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

From then on, updates are a single command: `/plugin marketplace update task-pipeline`.

After installation, Claude Code gains the commands `/task:bootstrap`, `/task:design`, `/task:build`, `/task:ship`, `/task:roadmap`, `/task:auto-roadmap`. The built-in PreToolUse artifact-validator hook activates automatically. Named agents are installed as part of the plugin — eight files under `agents/`: six auditor-class (three for the `/task:build` audit phase — Reuse / Simplicity / Clarity — and three for `/task:roadmap --refine` — Coverage / Decomposition / Clarity) drive the parallel audit; two executor-class (`auto-roadmap-design-runner.md` and `auto-roadmap-build-runner.md`) let `/task:auto-roadmap` run the per-item design (open + blueprint) and build (implement) phases separately. The split into two runners lets the implement stage run on a cheaper model than design + audit + ship: the orchestrator reads `plan.md → Implement-Model:` (`opus|sonnet|haiku`) between the two spawns and passes the value into `Agent.model` for the build runner.

> ⚠️ If you invoke these agents manually via `Agent(...)` from your own integrations, you must use the plugin prefix: `subagent_type: task:audit-reuse-auditor` / `task:audit-simplicity-auditor` / `task:audit-clarity-auditor` / `task:audit-roadmap-coverage-auditor` / `task:audit-roadmap-decomposition-auditor` / `task:audit-roadmap-clarity-auditor` / `task:auto-roadmap-design-runner` / `task:auto-roadmap-build-runner`. Without the prefix the runtime silently routes to the catch-all `claude` agent — it looks like "0 tool uses Done", with no error.

In a new project: call `/task:bootstrap` once. The skill inspects the repo, asks two interactive questions (language, test policy), and writes `.task/config/config.md`.

<details>
<summary>Local development</summary>

```text
/plugin marketplace add /path/to/task-pipeline
/plugin install task@task-pipeline
```

</details>

<details>
<summary>If a skill's bash script fails with <code>No such file or directory</code></summary>

Symptom — the model writes something like this in the Bash tool:

```
CLAUDE_SKILL_DIR="/.../skills/build" bash "${CLAUDE_SKILL_DIR}/audit-context.sh"
→ bash: /audit-context.sh: No such file or directory  (exit 127)
```

Cause — Claude Code substitutes `${CLAUDE_SKILL_DIR}` into the skill text **at prompt load time** (it is not a shell env var), and the model is supposed to run the command verbatim. When the model "defensively" adds an inline assignment `CLAUDE_SKILL_DIR=… bash "${CLAUDE_SKILL_DIR}/…"` on the same line, bash expands the variable in the parent shell *before* the assignment takes effect, so the path resolves to nothing → `bash "/audit-context.sh"`.

A second variant shows up in `/task:auto-roadmap`: its audit phase runs inline — the main thread reads `skills/build/phases/audit.md` directly, no `${CLAUDE_SKILL_DIR}` substitution happens, and the model guesses the path from the directory of the file it read → it wrongly puts the script in `phases/` (`.../skills/build/phases/audit-context.sh` → exit 127), even though `audit-context.sh` lives in the **root** of the build skill. On a second try the model usually climbs back up to the root on its own.

Each skill that uses `${CLAUDE_SKILL_DIR}` explicitly tells the model to "run verbatim" right next to the bash block; the inline call from auto-roadmap additionally provides the ready-made absolute path `${CLAUDE_PLUGIN_ROOT}/skills/build/audit-context.sh`. Update the plugin: `/plugin marketplace update task-pipeline`. Manual workaround (if you can't update): `CLAUDE_SKILL_DIR="<abs-path-to-skill-root>" bash -c 'bash "${CLAUDE_SKILL_DIR}/<script>.sh"'` — the assignment and expansion happen in a single child shell in the right order.

</details>

## Structure & artifacts

Each `.task/` subfolder has exactly one role:

```
.task/
  config/config.md          ← pipeline settings (created by /task:bootstrap)
  log/<task-id>/<N>-<slug>/ ← archive of closed subtasks (append-only history)
  roadmap/<slug>.md         ← roadmap for a large initiative (backlog)
  roadmap/<slug>.spec.md    ← (opt.) sidecar of the initiative's key technical decisions;
                              items reference its sections via ### Spec references,
                              blueprint reads them during implementation
  roadmap/<slug>.refine.md  ← (opt.) findings sidecar for /task:roadmap --refine
                              (append-only ## Iteration N; high → auto-fix, med/low → manual review)
  workspace/<task-id>/      ← the active umbrella task (umbrella subfolder)
    task.md                 ← title + Description
    plan.md                 ← implementation plan
    audit.md                ← findings from audit iterations
    summary.md              ← final summary for the commit
    auto.lock               ← (only during /task:auto-roadmap: per-umbrella sentinel)
    auto-error.log          ← (postmortem on a /task:auto-roadmap FAIL)
```

The pointer to the active umbrella task is a single-line file `.task-current` in the **root of the worktree** (it holds the lowercase task-id), excluded via `.git/info/exclude`. The path to the subfolder is resolved through it — each worktree, holding its own `.task-current`, automatically lands in its own umbrella task.

Inside `log/<task-id>/<N>-<slug>/` the files lie **flat** (no `workspace/` subfolder) — it's an archive, not active state.

### Umbrella-task files

Each umbrella task lives in `.task/workspace/<task-id>/`. All files are plain Markdown:

- `task.md` — what we're doing and why (Description; sometimes Decisions from the Socratic mode of design idea).
- `plan.md` — how we're doing it (Steps with a three-layer Goal/Touches/Logic contract; optional Tests).
- `audit.md` — what the audit found. **Append-only** by iteration.
- `summary.md` — the result in ≤ 8 lines, overwritten each time. The source of the commit message.
- `auto.lock`, `auto-error.log` *(written by `/task:auto-roadmap`)* — on success the last item is closed with `/task:ship --full` (Substep 3.9 Branch B, slug from `summary.md`), which sweeps the whole subfolder; on failure the user runs `/task:ship --full chore-finalize` manually.

All bash scripts resolve `WS_DIR` through the shared helper `skills/_lib/resolve-ws.sh` (priority: `$TASK_ID_OVERRIDE` env > positional argument > `.task-current`).

The full inter-skill contract is in [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md).

### Parallel worktrees

The `.task/` folder is excluded from git, so a freshly created worktree doesn't contain it. Access to the shared state is provided by a symlink `.task` → the main tree's `.task/`. You don't need to create it by hand — `/task:bootstrap` does it:

```bash
# Create the worktree however you like:
git worktree add ../my-repo-wt2 -b parallel-feature
cd ../my-repo-wt2

/task:bootstrap          # sees a linked worktree without .task →
                         # makes a symlink .task → <main>/.task, appends to
                         # .git/info/exclude, and exits (config untouched)

/task:design implement parallel-feature
# creates .task/workspace/<task-id-2>/ (in the shared tree) and .task-current (its own)
```

`/task:bootstrap` is safe in a worktree: on a repeat run it's a no-op, and it never overwrites a foreign/broken symlink or a real `.task` folder — it asks you to sort it out by hand instead. If you forget to wire it up, the first pipeline command will prompt you to run `/task:bootstrap`. (Alternative — set the symlink by hand: `ln -s "$(cd ../my-repo/.task && pwd -P)" .task`.)

Each worktree has its own `.task-current` (it is **not** symlinked). Discipline for the shared `.task/`:

- **one task — one tree**: the shared `workspace/<task-id>/` — don't run a single task-id in two trees;
- **one roadmap — one tree** for `/task:ship`: the auto-mark of `roadmap/<slug>.md` is not locked across trees;
- **don't delete the main tree** while linked worktrees are alive (the symlinks would become broken).

More detail in [docs/spec/auto-roadmap.md § Cross-worktree safety](docs/spec/auto-roadmap.md#cross-worktree-safety).

## Commands

| Command | In brief |
|--------|--------|
| `/task:bootstrap` | Initializes the pipeline in a project: creates `.task/config/config.md`, sets up the local git exclusion for `.task/`. Idempotent. |
| `/task:roadmap <idea> \| --refine [<slug>]` *(opt.)* | Brainstorms an initiative roadmap → `.task/roadmap/<slug>.md` with ready-made task descriptions for `--from`. An optional sidecar `.task/roadmap/<slug>.spec.md` pins down key technical decisions (Blueprint reads them during planning). `--refine` — a parallel audit of an existing roadmap (Coverage / Decomposition / Clarity, ≤2 iterations; high → auto-applied, med/low → manual review). |
| `/task:auto-roadmap [<roadmap>] [--next \| --from #<N> \| --items <spec>]` *(opt.)* | Autopilot over a roadmap in the current interactive Claude Code session: for each item — design → build → ship. `--next` — the first unclosed item; `--from #N` — start from item N; `--items 3-5` or `1,3-5,8` — a selection. |
| `/task:design [<context>] [--from <path>[#<N>]] [--idea] [--phase <name>] [--refine]` | Open a task, write the Description, plan it out. Phase auto-detect (`open` → `blueprint`); `--phase` override. `--idea` — brainstorm the Description (architect from scratch / Socratic on a filled-in one). `--from <path>[#N]` — Description from a roadmap item. `--refine` — refine `plan.md`. |
| `/task:build [--phase <name>] [--auto]` | Implementation (`implement`) + audit with bounded auto-fix (`audit`). `--auto` — both phases in one call (≤1 implement, ≤2 audit). `--phase` — override. Fixes outside `Touches` from `plan.md` are marked `Skipped: out-of-scope`. |
| `/task:ship [--next] [<slug>]` | Commit + archiving under `.task/log/`. Default — full close: `workspace/<task-id>/` and `.task-current` are removed (`--full` is a backward-compatible alias). `--next` — `task.md` stays (Description cleared), transition to the next subtask. Auto-marks the roadmap item when `Roadmap:` + `Source item:` are present. |
| `validate` *(utility)* | Formal validator of artifact format. Invoked automatically. For a manual check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" [task\|plan\|roadmap <path>\|all]`. |

## Scenarios

### A. A single task

```text
/task:bootstrap                                  # once per project

# Manual mode — title + Description in one call (quick-draft):
/task:design "I want an HTTP retry system with backoff and dead-letter" # phase=open + quick-draft:
                                                 # task.md with a filled-in Description
                                                 # (### Problem / ### Outcome / ...)

# Need a multi-round Description brainstorm — the --idea flag:
/task:design --idea "an idea for X"              # open(header-only) → idea(architect) in one call
#   (alternative to the same entry: an empty /task:design when there's no task yet
#    — the skill asks for the idea and drops into architect)

/task:design                                     # phase=blueprint: a plan with steps
/task:design --idea                              # opt.: idea(Socratic) — refine the Description
/task:design --refine                            # opt.: phase=refine: plan alternatives

/task:build                                      # phase=implement: implement per the plan
/task:build                                      # phase=audit: lens fanout + bounded auto-fix
# or in a single call (opt-in):
/task:build --auto                                # both phases back-to-back; stop on per-phase budget

/task:ship                                       # slug auto-generated → e.g. feat-add-retries
                                                 # default: full close — workspace and .task-current removed
# or an explicit slug:
/task:ship feat-add-retries                       # the same full close with a given slug
```

If something goes wrong mid-way through the `/task:build` implement phase (a test/build fails), the skill makes **one** targeted quick-fix attempt. If that doesn't help — it stops. No automatic shotgun "try it and see" fixes.

`--auto` is opt-in. By default `/task:build` runs one phase per call and prints a chain hint "run /task:build again" — this gives a human checkpoint between `implement` and `audit`. With `--auto` both run automatically; the per-phase budget stops looping if `audit` doesn't converge within 2 iterations.

### B. A multi-stage initiative via a roadmap

```text
/task:bootstrap

/task:roadmap "migrate the public API to v2"
# → .task/roadmap/api-v2-migration.md with phases and ready-made descriptions
#   for ~10–15 tasks
# → (opt.) .task/roadmap/api-v2-migration.spec.md — if key technical decisions
#   surfaced during the brainstorm; items reference its sections via ### Spec references,
#   blueprint reads them at planning time

# One roadmap = one umbrella task. Items are sequential subtasks.
/task:design --from api-v2-migration              # phase=open, auto-picks the first [ ]
/task:build                                       # implement → audit
/task:ship --next                                 # transition to the next item (umbrella alive)
# → .task/log/api-v2-migration/0-migrate-auth-endpoints/
# Auto-mark: item 1 in the roadmap → `- [x]`. task.md stays (Description cleared).
# Without --next a bare /task:ship would have closed the umbrella entirely.

# Next item:
/task:design --from api-v2-migration              # phase=open continuation
/task:build
/task:ship --next                                 # transition again (this isn't the last item)
# → .task/log/api-v2-migration/1-update-client-sdk/, item 2 → `- [x]`

# At the end (the last roadmap item):
/task:ship --full                                  # slug auto-generated from summary.md
# → .task/log/api-v2-migration/{N}-feat-...-finalize/ with the archived task.md
# The chore-finalize slug isn't used in a clean finish of a manual run —
# it's reserved for manual recovery of an aborted /task:auto-roadmap
# (see the "If it failed on an item" block below in scenario B+).

# If you need to skip or redo an item:
/task:design --from api-v2-migration#5
```

### B+. Autopilot via `/task:auto-roadmap`

```text
/task:bootstrap
/task:roadmap "migrate the public API to v2"

# In a single active Claude Code session:
/task:auto-roadmap
# A wizard picks the roadmap and confirms the run.
#
# For each item:
#   1) main thread spawns auto-roadmap-design-runner (parent-session model)
#      → goes through design/phases/open.md → design/phases/blueprint.md
#      → returns: "OK: item #N \"...\" — plan.md ready, awaiting implement"
#   2) main thread reads plan.md → Implement-Model: (opus|sonnet|haiku)
#   3) main thread spawns auto-roadmap-build-runner with Agent.model = that value
#      → goes through build/phases/implement.md
#      → returns: "OK: item #N \"...\" — diff uncommitted, ready for audit"
#   4) main thread → /task:build --phase audit inline
#      — audit-context.sh sees a non-trivial diff →
#        Step 2b spawns 3 lens agents in parallel (the main thread can Agent(...))
#      — bounded auto-fix loop (≤2 iterations, touches-gate)
#      — on high-severity unfixed after 2 iterations → fail-stop
#   5) main thread → /task:ship inline (commit + close: --next on intermediate items, --full on the last)

# With flags:
/task:auto-roadmap api-v2-migration --next          # only the first unclosed item
/task:auto-roadmap api-v2-migration --from #3       # start from #3
/task:auto-roadmap api-v2-migration --items 3-5     # items #3, #4, #5
/task:auto-roadmap api-v2-migration --items 1,3-5,8 # a selection

# If it failed on item #5:
/task:ship --full chore-finalize                    # sweeps the subfolder and .task-current
/task:auto-roadmap api-v2-migration --from #5       # retry from #5
```

**Recommendation.** Run it in auto mode (auto-accept edits) — otherwise every `Edit` triggers a prompt.

**Limitations.**

- The main thread's context accumulates. Rough auto-compact thresholds: ~15 items on Sonnet 200k, ~25 on Opus 1M. Slice with `--items <range>` as needed.
- One session model for the whole run. For opus, run `/model opus` BEFORE starting.
- The session window must stay open for the whole run.

`/task:auto-roadmap` is **not for resume**: it refuses when `.task-current` exists or any `workspace/*/auto.lock` is present. It skips design's idea + refine phases — roadmap items already have a curated `Ready description`.

### C. Several subtasks in one umbrella task

```text
/task:design DT-5177 export refactor             # phase=open + quick-draft:
                                                  # task.md with a Description in one call
                                                  # (need a brainstorm — add --idea)
/task:design                                      # phase=blueprint
/task:build                                       # implement → audit
/task:ship --next                                 # transition: subtask to archive, umbrella alive
# → .task/log/dt-5177/0-feat-header-parser/

# the same task.md, a new Description (Description cleared by ship):
# IMPORTANT: between subtasks quick-draft is NOT applied — an empty Description
# in an active umbrella always goes to idea (architect), even if context is passed
# (the context isn't lost: it becomes the seed of round zero of the brainstorm).
/task:design "what we're doing in the new subtask" # Description empty → phase=idea (architect)
/task:build
/task:ship --next
# → .task/log/dt-5177/1-feat-body-emitter/

# finally (the last subtask — closing the umbrella entirely):
/task:ship chore-cleanup                          # default = full close (--full is an alias)
# → .task/log/dt-5177/2-chore-cleanup/  (with task.md)
```

### D. Returning to a closed umbrella task (without `/task:restore`)

`/task:restore` was removed in 0.3 (it was used once or twice in the entire history). To restore:

```text
# manually restore task.md from the latest full-close archive:
cp .task/log/dt-5177/2-chore-cleanup/task.md .task/workspace/dt-5177/task.md
mkdir -p .task/workspace/dt-5177
echo "dt-5177" > .task-current

# (opt.) clear everything from ## Description down if you want a clean start
# then the standard cycle:
/task:design "a new subtask"                      # Description empty → phase=idea (architect)
/task:build
/task:ship fix-edge-case                          # default = full close of the umbrella
```

`plan.md` / `summary.md` are left with the previous subtask — look in `.task/log/...`.

Scenarios can be combined: some tasks via `/task:roadmap` + `--from`, small fixes directly via `/task:design`.

## Code-access tiers

Details and rationale in [docs/spec/invariants.md § Three code-navigation tiers](docs/spec/invariants.md#three-code-navigation-tiers):

- **No code:** `/task:ship`, `validate`, `/task:auto-roadmap`. They read only `.task/`, `CLAUDE.md`, `git`. `/task:ship` additionally picks up `CONTRIBUTING.md` (if `config.md` → "Commit Format" points to it).
- **Structural scan only:** `/task:bootstrap`, `/task:roadmap` (brainstorm mode; `--refine` is Tier A, reading only `.task/roadmap/<slug>.md` + `CLAUDE.md` and spawning read-only lens auditors), `/task:design` (idea phase; the open phase — only on the quick-draft path). Manifests, top-level structure, `docs/`. No source files. (The open phase is mixed: on the header-only path (`--idea`) it's Tier A, only `.task/roadmap/` + git, no scan; on the quick-draft path it's Tier C — the same shallow scan as the idea architect.)
- **MCP-first:** `/task:design` (blueprint + refine phases), `/task:build` (both phases). MCP tools from `config.md`; built-in `Grep`/`Glob`/`Read` are the fallback.

The `/task:design` and `/task:build` orchestrators are Tier A (config gate + dispatch); the phase tier applies inside the companion file `phases/<phase>.md`.

## Language & tests

### Language policy

Configured in `config.md` → "Language". By default: the `task.md` Description is in your language, everything else is in English, commits follow "Commit Format".

### Test policy

Controlled via `Testing Policy` → `Mode`: `always` / `on-demand` *(default)* / `never`. In `on-demand`, tests are written only if `## Description` explicitly says "needs tests" / "with tests" / "cover with tests". `## Tests` in `plan.md` is either there or it isn't.

### Idempotency

`/task:bootstrap` regenerates `config.md` in full every time. After an interruption, `/task:build` reads the `TaskList` and resumes from the first unclosed step of the implement phase.

## Built-in PreToolUse hook

It intercepts any `Skill(task:design|build|ship|auto-roadmap)` call and runs `validate.sh all`. `bootstrap` / `roadmap` are deliberately excluded from the matcher — the intake phase. In-skill `validate.sh` calls remain as defense-in-depth.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill\\((task:)?(design|build|ship|auto-roadmap)\\)",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh\" all" }
        ]
      }
    ]
  }
}
```

To disable it — `/plugin disable task` or remove `hooks/hooks.json` locally.

## Comparison with alternatives

Three references: default Claude Code (plan mode + TodoWrite), [obra/superpowers](https://github.com/obra/superpowers), [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec).

### vs default Claude Code

| | Default Claude Code | task-pipeline |
|---|---|---|
| **Where the plan lives** | Text in chat; lost on `/clear` | `plan.md` as a file in `.task/workspace/`; editable by hand, readable by a colleague |
| **Plan-step contract** | Arbitrary text | `### Step N` with three layers: `Goal` / `Touches` / opt. `Logic` |
| **Step verification** | None | A step closes only if the `Touches` symbols are in `git diff` (+ RED→GREEN when `## Tests`) |
| **Auto-fix audit findings** | None | Bounded loop ≤2 iterations, scope-gated by `Touches` |
| **Interrupt / resume** | Lost on `/clear` | Plan + progress are files; auto-resumable via `TaskList` |
| **Result review** | Only whatever the model decides | `/task:build` audit phase with a 3-lens fanout (Reuse / Simplicity / Clarity) + bounded auto-fix loop |
| **Multi-task initiatives** | None | `/task:roadmap` → `/task:design --from`; autopilot `/task:auto-roadmap` |
| **Archive** | None | `.task/log/<task-id>/<N>-<slug>/` |

**Use default Claude Code** if the task is one or two files and twenty minutes. **Use task-pipeline** if the task is longer than one session, refactors >5 files, needs review by eye, or the plan itself should be a working artifact.

### vs superpowers

| | task-pipeline | superpowers |
|---|---|---|
| Initiation | By hand: `/task:…` | Auto-triggers by context |
| Form | Linear pipeline with checkpoints | A library of situational skills |
| Project config | `config.md` (stack, MCP, commits, language) | Minimal |
| TDD | On demand (`tests_required`) | Iron Law |
| Artifact languages | Any, via `config.md` | English by default |
| Platforms | Claude Code only | Claude Code, Codex, Cursor, Gemini CLI, Copilot CLI |

**Use task-pipeline** if you want a controlled checkpointed process, non-English languages, and an MCP-aware config.

### vs OpenSpec

| | task-pipeline | OpenSpec |
|---|---|---|
| Paradigm | Per-task workflow | Spec-driven (living `specs/` + deltas) |
| Storage | `.task/` locally, not in the repo | `openspec/` committed to the repo |
| Team visibility | Invisible (a personal tool) | Part of the repository |
| Language | Multilingual via `config.md` | English |

**Use task-pipeline** if you want a personal tool with no trace in the repo. **Use OpenSpec** if you work in a team where the spec is the source of truth.

<details>
<summary>Repository structure (for editors)</summary>

```
.claude-plugin/plugin.json       plugin manifest (name `task`, version, metadata)
.claude-plugin/marketplace.json  catalog for the `task-pipeline` marketplace
hooks/hooks.json                 PreToolUse hook → validate.sh
skills/                          SKILL.md + companion phase files + bash helpers
  _lib/                          shared bash helpers:
                                   preamble.sh, resolve-ws.sh, derive-task-id.sh,
                                   roadmap.sh, auto-locks.sh, fail-log.sh,
                                   auto-roadmap-helpers.sh (extract Implement-Model,
                                   refresh mtime, record orchestrator fail),
                                   phase-detect.sh (workspace state → phase name),
                                   touches-gate.sh (files-level scope gate);
                                   templates/ (shared markdown: summary.md,
                                   conventional-commits.md)
  bootstrap/                     bootstrap/SKILL.md
  roadmap/                       SKILL.md (roadmap brainstorm) +
                                   phases/refine.md (only for --refine)
  design/                        SKILL.md (thin orchestrator) + phases/
                                   {open,idea,blueprint,refine}.md
  build/                         SKILL.md (orchestrator + --auto chain + bounded audit
                                   auto-fix loop) + phases/{implement,audit}.md +
                                   audit-context.sh
  ship/                          SKILL.md + close.sh + commit-context.sh
  auto-roadmap/                  SKILL.md (per-item loop in the main thread) +
                                   auto-roadmap-context.sh
  validate/                      SKILL.md + validate.sh (validator; not user-invocable)
agents/                          named subagents
  audit-reuse-auditor.md         build-audit lens: DRY / duplication / premature abstractions (read-only)
  audit-simplicity-auditor.md    build-audit lens: dead code / over-engineering / scope creep (read-only)
  audit-clarity-auditor.md       build-audit lens: misleading names / magic values / redundant comments (read-only)
  audit-roadmap-coverage-auditor.md       roadmap-refine lens: end-to-end coverage / dependency graph (read-only)
  audit-roadmap-decomposition-auditor.md  roadmap-refine lens: atomicity / sizing / duplicate work (read-only)
  audit-roadmap-clarity-auditor.md        roadmap-refine lens: titles / Context-vs-Goal / testable AC (read-only)
  auto-roadmap-design-runner.md  executor-class (narrow): design open+blueprint phases
                                   for one roadmap item (parent-session model)
  auto-roadmap-build-runner.md   executor-class (narrow): build implement phase only,
                                   spawned with Agent.model from plan.md → Implement-Model
  _shared/audit-rules.md         shared prompt-layer rules for all six audit-*-auditor agents
                                   (build-audit family + roadmap-refine family)
  _shared/runner-rules.md        shared registry of rules the two roadmap runners inherit
                                   from nested phase files (sources in build/phases/implement.md,
                                   design/phases/blueprint.md § Step 3, docs/spec/invariants.md;
                                   edits must stay in sync)
CLAUDE.md                        checklist of invariants + links to docs/spec/
docs/spec/                       full specification for the editing assistant
  README.md                      spec index
  pipeline.md                    pipeline diagram, phase dispatch, /task:auto-roadmap
  artifact-contract.md           producer/consumer table, identifiers
  auto-roadmap.md                /task:auto-roadmap mechanics
  invariants.md                  all invariants + Shared prompt preamble (Tiers A/B/C)
  internals.md                   layout, bash helpers, agent classes, frontmatter, editing protocol
CONTRIBUTING.md                  commit format and release procedure
CHANGELOG.md                     public release log (English)
README.md                        this file
```

</details>

## Want to contribute

> *This section is for those editing the tool itself. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) — it has the commit format, the list of allowed scopes, and the release procedure.*

`SKILL.md` (and the companion `phases/<phase>.md` files) is a prompt contract that another Claude instance will read in someone else's project. The invariants that must not be broken (the artifact contract, the three code-navigation tiers, append-only iterations, the orchestration of the build audit auto-fix loop with the touches-gate) are pinned in [`docs/spec/`](docs/spec/README.md); a compact checklist is in [`CLAUDE.md`](CLAUDE.md). The repeated preamble is in [docs/spec/invariants.md § Shared prompt preamble](docs/spec/invariants.md#shared-prompt-preamble) (three profiles A/B/C). If you change something — update the relevant `docs/spec/*.md` file and this README in the same commit; `CHANGELOG.md` is edited only on explicit request; the `CLAUDE.md` checklist is touched only when adding/removing an invariant.
