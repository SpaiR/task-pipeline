# Capture a single task

The everyday flow: discuss in chat, capture to a file, implement. One skill captures a single task — [`to-task`](/reference/to-task).

## What it writes

`to-task` always writes `## Description` **and** `## Plan` (Goal / Touches / Logic steps) together, plus `## Tests` when the testing policy calls for it. A task worth an artifact is a task whose approach is worth writing down, so the Plan is never optional — a task too small to deserve a plan is too small to deserve a file; just do it in chat.

## The flow

```text
# talk the task through in chat, then:

/task:to-task
# → drafts .task/task/http-retry-backoff.md:
#   ## Description + ## Plan (Goal / Touches / Logic steps)
# → prints a digest, then:
#   → Next: implement it now, or in a fresh session run:
#     `implement .task/task/http-retry-backoff.md`

implement .task/task/http-retry-backoff.md
# → follows the ## Execution pointer into .task/CLAUDE.md:
#   implement per the Plan → commit → task:code-reviewer reviews, fixes, commits
```

Each `## Plan` step has three layers:

- **Goal** — the observable end state the step reaches.
- **Touches** — the files it changes (this list also scopes which review fixes get applied).
- **Logic** — optional, only when the "how" is non-obvious.

## Tests

Whether a task gets a `## Tests` section is governed by `.task/CLAUDE.md` → Testing Policy:

- `always` — every capture includes Tests.
- `on-demand` (default) — Tests are written only if the discussion explicitly asks ("with tests", "cover with tests").
- `never` — no Tests section.

## Fresh only

`to-task` always drafts a new `## Description` and `## Plan` together — it never targets an existing file to add or replace just the plan. An existing slug is surfaced first, with a chip to pick a different slug or overwrite; from a roadmap item whose own file already exists, the chip is to regenerate from the item or decline. `.task/` is git-ignored, so an overwritten file isn't recoverable — the chip exists so that's never silent.

## Editing by hand

The artifact is a plain Markdown file. To change scope, edit `## Description` and `## Plan` directly, or re-run `/task:to-task` — it asks before overwriting an existing slug.

→ Next: [Grill before you capture](/guide/grill) — pressure-test the decision first.
