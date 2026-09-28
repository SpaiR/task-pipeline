# task-pipeline

[![Release](https://img.shields.io/github/v/release/SpaiR/task-pipeline?sort=semver)](https://github.com/SpaiR/task-pipeline/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2)

**Docs & guides → [spair.github.io/task-pipeline](https://spair.github.io/task-pipeline/)**

> A plan file is only as good as the argument that produced it.

```text
You:    "Let's cache the API responses in Redis."
Claude: "Great idea! I'll start implementing."
```

That second line is where projects quietly go wrong: the model agrees and starts building before the plan was ever argued. `task-pipeline` keeps the discussion and the doing apart. You talk the work through in chat, optionally let `/task:grill` interrogate it, then one command freezes the result into a Markdown file under `.task/`. Any session — this one or a fresh one tomorrow — implements that file, commits, and hands the diff to the plugin's reviewer, which proves each finding before fixing it and commits its fixes on top.

It's for work longer than one session. A twenty-minute fix doesn't need it.

```text
discuss in chat
  → grill it (optional — interrogate the plan first)
  → capture to a file: to-task | to-roadmap | to-spec
  → any session implements it, then task:code-reviewer reviews and fixes
```

## Quickstart

Requires only [Claude Code](https://docs.claude.com/en/docs/claude-code).

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

Update later with `/plugin marketplace update task-pipeline`.

Talk a task through in chat — say, an HTTP retry system with backoff and a dead-letter queue. Then, optionally, grill it:

```text
/task:grill
#   → one question at a time, each with a recommended answer:
#     "Retry the 429s too, or only 5xx and timeouts?"  [recommended: 429s too]
#   → closes with a pre-mortem and a decision ledger; writes nothing
```

Capture the discussion:

```text
/task:to-task
#   → drafts .task/task/http-retry-backoff.md: ## Description + ## Plan (Goal/Touches/Logic steps)
#   → footer: implement it now, or in a fresh session run:
#     `implement .task/task/http-retry-backoff.md`
```

Hand the file to any session:

```text
"implement .task/task/http-retry-backoff.md"
#   → implements the plan and commits
#   → task:code-reviewer proves each finding, fixes it, runs your build and tests,
#     and commits its fixes as a second commit on top
```

There is no setup command: the first capture in a project writes `.task/CLAUDE.md` itself.

> [!TIP]
> Roadmap-driven initiatives, `/task:roadmap-to-workflow`, and returning to a task later are covered in the **[guide](https://spair.github.io/task-pipeline/guide/roadmaps)**.

## Commands

What you capture is the skill you pick — there are no flags.

| Command | What it does |
|--------|--------|
| `/task:grill [topic]` | Interrogates a plan one question at a time and ends with a pre-mortem. Writes nothing. |
| `/task:to-task [<roadmap-slug>[#N] \| context]` | Captures one task into `.task/task/<slug>.md`: description plus a stepwise plan. |
| `/task:to-roadmap [initiative]` | Captures a multi-task initiative into `.task/roadmap/<slug>.md`: a backlog of items plus its `## Architecture`. |
| `/task:to-spec [decision area]` | Pins load-bearing technical decisions into `.task/spec/<slug>.md`, which tasks and roadmaps cite via `Spec:`. |
| `/task:roadmap-to-workflow [<roadmap-slug>]` | Autopilot: plans, implements, reviews and ticks each unchecked roadmap item in dependency order. |
| `validate` *(utility)* | Optional format check: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. |

Full reference: **[Commands](https://spair.github.io/task-pipeline/reference/commands)**.

## Why you can trust this

It runs bash, edits files, and writes commits, so here is exactly what it will and won't touch:

- **Nothing is committed until the implementing session does so.** Until then every change is a working-tree edit you can `git restore`. The one exception is `/task:roadmap-to-workflow`, which commits each item as it lands.
- **Commits stage only task-related files, and nothing is ever pushed.**
- **No hidden orchestration, no hooks.** The plugin ships one agent, `agents/code-reviewer.md`, and one Workflow driver, `skills/_lib/roadmap-driver.js`; both are readable files in this repo.
- **No trace in your repo.** `.task/` ignores itself through its own `.task/.gitignore`, so it never shows in `git status`. `rm -rf .task` leaves the repo exactly as before.

More in **[Trust](https://spair.github.io/task-pipeline/guide/trust)**.

## Configuration

Settings live in `.task/CLAUDE.md`, written once by the first capture and yours to edit after that. It sets the artifact language, the test policy (`always`, `on-demand` by default, or `never`), the build and test commands the reviewer runs, and the instructions an implementing session follows. All worktrees of a repo share one `.task/`. Details: **[Configuration](https://spair.github.io/task-pipeline/reference/configuration)**.

## Comparison with alternatives

Most spec-driven tools answer "the model codes before it understands" with more templates and the same ceremony for every task. task-pipeline answers it with a grill step that argues with the plan, and a capture sized to the work — flat Markdown under `.task/`, no MCP server, no API keys, no task database. Head-to-head tables against default Claude Code, superpowers, Matt Pocock's skills, OpenSpec, spec-kit and Task Master: **[Comparison](https://spair.github.io/task-pipeline/guide/comparison)**.

## Contributing

Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) for commit format, scopes and repository layout. The invariants are in [`docs/contract.md`](docs/contract.md), with a checklist in [`CLAUDE.md`](CLAUDE.md). Run `bash tests/run.sh` before every commit.
