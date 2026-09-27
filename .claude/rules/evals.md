---
paths:
  - "evals/**"
---

# Editing the eval cases

- **Case shape.** One directory per case: `prompt.md` (frontmatter such as `name`, `tags`, `runs`, `max_turns`, `allowed_tools`, then the user prompt as the body) and one file per grader under `graders/`. Every case starts from a scratch project with no `.task/`.
- **List `Skill` in `allowed_tools`.** Runs are in don't-ask mode, so without it the skill call is denied and only the `tool_used: Skill` grader passes.
- **Patterns are JavaScript regexes.** An inline `(?m)` throws; put multiline in a `flags: m` key.
- **A file target takes one literal path**, relative to the run's workspace; a glob fails with "does not exist". Name the slug in the prompt, or use a `file_exists` grader, the one that accepts a glob.
- **Three of the five cases still carry these bugs**; `to-roadmap-fresh` passed under its earlier name, and `to-task-from-chat` follows the fixed format but has not been run yet. `evals/README.md` § Status has the detail.
- **Run** `claude plugin eval .`, or one case with `claude plugin eval --case '<name>*' .`. It needs the early-access feature and is not in CI: a signal, not a gate.
- **Run output is ignored.** `evals/results/` is gitignored; never commit it.
- **Adding or removing a case** updates the case table in `evals/README.md`, and its "Still missing a case" line when a skill gains its first case.
