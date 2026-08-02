# Why you can trust this

`task-pipeline` runs bash, edits files, and writes commits. So here is exactly what it will and won't touch. It's MIT-licensed and built by [SpaiR](https://github.com/SpaiR).

## Nothing is committed until you say so

Nothing is committed until an implementing session runs, per the `## Execution` block. Until then, every change the pipeline made is just working-tree edits — back them out with plain `git restore` / `git checkout`. The capture skills themselves only write Markdown under `.task/`.

One exception, and it's opt-in: [`roadmap-to-workflow`](/guide/autopilot) (autopilot) commits each roadmap item as it lands — that's the point of running an approved roadmap hands-off. It still never pushes.

## Commits stage only task-related files, and never push

The executing session stages only the files it touched and commits per your `config.md` → Commit Format. The review pass that follows amends **that** commit — keeping its message and its trailers — rather than stacking a "review fixes" commit on top, so one task stays one commit. It touches no other commit: no rebase, no reset, and it does **not** push. Nothing leaves your machine unless you push it yourself.

## No hidden orchestration

The capture skills spawn nothing. The plugin ships exactly one subagent — `task:code-reviewer`, the review pass an implementing session hands its commit to — and its entire prompt is a Markdown file in the repo (`agents/code-reviewer.md`) you can read before it ever runs. It works in the same working tree as the implementation, edits only what it can prove is broken, and never pushes. The one skill that spawns parallel sessions — [`roadmap-to-workflow`](/guide/autopilot) — is a plain dynamic Workflow that the skill itself authors, also inspectable before it runs. There is no hook, no background gate intercepting your tool calls.

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
| commits | only when the `## Execution` block runs; only task-related files; the reviewer amends that same commit, never another; never pushes |
| orchestrates | only via a Workflow you can read first; no hooks; one subagent, the reviewer, whose prompt is a file in the repo |
| touches your repo | never a tracked file; invisible to `git status`; fully removable |

→ Next: [Comparison with alternatives](/guide/comparison).
