---
type: regex
target: {source: file, path: '.task/spec/event-envelope.md'}
match: contains
flags: m
pattern: '^## 1\. '
---
Numbered `## N.` decision sections are what `### Spec references … §N` citations
resolve against; validate.sh errors without them.
