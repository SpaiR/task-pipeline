# Returning to a task later

There's no pointer to re-point and no "current task" to restore. A task file is just a file — pick it back up in this session or a brand-new one.

## Find what's captured

```text
ls .task/task/
# every task you've captured that you haven't deleted — closed tasks are just
# files that stay put; git history is the record, there is no archive
```

Want just the tasks that still have no Plan (the `to-task`-only captures)?

```text
grep -L '^## Plan' .task/task/*.md
```

## Pick one up

```text
implement .task/task/http-retry-backoff.md
# any session, any time — the artifact path is the handle
```

No pointer to re-point, nothing to restore from an archive.

## Change scope before re-running

The artifact is plain Markdown. Edit the `## Description` (and `## Plan`, if present) by hand, or run [`/task:to-plan`](/reference/to-plan) again:

- on a file that already has a `## Plan`, `to-plan` **revises** it in place and shows a one-line note of what changed;
- on a `to-task`-only file with no `## Plan` yet, the same command **promotes** it in place.

## Where a roadmap stands

Grep its checkboxes directly:

```text
grep '^### - \[ \]' .task/roadmap/api-v2-migration.md
# every item still unchecked
```

## Combining scenarios

None of these modes are exclusive. Capture a couple of small fixes directly with `to-task`, run a larger one through `to-plan`, and reserve `to-roadmap` + `roadmap-to-workflow` for the initiative-sized work — all sharing the same flat `.task/`, all invisible to `git status`.

→ Next: [Why you can trust this](/guide/trust).
