# CLAUDE.md

Guidance for Claude Code when editing **this repository**. User-facing documentation lives in `README.md`; the full artifact contract lives in [`docs/contract.md`](docs/contract.md).

## Quick orient

A collection of user-invocable Claude Code skills implementing a chat-first "context serialization protocol", not an orchestration engine: discuss freely in chat, then fix the discussion into a fixed-format Markdown artifact under `.task/` with one short skill. Depth of capture is the skill name, never a flag. Skills in `skills/<name>/SKILL.md`; no phase companions, no subagents, no lock protocol, no hook gate. No build/test/lint. Work here is editing markdown (occasional bash) and reasoning about pipeline semantics.

```
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-plan | to-roadmap        ← capture depth is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
```

`grill` sits at the "discuss freely" stage: it interrogates a plan/decision one question at a time, keeps a decision-plus-rationale ledger, ends with a pre-mortem, and routes to the right capture skill — it writes no artifacts and touches nothing under `.task/`. `to-task` captures `## Description` only into `.task/task/<slug>.md`; `to-plan` adds `## Plan` (Goal/Touches/Logic steps); `to-roadmap` captures a multi-task initiative into `.task/roadmap/<slug>.md`; `to-spec` captures load-bearing technical decisions into a standalone `.task/spec/<slug>.md`, referenced by tasks/roadmaps via a `Spec:` header and read by the executing session as a fixed anchor. There is **no execution skill** — every artifact carries a stamped `## Execution` block, and an ordinary session told `implement .task/task/<slug>.md` follows it: implement the plan, run `/verify` + `/code-review`, apply review fixes only within **Touches**, commit per `config.md` → Commit Format, tick the roadmap item if `Roadmap:`/`Source item:` are present. `roadmap-to-workflow` is the one launcher: authors + invokes a dynamic Workflow over a roadmap's unchecked items, dependency-ordered waves, opus-plans/sonnet-implements per item by default.

Full artifact shapes, producer/consumer table, and bash-layer contract: [docs/contract.md](docs/contract.md). Read it before any non-trivial edit to a skill or bash helper.

## Invariants — don't break these when editing skills

- `.task/` is **flat**: `.task/config/config.md`, `.task/task/<slug>.md` (one file per task), `.task/roadmap/<slug>.md`, `.task/spec/<slug>.md` (one file per spec). No `.task/workspace/`, no `.task/log/`, no `<task-id>/` subfolders, no `.spec.md` roadmap sidecar (specs are standalone under `.task/spec/`), no archive — git history is the record.
- **Slug is the identity.** Kebab-case English, derived from the title; it is the filename, not a header. No task-id, no `[TASK-ID]` bracket, no umbrella grouping.
- Config-gate has three categories: `to-task` / `to-plan` / `to-roadmap` / `to-spec` auto-run setup inline in a fresh project (writing `config.md`); every other skill checks `.task/config/config.md` and hard-stops if absent; `grill` is the exception that neither checks nor creates `config.md` — it touches nothing under `.task/` and can run before any capture exists (bash-layer precondition, not relaxed by prompt edits).
- `task.md` is the single contract: `# <Title>` (plain, no bracket), optional `Roadmap:` / `Source item: #N` / repeatable `Spec: <slug>` headers, `---`, `## Description`, optional `## Plan` (`### Step N:` blocks with Goal/Touches/Logic), optional `## Tests` (`### Test N:`), and a stamped `## Execution` block (English, parser-stable) that is the mechanism replacing the deleted `build`/`ship` skills. `Roadmap:` + `Source item:` are load-bearing for the auto-mark step, `Spec:` for the executing session's fixed-anchor read — keep them ASCII, above the `---`. Specs themselves live at `.task/spec/<slug>.md`, authored only by `to-spec`.
- Pipeline is invisible to the project — no tracked edits outside `.task/`, excluded via `.git/info/exclude` (pattern `.task`). Markers are exactly `git config task.root` + the exclude entry — **nothing else**: no active-task pointer, no `TASK_ID_OVERRIDE`, no per-worktree pointer file.
- `resolve-ws.sh` is a pure `.task/`-root finder (exports `AI_DIR`): `task.root` git config → ancestor walk for `.task/config/config.md` → `dirname(git-common-dir)/.task` → `./.task`. No workspace resolution, no pointer read/write/self-heal logic anywhere.
- Orchestration, verification, review, and commits are delegated to the platform (`/verify`, `/code-review`, dynamic Workflows) — never hand-rolled inside a skill.
- Every skill carries `disable-model-invocation: true` + `user-invocable: true` (exception: `validate`, `user-invocable: false`). Artifacts and user dialog follow `config.md` → Language; parser-stable strings (headers, commit trailers, the `## Execution` block) stay English.
- Interaction conventions, all three: (a) every user-facing output ends `→ Next: <command or artifact path>` or `→ Done.`; (b) every content-confirmation is posed via `AskUserQuestion` with **Accept** / **Edit** / **Decline** chips — Edit triggers a focused follow-up, then re-shows for confirmation; (c) every 2–4 option path fork uses `AskUserQuestion` chips. All flag-free — no `--plan`, `--from`, `--phase`, `--refine` anywhere user-facing.
- `roadmap-to-workflow`'s auto-mark (ticking a roadmap item's checkbox) is done by the **driver** after an item's agent returns OK, never inside the per-item agent — avoids racing parallel writes to the roadmap file.
- Commit/PR/release rules: see below and [`CONTRIBUTING.md`](CONTRIBUTING.md) — read it before committing anything in this repo.

