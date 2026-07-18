# task-pipeline

[![Release](https://img.shields.io/github/v/release/SpaiR/task-pipeline?sort=semver)](https://github.com/SpaiR/task-pipeline/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2)

If you've ever tried to cram Claude into one big "do everything in this ticket" session, you know how it ends: the model starts writing code before it understands the task, "fixes" one bug and breaks three others, and reports "done" while half the acceptance criteria are still stubs. And the plan you talked through in chat? Gone the moment you `/clear`.

`task-pipeline` keeps the discussion and the doing apart. Discuss the task freely in chat; when you're ready, one command freezes that discussion into a Markdown file under `.task/`. Any session — this one, or a fresh one tomorrow — implements that file the same way: work the plan, run `/verify`, run `/code-review`, commit.

No push, no trace in your repo — delete `.task/` and it's like it was never there. [Here's exactly what it will and won't touch](#why-you-can-trust-this).

It's for tasks longer than one session — a two-file, twenty-minute fix doesn't need this.

```text
discuss in chat
  → capture to a file
  → any session implements it
```

## Quickstart

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

Talk a task through in chat — say, an HTTP retry system with backoff and a dead-letter queue — then capture it:

```text
/task:to-plan
#   → drafts .task/task/http-retry-backoff.md: ## Description + ## Plan (Goal/Touches/Logic steps)
#   → footer: implement it now, or in a fresh session run:
#     `implement .task/task/http-retry-backoff.md`
```

Hand the file to any session — this one or a fresh one:

```text
"implement .task/task/http-retry-backoff.md"
#   → follows the artifact's ## Execution block: implement per the plan
#   → runs /verify (does it actually work?) and /code-review (is it clean?)
#   → commits per config.md → Commit Format
```

That session follows the artifact's own `## Execution` block: implement the plan, run `/verify` and `/code-review`, apply review fixes within the files named in **Touches**, then commit per `config.md` → Commit Format.

The first capture in a fresh project also writes `.task/config/config.md` inline (detect language + test policy, one confirmation) — there's no separate setup command to run first. Prefer a lighter touch? `/task:to-task` skips the Plan — good for a quick capture you'll flesh out with `/task:to-plan` later, or hand straight to implementation when the fix is obvious.

> [!TIP]
> More scenarios — roadmap-driven initiatives, `/task:roadmap-to-workflow`, and returning to a task later — live in **[docs/usage.md](docs/usage.md)**.

## Why

`task-pipeline` doesn't fight the one-big-session failure with more machinery — it leans on what Claude Code already ships (dynamic Workflows, `/verify`, `/code-review`) and adds just enough structure around them: one artifact per task (`.task/task/<slug>.md`) that carries the discussion's "what, why, and how," and a fixed `## Execution` block that hands the rest to the platform. The plan lives in that file, not in chat — so it survives the `/clear` that would otherwise erase it.

Concretely, you get:

- **The plan survives `/clear`, compaction, and tomorrow's fresh session.** The artifact's path (`.task/task/<slug>.md`) is the handle. Pick it up in this session or a brand-new one — there's no active-task state to lose or heal.
- **Zero ceremony while you think.** Think out loud, explore approaches, change your mind — all in normal conversation. Only when you're ready do you fix it into `.task/task/<slug>.md` with `to-task` or `to-plan`.
- **Nothing new to learn on the execution side.** There is no `build`/`ship` step to run — any session told `implement .task/task/<slug>.md` reads the artifact and follows its own `## Execution` block through to a commit.
- **Verification and review are written into every artifact, not left to the model's mood.** Verification is `/verify`, review is `/code-review` — no hand-rolled audit loop.
- **Your language for content, English only where parsers need it.** The Description is written in your language; everything parser-stable (headers, commit trailers, the `## Execution` block) stays English, per the policy in `config.md`.

## Why you can trust this

It runs bash, edits files, and writes commits — so here is exactly what it will and won't touch:

- **Nothing is committed until the implementing session does so, per `## Execution`.** Until then every change is just working-tree edits; back them out with plain `git restore` / `git checkout`.
- **Commits stage only task-related files, and never push.** Nothing leaves your machine.
- **No hidden orchestration.** There are no subagents in this plugin's capture skills; `/task:roadmap-to-workflow` is a plain Workflow this skill itself authors, which you can inspect before it runs.
- **The pipeline leaves no trace in the repo.** `.task/` is excluded via `.git/info/exclude` (not `.gitignore`), so it never shows up in `git status`; delete it with `rm -rf .task` and the repo is exactly as before.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) — this ships as a Claude Code plugin.
- `/verify` and `/code-review` available in your Claude Code install (both ship with Claude Code) — every task's `## Execution` block invokes them directly.

## Installation

The pipeline ships as a Claude Code plugin (`task`) inside the `task-pipeline` marketplace. The recommended path is through the marketplace:

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

From then on, updates are a single command: `/plugin marketplace update task-pipeline`.

After installation, Claude Code gains the commands `/task:grill`, `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, `/task:to-spec`, `/task:roadmap-to-workflow`. There is no hook — enforcement is by convention, not a gate.

In a new project you don't have to run setup by hand first: the first `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec` in an unconfigured project detects language and test policy, presents both for one confirmation, writes `.task/config/config.md`, and continues with the requested capture. `/task:grill` needs no config at all — it writes nothing and can run at the discussion stage before any capture exists. `/task:roadmap-to-workflow` presupposes an existing roadmap, so a fresh-project first-use of it hard-stops with a redirect to run a capture skill first.

<details>
<summary>Local development</summary>

```text
/plugin marketplace add /path/to/task-pipeline
/plugin install task@task-pipeline
```

</details>

## Command reference

**Next-step footer:** every capture skill ends its output with a copy-pasteable `→ Next: ...` line naming the artifact path explicitly, e.g. `implement .task/task/<slug>.md` — the path *is* the handle, so there's nothing else to remember.

`validate` is an internal, optional self-check — not a slash command, not a gate. For a manual check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`.

### One file per task; a roadmap is a backlog of items

Each capture produces exactly one `.task/task/<slug>.md`, where `<slug>` is both the filename and the identity — no task-id, no umbrella folder. A closed task is just a file that stays in `.task/task/` (or you delete it); git history is the record, there is no archive. A **roadmap** (`.task/roadmap/<slug>.md`) groups several such items into one initiative; `to-task`/`to-plan` can open the next unchecked item directly, or `roadmap-to-workflow` fans the whole backlog out at once. A **spec** (`.task/spec/<slug>.md`) is a standalone file of load-bearing technical decisions that tasks and roadmaps point at with a `Spec:` header.

## Commands

| Command | In brief |
|--------|--------|
| `/task:grill [<context>]` | Pre-capture interrogation: stress-tests a plan/decision one question at a time, keeps a decision-plus-rationale ledger, ends with a pre-mortem, then routes to the right capture skill. Writes nothing and touches nothing under `.task/` — grill *before* you capture, so `to-spec`/`to-plan`/`to-task`/`to-roadmap` serialize something already examined. Needs no config; runs before any capture exists. |
| `/task:to-task [<context>]` | Fixes the chat discussion (or a roadmap item) into `.task/task/<slug>.md` — Description only, no Plan. Lightest of the three capture skills; use it to record the "what and why" before diving in directly, or before `to-plan` later. |
| `/task:to-plan [<context>]` | Fixes the chat discussion (or a roadmap item) into `.task/task/<slug>.md` with **`## Description` + `## Plan`** (Goal/Touches/Logic steps) and, when the testing policy calls for it, `## Tests`. Deepest one-task capture — hand straight to implementation. Re-running it on a `to-task`-only file adds the Plan in place. |
| `/task:to-roadmap <idea>` | Fixes a multi-task initiative discussed in chat into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items, each with optional `**Dependencies:**` and `**Model:**` hints, referencing standalone specs via `Spec:` headers where a load-bearing technical decision applies. Closes with a report-only self-check; findings are surfaced, never silently rewritten into the file. |
| `/task:to-spec [<context>]` | Fixes load-bearing technical decisions discussed in chat into a standalone `.task/spec/<slug>.md` — numbered Decision / Rationale / Constrains sections. Orthogonal to the depth-capture skills: tasks and roadmaps reference a spec via a `Spec:` header, and the implementing session reads it as a fixed anchor. Capture it before, alongside, or independently of any roadmap. |
| `/task:roadmap-to-workflow [<roadmap>]` | Autopilot over an approved roadmap: authors and invokes a dynamic Workflow that runs the roadmap's unchecked items in dependency-ordered waves (parallel within a wave, isolated worktrees). Default per-item shape is opus-plans/sonnet-implements — a first agent runs `to-plan` for the item, a second implements + verifies + reviews + commits, using the item's `**Model:**` hint if present. The driver ticks the roadmap checkbox after each item lands. Launched with no arguments it asks (via chips) which roadmap and how much to run; falls back to one-item-at-a-time by hand if the Workflow tool is unavailable. |
| `validate` *(utility)* | Optional formal validator of `.task/task/<slug>.md` / roadmap format. Never invoked automatically — no hook calls it. Manual check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" [task <slug>\|roadmap <slug>\|spec <slug>\|all]`. |

## Comparison with alternatives

Three references: default Claude Code (plan mode + TodoWrite), [obra/superpowers](https://github.com/obra/superpowers), [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec).

The two contrasts that matter most — where the plan lives, and when a task is too small to bother — are surfaced up top (the `/clear`-durable file, and "a two-file, twenty-minute fix doesn't need this"). The full breakdown is in the collapsed blocks below.

<details>
<summary><strong>vs default Claude Code</strong></summary>

| | Default Claude Code | task-pipeline |
|---|---|---|
| **Where the plan lives** | Text in chat; lost on `/clear` | `## Plan` inside `.task/task/<slug>.md`; editable by hand, readable by a colleague |
| **Plan-step contract** | Arbitrary text | `### Step N` with three layers: `Goal` / `Touches` / opt. `Logic` |
| **Result review** | Only whatever the model decides | The artifact's `## Execution` block runs `/verify` (does it work end-to-end?) and `/code-review` (is it clean?) before commit |
| **Interrupt / resume** | Lost on `/clear` | The task file is on disk; pick it up in any session with `implement .task/task/<slug>.md` |
| **Multi-task initiatives** | None | `/task:to-roadmap` → `/task:to-plan`/`/task:to-task` per item (or autopilot `/task:roadmap-to-workflow`) |
| **Record of what shipped** | None | git history of `.task/task/<slug>.md` and the diff it produced |

**Use default Claude Code** if the task is one or two files and twenty minutes. **Use task-pipeline** if the task is longer than one session, needs a plan you can hand-edit, or should leave a record.

</details>

<details>
<summary><strong>vs superpowers</strong></summary>

| | task-pipeline | superpowers |
|---|---|---|
| Initiation | By hand: `/task:…` | Auto-triggers by context |
| Form | Linear capture → hand off to any session | A library of situational skills |
| Project config | `config.md` (stack, commits, language) | Minimal |
| Result review | `/verify` + `/code-review` | Iron Law TDD |
| Artifact languages | Any, via `config.md` | English by default |
| Platforms | Claude Code only | Claude Code, Codex, Cursor, Gemini CLI, Copilot CLI |

**Use task-pipeline** if you want a controlled capture-then-implement process, non-English languages, and no hand-rolled audit machinery.

</details>

<details>
<summary><strong>vs OpenSpec</strong></summary>

| | task-pipeline | OpenSpec |
|---|---|---|
| Paradigm | Per-task capture, chat-first | Spec-driven (living `specs/` + deltas) |
| Storage | `.task/` locally, not in the repo | `openspec/` committed to the repo |
| Team visibility | Invisible (a personal tool) | Part of the repository |
| Language | Multilingual via `config.md` | English |

**Use task-pipeline** if you want a personal tool with no trace in the repo. **Use OpenSpec** if you work in a team where the spec is the source of truth.

</details>

## Configuration & policy

All of this lives in `.task/config/config.md`, written inline on first use of a capture skill:

- **Language** — by default the Description is in your language, everything else (headers, the `## Execution` block, commits) is in English, per "Commit Format".
- **Test policy** — `Testing Policy → Mode`: `always` / `on-demand` *(default)* / `never`. In `on-demand`, `## Tests` is written only if the Description explicitly asks for it ("needs tests" / "with tests" / "cover with tests").
- **Idempotency** — `config.md` is regenerated in full whenever setup runs again. After an interruption, implementation picks up from `.task/task/<slug>.md` as it stands.

## How it works

```text
discuss freely in chat
  ↓
/task:grill              grill before you capture — interrogate the decision, no artifact
  ↓
/task:to-task            capture what and why — no plan
/task:to-plan             …  + a Plan (Goal/Touches/Logic steps)
/task:to-roadmap          … a whole multi-task initiative
/task:to-spec             … pin technical decisions (tasks/roadmaps cite via Spec:)
  ↓                                          ↓
implement it now,                /task:roadmap-to-workflow
in a fresh session:                fans unchecked items out to
"implement .task/task/<slug>.md"   a dynamic Workflow, one per item
  → /verify → /code-review → commit
```

`/task:grill` is the optional pre-capture step: point it at a plan or decision and it interrogates one question at a time, keeps a decision-plus-rationale ledger, ends with a pre-mortem, and routes you to the right capture skill — writing nothing itself. Grill *before* you capture, so the artifact serializes a decision that has already been pressure-tested.

Depth of capture is the skill you pick, not a flag: `to-task` for a quick "what and why", `to-plan` when you already know the approach, `to-roadmap` for a multi-task initiative. `to-spec` is orthogonal — it pins load-bearing technical decisions into `.task/spec/<slug>.md`, which tasks and roadmaps reference via a `Spec:` header and the implementing session honors as a fixed anchor. There is no execution skill — capture ends with a copy-pasteable path, and any session (the same one, a fresh one, or one spawned by `roadmap-to-workflow`) executes the artifact directly.

The pipeline is built on a small set of invariants; the full contract lives in [`docs/contract.md`](docs/contract.md).

- **Artifacts.** `.task/` is flat — one file per task under `.task/task/<slug>.md`, one file per initiative under `.task/roadmap/<slug>.md`, one file per spec under `.task/spec/<slug>.md`. No workspace subfolders, no log, no archive, no active-task pointer — the artifact's path is the only handle there is. Full producer/consumer table: [docs/contract.md](docs/contract.md).
- **No hook gate.** There is no `hooks/hooks.json` — the plugin ships no hook at all. Enforcement is by convention: `validate.sh` is available as an optional self-check, never wired to a PreToolUse matcher.
- **Parallel worktrees.** All worktrees of a repo share one `.task/` automatically — its location is recorded in `git config task.root` on first setup, so nested, sibling, and bare-repo worktrees resolve it with zero setup (no symlink, no join step). This is what lets `/task:roadmap-to-workflow` fan items out to isolated worktrees that still share one `.task/`.

## Contributing

> *This section is for those editing the tool itself.* Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) — it carries the commit format, the list of allowed scopes, the release procedure, and the repository layout.

Each `SKILL.md` is a prompt contract that another Claude instance will read in someone else's project. The invariants that must not be broken — the `task.md` format, the flat `.task/` layout, the pipeline staying invisible outside `.task/` — are pinned in [`docs/contract.md`](docs/contract.md); a compact checklist is in [`CLAUDE.md`](CLAUDE.md). If you change something, update `docs/contract.md` and this README in the same commit; `CHANGELOG.md` is edited only on explicit request.
