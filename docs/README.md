# Documentation

Maintainer-facing docs for the task-pipeline plugin.

| File | Topic |
|------|-------|
| [contract.md](contract.md) | **The single source of truth** — the flat `.task/` layout, `AI_DIR` root resolution, the `task.md` (incl. canonical `## Execution` block), roadmap-file, and spec-file formats, the repeatable `Spec:` header, slug-as-identifier rules, producer/consumer table, the `skills/_lib/` keep/rewrite/delete inventory, the handoff-footer convention, the marker inventory, and the interaction conventions. |
| [usage.md](usage.md) | Extended usage scenarios beyond the single-task flow — a multi-task initiative via a roadmap, the `roadmap-to-workflow` autopilot, mixing hand-picked items with autopilot, and returning to a task later. |
| [troubleshooting.md](troubleshooting.md) | First-run problems (commands not appearing, setup) and v3 edge cases — roadmap, worktree, and hook-free / pointer-free pipeline gotchas. |

Read `contract.md` before any non-trivial edit to a skill or a `skills/_lib/` helper. User-facing usage lives in the repo `README.md`.
