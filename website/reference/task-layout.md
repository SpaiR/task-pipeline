# .task/ layout

`.task/` is **flat** — one file per task, one per roadmap, one per spec. No workspace subfolders, no log, no archive, no active-task pointer. It sits once at the pipeline root and is shared by every worktree of the repo.

```text
.task/
├── CLAUDE.md                  project policy + how to execute a task; auto-loaded
│                              by any session that reads a file under .task/
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
Roadmap: [<slug>](../roadmap/<slug>.md)   (optional — roadmap items only)
Source item: #N                           (optional — the item number)
Spec: [<slug>](../spec/<slug>.md)         (optional, repeatable — each cites a spec)
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
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

- **Line 1** is a plain `# <Title>` — no bracketed task-id.
- `Roadmap:` / `Source item:` / `Spec:` headers sit above the `---`, ASCII.
- Cross-references are **Markdown links**, so a `.task/` file is navigable in a Markdown viewer or plan-review tool. The link **text** is the slug that carries the identity; the target is what a viewer follows, and is always `../<kind>/<slug>.md` — `task/`, `roadmap/` and `spec/` are siblings under `.task/`. `Source item:` is a number, not a reference, so it stays bare.
- `## Description` is mandatory; `## Plan` and `## Tests` are optional.
- `## Execution` is a one-line pointer, stamped verbatim by `to-task` / `to-plan`. The instructions it names live once in `.task/CLAUDE.md` → `## Executing a task` — that is the mechanism carrying implement → commit → review.

## roadmap.md

An item backlog. Line 1 is its `# <Title>`; optional `Spec:` headers sit directly under it, above the intro prose:

```markdown
# <Title>
Spec: [<slug>](../spec/<slug>.md)   (optional, repeatable)

<intro prose>
```

Each item:

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

The checkbox is the progress marker; `**Dependencies:**` drives the wave ordering in [`roadmap-to-workflow`](/reference/roadmap-to-workflow). Write `—` (or `-` / `none` / `n/a`) when an item has none — any other word is read as an item number and stops the run.

An item that leans on a spec decision cites it as `### Spec references → [<slug>](../spec/<slug>.md) §N`. `## Prerequisites` and `## Backlinks` hold Markdown links too — a sibling roadmap is `[<slug>](<slug>.md)`, a spec `[<slug>](../spec/<slug>.md)`.

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
