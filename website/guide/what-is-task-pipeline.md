# What is task-pipeline?

If you've ever tried to cram Claude into one big "do everything in this ticket" session, you know how it ends: the model starts writing code before it understands the task, "fixes" one bug and breaks three others, and reports "done" while half the acceptance criteria are still stubs. And the plan you talked through in chat? Gone the moment you `/clear`.

`task-pipeline` keeps **the discussion and the doing apart.**

- Discuss the task freely in chat — think out loud, explore approaches, change your mind.
- When you're ready, one command freezes that discussion into a Markdown file under `.task/`.
- Any session — this one, or a fresh one tomorrow — implements that file the same way: work the plan, run `/verify`, run `/code-review`, commit.

```text
discuss in chat
  → capture to a file
  → any session implements it
```

## The idea: serialize the context, don't orchestrate it

`task-pipeline` is **not** an orchestration engine. It's a **context-serialization protocol**: a way to take the "what, why, and how" that lives in a chat and pin it into a fixed-format file that outlives the conversation.

That distinction is why it's small. It doesn't try to replace Claude Code's execution loop — it leans on what Claude Code already ships (dynamic Workflows, `/verify`, `/code-review`) and adds just enough structure around them:

- **one artifact per task** — `.task/task/<slug>.md`, carrying the discussion's decisions;
- **a stamped `## Execution` block** inside that artifact, which hands the rest back to the platform.

The plan lives in the file, not in chat — so it survives the `/clear`, the compaction, and the fresh session tomorrow that would otherwise erase it.

## The shape of the pipeline

```text
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-plan | to-roadmap        ← capture depth is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
```

A few things to notice, because they're the load-bearing design choices:

- **Depth of capture is the skill you pick, not a flag.** [`to-task`](/reference/to-task) records just the "what and why". [`to-plan`](/reference/to-plan) adds a step-by-step Plan. [`to-roadmap`](/reference/to-roadmap) captures a whole multi-task initiative. There is no `--plan` or `--deep` switch anywhere.
- **There is no execution skill.** You don't run a `build` or `ship` command. Every artifact carries its own `## Execution` block, and any ordinary session told `implement .task/task/<slug>.md` follows it.
- **[`grill`](/reference/grill) sits before capture.** It interrogates a plan one question at a time and hands off to the right capture skill — it writes nothing itself.
- **[`to-spec`](/reference/to-spec) is orthogonal.** It pins load-bearing technical decisions into their own file, which tasks and roadmaps point at with a `Spec:` header.

## When to use it (and when not to)

It's for tasks **longer than one session** — work that needs a plan you can hand-edit, or that should leave a record. A two-file, twenty-minute fix doesn't need this; default Claude Code is the better tool there.

The [comparison page](/guide/comparison) walks through exactly where it fits against the alternatives.

→ Next: [Getting started](/guide/getting-started) — install it and run the first capture end to end.
