# Specs

A **spec** pins load-bearing technical decisions — a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning wouldn't survive re-derivation — into a standalone file at `.task/spec/<slug>.md`.

A spec is **orthogonal** to the depth-capture skills. `to-task` / `to-plan` / `to-roadmap` decompose *work*; [`to-spec`](/reference/to-spec) pins the *decisions* that work must honor. One spec can be cited by many tasks and roadmaps, and can be captured before, alongside, or independently of any of them.

## Why specs exist

Put a technical decision in a task's Plan and it's local to that task. Put it in a spec and it becomes a fixed anchor: every task that references it reads it first and honors it, instead of re-deriving a different choice. That's the point — to stop the same decision being re-litigated (and re-decided differently) across tasks.

A rule of thumb: if a later `to-plan` or executing session would be *free to pick a different answer*, and that would break consistency, it's spec material. A detail local to one task is not.

## Capture one

```text
/task:to-spec "the event envelope format"
# → .task/spec/event-envelope.md — numbered sections, each:
#   **Decision:** what was chosen (concrete — real symbols/shapes expected here)
#   **Rationale:** the reasoning that must survive
#   **Constrains:** what it pins for consumers, what it leaves free
```

The digest lists **every** pin in full — because a spec is read downstream as a fixed anchor, that digest is your one glance to catch a misstated decision before tasks start relying on it.

## Reference it from a task or roadmap

A spec doesn't wire itself in — the referencing skill does that. When you capture a task or roadmap that relies on a spec, it adds a `Spec:` header:

```markdown
# Migrate auth endpoints
Roadmap: api-v2-migration
Source item: #1
Spec: event-envelope
---
## Description
…
```

You can carry more than one `Spec:` line. Roadmaps reference specs the same way, and items cite specific sections as `### Spec references → event-envelope §2`.

## How the executing session uses it

When a session implements a task carrying a `Spec:` header, its `## Execution` block tells it to **read each referenced spec first and treat its decisions as fixed** before implementing. The spec is an anchor, not a plan — it says what was decided and why, not how to build it.

## Where specs live

Specs are standalone files under `.task/spec/`, independent of any roadmap. A spec is authored **only** by `to-spec` — `to-task` / `to-plan` / `to-roadmap` can reference a spec via a header, but never write or edit the spec file itself.

→ Next: [Returning to a task later](/guide/returning-later).
