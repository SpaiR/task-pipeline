---
type: regex
target: {source: file, path: '.task/roadmap/clamp.md'}
match: contains
flags: m
pattern: '^### - \[ \] 1\. '
---
An item ticked over uncommitted work would claim work no commit holds.
