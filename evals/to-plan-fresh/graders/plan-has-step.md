---
type: regex
target: {source: file, path: '**/.task/task/*.md'}
match: contains
pattern: '(?m)^### Step 1:'
---
A to-plan capture carries a `## Plan` of `### Step N:` blocks — an empty Plan
heading is a validate.sh error.
