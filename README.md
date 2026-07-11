# task-pipeline

A linear task workflow for Claude Code: from intake to commit, through explicit checkpoints, on your terms.

[![Release](https://img.shields.io/github/v/release/SpaiR/task-pipeline?sort=semver)](https://github.com/SpaiR/task-pipeline/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2)

```text
/task:bootstrap                          # once per project (or auto-runs on 1st design/roadmap)
  ↓
[/task:roadmap [--refine]]               ← optional: roadmap for a large initiative
  ↓
  ├─ [/task:auto-roadmap] ──┐            ← optional: autopilot over an approved roadmap
  ↓                          │
/task:design  [--from …]     │           plan it out
  ↓                          │
/task:build   [--auto]       │           implement + audit
  ↓                          │
/task:ship    [--next]  ─────┘           commit + close
```

## Quickstart

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline

/task:bootstrap                              # once per project (optional — 1st design/roadmap auto-runs it)
/task:design "fix the flaky retry logic"     # opens the task + writes the Description
/task:design                                 # run again → builds the plan
/task:build --auto                           # implement + audit
/task:ship                                   # commit + close
```

`design → build → ship` is the whole core; everything else (`roadmap`, `auto-roadmap`, and the flags) is optional.

## Why

If you've ever tried to cram Claude into one big "do everything in this ticket" session, you know how it ends: the model starts writing code before it understands the task; it "fixes" one bug and breaks three others; it reports "done" while half the acceptance criteria are still stubs. `task-pipeline` solves this not with magic but with boring discipline: each stage of a task is a separate slash command with an explicit contract, artifacts live as files in `.task/`, and nothing runs "by itself."

Concretely, you get:

- **Invisible to the project.** All pipeline state lives in `.task/`, excluded via `.git/info/exclude` (not `.gitignore`). A colleague who clones the repo without the pipeline sees no trace of it.
- **Multilingual.** Task descriptions and discussion happen in your language (English, Russian, anything). The plan, audit, and commits follow the policy in `config.md`.
- **Three explicit checkpoints.** `/task:design` (plan), `/task:build` (implementation + checks), `/task:ship` (commit + close). You decide when to move on; stop, fix an artifact by hand, and continue.
- **A paper trail.** `task.md` (what and why), `plan.md` (how), `audit.md` (what the audit found), `summary.md` (the result). Plain Markdown, readable without an agent.
- **Project-aware.** A single `/task:bootstrap` pins down the stack, the MCP tool priority (whatever code-navigation / library-docs servers you happen to have connected), and the commit format. Every step follows it afterward.
- **Bounded auto-fix + filters.** `/task:build` applies the problems it finds (≤2 iterations), but only within the declared `Touches` scope. Weak or out-of-scope findings land in `### Filtered (low confidence)` for manual review.
- **An archive.** `/task:ship` files completed subtasks under `.task/log/{task-id}/{N}-{slug}/` — six months later you can still see what was done, and when.

## Why you can trust this

It runs bash, edits files, and writes commits — so here is exactly what it will and won't touch:

- **Nothing is committed until `/task:ship`.** Until then every change is just working-tree edits; back them out with plain `git restore` / `git checkout`.
- **`/task:ship` only _stages_ task files, and never pushes.** It writes a local commit for you to review; nothing leaves your machine, and it never stages anything under `.task/`.
- **The audit agents are read-only.** The three review lenses (Reuse / Simplicity / Clarity) run with a `Read`/`Grep`/`Glob` allowlist — they cannot edit your code.
- **Auto-fix is bounded and scoped.** The build audit applies fixes for at most 2 iterations, and only within the files the plan declared under `Touches`; anything out of scope is flagged, not changed.
- **The pipeline leaves no trace in the repo.** `.task/` is excluded via `.git/info/exclude` (not `.gitignore`), so it never shows up in `git status`; delete it with `rm -rf .task` and the repo is exactly as before.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) — this ships as a Claude Code plugin.
- MCP code-navigation tools are **optional** and the pipeline is agnostic about which one you use: `/task:bootstrap` records whichever servers you have connected (by role, not by product), and the built-in `Grep`/`Glob`/`Read` are always the fallback.

## Installation

The pipeline ships as a Claude Code plugin (`task`) inside the `task-pipeline` marketplace. The recommended path is through the marketplace:

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

From then on, updates are a single command: `/plugin marketplace update task-pipeline`.

After installation, Claude Code gains the commands `/task:bootstrap`, `/task:design`, `/task:build`, `/task:ship`, `/task:roadmap`, `/task:auto-roadmap`, plus nine named agents and a PreToolUse artifact-validator hook that activates automatically.

In a new project you don't have to run setup by hand first: the first `/task:design` or `/task:roadmap` in an unconfigured project auto-runs setup inline (inspect the repo → detect language and test policy → one confirmation), then continues the requested action. You can still call `/task:bootstrap` explicitly to do it deliberately — it inspects the repo, detects language and test policy, presents both as defaults, and writes `.task/config/config.md` after a single confirmation (accept, edit either value, or decline). The explicit command stays available and idempotent for re-running setup on demand. (`/task:build`, `/task:ship`, and `/task:auto-roadmap` do **not** auto-run setup — they presuppose prior pipeline state, so a fresh-project first-use of them still hard-stops with a "run `/task:bootstrap` first" redirect.)

> [!NOTE]
> Invoking the agents manually via `Agent(...)`, or hitting a `No such file or directory` from a skill's bash script? See [docs/troubleshooting.md](docs/troubleshooting.md).

<details>
<summary>Local development</summary>

```text
/plugin marketplace add /path/to/task-pipeline
/plugin install task@task-pipeline
```

</details>

## Command reference

```text
/task:bootstrap  — once per project (or auto-runs on 1st design/roadmap); creates .task/config/config.md
  ↓
[/task:roadmap [--refine]]  — optional; roadmap for a large initiative → .task/roadmap/<slug>.md
  ↓                          --refine: parallel audit of an existing roadmap
                              (Coverage / Decomposition / Clarity, ≤2 iterations)
  ├─→ [/task:auto-roadmap] — optional; autopilot over an approved roadmap
  ↓                         in the current interactive session.
/task:design  — open a task, write the Description, plan it out
  ↓             (phase auto-detect: open(quick-draft) → blueprint; [--idea] brainstorm)
/task:build [--auto] — implementation + audit with an auto-fix loop
  ↓             (phase auto-detect: implement → audit;
                 --auto — opt-in: both phases in one call)
/task:ship [--next]  — commit + close
                        default → full close of the umbrella task
                        --next  → transition to the next subtask (task.md stays)
```

**Re-entry semantics:** `/task:design` and `/task:build` look at the state of `.task/workspace/<task-id>/` and automatically resume from the right phase. Override with `--phase <open|idea|blueprint|refine|implement|audit>`. `/task:build` additionally accepts `--auto` (opt-in one-shot: runs `implement → audit` in a single call, mutually exclusive with `--phase`).

**Next-step footer:** every core command ends its output with a single copy-pasteable `→ Next: <command>` line naming the exact next step (or `→ Done.` when the flow is complete), so you never have to remember which command comes next — just paste the line. The convention is defined once in [`docs/spec/invariants.md § Interaction conventions`](docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar).

`validate` is an internal utility: the pipeline invokes it as a precondition gate, not via a slash command. For a manual check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`.

### Umbrella task vs subtask

`task.md` is an **umbrella task**: a task with one `task-id` and a shared title, under which there may be several subtasks. Each `/task:design → /task:build → /task:ship` cycle is one subtask. Interactive `/task:ship` **proposes** close-or-transition based on whether pending work remains and acts on one confirmation — you can flip the proposal there. A full close ends the umbrella task entirely; a transition clears the Description and keeps the title, so the next cycle starts from the same umbrella task. `/task:ship --next` forces the transition without inferring. (Under `/task:auto-roadmap` the mode is chosen by the autopilot, not proposed interactively.)

## Commands

| Command | In brief |
|--------|--------|
| `/task:bootstrap` | Initializes the pipeline in a project: creates `.task/config/config.md`, sets up the local git exclusion for `.task/`, and prints a short getting-started primer. Idempotent. |
| `/task:roadmap <idea> \| --refine [<slug>]` *(opt.)* | Brainstorms an initiative roadmap → `.task/roadmap/<slug>.md` with ready-made task descriptions for `--from`; each task's Size and Class are inferred during authoring (Size from the outcome count, Class from task shape, user-overridable) rather than asked for. An optional sidecar `.task/roadmap/<slug>.spec.md` pins down key technical decisions (Blueprint reads them during planning). Authoring closes with a light, report-only self-check over the saved file (same three lenses as `--refine`), escalating to `--refine` inline when the findings warrant it. `--refine` — a parallel audit of an existing roadmap (Coverage / Decomposition / Clarity, ≤2 iterations; high → auto-applied, med/low → manual review). |
| `/task:auto-roadmap [<roadmap>] [--next \| --from #<N> \| --items <spec>]` *(opt.)* | Autopilot over a roadmap in the current interactive Claude Code session: for each item — design → build → ship. `--next` — the first unclosed item; `--from #N` — start from item N; `--items 3-5` or `1,3-5,8` — a selection. |
| `/task:design [<context>] [--from <path>[#<N>]] [--idea] [--phase <name>]` | Open a task, write the Description, plan it out. Phase auto-detect (`open` → `blueprint`); `--phase` override. `--idea` — brainstorm the Description (architect from scratch / Socratic on a filled-in one). `--from <path>[#N]` — Description from a roadmap item. (`--phase refine` critically reviews an existing `plan.md` — a repair-level option, see docs/troubleshooting.md.) |
| `/task:build [--phase <name>] [--auto]` | Implementation (`implement`) + audit with bounded auto-fix (`audit`). `--auto` — both phases in one call (≤1 implement, ≤2 audit). `--phase` — override. Fixes outside `Touches` from `plan.md` are marked `Skipped: out-of-scope`. |
| `/task:ship [--next]` | Commit + archiving under `.task/log/`. Interactive ship infers close-vs-transition from remaining work and proposes it in the single commit confirmation (you can flip it); `--next` forces transition. Full close removes `workspace/<task-id>/` and `.task-current`; transition keeps `task.md` (Description cleared) for the next subtask. Auto-marks the roadmap item when `Roadmap:` + `Source item:` are present. The commit slug is always auto-derived. |
| `validate` *(utility)* | Formal validator of artifact format. Invoked automatically. For a manual check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" [task\|plan\|roadmap <path>\|all]`. |

## Example — a single task

```text
/task:bootstrap                                  # once per project (optional — 1st design/roadmap auto-runs it)

# Manual mode — title + Description in one call (quick-draft):
/task:design "I want an HTTP retry system with backoff and dead-letter" # phase=open + quick-draft:
                                                 # task.md with a filled-in Description
                                                 # (### Problem / ### Outcome / ...)

# Need a multi-round Description brainstorm — the --idea flag:
/task:design --idea "an idea for X"              # open(header-only) → idea(architect) in one call
#   (alternative to the same entry: an empty /task:design when there's no task yet
#    — the skill asks for the idea and drops into architect)

/task:design                                     # run again → phase=blueprint: builds plan.md with steps
/task:design --idea                              # opt.: idea(Socratic) — refine the Description

/task:build                                      # phase=implement: implement per the plan
/task:build                                      # phase=audit: lens fanout + bounded auto-fix
                                                 # default output: one summary line (found/fixed/filtered);
                                                 # full detail stays in audit.md
# or in a single call (opt-in):
/task:build --auto                                # both phases back-to-back; stop on per-phase budget

/task:ship                                       # commit composed from artifacts, one accept/decline/edit confirm
                                                 # slug auto-generated → e.g. feat-add-retries
                                                 # proposes close-or-transition from remaining work; accept or flip it
# or force the transition without inferring:
/task:ship --next                                # transition to the next subtask (task.md stays)
```

> [!NOTE]
> If something goes wrong mid-way through the `/task:build` implement phase (a test/build fails), the skill makes **one** targeted quick-fix attempt, then stops. No automatic shotgun "try it and see" fixes.

`--auto` is opt-in. By default `/task:build` runs one phase per call and prints a chain hint "run /task:build again" — a human checkpoint between `implement` and `audit`. With `--auto` both run automatically; the per-phase budget stops looping if `audit` doesn't converge within 2 iterations.

> [!TIP]
> More scenarios — roadmap-driven initiatives, the `/task:auto-roadmap` autopilot, several subtasks under one umbrella, and returning to a closed task — live in **[docs/usage.md](docs/usage.md)**.

## Comparison with alternatives

Three references: default Claude Code (plan mode + TodoWrite), [obra/superpowers](https://github.com/obra/superpowers), [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec).

<details>
<summary><strong>vs default Claude Code</strong></summary>

| | Default Claude Code | task-pipeline |
|---|---|---|
| **Where the plan lives** | Text in chat; lost on `/clear` | `plan.md` as a file in `.task/workspace/`; editable by hand, readable by a colleague |
| **Plan-step contract** | Arbitrary text | `### Step N` with three layers: `Goal` / `Touches` / opt. `Logic` |
| **Step verification** | None | A step closes only if the `Touches` symbols are in `git diff` (+ RED→GREEN when `## Tests`) |
| **Auto-fix audit findings** | None | Bounded loop ≤2 iterations, scope-gated by `Touches` |
| **Interrupt / resume** | Lost on `/clear` | Plan + progress are files; auto-resumable via `TaskList` |
| **Result review** | Only whatever the model decides | `/task:build` audit phase with a 3-lens fanout (Reuse / Simplicity / Clarity) + bounded auto-fix loop; reports one summary line by default, full detail in `audit.md` |
| **Multi-task initiatives** | None | `/task:roadmap` → `/task:design --from`; autopilot `/task:auto-roadmap` |
| **Archive** | None | `.task/log/<task-id>/<N>-<slug>/` |

**Use default Claude Code** if the task is one or two files and twenty minutes. **Use task-pipeline** if the task is longer than one session, refactors >5 files, needs review by eye, or the plan itself should be a working artifact.

</details>

<details>
<summary><strong>vs superpowers</strong></summary>

| | task-pipeline | superpowers |
|---|---|---|
| Initiation | By hand: `/task:…` | Auto-triggers by context |
| Form | Linear pipeline with checkpoints | A library of situational skills |
| Project config | `config.md` (stack, MCP, commits, language) | Minimal |
| TDD | On demand (`tests_required`) | Iron Law |
| Artifact languages | Any, via `config.md` | English by default |
| Platforms | Claude Code only | Claude Code, Codex, Cursor, Gemini CLI, Copilot CLI |

**Use task-pipeline** if you want a controlled checkpointed process, non-English languages, and an MCP-aware config.

</details>

<details>
<summary><strong>vs OpenSpec</strong></summary>

| | task-pipeline | OpenSpec |
|---|---|---|
| Paradigm | Per-task workflow | Spec-driven (living `specs/` + deltas) |
| Storage | `.task/` locally, not in the repo | `openspec/` committed to the repo |
| Team visibility | Invisible (a personal tool) | Part of the repository |
| Language | Multilingual via `config.md` | English |

**Use task-pipeline** if you want a personal tool with no trace in the repo. **Use OpenSpec** if you work in a team where the spec is the source of truth.

</details>

## Configuration & policy

All of this lives in `.task/config/config.md`, written by `/task:bootstrap`:

- **Language** — by default the `task.md` Description is in your language, everything else is in English, commits follow "Commit Format".
- **Test policy** — `Testing Policy → Mode`: `always` / `on-demand` *(default)* / `never`. In `on-demand`, tests are written only if `## Description` explicitly asks for them ("needs tests" / "with tests" / "cover with tests").
- **Idempotency** — `/task:bootstrap` regenerates `config.md` in full every time. After an interruption, `/task:build` reads the `TaskList` and resumes from the first unclosed step of the implement phase.

## How it works

The pipeline is built on a few invariants; the full reasoning lives in [`docs/spec/`](docs/spec/README.md).

- **Artifacts.** Each `.task/` subfolder has one role — `config/`, `roadmap/`, `workspace/<task-id>/`, `log/<task-id>/<N>-<slug>/`. The pointer to the active umbrella is a one-line `.task-current` in the worktree root. If it is ever left empty or pointing at a closed or deleted workspace, the next command clears it automatically with a one-line notice — no manual cleanup — while a valid in-flight task is never touched. Full producer/consumer contract: [docs/spec/artifact-contract.md](docs/spec/artifact-contract.md).
- **Code-navigation tiers.** Each skill reads only as much of your code as its job needs — from `.task/`-only (`/task:ship`, `validate`) through a structural scan to MCP-first navigation (`/task:design` blueprint, `/task:build`). Details: [docs/spec/invariants.md § Three code-navigation tiers](docs/spec/invariants.md#three-code-navigation-tiers).
- **Validator hook.** A PreToolUse hook intercepts `Skill(task:build|ship|auto-roadmap)` and runs `validate.sh all` before the skill body. `bootstrap` / `roadmap` / `design` are deliberately excluded (the intake phase): each can be the first command in a fresh project and auto-runs setup inline, so a blocking pre-hook would make that inline setup unreachable. `design` still runs the identical `validate.sh all` in its own Step 0, so mid-pipeline validation coverage is preserved. Disable with `/plugin disable task` or by removing [`hooks/hooks.json`](hooks/hooks.json) locally.
- **Parallel worktrees.** `.task/` is excluded from git, so a fresh worktree gets a `.task` symlink to the main tree's state — `/task:bootstrap` wires it up. Discipline and edge cases: [docs/spec/auto-roadmap.md § Cross-worktree safety](docs/spec/auto-roadmap.md#cross-worktree-safety).

## Contributing

> *This section is for those editing the tool itself.* Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) — it carries the commit format, the list of allowed scopes, the release procedure, and the repository layout.

`SKILL.md` (and the companion `phases/<phase>.md` files) is a prompt contract that another Claude instance will read in someone else's project. The invariants that must not be broken — the artifact contract, the three code-navigation tiers, append-only iterations, the build audit auto-fix loop with the touches-gate — are pinned in [`docs/spec/`](docs/spec/README.md); a compact checklist is in [`CLAUDE.md`](CLAUDE.md). If you change something, update the relevant `docs/spec/*.md` file and this README in the same commit; `CHANGELOG.md` is edited only on explicit request.
