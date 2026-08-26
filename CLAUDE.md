# CLAUDE.md

Guidance for Claude Code when editing **this repository**. User-facing documentation lives in `README.md`; the full artifact contract lives in [`docs/contract.md`](docs/contract.md).

## Quick orient

A collection of user-invocable Claude Code skills implementing a chat-first "context serialization protocol", not an orchestration engine: discuss freely in chat, then fix the discussion into a fixed-format Markdown artifact under `.task/` with one short skill. Depth of capture is the skill name, never a flag. Skills in `skills/<name>/SKILL.md`; the plugin ships exactly one agent, `agents/code-reviewer.md` (the review pass — see the invariants below), and no phase companions, no lock protocol, no hook gate. No build/test/lint. Work here is editing markdown (occasional bash) and reasoning about pipeline semantics.

```
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-plan | to-roadmap        ← capture depth is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
  ↓                       ↓
task:code-reviewer                    ← the plugin's own review pass, spawned by both:
                                        prove → fix within Touches → Build and Tests → amend
```

`grill` sits at the "discuss freely" stage: it interrogates a plan/decision one question at a time, keeps a decision-plus-rationale ledger, ends with a pre-mortem, and routes to the right capture skill — it writes no artifacts and touches nothing under `.task/`. `to-task` captures `## Description` only into `.task/task/<slug>.md`; `to-plan` adds `## Plan` (Goal/Touches/Logic steps); `to-roadmap` captures a multi-task initiative into `.task/roadmap/<slug>.md`; `to-spec` captures load-bearing technical decisions into a standalone `.task/spec/<slug>.md`, referenced by tasks/roadmaps via a `Spec:` header and read by the executing session as a fixed anchor. There is **no execution skill** — every artifact carries a stamped one-line `## Execution` pointer to `.task/CLAUDE.md` → `## Executing a task`, and an ordinary session told `implement .task/task/<slug>.md` follows it: implement the plan, commit per `.task/CLAUDE.md` → Commit Format, spawn `task:code-reviewer` on the resulting diff (it proves each finding, fixes what it confirms within **Touches**, runs `.task/CLAUDE.md` → Build and Tests, and amends the commit), tick the roadmap item if `Roadmap:`/`Source item:` are present. `roadmap-to-workflow` is the one launcher: authors + invokes a dynamic Workflow over a roadmap's unchecked items, dependency-ordered waves, opus-plans/sonnet-implements/`task:code-reviewer`-reviews per item by default.

Full artifact shapes, producer/consumer table, and bash-layer contract: [docs/contract.md](docs/contract.md). Read it before any non-trivial edit to a skill or bash helper.

## Invariants — don't break these when editing skills

