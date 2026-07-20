# Capture a single task

The everyday flow: discuss in chat, capture to a file, implement. Two skills capture a single task — the difference is depth.

## to-task vs to-plan

| | [`to-task`](/reference/to-task) | [`to-plan`](/reference/to-plan) |
|---|---|---|
| Writes | `## Description` only | `## Description` **+** `## Plan` (+ `## Tests` when policy calls for it) |
| Use when | You want to record the "what and why" before deciding an approach | You know enough about the approach to hand straight to implementation |
| Output file | `.task/task/<slug>.md` | `.task/task/<slug>.md` (same shape, with a Plan) |

Both produce one file per task, and both stamp the same `## Execution` block. Depth is the skill you pick — there is no flag.

## The flow

```text
# talk the task through in chat, then:

/task:to-plan
# → drafts .task/task/http-retry-backoff.md:
#   ## Description + ## Plan (Goal / Touches / Logic steps)
# → prints a digest, then:
#   → Next: implement it now, or in a fresh session run:
#     `implement .task/task/http-retry-backoff.md`

implement .task/task/http-retry-backoff.md
# → follows the ## Execution block:
#   implement per the Plan → /verify → /code-review → commit
```

Each `## Plan` step has three layers:

- **Goal** — the observable end state the step reaches.
- **Touches** — the files it changes (this list also scopes which review fixes get applied).
- **Logic** — optional, only when the "how" is non-obvious.

## From a quick capture to a full plan

Start light with `to-task`, then deepen later. Running `to-plan` on a file that already exists does the right thing automatically:

- **Promote** — the file has a Description but no Plan yet → `to-plan` inserts a `## Plan` in place, leaving the Description untouched.
- **Revise** — the file already has a Plan → `to-plan` replaces it in place and shows a one-line note of what changed, rather than starting over or appending a duplicate.

```text
/task:to-task
# → .task/task/http-retry-backoff.md — Description only

# …later, once you know the approach…
/task:to-plan http-retry-backoff
# → promotes it in place: adds ## Plan, Description stays as-is
```

## Tests

Whether a task gets a `## Tests` section is governed by `config.md` → Testing Policy:

- `always` — every `to-plan` capture includes Tests.
- `on-demand` (default) — Tests are written only if the discussion explicitly asks ("with tests", "cover with tests").
- `never` — no Tests section.

Only `to-plan` writes `## Tests`; `to-task` never does.

## Editing by hand

The artifact is a plain Markdown file. To change scope, edit the `## Description` (and `## Plan`, if present) directly — or re-run `/task:to-plan` to revise the plan through the tool. Either way, it's just a file.

→ Next: [Grill before you capture](/guide/grill) — pressure-test the decision first.
