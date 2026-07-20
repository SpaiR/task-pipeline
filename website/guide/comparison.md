# Comparison with alternatives

## What task-pipeline optimizes for

- **A fixed, checkable plan contract.** Steps are `### Step N` with `Goal` / `Touches` / optional `Logic` — a format a validator (`validate.sh`) checks and reports on every write, not free text. The check is informational; it gates nothing.
- **Rails, not a generator.** You work out the plan in chat and stay its author; the capture skill serializes that decision to disk and keeps the implementing session on it. It does not invent a plan from a one-line prompt. Autopilot exists (`roadmap-to-workflow` fans a roadmap out to sessions) but it is an explicit opt-in over a roadmap you already approved.
- **Attachable per-decision specs.** After a chat discussion you can pin one or several load-bearing decisions into `.task/spec/<slug>.md` and cite them from any task, plan, or roadmap via a `Spec:` header; the implementing session reads them as fixed anchors.
- **Roadmap traceability.** A roadmap fans out into a generated plan per item, the driver ticks each item's checkbox as it lands, and the git history of the artifacts shows what was done.
- **A small surface.** No orchestration engine, no subagents in the capture skills, no hooks, no MCP server, no API keys, no task database — all state is flat Markdown under `.task/`, and the heavy lifting is delegated to Claude Code's own `/verify`, `/code-review`, and Workflows. The consequences: everything is auditable as plain text, there is nothing extra to maintain, and there is zero lock-in.

Two honest limits frame all of it: the plan lives in a `/clear`-durable file rather than in chat, and a two-file, twenty-minute fix does not need any of this.

The sections below compare against five references — default Claude Code (plan mode + TodoWrite), [obra/superpowers](https://github.com/obra/superpowers), [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec), [github/spec-kit](https://github.com/github/spec-kit), and [claude-task-master](https://github.com/eyaltoledano/claude-task-master) — on one shared axis set: where the plan lives, who authors the plan, plan format, result review, moving parts & infrastructure, trace in the repo, and multi-task initiatives. Each ends with an honest "Use X if".

## vs default Claude Code

| | Default Claude Code | task-pipeline |
|---|---|---|
| **Where the plan lives** | Text in chat; lost on `/clear` | `## Plan` inside `.task/task/<slug>.md`; hand-editable, `/clear`-durable |
| **Who authors the plan** | You draft it in plan mode, but it evaporates with the context | You author it in chat; the skill only serializes what you decided |
| **Plan format** | Arbitrary text / TodoWrite items | `### Step N` with `Goal` / `Touches` / optional `Logic`, checked by `validate.sh` on write |
| **Result review** | Whatever the model decides to do | The `## Execution` block runs `/verify` (works end-to-end?) and `/code-review` (clean?) before commit |
| **Moving parts** | None beyond the chat | Flat Markdown under `.task/`; nothing else added |
| **Trace in the repo** | None | Normal code commits; the plan artifacts stay local and git-excluded |
| **Multi-task initiatives** | None | `to-roadmap` → a plan per item, or opt-in autopilot `roadmap-to-workflow` |

**Use default Claude Code** if the task is one or two files and twenty minutes. **Use task-pipeline** if the task is longer than one session, needs a plan you can hand-edit and resume, or should leave a record.

## vs superpowers

| | task-pipeline | superpowers |
|---|---|---|
| **Who authors the plan** | You, by hand; a `/task:…` skill serializes it | Auto-triggered by context; a skills library steers the agent |
| **Form** | Linear capture → any session implements | A library of situational skills |
| **Project config** | `config.md` (stack, commits, language) | Minimal |
| **Result review** | `/verify` + `/code-review`, Claude Code's own gates | Test-first TDD (red/green/refactor) plus a between-task code-review skill |
| **Moving parts** | Flat Markdown under `.task/`; Claude Code only | Skills library installed across many agents |
| **Platforms** | Claude Code only | Claude Code, Antigravity, Codex App, Codex CLI, Cursor, Factory Droid, GitHub Copilot CLI, Kimi Code, OpenCode, Pi |
| **Artifact languages** | Any, via `config.md` | English by default |

**Use task-pipeline** if you want a controlled capture-then-implement process, non-English artifacts, and reviews that run on Claude Code's own gates. **Use superpowers** if you want skills that fire automatically, a strict test-first workflow, and one library that follows you across many coding agents.

## vs OpenSpec

| | task-pipeline | OpenSpec |
|---|---|---|
| **Paradigm** | Per-task capture, chat-first | Spec-driven (a living spec set + deltas) |
| **Who authors the plan** | You in chat; captured after the discussion | You and the agent author specs up front as the source of truth |
| **Spec granularity** | Pinned per-decision `.task/spec/<slug>.md` files, cited via `Spec:` | A living whole-system spec |
| **Moving parts** | Flat Markdown under `.task/`, git-excluded | An `openspec/` directory committed to the repo |
| **Trace in the repo** | Invisible — a personal tool, no repo trace | Part of the repository, visible to the team |
| **Language** | Multilingual via `config.md` | English |

**Use task-pipeline** if you want a personal tool with no trace in the repo and specs pinned per decision. **Use OpenSpec** if you work in a team where a whole-system spec committed to the repo is the source of truth.

## vs GitHub spec-kit

| | task-pipeline | GitHub spec-kit |
|---|---|---|
| **Paradigm** | Chat-first capture; no forms, no fixed phase sequence | Form-first, spec-driven ceremony |
| **Who authors the plan** | You in chat; the skill serializes it | Driven through a command sequence you fill in and refine |
| **Workflow** | One short capture skill (`to-task` / `to-plan` / `to-roadmap`) | `/speckit.constitution` → `/speckit.specify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.implement` |
| **Moving parts** | Flat Markdown under `.task/`; nothing to install | A `specify` CLI (installed via `uv`) plus per-agent integrations |
| **Trace in the repo** | Invisible — git-excluded | A `.specify/` artifact tree committed to the repo |
| **Platforms** | Claude Code only | 30+ AI coding agents, cross-agent |

**Use task-pipeline** if you want chat-first capture with no ceremony and no repo trace. **Use spec-kit** if you want an explicit, phased spec workflow whose artifacts live in the repo and travel across many coding agents.

## vs claude-task-master

| | task-pipeline | claude-task-master |
|---|---|---|
| **Who authors the plan** | You author it in chat; the skill serializes your decisions | Generated: `task-master parse-prd` turns a PRD into tasks |
| **Where tasks live** | `## Plan` in flat Markdown under `.task/` | Its own `.taskmaster/` task store |
| **Moving parts & infrastructure** | No MCP server, no API keys, no task database | Runs as an MCP server (`npx task-master-ai`); needs a provider API key (Anthropic / OpenAI / Gemini / others), or the Claude Code CLI without keys |
| **Result review** | `/verify` + `/code-review` before commit | Tracks task status; review is not its job |
| **Editors** | Claude Code | Cursor, Windsurf, VS Code, Q Developer CLI and others, via MCP |

**Use task-pipeline** if you want to serialize your own decisions into flat Markdown with no extra infrastructure. **Use Task Master** if you want tasks generated from a PRD into a managed store and an MCP-native tracker shared across several editors.

→ Next: [Troubleshooting](/guide/troubleshooting).
