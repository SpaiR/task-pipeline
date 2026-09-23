# to-spec

Fixes load-bearing technical decisions into a standalone `.task/spec/<slug>.md` — numbered Decision / Rationale / Constrains sections. Orthogonal to the depth-capture skills: tasks and roadmaps reference a spec via a `Spec:` header, and the executing session reads it as a fixed anchor.

See the [specs guide](/guide/specs) for when a decision is spec material.

## Usage

```text
/task:to-spec [decision area]
```

**Input** — `$ARGUMENTS`: a rough description of the decision area, or a reference back to a prior discussion (`"write a spec from what we settled"`).

## When to use it

For a protocol, a cross-cutting data shape, or a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation. Two stops-and-redirects:

- Only behavioral outcomes, or details local to one task → `to-spec` **stops and redirects** you to `to-task` / `to-plan`.
- Only the initiative's technical shape — which components it builds, how its items connect — with no rejected alternative to preserve → `to-spec` **stops and redirects** you to [`/task:to-architecture`](/reference/to-architecture) instead: that's a roadmap's `## Architecture` section, not a spec. When a discussion holds both, `to-spec` pins the real decisions and names the rest in the digest.

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

**The decision test.** Every section's **Decision** must name a concrete technical artifact — a type, a format, a protocol, a boundary rule — and its **Rationale** must name at least one alternative that was rejected, with why. A section that fails the test isn't a decision: a restated roadmap item, or a component layout, is the initiative's technical shape, which belongs in a roadmap's `## Architecture` section instead. `to-spec` drops a section that fails the test and names it in the digest rather than writing it anyway.

## Output

The digest lists **every** pin in full — a spec is read downstream as a fixed anchor, so this is your one glance to catch a misstated decision:

```text
Wrote `.task/spec/event-envelope.md`
# Spec: Event envelope
Pins:
- 1. {decision, one line}
- 2. …
Left for /task:to-architecture: {technical shape dropped by the decision test, one line | omitted when none}
validate: OK — 0 errors, 0 warnings

→ Next: `/task:to-plan` for a task that leans on `.task/spec/event-envelope.md` —
  or attach it by hand with the line
  `Spec: [event-envelope](../spec/event-envelope.md)`, above the `---` in a task
  or directly under a roadmap's `# <Title>`.
```

## Does not

- Write a Plan, a step list, or implementation code — a spec pins decisions, it doesn't plan.
- Capture behavioral outcomes or single-task details — those belong in a task's `### Outcomes` / `### Acceptance criteria`.
- Capture a component map, a module layout, or how an initiative's items connect — that's a roadmap's `## Architecture` section, written by [`to-architecture`](/reference/to-architecture).
- Wire the `Spec:` header into a task or roadmap — that's the referencing skill's job.
- Write a filler spec when no real decision was settled — it stops and redirects instead.
