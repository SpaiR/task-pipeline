# What is task-pipeline?

You float an approach in chat — "let's cache the API responses in Redis" — and Claude answers "Great idea! I'll start implementing," before the plan was ever argued, before anyone asked the one question that would have changed it. That's the failure this fixes: the model agrees and starts coding before it understands, and the ceremony around it never fits the work — a two-line fix and a month-long migration get shoved through the same process, or through none at all. The thinking you did in chat is never pinned down; it's just scrollback.

`task-pipeline` keeps **the discussion and the doing apart.** Here's the whole loop, start to finish:

```text
# 1. talk it through in chat — no ceremony, change your mind freely
you: add HTTP retry with backoff to the payments client

# 2. grill the plan first (optional) — one question at a time, writes nothing
/task:grill
  → Retry the 429s too, or only 5xx and timeouts?  [recommended: 429s too]
    decision ledger → route to /task:to-plan

# 3. when you're ready, one command freezes that discussion into a file
/task:to-plan
  → wrote .task/task/http-retry-backoff.md   (## Description + ## Plan)

# 4. hand the file to any session — this one, or a fresh one next week
implement .task/task/http-retry-backoff.md
  → work the plan · /verify · /code-review · commit
```

Four beats: discuss, grill (optional), capture, implement. The plan you talked through — and argued, if you grilled it — is now a file on disk, not chat scrollback, which is exactly why the last step works just as well in a brand-new session tomorrow.

## The idea: pin the chat to a file, don't orchestrate it

What you just watched has a name. `task-pipeline` doesn't drive your work — it takes the "what, why, and how" that lives in a chat and pins it into a fixed-format file that outlives the conversation. It's **not** an orchestration engine; the precise term is a **context-serialization protocol**.

That distinction is why it stays small, and it's the opposite bet from the breadth-first tools nearby: rather than dozens of skills or a full SDLC, it leans on what Claude Code already ships (dynamic Workflows, `/verify`, `/code-review`) and adds just enough structure around them:

- **one file per task** — `.task/task/<slug>.md`, carrying the discussion's decisions;
- **a stamped `## Execution` block** inside that file, which hands the rest back to the platform.

What gets pinned is an *argued* decision, serialized at the depth you chose — the skill you pick decides how much structure the file carries, from a bare "what and why" to a stepwise plan. (And yes, the file then outlives the `/clear`, the compaction, and tomorrow's fresh session that would otherwise erase it — table stakes, not the point.)

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

→ Next: [Your first win in 5 minutes](/guide/first-win) — the whole loop end to end, before you even install.
