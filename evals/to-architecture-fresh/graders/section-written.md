---
type: regex
target: {source: file, path: '.task/roadmap/structured-logging.md'}
match: contains
flags: m
pattern: '^## Architecture\s*$[\s\S]*^### Components\s*$'
---
With no roadmap yet, fresh mode writes the roadmap and then its `## Architecture`
section, which must carry the required `### Components` sub-heading. The prompt
names the slug, since a file target takes one literal path, not a glob.
