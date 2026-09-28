---
type: regex
target: {source: file, path: '.git/logs/HEAD'}
match: contains
pattern: '\tcommit: fix'
---
The planted defect is fixed in one commit on top of the implementation.
