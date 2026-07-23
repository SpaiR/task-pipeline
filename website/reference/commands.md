# Commands overview

Six user-invocable skills, plus one internal utility. Depth of capture is the skill you pick — there are no flags anywhere.

| Command | In brief |
|---|---|
| [`/task:grill`](/reference/grill) | Pre-capture interrogation: stress-tests a plan one question at a time, keeps a decision-plus-rationale ledger, ends with a pre-mortem, routes to the right capture skill. Writes nothing. Needs no config. |
| [`/task:to-task`](/reference/to-task) | Fixes the chat (or a roadmap item) into `.task/task/<slug>.md` — Description only, no Plan. The lightest capture. |
| [`/task:to-plan`](/reference/to-plan) | Fixes the chat (or a roadmap item) into `.task/task/<slug>.md` with Description **+** Plan (and Tests when policy calls for it). The deepest one-task capture. |
| [`/task:to-roadmap`](/reference/to-roadmap) | Fixes a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items. |
| [`/task:to-spec`](/reference/to-spec) | Fixes load-bearing technical decisions into a standalone `.task/spec/<slug>.md`, cited by tasks/roadmaps via a `Spec:` header. |
| [`/task:roadmap-to-workflow`](/reference/roadmap-to-workflow) | Autopilot over an approved roadmap: authors and invokes a dynamic Workflow that runs unchecked items in dependency-ordered waves — parallel planning, serialized implementation. |
| [`validate`](/reference/validate) *(utility)* | Optional format checker for `.task/` artifacts. Not a slash command, not a gate. |

## The next-step footer

Every capture skill ends its output with a copy-pasteable `→ Next: …` line naming the artifact path explicitly, e.g. `implement .task/task/<slug>.md`. The path *is* the handle, so there's nothing else to remember.

## One file per task; a roadmap is a backlog of items

Each capture produces exactly one `.task/task/<slug>.md`, where `<slug>` is both the filename and the identity — no task-id, no umbrella folder. A **roadmap** (`.task/roadmap/<slug>.md`) groups several such items into one initiative. A **spec** (`.task/spec/<slug>.md`) is a standalone file of technical decisions that tasks and roadmaps point at with a `Spec:` header. See [.task/ layout](/reference/task-layout) for the full shapes.
