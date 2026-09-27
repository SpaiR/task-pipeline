---
type: regex
target: {source: file, path: '.task/roadmap/structured-logging.md'}
match: not_contains
flags: m
pattern: '^\*\*Dependencies:\*\*\s*—\s*,'
---
A technical-ordering line may add a dependency to an item that had none; the
no-dependency em dash must be replaced, never appended to — `—, 1` is an
unparsable value that stops roadmap-to-workflow.
