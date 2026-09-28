---
type: regex
target: {source: file, path: '.git/logs/HEAD'}
match: not_contains
pattern: '\t(commit \(amend\)|rebase)'
---
The reviewer commits on top and never rewrites the history it reviewed.
