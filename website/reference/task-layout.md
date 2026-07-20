# .task/ layout

`.task/` is **flat** — one file per task, one per roadmap, one per spec. No workspace subfolders, no log, no archive, no active-task pointer. It sits once at the pipeline root and is shared by every worktree of the repo.

```text
.task/
├── config/
│   └── config.md              project policy — language, tests, commits
├── task/
│   ├── http-retry-backoff.md  one file per task; slug = filename = identity
│   └── migrate-auth-endpoints.md
├── roadmap/
│   └── api-v2-migration.md    one file per multi-task initiative
└── spec/
    └── event-envelope.md      one file per technical-decision spec
```

::: tip Invisible to your repo
`.task/` is excluded through `.git/info/exclude` (not `.gitignore`), so it never shows in `git status` and never touches a tracked file. Delete it with `rm -rf .task` and the repo is exactly as before.
:::

## task.md

```markdown
# <Title>
Roadmap: <slug>          (optional — roadmap items only)
Source item: #N          (optional — the item number)
Spec: <slug>             (optional, repeatable — each cites a spec anchor)
---
## Description
Why + what, distilled from the chat.

## Plan                  (written only by to-plan)
### Step 1: <short title>
**Goal:** <observable end state>
**Touches:** `path/one` `path/two`
**Logic:** <optional — only when non-obvious>

## Tests                 (optional; per Testing Policy)
### Test 1: <what is asserted>

## Execution
> …stamped verbatim by every capture skill…
```

- **Line 1** is a plain `# <Title>` — no bracketed task-id.
- `Roadmap:` / `Source item:` / `Spec:` headers sit above the `---`, ASCII.
- `## Description` is mandatory; `## Plan` and `## Tests` are optional.
- `## Execution` is stamped boilerplate — the mechanism that replaces a `build`/`ship` step.

## roadmap.md

An item backlog. Each item:

```markdown
### - [ ] 1. <Task title>

**Dependencies:** — / 1, 2, …
**Model:** haiku | sonnet | opus      (optional)

**Ready description:**

> ### Context
> ### Goal
> ### Outcomes
> ### Invariants          (optional)
> ### Acceptance criteria
```

The checkbox is the progress marker; `**Dependencies:**` drives the wave ordering in [`roadmap-to-workflow`](/reference/roadmap-to-workflow).

## spec.md

```markdown
# Spec: <Title>

> One-line purpose.

## 1. <decision title>
**Decision:** <what was chosen>
**Rationale:** <why — the reasoning that must survive>
**Constrains:** <what it pins; what it leaves free>
```

## For maintainers

This page is the user-facing overview. The authoritative, parser-level contract — root resolution, the producer/consumer table, the exact `## Execution` text, and the bash layer — lives in the repo's [`docs/contract.md`](https://github.com/SpaiR/task-pipeline/blob/main/docs/contract.md).
