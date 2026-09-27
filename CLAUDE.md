# CLAUDE.md

Guidance for Claude Code when editing **this repository**. User docs are the `website/` site, which owns usage prose, and `README.md`. The contract is [`docs/contract.md`](docs/contract.md); read the section a rule links before a non-trivial edit. Path-specific how-to in `.claude/rules/` loads when you read a matching file.

**Where a rule lives.** Every rule a `/self-audit` lens enforces, and every irreversible one (CHANGELOG, version, commits), stays here as a one-liner linking the contract section that holds its full statement and the why. `.claude/rules/` holds path-specific how-to only.

## Quick orient

The `task` plugin: five skills implementing a chat-first context-serialization protocol, not an orchestration engine. One skill fixes a chat discussion into a Markdown artifact under `.task/`; what you capture — one task with its plan, an initiative with its architecture, or the decisions they must honor — is the skill name, never a flag. No execution skill: a session told `implement .task/task/<slug>.md` follows its `## Execution` pointer, `roadmap-to-workflow` fans items out through the driver `skills/_lib/roadmap-driver.js`, and both hand the diff to the one agent, `agents/code-reviewer.md`. No build step, no plugin hook; the bash layer is tested and shellchecked in CI. Work here is mostly Markdown and pipeline reasoning.

```
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-roadmap                  ← what you capture is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
  ↓                       ↓
task:code-reviewer                    ← the plugin's own review pass, spawned by both:
                                        prove → fix within Touches → Build and Tests → commit the fixes
```

## Verify

- `bash tests/run.sh [filter]` is the gate, green before every commit. Driver cases need `node`, some hook checks `jq`; a SKIP line is not a pass.
- `claude plugin validate --strict .` checks the marketplace manifest; `npm --prefix website ci && npm --prefix website run docs:build` builds the site.
- `claude plugin eval .` runs the prompt evals (early access, not in CI: a signal only); `/self-audit` checks the repo against its own rules.
- CI: `.github/workflows/tests.yml` runs the suite and shellcheck; `docs-check.yml` builds the site on PRs; `docs.yml` deploys it.

## Invariants — don't break these when editing skills

