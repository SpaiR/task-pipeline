# Comparison with alternatives

Three references worth comparing against: default Claude Code (plan mode + TodoWrite), [obra/superpowers](https://github.com/obra/superpowers), and [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec).

Two contrasts matter most: **where the plan lives**, and **when a task is too small to bother**. `task-pipeline` keeps the plan in a `/clear`-durable file, and it's explicitly not for a two-file, twenty-minute fix. The full breakdowns follow.

## vs default Claude Code

| | Default Claude Code | task-pipeline |
|---|---|---|
| **Where the plan lives** | Text in chat; lost on `/clear` | `## Plan` inside `.task/task/<slug>.md`; hand-editable, readable by a colleague |
| **Plan-step contract** | Arbitrary text | `### Step N` with three layers: Goal / Touches / optional Logic |
| **Result review** | Only whatever the model decides | The `## Execution` block runs `/verify` (does it work end-to-end?) and `/code-review` (is it clean?) before commit |
| **Interrupt / resume** | Lost on `/clear` | The task file is on disk; pick it up in any session with `implement .task/task/<slug>.md` |
| **Multi-task initiatives** | None | `to-roadmap` → `to-plan`/`to-task` per item, or autopilot `roadmap-to-workflow` |
| **Record of what shipped** | None | git history of `.task/task/<slug>.md` and the diff it produced |

**Use default Claude Code** if the task is one or two files and twenty minutes. **Use task-pipeline** if the task is longer than one session, needs a plan you can hand-edit, or should leave a record.

## vs superpowers

| | task-pipeline | superpowers |
|---|---|---|
| Initiation | By hand: `/task:…` | Auto-triggers by context |
| Form | Linear capture → hand off to any session | A library of situational skills |
| Project config | `config.md` (stack, commits, language) | Minimal |
| Result review | `/verify` + `/code-review` | Iron Law TDD |
| Artifact languages | Any, via `config.md` | English by default |
| Platforms | Claude Code only | Claude Code, Codex, Cursor, Gemini CLI, Copilot CLI |

**Use task-pipeline** if you want a controlled capture-then-implement process, non-English languages, and no hand-rolled audit machinery.

## vs OpenSpec

| | task-pipeline | OpenSpec |
|---|---|---|
| Paradigm | Per-task capture, chat-first | Spec-driven (living `specs/` + deltas) |
| Storage | `.task/` locally, not in the repo | `openspec/` committed to the repo |
| Team visibility | Invisible (a personal tool) | Part of the repository |
| Language | Multilingual via `config.md` | English |

**Use task-pipeline** if you want a personal tool with no trace in the repo. **Use OpenSpec** if you work in a team where the spec is the source of truth.

→ Next: [Troubleshooting](/guide/troubleshooting).
