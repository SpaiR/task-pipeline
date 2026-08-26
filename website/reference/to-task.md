# to-task

Distils the chat discussion (or a roadmap item) into `.task/task/<slug>.md` with a `## Description` only — no `## Plan`. The lightest of the three capture skills.

See the [single-task guide](/guide/single-task) for how it fits the everyday flow.

## Usage

```text
/task:to-task [<context>]
```

**Input** — `$ARGUMENTS`, optional. Recognized forms:

| Form | Behavior |
|---|---|
| *(empty)* | Draft from the chat discussion so far. |
| `<roadmap-slug>` or `<roadmap-slug>#<N>` | Open from that roadmap item instead of the chat. |
| anything else | Free-form context folded into the draft alongside the chat. |

## What it writes

```markdown
# {Short task title}
Spec: [{spec-slug}](../spec/{spec-slug}.md)   (one line per relevant spec; omitted if none)
---
## Description

{why + what, in your own framing}

## Execution
> …stamped verbatim…
```

When opened from a roadmap item, it also stamps `Roadmap: [<slug>](../roadmap/<slug>.md)` and `Source item: #N` so the executing session can tick the right checkbox.

## First run

On a fresh project, `to-task` runs setup inline: detect language + test policy → write `.task/CLAUDE.md` (no confirmation chip) → record `git config task.root`, exclude `.task`. Then it continues into the capture. See [Configuration](/reference/configuration).

## Output

A structural digest, then the handoff footer:

```text
Wrote `.task/task/http-retry-backoff.md`
# HTTP retry with backoff
Sections: Description, Execution
Captured:
- {the why, one line}
- {the what / scope, one line}
validate: OK — 0 errors, 0 warnings

→ Next: implement it now, deepen it into a plan with `/task:to-plan`, or in a
  fresh session run: `implement .task/task/http-retry-backoff.md`
```

## Does not

- Write a `## Plan` or `## Tests` section — both are [`to-plan`](/reference/to-plan)'s contract.
- Scan the codebase beyond `CLAUDE.md` + top-level manifests — it captures discussion, not implementation.
- Author a spec file — referencing one via a `Spec:` header is fine; writing it is [`to-spec`](/reference/to-spec)'s job.
- Silently overwrite an existing task file — it surfaces the collision and lets you choose. It first reads what the existing file holds and tells you (`Description, Plan (4 steps), Tests (2)`); when there is a `## Plan` in it, the recommended option is to deepen the file with `/task:to-plan` instead, since `.task/` is git-excluded and an overwritten Plan is gone for good.
