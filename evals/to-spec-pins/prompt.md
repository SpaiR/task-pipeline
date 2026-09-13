---
name: to-spec-pins
tags: [capture, to-spec]
runs: 2
max_turns: 20
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep]
---
We settled the event envelope: every event carries id, type, occurred_at in UTC
RFC 3339, a monotonically increasing per-stream sequence, and an opaque payload.
Consumers must ignore unknown fields rather than reject them, and the envelope is
versioned by adding fields only — never renaming or removing one. We chose this
over a per-event-type schema because consumers have to route without parsing the
payload.

/task:to-spec write that up
