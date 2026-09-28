---
name: to-task-from-chat
tags: [capture, to-task]
runs: 2
max_turns: 25
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
---
We just agreed to add a rate limiter to the public API: 100 requests a minute per
API key, returning 429 with a Retry-After header, and the limit configurable per
key later. Nothing else changes.

/task:to-task capture that — call it api-rate-limiter
