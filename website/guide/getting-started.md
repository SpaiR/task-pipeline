# Getting started

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) — `task-pipeline` ships as a Claude Code plugin.
- A build/test command worth running — the review pass runs whatever your project declares in `.task/CLAUDE.md` → Build and Tests. It's optional: with nothing declared, the reviewer reports the skip in words rather than implying a green run. No platform slash command is required; review is the plugin's own `task:code-reviewer` agent, so it only needs the plugin enabled — if it doesn't resolve, see [Troubleshooting](/guide/troubleshooting#code-reviewer-agent-not-found).
- Dynamic Workflows — only [`/task:roadmap-to-workflow`](/guide/autopilot) needs them, to fan a roadmap's items out to parallel sessions. Everything else works without. There's no pinned version to match: task-pipeline uses these features as your Claude Code install exposes them.

## Install

The pipeline ships as a Claude Code plugin (`task`) inside the `task-pipeline` marketplace. Install it through the marketplace:

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

From then on, updates are a single command:

```text
/plugin marketplace update task-pipeline
```

After installation, Claude Code gains these commands:

`/task:grill` · `/task:to-task` · `/task:to-plan` · `/task:to-roadmap` · `/task:to-spec` · `/task:roadmap-to-workflow`

There is no hook — enforcement is by convention, not a gate. (If the commands don't show up, see [Troubleshooting](/guide/troubleshooting#commands-appear).)

::: details Local development install
```text
/plugin marketplace add /path/to/task-pipeline
/plugin install task@task-pipeline
```
:::

## Your first capture

You don't run a setup command first. The first capture in a new project detects your language and test policy, writes `.task/CLAUDE.md`, tells you what it wrote, and continues straight into the capture.

Talk a task through in chat — say, an HTTP retry system with backoff and a dead-letter queue — then capture it:

```text
/task:to-plan
```

On a fresh project this will:

1. **Detect and write the settings.** It reads `CLAUDE.md` and your commit conventions, writes `.task/CLAUDE.md`, records `git config task.root`, excludes `.task` from git, and reports what it wrote:
   > Wrote `.task/CLAUDE.md` — Language: follow task.md Description; Testing Policy: on-demand.

   There is no confirmation to click: if a detected value is wrong, edit the file. Setup writes it once and never rewrites it.

2. **Write the artifact.** It drafts `.task/task/http-retry-backoff.md` with a `## Description` and a `## Plan` (Goal / Touches / Logic steps), then prints a short digest of what it captured.

3. **Hand you a path.** It ends with a copy-pasteable footer:
   > → Next: implement it now, or in a fresh session run: `implement .task/task/http-retry-backoff.md`

## Implement it

Hand the file to any session — this one, or a fresh one tomorrow. `implement` is an ordinary chat message, **not** a slash command — type it as you'd type any instruction:

```text
implement .task/task/http-retry-backoff.md
```

That session follows the artifact's `## Execution` pointer into `.task/CLAUDE.md` → `## Executing a task`:

- implement per the `## Plan` (or the `## Description` if there's no plan);
- commit per `.task/CLAUDE.md` → Commit Format;
- spawn `task:code-reviewer` on that diff — it proves each defect it suspects before touching anything, fixes the confirmed ones within the files named in **Touches**, reports the rest, runs `.task/CLAUDE.md` → Build and Tests, and commits its fixes as a second commit on top.

Nothing is committed until this step runs. Until then, every change is just working-tree edits.

## What landed in .task/

```text
.task/
├── CLAUDE.md                        ← written once, on first capture; yours to edit
└── task/
    └── http-retry-backoff.md        ← your task; the slug is its identity
```

`.task/CLAUDE.md` is a nested `CLAUDE.md`, so Claude Code loads it into any session that reads a file under `.task/` — that's how an implementing session picks up your settings without being told to.

`.task/` is flat and invisible to your repo — it's excluded via `.git/info/exclude`, so it never shows in `git status`. Delete it with `rm -rf .task` and the repo is exactly as before. See [.task/ layout](/reference/task-layout) for the full picture.

## Prefer a lighter touch?

[`/task:to-task`](/reference/to-task) skips the Plan — good for a quick capture of the "what and why" that you'll flesh out with `/task:to-plan` later, or hand straight to implementation when the fix is obvious.

→ Next: [Core concepts](/guide/core-concepts) — the handful of ideas that make the rest predictable.
