# Your first win in 5 minutes

Haven't decided to install yet? This is the whole thing, end to end, on a task small enough to finish in one sitting. Read it once and you'll know whether the two-command install is worth it.

We'll add a `--quiet` flag to a CLI — small, real, one file of code.

## 1. Install (30 seconds)

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

That's the whole setup. There's no bootstrap step — the first capture writes `.task/config/config.md` for you.

## 2. Talk it through (1 minute)

No command yet, no ceremony. Just chat, the way you already would:

```text
you:  add a --quiet flag to the CLI that silences normal output
you:  default off; when it's set, suppress info and debug logs
you:  but always still print real errors to stderr
you:  no config file, just the flag
```

You've explored it, changed your mind once, landed on the shape. That discussion is the part that normally dies on `/clear`.

## 3. Capture it (one command)

```text
/task:to-plan
```

On a fresh project this detects your language and test policy, shows one confirmation chip, writes `config.md`, then drafts the task file and prints a short digest of what it captured. You don't pre-approve a draft — the chat was the review; the file is already written when the digest appears.

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
> If `Spec:` headers are present, read each `.task/spec/<slug>.md` first and honor its
> decisions as fixed. `.task/` is pipeline-internal and invisible to the repo: never name
> `.task/` paths, spec/roadmap/task slugs, or `§` numbers in code, comments, commits, or PR
> text. Implement the Plan above (or the Description if none) with the tools in
> `.task/config/config.md` → Code Navigation / Code Editing. Run `/verify` end-to-end and
> `/code-review`, applying fixes ONLY within **Touches** (report the rest); with no `## Plan`,
> scope fixes to what you changed. Commit per `.task/config/config.md` → Commit Format. If
> `Roadmap:` + `Source item:` are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
```

The `## Execution` block is stamped verbatim on every task — it's the standing instruction any session follows, so you never re-explain the process.

## 5. Implement it

Hand the path to any session — this one, or a fresh one after a `/clear`:

```text
implement .task/task/quiet-flag.md
```

That session works the plan, runs `/verify` (does it actually work?) and `/code-review` (is it clean?), applies review fixes only within the files under **Touches**, and commits. Nothing was committed before this step — until now it was all working-tree edits.

## 6. What the commit looks like

```text
feat(cli): add --quiet flag to silence normal output

- register a boolean --quiet flag, default off
- raise the logger floor to error when set; errors still reach stderr
```

One file of code, one commit, and a `.task/quiet-flag.md` you can delete or keep as the record. That's the loop. Everything else in these docs is the same loop at larger sizes — plans, roadmaps, specs, autopilot.

→ Next: [Core concepts](/guide/core-concepts) — the handful of ideas that make the rest predictable.
