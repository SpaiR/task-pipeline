---
name: to-plan-fresh
tags: [capture, to-plan]
runs: 2
max_turns: 20
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep]
---
The CLI's config loader reads every key with process.env directly, scattered over
a dozen files, so a missing variable surfaces as a runtime undefined rather than
a startup error. We want one typed config module, validated once at startup, with
the rest of the code reading from it.

/task:to-plan
