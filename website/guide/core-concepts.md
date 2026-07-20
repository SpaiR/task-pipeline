# Core concepts

Six ideas carry the whole design. Once they click, everything else follows.

## 1. The artifact is the unit of work

Every task is exactly one Markdown file: `.task/task/<slug>.md`. It carries the "why + what" from your discussion, an optional step-by-step Plan, and a stamped `## Execution` block. That file is the contract between the discussion and the doing — nothing important lives outside it.

## 2. The slug is the identity

`<slug>` is a kebab-case English phrase derived from the task title — for example `http-retry-backoff`. It is **both the filename and the identity**. There is no task-id, no `[TASK-123]` bracket, no umbrella folder grouping. To refer to a task, you name its file.

## 3. The path is the handle

There is **no active-task pointer** — nothing tracks "the current task" that you could lose or that could go stale. To pick a task back up, in any session, you name its path:

```text
implement .task/task/http-retry-backoff.md
```

This is why the plan survives `/clear`, compaction, and tomorrow's fresh session: the handle is a file path on disk, not conversation state.

## 4. Execution is a block, not a skill

There is no `build` or `ship` command to learn. Every artifact carries a `## Execution` block — a few lines of stamped, English boilerplate — and any ordinary session told to implement the file simply follows it:

> Implement the Plan (or the Description if none). Run `/verify` end-to-end and `/code-review`, applying fixes only within **Touches**. Commit per `config.md` → Commit Format. If it's a roadmap item, tick its checkbox.

The mechanism that used to be two separate skills is now text inside the file. That's the whole execution side.

## 5. config.md holds project policy

`.task/config/config.md` is written once, inline, on your first capture. It records:

- **Language** — by default your Description is in your language; everything parser-stable (headers, the `## Execution` block, commit trailers) stays English.
- **Testing policy** — `always` / `on-demand` (default) / `never`, which governs whether a task gets a `## Tests` section.
- **Commit format**, code-navigation tool priority, and project conventions.

See [Configuration](/reference/configuration) for the details.

## 6. The pipeline is invisible to your repo

`.task/` is excluded through `.git/info/exclude` (not `.gitignore`), so it never shows up in `git status` and never touches a tracked file. It's a personal tool — a teammate cloning the repo sees nothing. Delete `.task/` and the repo is exactly as it was. The only markers the pipeline leaves are the git-exclude entry and a `git config task.root` value so parallel worktrees share one `.task/`.

## The interaction conventions

Every skill follows the same three habits, so the tool feels consistent:

- **(a) Next-step footer.** Every output ends with `→ Next: <runnable command>` or `→ Done.` — the path *is* the handle, so there's nothing else to remember.
- **(b) Write-then-digest.** A capture writes its artifact immediately, then prints a short structural digest (path, title, sections, the load-bearing decisions, the `validate.sh` result). The chat discussion *was* the review — there's no "confirm before writing" gate, because the file is git-excluded and a wrong write costs one deletion. ([`grill`](/reference/grill) writes nothing, so its decision ledger *is* the digest.)
- **(c) Chip forks.** Any real either/or decision the skill can't infer is a small multiple-choice prompt, never a guess.

→ Next: [Capture a single task](/guide/single-task) — the everyday flow in full.
