---
layout: home

hero:
  name: task-pipeline
  text: Discuss in chat. Capture to a file. Implement in any session.
  tagline: A chat-first task pipeline for Claude Code. The plan lives in a file under .task/, so it survives the /clear that would otherwise erase it.
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
    details: The artifact's path is the handle. Pick a task up in this session or a brand-new one tomorrow — there's no active-task state to lose.
  - icon: 💬
    title: Zero ceremony while you think
    details: Think out loud, explore approaches, change your mind — all in normal conversation. Only when you're ready do you fix it into a file.
  - icon: 🚀
    title: Nothing new to learn to run it
    details: There is no build or ship step. Any session told to implement a task file reads it and follows its own Execution block through to a commit.
  - icon: ✅
    title: Verify and review, every time
    details: Each artifact bakes in /verify (does it work end-to-end?) and /code-review (is it clean?) before commit — not left to the model's mood.
  - icon: 👻
    title: Invisible to your repo
    details: .task/ is excluded via .git/info/exclude, never .gitignore. It never shows in git status; delete it with rm -rf .task and the repo is exactly as before.
  - icon: 🌍
    title: Your language for content
    details: Descriptions are written in your language; only parser-stable strings (headers, commit trailers, the Execution block) stay English.
---

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
    <div class="tp-out">  → follows the artifact's ## Execution block:</div>
    <div class="tp-out">    implement · /verify · /code-review · commit</div>
  </div>
</div>

## Install in two commands

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

That's the whole setup. The first capture in a new project writes `.task/config/config.md` for you — there's no separate bootstrap step. See [Getting started](/guide/getting-started) for the first run end to end.

## Is it for you?

`task-pipeline` is for tasks longer than one session — work that needs a plan you can hand-edit, or that should leave a record. **A two-file, twenty-minute fix doesn't need this**; default Claude Code (plan mode + TodoWrite) is the better tool there.

Reach for it when the plan is worth keeping: when you want it to survive `/clear`, when a colleague (or tomorrow-you) should be able to read it, or when the work spans several tasks. The [comparison page](/guide/comparison) lays out where it fits against default Claude Code, superpowers, and OpenSpec.
