---
type: regex
target: files
match: not_contains
pattern: '\.task/'
---
grill writes NOTHING, above all nothing under `.task/`. Serializing the ledger is
the capture skills' job.

Note: asserting the absence of files this way combines a documented `files`
target with `match: not_contains`; the eval reference documents no dedicated
"no such file" grader. Re-check this grader once `plugin eval` is enabled.
