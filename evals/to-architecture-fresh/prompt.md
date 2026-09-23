---
name: to-architecture-fresh
tags: [capture, to-architecture]
runs: 2
max_turns: 30
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
---
We're replacing the CLI's ad-hoc logging with structured logs, in three steps.
First a logger core that every command gets through a shared context object,
emitting JSON lines. Then each command migrates from console.log to that
logger, one command group at a time — the groups are `auth`, `config` and
`deploy`, one item each. Last, a single item for the `--log-level` flag and a
redaction filter that strips tokens before anything is written.

Technically: the logger core is a new `src/log/` module; the context object is
the existing `src/cli/context.ts`, which gains a `log` field. The migration
items depend on the core landing first, and the redaction filter plugs into the
core's write path, so it needs the core too. Commands never import the logger
directly — they only see it through the context.

/task:to-architecture capture the roadmap with its architecture — call it structured-logging
