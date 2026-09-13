---
type: regex
target: {source: file, path: '**/.task/task/*.md'}
match: contains
pattern: '\*\*Touches:\*\*\s*`'
---
Every step names the real paths it changes; a Touches list of prose is not usable
as the reviewer's fix scope.
