---
type: regex
target: {source: file, path: '.git/logs/HEAD'}
match: 'count:1'
pattern: '\tcommit: '
---
The only such entry is the fixture's commit; any commit by the reviewer would make two.
