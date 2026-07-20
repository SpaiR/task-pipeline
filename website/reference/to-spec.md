# to-spec

Fixes load-bearing technical decisions into a standalone `.task/spec/<slug>.md` — numbered Decision / Rationale / Constrains sections. Orthogonal to the depth-capture skills: tasks and roadmaps reference a spec via a `Spec:` header, and the executing session reads it as a fixed anchor.

See the [specs guide](/guide/specs) for when a decision is spec material.

## Usage

```text
/task:to-spec [<context>]
```

**Input** — `$ARGUMENTS`: a rough description of the decision area, or a reference back to a prior discussion (`"write a spec from what we settled"`).

## When to use it

For a protocol, a cross-cutting data shape, or a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation. If the discussion settled only behavioral outcomes, or details local to one task, `to-spec` **stops and redirects** you to `to-task` / `to-plan`.

## What it writes

```markdown
# Spec: <Title>

> One-line purpose.

## 1. <decision title>
**Decision:** <what was chosen — concrete, real symbols/shapes expected here>
**Rationale:** <the reasoning that must survive re-derivation>
**Constrains:** <what this pins for consumers; what it leaves free>

## 2. …
```

One decision per numbered section; numbers are contiguous from 1, because citations depend on stable numbering.

## Output

The digest lists **every** pin in full — a spec is read downstream as a fixed anchor, so this is your one glance to catch a misstated decision:

```text
Wrote `.task/spec/event-envelope.md`
# Spec: Event envelope
Pins:
- 1. {decision, one line}
- 2. …
validate: OK — 0 errors, 0 warnings

→ Next: `/task:to-plan` a task that relies on this spec — or add a
  `Spec: event-envelope` header to an existing roadmap or task.
```

## Does not

- Write a Plan, a step list, or implementation code — a spec pins decisions, it doesn't plan.
- Capture behavioral outcomes or single-task details — those belong in a task's `### Outcomes` / `### Acceptance criteria`.
- Wire the `Spec:` header into a task or roadmap — that's the referencing skill's job.
- Write a filler spec when no real decision was settled — it stops and redirects instead.
