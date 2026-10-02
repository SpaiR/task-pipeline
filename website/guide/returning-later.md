# Returning to a task later

There's no pointer to re-point and no "current task" to restore. A task file is just a file — pick it back up in this session or a brand-new one.

## Find what's captured

```text
ls .task/task/
# every task you've captured that you haven't deleted — closed tasks are just
# files that stay put; git history is the record, there is no archive
```

## Pick one up

```text
implement .task/task/http-retry-backoff.md
# any session, any time — the artifact path is the handle
```

No pointer to re-point, nothing to restore from an archive.

## Change scope before re-running

The artifact is plain Markdown. Edit `## Description` and `## Plan` by hand, or re-run [`/task:to-task`](/reference/to-task) — it asks before overwriting an existing slug; for a roadmap item's own file the chip offers to regenerate it from the item, which replaces the old Plan and any hand edits. There's no promote or revise mode: a fresh capture always writes Description and Plan together.

## Where a roadmap stands

Read its status lines directly:

```text
awk '/^### [0-9]+\. /{h=$0} /^- \[ \] Done/{print h}' .task/roadmap/api-v2-migration.md
# every item still unchecked
```

## Combining scenarios

None of these modes are exclusive. Capture a couple of small fixes with `to-task`, and reserve `to-roadmap` + `roadmap-to-workflow` for the initiative-sized work — all sharing the same flat `.task/`, all invisible to `git status`.

→ Next: [Why you can trust this](/guide/trust).
