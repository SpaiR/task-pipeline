# to-task

Distils the chat (or a roadmap item) into `.task/task/<slug>.md` with `## Description` **and** `## Plan` (Goal / Touches / Logic steps), plus `## Tests` when the testing policy calls for it. The one single-task capture: a task worth an artifact is a task whose approach is worth writing down, so the Plan is never optional.

See the [single-task guide](/guide/single-task) for how it fits the everyday flow.

## Usage

```text
/task:to-task [<roadmap-slug>[#N] | context]
```

**Input** — `$ARGUMENTS`, optional. Recognized forms:

| Form | Behavior |
|---|---|
| *(empty)* | Draft from the chat discussion so far. With no chat to draft from, open an item from a roadmap that has open items. |
| `<roadmap-slug>` or `<roadmap-slug>#<N>` | Open from that roadmap item instead of the chat. When the project has roadmaps, a `<slug>#<N>` that names none stops and lists the ones that exist; with no roadmap and no chat to draft from, it stops and points at `/task:to-roadmap`. |
| anything else | Free-form context folded into the draft alongside the chat. |

## When to use it

Any task that gets its own file. `to-task` is fresh-only — it always drafts a new `## Description` and `## Plan` together, never targets an existing file to add or replace just the plan. A task too small to deserve a plan is too small to deserve a file — just do it in chat.

## What it writes

```markdown
# {Short task title}

Spec: [{spec-slug}](../spec/{spec-slug}.md)   (one line per relevant spec; omitted if none)

---
## Description

{why + what, in your own framing}

## Plan

### Step 1: {short action title}

**Goal:** {the observable end state this step reaches}

**Touches:**

- `path/one`
- `path/two`

**Logic:** {optional — pseudocode, only when the how is non-obvious}

## Tests                 (optional; per Testing Policy)
### Test 1: {what is asserted}

## Execution
> …stamped verbatim…
```

`Touches` lists real full paths — and also scopes which review fixes get applied: `task:code-reviewer` fixes confirmed defects inside these files, plus a regression the same diff caused outside them, and reports everything else instead of widening the change. `Logic` appears only where Goal + Touches leave genuine ambiguity.

When opened from a roadmap item, it also stamps `Roadmap: [<slug>](../roadmap/<slug>.md)` and `Source item: #N` so `task:code-reviewer` can tick the right checkbox once its review passes.

## From a roadmap item

When the task comes from a roadmap item, `to-task` also reads that roadmap's `## Architecture` section, if it has one — see [`to-roadmap`](/reference/to-roadmap). It's read as **intended shape, not a fixed anchor**: the Plan's `Touches` and `Goal`s follow its components and interfaces by default, and a step is free to depart when the actual code disagrees, as long as its `Goal` states why in one clause. The digest's `architecture:` line reports which happened.

## Tests

Governed by `.task/CLAUDE.md` → Testing Policy: `always` writes Tests every time; `on-demand` (default) only when the discussion asks; `never` omits them. Each `## Plan` step that satisfies a test references it by number.

## First run

On a fresh project, `to-task` runs setup inline: detect language + test policy → write `.task/CLAUDE.md` (no confirmation chip) → record `git config task.root`, write the self-ignoring `.task/.gitignore`. Then it continues into the capture. See [Configuration](/reference/configuration).

## Slug collision

An existing slug is never silently overwritten:

- **Chat-draft mode** — the slug is already in `TASKS:` → a chip: **Pick a different slug** *(Recommended)* / **Overwrite it** / **Decline — stop without writing**. It first states the existing file's headings, so an overwrite's cost is visible.
- **From a roadmap item whose own file already exists** — a chip: **Regenerate from the item** *(Recommended — the Description is re-derived from the ready description, so only the old Plan and any hand edits are replaced)* / **Decline — stop without writing**.

## Output

```text
Wrote `.task/task/http-retry-backoff.md`
# HTTP retry with backoff
Sections: Description, Plan (3 steps), Execution
Plan:
- Step 1: {short title}
- Step 2: …

architecture: followed | deviated in step N — {reason} | none

validate: OK — 0 errors, 0 warnings

→ Next: implement it now, or in a fresh session run:
  `implement .task/task/http-retry-backoff.md`
```

## Does not

- Silently overwrite an existing task file — every existing slug goes through a collision chip first.
- Modify the source roadmap file or a referenced spec — both are read-only here.
- Author a spec file — referencing one via a `Spec:` header is fine; writing it is [`to-spec`](/reference/to-spec)'s job.
- Leave `## Plan` present with zero steps, or `## Tests` with zero tests — both fail `validate.sh`.
- Write a task file without a `## Plan` — a Description with no approach is chat, not an artifact.
- Stamp a size hint — size hints live only on roadmap items as `**Size:**`.
