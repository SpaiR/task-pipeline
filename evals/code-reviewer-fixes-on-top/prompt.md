---
tags: [agent, code-reviewer]
runs: 2
timeout_seconds: 900
allowed_tools: [Agent, Read, Glob, Grep, Bash, Edit, Write]
---
The task `.task/task/add-clamp.md` has been implemented. Spawn the `task:code-reviewer` agent on it (pass the file's absolute path), then reply with the last line of its report, verbatim. Do not run commands or edit files yourself.
