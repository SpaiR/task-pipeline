# FAQ

The objections that come up most, answered short. Each links to the page with the full story rather than repeating it.

## Does it conflict with plan mode?

No — they do different jobs and compose. Plan mode helps you think inside one session; task-pipeline persists the result of that thinking to a file so it survives `/clear` and a fresh session tomorrow. Use plan mode to explore, then run `/task:to-plan` when the plan is worth keeping. See the [comparison with default Claude Code](/guide/comparison#vs-default-claude-code).

## What if I don't want it to commit?

Then it won't. The capture skills only ever write Markdown under `.task/` — nothing is staged or committed until you explicitly tell a session to `implement <path>`. Even then it commits only the files it touched and never pushes, so nothing leaves your machine unless you push it yourself. Back out any working-tree change with plain `git restore`. Full detail: [Why you can trust this](/guide/trust#nothing-is-committed-until-you-say-so).

## Does it work in a monorepo or with git worktrees?

Yes. There's one `.task/` per repo, and every worktree resolves the same one through `git config task.root` (with an upward-walk fallback). If a worktree can't find `.task/`, run any capture skill from it once to record the anchor, or set it by hand with `git config --local task.root /path/that/contains/dot-task`. See [worktree can't find .task/](/guide/troubleshooting#a-worktree-cant-find-task).

## What if I just read the file myself and ignore the Execution block?

That's fine — it's plain Markdown, not a runtime. The `## Execution` block is a standing instruction for a session that has no other context; it isn't enforced by anything. You're free to read the `## Description` and `## Plan` and implement by hand, or hand the file to a session and let it follow the block. There's [no hook and no hidden orchestration](/guide/trust#no-hidden-orchestration) making you do either.

## Does it work in languages other than English?

Yes. Descriptions and the dialogue follow `config.md` → Language, so you can write and discuss tasks in your own language. Only the format's fixed strings — section headers, commit trailers, and the `## Execution` block — stay English, so the validator and any implementing session read them the same way. See [Configuration](/reference/configuration).

## How do I uninstall cleanly?

Two independent parts. Remove the artifacts with `rm -rf .task` — since `.task/` was never tracked (it lives in `.git/info/exclude`, not `.gitignore`), the repo is left exactly as it was. Remove the plugin itself through `/plugin` (uninstall `task@task-pipeline`). If you want to erase the last traces, drop the `.task` line from `.git/info/exclude` and run `git config --unset task.root`. See [Why you can trust this](/guide/trust#the-pipeline-leaves-no-trace-in-your-repo).

→ Next: [Troubleshooting](/guide/troubleshooting) — symptoms and fixes for the first run and the edge cases.
