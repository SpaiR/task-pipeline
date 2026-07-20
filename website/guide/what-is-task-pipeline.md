# What is task-pipeline?

If you've ever tried to cram Claude into one big "do everything in this ticket" session, you know how it ends: the model starts writing code before it understands the task, "fixes" one bug and breaks three others, and reports "done" while half the acceptance criteria are still stubs. And the plan you talked through in chat? Gone the moment you `/clear`.

`task-pipeline` keeps **the discussion and the doing apart.** Here's the whole loop, start to finish:

```text
# 1. talk it through in chat — no ceremony, change your mind freely
you: add HTTP retry with backoff to the payments client

# 2. when you're ready, one command freezes that discussion into a file
/task:to-plan
  → wrote .task/task/http-retry-backoff.md   (## Description + ## Plan)

# 3. hand the file to any session — this one, or a fresh one next week
implement .task/task/http-retry-backoff.md
  → work the plan · /verify · /code-review · commit
```

Three beats: discuss, capture, implement. The plan you talked through is now a file on disk, not chat scrollback — which is exactly why step 3 works just as well in a brand-new session tomorrow.

## The idea: serialize the context, don't orchestrate it

What you just watched has a name. `task-pipeline` is **not** an orchestration engine — it's a **context-serialization protocol**: a way to take the "what, why, and how" that lives in a chat and pin it into a fixed-format file that outlives the conversation.

That distinction is why it stays small, and it's the opposite bet from the breadth-first tools nearby: rather than dozens of skills or a full SDLC, it leans on what Claude Code already ships (dynamic Workflows, `/verify`, `/code-review`) and adds just enough structure around them:

- **one file per task** — `.task/task/<slug>.md`, carrying the discussion's decisions;
- **a stamped `## Execution` block** inside that file, which hands the rest back to the platform.

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
