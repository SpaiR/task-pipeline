---
layout: home
title: Plan files for Claude Code

hero:
  name: task-pipeline
  text: Freeze a Claude Code chat into one Markdown plan file any session can implement.
  tagline: Talk it through, grill the plan, capture it at the depth you pick. Any later session reads the file and runs it. A free plugin — no server, no hooks, no MCP.
  image:
    src: /logo.svg
    alt: task-pipeline
  actions:
    - theme: brand
      text: See it work in 5 min
      link: /guide/first-win
    - theme: alt
      text: What is this?
      link: /guide/what-is-task-pipeline
    - theme: alt
      text: How it compares
      link: /guide/comparison

features:
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7"/><path d="M7 3v4a1 1 0 0 0 1 1h7"/></svg>'
    title: The plan survives /clear
    details: The file's path is the handle. Pick a task up in this session or a brand-new one tomorrow — there's no active-task state to lose.
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>'
    title: The plan gets grilled first
    details: An optional grill step interrogates the plan one question at a time and ends on a pre-mortem. It's allowed to disagree with you.
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/></svg>'
    title: You pick the depth, not a flag
    details: A quick fix and a month-long migration don't deserve the same paperwork. Capture is the skill you reach for — to-task, to-plan, to-roadmap, to-spec — not a template to fill out.
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/></svg>'
    title: Any session can run it
    details: Tell any session `implement &lt;path&gt;`. It reads the file, works the plan, runs your project's own checks, and commits. Just a chat instruction — you already know how.
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>'
    title: Leaves no trace in your repo
    details: The pipeline's files live under `.task/`, git-excluded. Delete the folder and your repo is exactly as it was — no config committed, nothing pushed, zero lock-in.
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/></svg>'
    title: Roadmaps for real initiatives
    details: Capture a multi-task initiative once, then run it hands-off — dependency-ordered waves, each item planned and implemented in its own session.
---

<div class="tp-proof">MIT-licensed · built by <a href="https://github.com/SpaiR">SpaiR</a> · a Claude Code plugin</div>

## A plan file is only as good as the argument that produced it

<div class="tp-terminal">
  <div class="tp-terminal__bar">
    <span class="tp-terminal__dot"></span>
    <span class="tp-terminal__dot"></span>
    <span class="tp-terminal__dot"></span>
    <span class="tp-terminal__title">claude-code</span>
  </div>
  <div class="tp-terminal__body">
    <div class="tp-comment"># 1. talk the task through in chat — an HTTP retry system with backoff…</div>
    <div class="tp-sp"></div>
    <div class="tp-comment"># 2. grill the plan first (optional) — one question at a time</div>
    <div class="tp-prompt">/task:grill</div>
    <div class="tp-out">  → Retry the 429s too, or only 5xx and timeouts?  [recommended: 429s too]</div>
    <div class="tp-out">    decision ledger → route to /task:to-plan</div>
    <div class="tp-sp"></div>
    <div class="tp-comment"># 3. freeze the discussion into a file</div>
    <div class="tp-prompt">/task:to-plan</div>
    <div class="tp-out">  → wrote .task/task/http-retry-backoff.md</div>
    <div class="tp-out">    ## Description + ## Plan (Goal / Touches / Logic steps)</div>
    <div class="tp-sp"></div>
    <div class="tp-comment"># 4. hand the file to any session — this one, or a fresh one tomorrow</div>
    <div class="tp-prompt">implement .task/task/http-retry-backoff.md</div>
    <div class="tp-out">  → follows the file's ## Execution block — the steps that</div>
    <div class="tp-out">    tell any session what to do next:</div>
    <div class="tp-out">    implement · /verify · /code-review · commit</div>
  </div>
</div>

::: details Here's the actual file it writes
This is an example of what `/task:to-plan` produces for the run above — a plain Markdown file under `.task/`, not a screenshot. Header, `---`, `## Description`, a step-by-step `## Plan`, and the stamped `## Execution` block that tells any session what to do next.

```markdown
# HTTP retry with backoff
---
## Description

### Problem
Outbound calls to the payments API fail intermittently under load, and a single
timeout currently drops the whole request.

### Outcome
Transient failures (timeouts, 5xx, 429) retry with exponential backoff and
jitter, capped at 5 attempts. A request that exhausts every attempt lands in a
dead-letter queue for later inspection instead of being silently lost.

## Plan

### Step 1: Wrap the payments client in a retry policy
**Goal:** Every outbound payments call retries transient failures with
exponential backoff plus jitter, giving up after 5 attempts.
**Touches:** `src/payments/client.ts` `src/payments/retry.ts`
**Logic:** Classify the error — timeout / 5xx / 429 are retryable, other 4xx
fail fast. Sleep `base * 2 ** attempt` plus random jitter between tries; surface
the last error once the cap is hit.

### Step 2: Route exhausted retries to a dead-letter queue
**Goal:** A call that fails all 5 attempts is written to the DLQ with its payload
and last error, instead of surfacing as an unhandled failure.
**Touches:** `src/payments/client.ts` `src/payments/dead-letter.ts`
**Logic:** After the retry cap, enqueue `{ request, lastError, attempts }` and
return a typed `RetriesExhausted` result the caller can branch on.

## Execution
> If `Spec:` headers are present, read each `.task/spec/<slug>.md` first and honor its
> decisions as fixed. `.task/` is pipeline-internal and invisible to the repo: never name
> `.task/` paths, spec/roadmap/task slugs, or `§` numbers in code, comments, commits, or PR
> text. Implement the Plan above (or the Description if none) with the tools in
> `.task/config/config.md` → Code Navigation / Code Editing. Run `/verify` end-to-end and
> `/code-review`, applying fixes ONLY within **Touches** (report the rest); with no `## Plan`,
> scope fixes to what you changed. Commit per `.task/config/config.md` → Commit Format. If
> `Roadmap:` + `Source item:` are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
```
:::

## Install in two commands

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

That's the whole setup. The first capture in a new project writes `.task/config/config.md` for you — there's no separate bootstrap step. See [Getting started](/guide/getting-started) for the first run end to end.

## Small on purpose

task-pipeline is **not** an orchestration engine. No subagents, no hooks, no execution loop of its own — just one file per task, and your project's own checks running before commit. The neighbors sell breadth — dozens of skills, a full SDLC in a box. This one sells the opposite: the least structure that still makes a plan outlive its session.

## Is it for you?

`task-pipeline` is for tasks longer than one session — work that needs a plan you can hand-edit, or that should leave a record. **A two-file, twenty-minute fix doesn't need this**; default Claude Code (plan mode + TodoWrite) is the better tool there.

Reach for it when the plan deserves an argument and a record: real forks to interrogate, decisions a colleague — or tomorrow-you — will reread, work that spans several tasks. And when it should outlast a `/clear`. Descriptions are written in your language; only the format's fixed strings (section headers, commit trailers, the Execution block) stay English. The [comparison page](/guide/comparison) lays out where it fits against six references — default Claude Code, superpowers, Matt Pocock's skills, OpenSpec, spec-kit, and claude-task-master.

If this is the shape of tool you've wanted, [star it on GitHub](https://github.com/SpaiR/task-pipeline) — it's how you'll find it again.
