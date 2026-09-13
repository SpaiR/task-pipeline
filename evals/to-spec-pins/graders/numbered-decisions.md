---
type: regex
target: {source: file, path: '**/.task/spec/*.md'}
match: contains
pattern: '(?m)^## 1\. '
---
Numbered `## N.` decision sections are what `### Spec references … §N` citations
resolve against; validate.sh errors without them.
