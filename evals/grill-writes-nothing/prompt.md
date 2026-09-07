---
name: grill-writes-nothing
tags: [pre-capture, grill]
runs: 2
max_turns: 12
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep]
---
I want to cache every database read in a global in-memory map, keyed by query
string, with no expiry. It will make the app much faster.

/task:grill
