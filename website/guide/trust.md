# Why you can trust this

`task-pipeline` runs bash, edits files, and writes commits. So here is exactly what it will and won't touch. It's MIT-licensed and built by [SpaiR](https://github.com/SpaiR).

## Nothing is committed until you say so

Nothing is committed until an implementing session runs, per the `## Execution` block. Until then, every change the pipeline made is just working-tree edits — back them out with plain `git restore` / `git checkout`. The capture skills themselves only write Markdown under `.task/`.

One exception, and it's opt-in: [`roadmap-to-workflow`](/guide/autopilot) (autopilot) commits each roadmap item as it lands — that's the point of running an approved roadmap hands-off. It still never pushes.

## Commits stage only task-related files, and never push

The executing session stages only the files it touched and commits per your `config.md` → Commit Format. It does **not** push. Nothing leaves your machine unless you push it yourself.

## No hidden orchestration

There are no subagents in the capture skills. The one skill that spawns parallel sessions — [`roadmap-to-workflow`](/guide/autopilot) — is a plain dynamic Workflow that the skill itself authors, and you can inspect it before it runs. There is no hook, no background gate intercepting your tool calls.

## The pipeline leaves no trace in your repo

`.task/` is excluded via `.git/info/exclude` (not `.gitignore`), so:

- it never shows up in `git status`;
- it never touches a tracked file — a teammate cloning the repo sees nothing;
- `rm -rf .task` returns the repo to exactly how it was.

The only markers the pipeline writes are that git-exclude entry and a `git config task.root` value (so parallel worktrees resolve the same `.task/`). Nothing else — no active-task pointer, no per-worktree state file.

## What that adds up to

| The pipeline… | …and specifically |
|---|---|
| edits files | only Markdown under `.task/`, until you run an implementing session |
| commits | only when the `## Execution` block runs; only task-related files; never pushes |
| orchestrates | only via a Workflow you can read first; no hooks, no hidden subagents |
| touches your repo | never a tracked file; invisible to `git status`; fully removable |

→ Next: [Comparison with alternatives](/guide/comparison).
