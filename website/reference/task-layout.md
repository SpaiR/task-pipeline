# .task/ layout

`.task/` is **flat** — one file per task, one per roadmap, one per spec. No workspace subfolders, no log, no archive, no active-task pointer. It sits once at the pipeline root and is shared by every worktree of the repo.

```text
.task/
├── CLAUDE.md                  project policy + how to execute a task; auto-loaded
│                              by any session that reads a file under .task/
├── .gitignore                 a single *: ignores the folder itself
├── task/
│   ├── http-retry-backoff.md  one file per task; slug = filename = identity
│   └── migrate-auth-endpoints.md
├── roadmap/
│   └── api-v2-migration.md    one file per multi-task initiative
└── spec/
    └── event-envelope.md      one file per technical-decision spec
```

::: tip Invisible to your repo
`.task/` ignores itself through its own `.task/.gitignore` (a single `*`, which covers that file too), so it never shows in `git status` and never touches a tracked file or `.git/info/exclude`. Delete it with `rm -rf .task` and the repo is exactly as before. One side effect: a search scoped to `.task/` finds nothing — see [Troubleshooting](/guide/troubleshooting#search-in-task).
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

## Plan                  (required; to-task and the per-item plan agent write it)
### Step 1: <short title>

**Goal:** <observable end state>

**Touches:**

- `path/one`
- `path/two` (<symbol>)

**Logic:** <optional — only when non-obvious>

## Tests                 (optional; per Testing Policy)
### Test 1: <what is asserted>

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

- **Line 1** is a plain `# <Title>` — no bracketed task-id.
- `Roadmap:` / `Source item:` / `Spec:` headers sit above the `---`, ASCII, each its own paragraph — the blank lines keep a Markdown preview from merging them into one line or rendering the block as a heading.
- Plan fields (`**Goal:**`, `**Touches:**`, `**Logic:**`) each start their own paragraph, and `Touches` is a list, one file per bullet.
- Cross-references are **Markdown links**, so a `.task/` file is navigable in a Markdown viewer or plan-review tool. The link **text** is the slug that carries the identity; the target is what a viewer follows, and is always `../<kind>/<slug>.md` — `task/`, `roadmap/` and `spec/` are siblings under `.task/`. `Source item:` is a number, not a reference, so it stays bare.
- `## Description` and `## Plan` are always written together, and both are required; `## Tests` is optional, per Testing Policy.
- `## Execution` is a one-line pointer, stamped verbatim by `to-task` and `roadmap-to-workflow`'s per-item plan agent. Roadmaps and specs carry none. The instructions it names live once in `.task/CLAUDE.md` → `## Executing a task` — that is the mechanism carrying implement → commit → review.

## roadmap.md

An item backlog. Line 1 is its `# <Title>`; optional `Spec:` headers sit directly under it, above the intro prose:

```markdown
# <Title>
Spec: [<slug>](../spec/<slug>.md)   (optional, repeatable)

<intro prose>
```

Each item:

```markdown
### 1. <Task title>

- [ ] Done

**Dependencies:** — / 1, 2, …

**Size:** S | M | L      (optional)

**Ready description:**

> **Context**
>
> …
>
> **Goal**
>
> …
>
> **Outcomes**
>
> …
>
> **Invariants**          (optional)
>
> …
>
> **Acceptance criteria**
>
> …
```

The `- [ ] Done` line directly under the heading is the progress marker, and a Markdown preview renders it as a checkbox; `**Dependencies:**` drives the wave ordering in [`roadmap-to-workflow`](/reference/roadmap-to-workflow). Write `—` (or `-` / `none` / `n/a`) when an item has none — any other word is read as an item number and stops the run.

An item that leans on a spec decision cites it on the last line of its Ready description, as `> **Spec references:** [<slug>](../spec/<slug>.md) §N`. `## Prerequisites` and `## Backlinks` hold Markdown links too — a sibling roadmap is `[<slug>](<slug>.md)`, a spec `[<slug>](../spec/<slug>.md)`.

A roadmap also carries a `## Architecture` section — components, interfaces between items, a sketch per item, technical ordering — written by [`to-roadmap`](/reference/to-roadmap) in the same pass as the items. No parser reads it; planners follow it as the intended shape. (An older roadmap captured before `to-roadmap` always wrote this section stays valid without one.)

## spec.md

```markdown
# Spec: <Title>

> <One sentence: which decisions this spec pins, and for what.>

## 1. <decision title>

**Decision:** <what was chosen>

**Rationale:** <why — the reasoning that must survive>

**Constrains:** <what it pins; what it leaves free>
```

## For maintainers

This page is the user-facing overview. The authoritative, parser-level contract — root resolution, the producer/consumer table, the exact `## Execution` text, and the bash layer — lives in the repo's [`docs/contract.md`](https://github.com/SpaiR/task-pipeline/blob/main/docs/contract.md).