- `.task/` is **flat**: `.task/CLAUDE.md`, `.task/task/<slug>.md` (one file per task), `.task/roadmap/<slug>.md`, `.task/spec/<slug>.md` (one file per spec). No `.task/workspace/`, no `.task/log/`, no `<task-id>/` subfolders, no `.spec.md` roadmap sidecar (specs are standalone under `.task/spec/`), no archive — git history is the record.
- `.task/CLAUDE.md` is a **nested `CLAUDE.md`, not a bespoke config format**: the platform auto-loads it into any session that reads a file under `.task/`, which is how the executing session and `task:code-reviewer` get Language / Testing Policy / Build and Tests / Commit Format / `## Executing a task` without being told to. Two limits are load-bearing — the auto-load fires only for file-read tools (never for `cat`/`sed`), and a nested `CLAUDE.md` is **not** re-injected after `/compact`. Hence the explicit `## Execution` pointer in every artifact, and the reviewer's explicit read in its phase 0. **Written once by setup, then user-owned** — never rewritten, never section-repaired; to regenerate it the user deletes it and re-runs any capture.
- **Slug is the identity.** Kebab-case English, derived from the title; it is the filename, not a header. No task-id, no `[TASK-ID]` bracket, no umbrella grouping.
- Setup-gate has three categories: `to-task` / `to-plan` / `to-roadmap` / `to-spec` auto-run setup inline in a fresh project (writing `.task/CLAUDE.md`, no confirmation chip); every other skill checks `.task/CLAUDE.md` and hard-stops if absent; `grill` is the exception that neither checks nor creates it — it touches nothing under `.task/` and can run before any capture exists (bash-layer precondition, not relaxed by prompt edits).
- `task.md` is the single contract: `# <Title>` (plain, no bracket), optional `Roadmap:` / `Source item: #N` / repeatable `Spec:` headers, `---`, `## Description`, optional `## Plan` (`### Step N:` blocks with Goal/Touches/Logic), optional `## Tests` (`### Test N:`), and a stamped one-line `## Execution` pointer (English, parser-stable) to `.task/CLAUDE.md` → `## Executing a task`, which carries execution — implement → commit → review — without a separate skill. `Roadmap:` + `Source item:` are load-bearing for the auto-mark step, `Spec:` for the executing session's fixed-anchor read — keep them ASCII, above the `---`. Specs themselves live at `.task/spec/<slug>.md`, authored only by `to-spec`.
- **Cross-artifact references are Markdown links**, so a viewer can navigate a `.task/` file: `Roadmap: [<slug>](../roadmap/<slug>.md)`, `Spec: [<slug>](../spec/<slug>.md)`, `### Spec references → [<slug>](../spec/<slug>.md) §N`, and the `## Execution` pointer's `[.task/CLAUDE.md](../CLAUDE.md)`. Hrefs are relative to the artifact's own directory; every kind sits one level under `.task/`, so it is always `../<kind>/<slug>.md`. **The label carries the identity, the href is for viewers** — a consumer takes the slug from the label and rebuilds `$AI_DIR/<kind>/<slug>.md`, never follows the href literally (an agent's cwd is the project root, not `.task/task/`). Producers emit the link form; consumers, `validate.sh` included, still accept a bare slug — earlier versions wrote it and artifacts are hand-edited. Full rules: [docs/contract.md § Cross-artifact references](docs/contract.md#cross-artifact-references).
- Pipeline is invisible to the project — no tracked edits outside `.task/`, excluded via `.git/info/exclude` (pattern `.task`). Markers are exactly `git config task.root` + the exclude entry — **nothing else**: no active-task pointer, no `TASK_ID_OVERRIDE`, no per-worktree pointer file.
- `resolve-ws.sh` is a pure `.task/`-root finder (exports `AI_DIR`): `task.root` git config *when that path already holds a `.task/CLAUDE.md`* → ancestor walk for `.task/CLAUDE.md` → `dirname(git-common-dir)/.task` → `$CLAUDE_PROJECT_DIR/.task` when that path already holds a `.task/CLAUDE.md` → `./.task`. Steps 1 and 4 both claim a root **only on evidence** — a stale `task.root` left by a moved or copied repo falls through instead of sending capture setup to write a fresh `.task/CLAUDE.md` beside the real one. No workspace resolution, no pointer read/write/self-heal logic anywhere. Every producer writes under the resolved `$AI_DIR`, never a cwd-relative `.task/` — a cwd-relative write splits the root, since `validate.sh` resolves `AI_DIR` independently.
- Orchestration and commits stay delegated to the platform (dynamic Workflows, `.task/CLAUDE.md` → Commit Format) — never hand-rolled inside a skill. **Review is the pipeline's own**, and lives in exactly one place: the plugin-shipped `agents/code-reviewer.md`, resolved as `task:code-reviewer` and spawned by both execution paths (a plain session per `## Executing a task`; `roadmap-to-workflow`'s driver as its own stage in the per-item serial loop). The platform's `/verify` and `/code-review` are `disable-model-invocation`, so neither path can run them and the skip is silent — **never instruct any agent or `## Executing a task` to call them.** Verification rides inside the reviewer via `.task/CLAUDE.md` → Build and Tests, never as a separate skill. The reviewer proves each finding before fixing it, confines fixes to **Touches** plus regressions the same diff introduced outside them, and amends the implementation's commit — it never sets `isolation` (it must see and edit that same working tree) and never writes under `.task/`.
- Every skill carries `disable-model-invocation: true` + `user-invocable: true`. (`validate` is a bash-only utility — `skills/validate/validate.sh` with no `SKILL.md` — so it has no frontmatter.) Artifacts and user dialog follow `.task/CLAUDE.md` → Language — except `grill`, which by design reads nothing under `.task/` and so mirrors the chat's own language instead; parser-stable strings (headers, cross-artifact link labels, commit trailers, the `## Execution` pointer) stay English.
- Interaction conventions, all three: (a) every user-facing output ends `→ Next: <command or artifact path>` or `→ Done.`; (b) every capture **writes its artifact immediately, then prints a structural digest** as message text (path, title, sections written, the load-bearing decisions/pins captured one line each — for a spec, *all* pins — and the `validate.sh` result), inviting edits against the written file rather than gating on a preview or a confirmation chip — the chat discussion was the review. `grill` writes nothing, so its decision ledger *is* that digest. Exactly one chip survives, and it is not about distilled content: the slug-collision overwrite guard (a pre-write safety check on a destructive action). Step 0 setup writes `.task/CLAUDE.md` and reports — it does **not** ask. (c) every 2–4 option path fork uses `AskUserQuestion` chips. All flag-free — no `--plan`, `--from`, `--phase`, `--refine` anywhere user-facing.
- `roadmap-to-workflow`'s auto-mark (ticking a roadmap item's checkbox) is done by the **driver** after an item's agent returns OK, never inside the per-item agent — avoids racing parallel writes to the roadmap file.
- Commit/PR/release rules: see below and [`CONTRIBUTING.md`](CONTRIBUTING.md) — read it before committing anything in this repo.

## Editing protocol — quick rules

- Treat each `SKILL.md` as a prompt contract — output templates, section headers, step numbering are load-bearing.
- Changing the `task.md` template/separator coordinates `validate/validate.sh` and the `to-task`/`to-plan` template.
- Prefer Markdown + **bold** over XML.
- Every skill change updates `README.md` and `docs/contract.md` in the same commit; when it changes user-facing behavior, also update the matching `website/` guide/reference page (the docs site — `docs(website): …`, scope `website`). The site is the single owner of user-facing usage/troubleshooting prose; `docs/usage.md` and `docs/troubleshooting.md` are now thin pointers to it.
- **Never** update `CHANGELOG.md` autonomously. Edit it only when the user explicitly requests it.
- **Never change `.claude-plugin/plugin.json`'s `version` without explicit user confirmation.** Same rule for cutting `## [Unreleased]` into a numbered release.

## Commit format

Source of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md). Summary:

- Header: `<type>(<scope>): <short summary>` — under 72 chars, imperative, lowercase first letter, no trailing period.
- Types: `feat | fix | refactor | perf | docs | test | chore | revert`. **Do not invent types.**
- Scopes (optional but strongly preferred): skill names (`grill`, `to-task`, `to-plan`, `to-roadmap`, `to-spec`, `roadmap-to-workflow`, `validate`), or cross-cutting keys (`skills`, `agents`, `lib`, `plugin`, `github`, `readme`, `claudemd`, `changelog`, `contributing`, `contract`, `website`). **Do not invent scopes.**
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
