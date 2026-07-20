---
layout: home

hero:
  name: task-pipeline
  text: Your plan survives /clear. Nothing else does.
  tagline: Talk the task through in chat. One command freezes it into a file. Any session — this one, or a fresh one tomorrow — picks that file up and runs it, with nothing to re-explain.
  image:
    src: /logo.svg
    alt: task-pipeline
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: What is this?
      link: /guide/what-is-task-pipeline
    - theme: alt
      text: View on GitHub
      link: https://github.com/SpaiR/task-pipeline

features:
  - icon: 💾
    title: The plan survives /clear
    details: The file's path is the handle. Pick a task up in this session or a brand-new one tomorrow — there's no active-task state to lose.
  - icon: 💬
    title: Zero ceremony while you think
    details: Think out loud, explore approaches, change your mind — all in normal conversation. Only when you're ready do you fix it into a file.
  - icon: 🚀
    title: Any session can run it
    details: Tell any session `implement <path>` and it reads the file, works the plan, runs /verify and /code-review, and commits. It's just a chat instruction — you already know how.
  - icon: 🗺️
    title: Roadmaps for real initiatives
    details: Capture a multi-task initiative once, then run it hands-off — dependency-ordered waves, each item planned and implemented in its own session.
  - icon: ✅
    title: Verify and review, every time
    details: Each task file bakes in /verify (does it work end-to-end?) and /code-review (is it clean?) before commit — not left to the model's mood.
  - icon: 👻
    title: Invisible to your repo
    details: .task/ is excluded via .git/info/exclude, never .gitignore. It never shows in git status; delete it with rm -rf .task and the repo is exactly as before.
---

<div class="tp-badges">
  <a href="https://github.com/SpaiR/task-pipeline/blob/main/LICENSE" target="_blank" rel="noreferrer"><img src="https://img.shields.io/github/license/SpaiR/task-pipeline?color=8A2BE2&label=license" alt="MIT License"></a>
  <a href="https://github.com/SpaiR/task-pipeline/releases" target="_blank" rel="noreferrer"><img src="https://img.shields.io/github/v/tag/SpaiR/task-pipeline?color=8A2BE2&label=version&sort=semver" alt="Latest version"></a>
  <a href="/task-pipeline/guide/getting-started"><img src="https://img.shields.io/badge/Claude_Code-plugin-8A2BE2" alt="Claude Code plugin"></a>
</div>

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
    <div class="tp-comment"># 2. freeze the discussion into a file</div>
    <div class="tp-prompt">/task:to-plan</div>
    <div class="tp-out">  → wrote .task/task/http-retry-backoff.md</div>
    <div class="tp-out">    ## Description + ## Plan (Goal / Touches / Logic steps)</div>
    <div class="tp-sp"></div>
    <div class="tp-comment"># 3. hand the file to any session — this one, or a fresh one tomorrow</div>
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

## Small on purpose

task-pipeline is **not** an orchestration engine. No subagents, no hooks, no execution loop of its own — just one file per task and Claude Code's own `/verify` and `/code-review` doing the checking. Where the neighbors sell breadth (dozens of skills, a full SDLC in a box), this one sells the opposite: the least structure that still makes a plan outlive the session it was written in.

## Is it for you?

`task-pipeline` is for tasks longer than one session — work that needs a plan you can hand-edit, or that should leave a record. **A two-file, twenty-minute fix doesn't need this**; default Claude Code (plan mode + TodoWrite) is the better tool there.

Reach for it when the plan is worth keeping: when you want it to survive `/clear`, when a colleague (or tomorrow-you) should be able to read it, or when the work spans several tasks. Descriptions are written in your language; only the format's fixed strings (section headers, commit trailers, the Execution block) stay English. The [comparison page](/guide/comparison) lays out where it fits against default Claude Code, superpowers, and OpenSpec.

## Install in two commands

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

That's the whole setup. The first capture in a new project writes `.task/config/config.md` for you — there's no separate bootstrap step. See [Getting started](/guide/getting-started) for the first run end to end.