## Editing protocol — quick rules

- Treat each `SKILL.md` as a prompt contract — output templates, section headers, step numbering are load-bearing.
- Changing the `task.md` template/separator coordinates `validate/validate.sh` and the `to-task`/`to-plan` template.
- Prefer Markdown + **bold** over XML.
- Every skill change updates `README.md` and `docs/contract.md` in the same commit.
- **Never** update `CHANGELOG.md` autonomously. Edit it only when the user explicitly requests it.
- **Never change `.claude-plugin/plugin.json`'s `version` without explicit user confirmation.** Same rule for cutting `## [Unreleased]` into a numbered release.

## Commit format

Source of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md). Summary:

- Header: `<type>(<scope>): <short summary>` — under 72 chars, imperative, lowercase first letter, no trailing period.
- Types: `feat | fix | refactor | perf | docs | test | chore | revert`. **Do not invent types.**
- Scopes (optional but strongly preferred): skill names (`grill`, `to-task`, `to-plan`, `to-roadmap`, `to-spec`, `roadmap-to-workflow`, `validate`), or cross-cutting keys (`skills`, `lib`, `hooks`, `plugin`, `github`, `readme`, `claudemd`, `changelog`, `contributing`, `contract`). **Do not invent scopes.**
- Body: mandatory for all non-trivial commits; explain **why**, not what; 2–5 bullet list, imperative tense.
- Footer: `BREAKING CHANGE:` when header carries `!`; `Fixes #N` / `Closes #N` for issues/PRs.
- AI attribution: every Claude-assisted commit must carry `Co-Authored-By: Claude <noreply@anthropic.com>` as the last footer line.

## Pull requests

Source of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md#pull-request-title). When opening a PR (`gh pr create`), follow it — do NOT default to `gh`'s commit-derived title/body:

- **Title**: short descriptive prose for the whole change, sentence case, no `type(scope):` prefix, under ~72 chars.
- **Body**: use `.github/pull_request_template.md`. Only `## What` is mandatory; fill the rest when it applies, delete what doesn't. End with `Closes #N` / `Fixes #N` when relevant, then the `🤖 Generated with [Claude Code]` attribution line.
- **Label**: apply exactly one type label mapped from the commit type (`feat`→`enhancement`, `fix`→`fix`, `docs`→`documentation`, `refactor`→`refactor`, `perf`→`performance`, `test`/`chore`→`chore`); add `breaking-change` on top when relevant. **Do not invent labels.**

## Release procedure

Triggered only when the user explicitly requests a release. Execute in this exact order — do not reorder or merge steps:

1. **Release commit** — rename `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] — YYYY-MM-DD` (do not leave a fresh empty `## [Unreleased]` above it; for breaking changes, add a `## Migration` block to the entry) and bump `"version"` in `.claude-plugin/plugin.json` to match, in one commit: `chore(changelog): release vX.Y.Z`.
2. **Version sentinel commit** — `git commit --allow-empty -m "vX.Y.Z"`.
3. **Tag** — `git tag vX.Y.Z` on the sentinel commit. Then confirm with the user before running `git push origin main && git push origin vX.Y.Z` (the tag alone doesn't push the commits).
