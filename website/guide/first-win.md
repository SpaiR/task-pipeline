# Your first win in 5 minutes

Haven't decided to install yet? This is the whole thing, end to end, on a task small enough to finish in one sitting. Read it once and you'll know whether the two-command install is worth it.

We'll add a `--quiet` flag to a CLI — small, real, one file of code.

## 1. Install (30 seconds)

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

That's the whole setup — nothing to configure by hand: the first capture writes `.task/CLAUDE.md` for you.

## 2. Talk it through (1 minute)

No command yet, no ceremony. Just chat, the way you already would:

```text
you:  add a --quiet flag to the CLI that silences normal output
you:  default off; when it's set, suppress info and debug logs
you:  but always still print real errors to stderr
you:  no config file, just the flag
```

You've explored it, changed your mind once, landed on the shape. That discussion is the part that normally dies on `/clear`.

::: tip Optional: grill it first
When a plan has real forks — this flag's default, that error's fallback — run [`/task:grill`](/guide/grill) before you capture. It interrogates the plan one question at a time, keeps a decision ledger, and ends with a pre-mortem, then routes you to the right capture skill. It writes nothing and needs no config, so it works even as your very first command. Our `--quiet` flag is small enough to skip it; reach for it when the decision has more at stake.
:::

## 3. Capture it (one command)

```text
/task:to-plan
```

On a fresh project this detects your language and test policy, writes `.task/CLAUDE.md`, reports what it wrote, then drafts the task file and prints a short digest of what it captured. You don't pre-approve a draft — the chat was the review; the file is already written when the digest appears.

## 4. The file that lands

`.task/task/quiet-flag.md` — plain Markdown you can open and hand-edit:

```markdown
# Add a --quiet flag to the CLI
---
## Description

### Problem
The CLI always prints info and debug output; there's no way to run it silently
in a script and see only real failures.

### Outcome
A `--quiet` flag, off by default. When set, info and debug logs are suppressed,
but genuine errors still print to stderr. No config file — just the flag.

## Plan

### Step 1: Add the flag and gate log output on it
**Goal:** `mycli --quiet` runs with info/debug silenced while errors still reach
stderr; without the flag, output is unchanged.
**Touches:** `src/cli.ts` `src/logger.ts`
**Logic:** Register `--quiet` (boolean, default false). Thread it into the
logger as a min-level: quiet raises the floor to `error`, so info/debug are
dropped but `error` still writes to stderr.

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

That one-line `## Execution` pointer is stamped on every task. The instructions themselves live in `.task/CLAUDE.md`, in a single copy — so you never re-explain the process, and editing them there changes how *every* task is executed, including ones you captured earlier.

## 5. Implement it

Hand the path to any session — this one, or a fresh one after a `/clear`. `implement` is an ordinary chat message, **not** a slash command — type it as you'd type any instruction:

```text
implement .task/task/quiet-flag.md
```

That session works the plan and commits — then spawns `task:code-reviewer` on the diff. The reviewer reads the commit, proves each defect it suspects before touching anything, fixes the confirmed ones within the files under **Touches**, runs your build and tests, and amends that same commit. Nothing was committed before this step — until now it was all working-tree edits.

## 6. What the commit looks like

```text
feat(cli): add --quiet flag to silence normal output

- register a boolean --quiet flag, default off
- raise the logger floor to error when set; errors still reach stderr
```

One file of code, one commit, and a `.task/quiet-flag.md` you can delete or keep as the record. That's the loop. Everything else in these docs is the same loop at larger sizes — plans, roadmaps, specs, autopilot.

→ Next: [Getting started](/guide/getting-started) — install it and run the first capture in your own project.
