---
type: regex
target: {source: file, path: '.task/task/api-rate-limiter.md'}
match: contains
flags: m
pattern: '^### Step 1:'
---
Every to-task capture carries a `## Plan` of `### Step N:` blocks — an empty Plan
heading is a validate.sh error, and a Description with no Plan is not a capture.