- `.task/` is **flat**: `CLAUDE.md`, `.gitignore`, one file per artifact under `task/`, `roadmap/`, `spec/`. No subfolders, workspace, log or archive. [§ layout](docs/contract.md#task-layout-flat)
- `.task/CLAUDE.md` is a nested `CLAUDE.md`, written once by setup, then user-owned: never rewritten or section-repaired. It auto-loads only through file-read tools and is not re-injected after `/compact`, hence the `## Execution` pointer and the reviewer's phase-0 read. [§ format](docs/contract.md#taskclaudemd-format)
- **Slug is the identity**: kebab-case English from the title, the filename, never a header. No task-id, no `[TASK-ID]`, no umbrella grouping. [§ Slug](docs/contract.md#slug-as-identifier)
- Setup gate: the three captures run setup without a chip; `roadmap-to-workflow` and `validate.sh` hard-stop without `.task/CLAUDE.md`; `grill` touches nothing under `.task/`. [§ Setup gate](docs/contract.md#setup-gate-categories)
- `task.md` is the single contract: ASCII `Roadmap:`, `Source item:`, `Spec:` headers above `---`, `## Description`, `## Plan` (every producer writes it; `validate.sh` still accepts an older file without one), optional `## Tests`. Every task file ends with the stamped English `## Execution` pointer; roadmaps and specs carry none. [§ task.md](docs/contract.md#taskmd-format-tasktaskslugmd)
- **Cross-artifact references are Markdown links** (`../<kind>/<slug>.md`; a related roadmap `<slug>.md`). The label is the identity: consumers rebuild `$AI_DIR/<kind>/<slug>.md` from it and accept a bare slug. Only `to-spec` writes specs; users edit them after. [§ references](docs/contract.md#cross-artifact-references)
- The pipeline is **invisible** to the project: no tracked edits outside `.task/`, which its own `.task/.gitignore` (`*`) ignores; exactly two markers, `git config task.root` and `.task/.gitignore`. This repo's tracked `.task/` ignore is the dogfooding exception. [§ Markers](docs/contract.md#marker-inventory)
- `resolve-ws.sh` is a pure root finder: it exports `AI_DIR`, claiming a root only on evidence. Every producer writes under `$AI_DIR`, never a cwd-relative `.task/`. [§ Root resolution](docs/contract.md#root-resolution-skills_libresolve-wssh)
- Orchestration and commits stay delegated to the platform, never hand-rolled in a skill. The driver is reached by its registered name `task:roadmap-driver`, never by `scriptPath`. [§ driver contract](docs/contract.md#roadmap-to-workflow-execution-shape-driver-contract)
- Review lives only in `agents/code-reviewer.md`: it proves before fixing, stays within **Touches**, commits at most one fix commit on top (none when clean), never sets `isolation`. Nothing instructs a call to `/verify` or `/code-review`. [§ Agent layer](docs/contract.md#agent-layer-agents)
- Auto-mark is the reviewer's phase 7: OK verdict only, one baked flip command, never a plan or implement agent or a stage of its own. [§ Agent layer](docs/contract.md#agent-layer-agents)
- Frontmatter: every skill carries `disable-model-invocation: true`, `user-invocable: true` and a flag-free `argument-hint`; the four bash-calling skills share one identical `allowed-tools` line. Each holds exactly one `!`-injection, its Step 0 preflight call; `grill` and `.claude/skills/` hold none. [§ Frontmatter](docs/contract.md#frontmatter)
- Artifacts and dialog follow `.task/CLAUDE.md` → Language (`grill` mirrors the chat); parser-stable strings stay English. [§ Language split](docs/contract.md#language-split)
- User-facing output ends with a `→ Next:` footer or `→ Done.`; a capture writes, then prints a digest (its only chip: the slug-collision guard); 2–4 option forks use `AskUserQuestion`; no flags. [§ Interaction conventions](docs/contract.md#interaction-conventions)

## Editing protocol — quick rules

- Each `SKILL.md` is a prompt contract: output templates, section headers and step numbering are load-bearing.
- Edit the single owner, never a copy: the `task.md` shape, `skills/_lib/write-task.sh` (change `skills/validate/validate.sh` and the reviewer's phase 0 with it); setup and the `.task/CLAUDE.md` template, `skills/_lib/setup.md`; the plan pipeline, `skills/_lib/plan-driver.md` § Core; the from-roadmap block, `skills/_lib/roadmap-item.md`; roadmap capture, `skills/_lib/roadmap-capture.md` § Core; the commit fallback, `skills/_lib/templates/conventional-commits.md`.
- A plugin-skill change (`skills/*/SKILL.md`) updates `README.md`, `docs/contract.md` and, for user-facing behavior, its `website/` page in the same commit; self-audit is exempt.
- A helper or driver change ships its `tests/` case in the same commit (comment- and lint-only edits excepted), with the suite green.
- Prefer Markdown and **bold** over XML.
- **Never** edit `CHANGELOG.md`, change `.claude-plugin/plugin.json`'s `version`, or cut `## [Unreleased]` into a release unless the user explicitly asks. A repo hook asks first.
- Path rules, in `.claude/rules/`: `skills.md`, `lib-bash.md`, `tests.md`, `evals.md`, `website.md`, `agents.md`, `roadmap-driver.md`, `plugin-manifest.md`.

## Repo-local tooling

`.claude/` never ships. `/self-audit` fans out to four lens agents in `.claude/agents/`, read-only by instruction (no Edit or Write tools; Bash for reading), which nothing enforces. `.claude/settings.json` wires the release-file hook `.claude/hooks/guard-release-files.sh` and pre-approves the suite, `validate.sh`, the plugin validator and the site build. The lenses, the hook and `CONTRIBUTING.md` cite this file's headings by name: keep `## Quick orient`, `## Invariants — …`, `## Editing protocol — quick rules` and `## Release procedure` byte-identical.

## Commits and pull requests

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before committing: types and scopes from its closed lists, never invented; PR title, body template and label from it, not `gh`'s defaults. Every AI-assisted commit ends with a `Co-Authored-By:` trailer; the form is not pinned.

## Release procedure

Only on the user's explicit request, in this exact order — never reorder or merge steps:

1. **Release commit**, all in one `chore(changelog): release vX.Y.Z` commit — rename `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] — YYYY-MM-DD` (no fresh empty `## [Unreleased]` above it; a breaking release adds a `## Migration` block), and set the same number as `"version"` in `.claude-plugin/plugin.json` and as the nav label `text: 'vX.Y.Z'` in `website/.vitepress/config.mts`.
2. **Version sentinel commit** — `git commit --allow-empty -m "vX.Y.Z"`.
3. **Tag** — `git tag vX.Y.Z` on the sentinel commit. Then confirm with the user before running `git push origin main && git push origin vX.Y.Z` (the tag alone doesn't push the commits).
