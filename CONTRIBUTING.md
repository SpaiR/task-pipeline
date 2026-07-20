# Contributing to task-pipeline

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the pipeline
- Submitting a fix
- Proposing a new skill, agent, or invariant
- Improving the docs (README, CLAUDE.md, this file)

## We Develop on GitHub

We use [GitHub](https://github.com/SpaiR/task-pipeline) to host code, track issues and feature requests, and accept pull requests.

## Repository structure

```
.claude-plugin/plugin.json       plugin manifest (name `task`, version, metadata)
.claude-plugin/marketplace.json  catalog for the `task-pipeline` marketplace
skills/                          SKILL.md per skill + shared bash helpers
  _lib/                          shared bash helpers:
                                   resolve-ws.sh (pure .task/-root finder, exports AI_DIR),
                                   roadmap.sh (roadmap parsing / checkbox auto-mark helpers);
                                   templates/conventional-commits.md (commit-format fallback)
  to-task/                       SKILL.md — Description only, no Plan; folds in the
                                   inline config setup (former `bootstrap`) on a fresh project
  to-plan/                       SKILL.md — Description + `## Plan` (Goal/Touches/Logic);
                                   promotes/revises a to-task-only file in place
  to-roadmap/                    SKILL.md — multi-task initiative → .task/roadmap/<slug>.md
  to-spec/                       SKILL.md — load-bearing technical decisions →
                                   .task/spec/<slug>.md, referenced via `Spec:` headers
  roadmap-to-workflow/           SKILL.md — the one launcher; authors + invokes a dynamic
                                   Workflow over a roadmap's unchecked items
  validate/                      validate.sh — optional self-check; bash-only utility, no SKILL.md
CLAUDE.md                        invariants + maintainer guidance
docs/
  contract.md                    the authoritative artifact contract — flat .task/ layout,
                                   AI_DIR resolution, task.md + roadmap formats, producer/
                                   consumer table, bash-layer inventory, interaction conventions
  usage.md                       pointer to the docs site (user-facing usage moved to website/)
  troubleshooting.md              pointer to the docs site (user-facing guide moved to website/)
website/                         VitePress docs site (landing + guide + reference), deployed
                                   to GitHub Pages by .github/workflows/docs.yml; source of
                                   truth for user-facing usage/guide prose
CONTRIBUTING.md                  commit format, release procedure, this layout
CHANGELOG.md                     public release log (English)
README.md                        GitHub landing page (links to the docs site)
```

There is no `agents/` directory in v3 — `grill` / `to-task` / `to-plan` / `to-roadmap` / `to-spec` / `roadmap-to-workflow` are the only six skills (`validate` is a bash-only utility, not a skill), and `roadmap-to-workflow` reaches for the platform's own `agent()` / `parallel()` Workflow primitives rather than named subagents shipped by this plugin.

## All Code Changes Happen Through Pull Requests

1. Fork the project (or branch off `main`, if you have direct push access).
2. Make sure the artifact validator still passes against any `.task/` snapshot you used while developing: `bash skills/validate/validate.sh all`.
3. Manually run the affected skill in a real project before opening the PR — the repo has no build/test/lint, so dogfooding is the only smoke test.
4. Open the pull request against `main`.

This project is a collection of Markdown skills plus a handful of bash helpers. There is no compile step, no unit-test suite, and no linter. The bar for "it works" is: skills run end-to-end, invariants in [`CLAUDE.md`](CLAUDE.md) still hold, and the `validate.sh` script accepts the new artifact shapes.

### Pull Request Title

Write a short, **descriptive** title for the whole change — do **not** paste the first commit's header. The title is what a reviewer scans in the PR list, so it should read as plain prose describing the outcome, not as a `<type>(<scope>): …` commit line.

- Sentence case, no trailing period, aim for under ~72 characters.
- Describe the whole PR, not just its first or largest commit.
- No `type(scope):` prefix — the **type is carried by the label** (see [Labels](#labels) below), not the title.

Examples — `feat(to-spec): add standalone spec artifact and Spec: header` (commit) becomes **"Capture technical decisions in a standalone spec artifact"** (PR title); `docs: restructure README for public release` becomes **"Restructure the README for the public release"**.

### Pull Request Body

`.github/pull_request_template.md` pre-fills the body when you open a PR on GitHub. Fill the sections that apply and delete the rest — only **What** is mandatory.

```markdown
## What

<One or two sentences: the user-visible change and why it exists.>

## Why

<The motivation, constraint, prior incident, or complaint that prompted this.
 Skip if fully covered by What.>

## Changes

<Bullet list of the notable edits, grouped by file or subsystem. For a
 multi-item roadmap PR, group by roadmap item.>

## Verification

<How you dogfooded it — which skill(s) you ran end-to-end in a real project,
 and the `bash skills/validate/validate.sh all` result. The repo has no
 automated tests, so this section is how a reviewer trusts the change.>

## Notes for reviewer

<Anything that helps review: a design decision and the alternative rejected,
 a deliberate scope boundary, a follow-up left for later. Omit if none.>
```

Rules:

- **What** is required on every PR. The other sections are optional but strongly preferred on anything non-trivial.
- Close issues/PRs with a `Closes #<n>` / `Fixes #<n>` line at the bottom of the body (GitHub auto-links and auto-closes on merge).
- AI-assisted PRs keep the `🤖 Generated with [Claude Code]` attribution line at the very end of the body, mirroring the commit `Co-Authored-By` trailer (see [Contributing with AI Agents](#contributing-with-ai-agents)).

### Labels

Apply exactly one **type** label, derived from the PR's commit `type`:

| Commit `type`     | Label           |
|-------------------|-----------------|
| `feat`            | `enhancement`   |
| `fix`             | `fix`           |
| `docs`            | `documentation` |
| `refactor`        | `refactor`      |
| `perf`            | `performance`   |
| `test` / `chore`  | `chore`         |
| `revert`          | *(label of the change being reverted)* |

Then add **`breaking-change`** on top of the type label whenever the PR carries a `BREAKING CHANGE:` footer or a `!` in the header — it drives the major-version bump at release time, so it must be visible in the PR list.

The remaining labels (`bug`, `question`, `help wanted`, `good first issue`, `duplicate`, `invalid`, `wontfix`) are for **issue triage**, not PRs. Do not invent new labels — add a label to the repo first if a genuinely new category appears.

## Commit Message Format

*This specification adapts [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) to the task-pipeline repo. The project's runtime fallback (`skills/_lib/templates/conventional-commits.md`) is the **default** that ships to consumer projects without their own commit doc — this file is the source of truth for commits **inside this repo**.*

Each commit message consists of a **header**, a **body**, and a **footer**.

```
<header>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

The `header` is mandatory and must conform to the [Commit Message Header](#commit-message-header) format.

The `body` is mandatory for all commits except trivial ones (single-line typo fixes, `docs:` polish). When present it must explain **why**, not **what** — the diff already shows what changed.

The `footer` is optional. The [Commit Message Footer](#commit-message-footer) format describes what the footer is used for and the structure it must have.

### Commit Message Header

```
<type>(<scope>): <short summary>
  │       │             │
  │       │             └─⫸ Summary in imperative, present tense. Not capitalized. No period at the end.
  │       │
  │       └─⫸ Commit Scope: skill name | skills | lib | hooks | plugin | github | readme | claudemd | contract | changelog | contributing
  │
  └─⫸ Commit Type: feat | fix | refactor | perf | docs | test | chore | revert
```

The `<type>` and `<summary>` fields are mandatory; the `(<scope>)` field is optional but strongly preferred. Append `!` after the type or scope (e.g. `feat!:`, `refactor(plan)!:`) to signal a breaking change — this also requires a `BREAKING CHANGE:` footer.

#### Type

Must be one of the following:

* **feat** — A new skill, agent, hook, slash-command form, or any user-visible capability.
* **fix** — A bug fix in a skill, agent, bash helper, or hook.
* **refactor** — Internal change that does not add a feature or fix a bug (rename, restructure, extract).
* **perf** — A change whose primary goal is to shrink a skill/agent's token or context footprint (or its latency) **without** changing behavior. Distinct from `refactor`: the win is measured in tokens/context, not readability.
* **docs** — Documentation only: `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/`, this file, or prose inside skills.
* **test** — Changes to the project's only executable QA surface: the artifact validator (`skills/validate/validate.sh`).
* **chore** — Tooling, repo housekeeping, plugin manifest fields that do not affect users (keywords, description tweaks), and repo automation under `.github/`.
* **revert** — Reverts a previous commit. The body must name the reverted commit (`Reverts <sha>`) and say why.

#### Scope

**Do NOT invent new scopes.** Pick from the list below; if none fits, omit the scope entirely.

* **A skill name** (no `task:` prefix): `grill`, `to-task`, `to-plan`, `to-roadmap`, `to-spec`, `roadmap-to-workflow`, `validate`.
* **`skills`** — cross-cutting change that touches several skills at once.
* **`lib`** — the shared bash helpers under `skills/_lib/` (`resolve-ws.sh`, `roadmap.sh`) and `skills/validate/validate.sh`, plus their templates.
* **`hooks`** — `hooks/hooks.json`.
* **`plugin`** — `.claude-plugin/plugin.json` and install-path concerns.
* **`github`** — files under `.github/` (PR/issue templates, any repo automation).
* **`website`** — the VitePress docs site under `website/` (landing, guide, reference pages, theme, config).
* **`readme` / `claudemd` / `changelog` / `contributing` / `contract`** — single-doc edits (use `docs:` as the type for these; `contract` = `docs/contract.md`).

#### Summary

* use the imperative, present tense: "add" not "added" nor "adds"
* don't capitalize the first letter
* no dot (.) at the end
* keep the entire first line under 72 characters

### Commit Message Body

Same rules as the summary: imperative, present tense.

Explain **why** the change is being made — the motivation, the constraint, the prior incident, the user complaint. The diff already shows **what** changed; the body should give a future reader the reason they cannot reconstruct from the code alone.

Body is typically a 2–5 bullet list, one bullet per logical sub-change.

### Commit Message Footer

The footer carries breaking-change notes, deprecation notes, issue references, and AI co-authorship trailers.

```
BREAKING CHANGE: <breaking change summary>
<BLANK LINE>
<breaking change description + migration instructions>
<BLANK LINE>
<BLANK LINE>
Fixes #<issue number>
```

or

```
DEPRECATED: <what is deprecated>
<BLANK LINE>
<deprecation description + recommended update path>
<BLANK LINE>
<BLANK LINE>
Closes #<pr number>
```

A `BREAKING CHANGE:` footer is mandatory whenever the header carries `!`. The summary line is short; the description below explains what migration steps the user has to take. Mirror the same content in `CHANGELOG.md` under `Changed (breaking)` / `Removed (breaking)`.

A `DEPRECATED:` footer is required when something is kept working for one release with a warning before removal.

## Versioning Policy

The plugin follows [Semantic Versioning](https://semver.org/). The version of record lives in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) under `"version"` and is mirrored as a heading in [`CHANGELOG.md`](CHANGELOG.md). The two must always agree on `main`.

### Bump rules

* **Patch** (`X.Y.z` → `X.Y.(z+1)`) — bug fixes, internal refactors, doc improvements. No change to slash-command names, artifact contract, or install steps. Existing `.task/` directories continue to work without user action.
* **Minor** (`X.y.z` → `X.(y+1).0`) — new skills, new hooks; any backward-compatible addition. Existing flows and `.task/` directories keep working without user action.
* **Major** (`x` → `(x+1).0.0`) — any breaking change to the artifact contract or the slash-command surface. Anything tagged `Changed (breaking)` / `Removed (breaking)` in the changelog forces a major bump and requires a written migration note.

As of `1.0.0` the artifact contract and the slash-command surface are stable, so SemVer applies in full: breaking changes bump major, never minor. Every breaking change is loud — `!` in the commit header, a dedicated `Changed (breaking)` / `Removed (breaking)` changelog section, and a migration note.

### How to cut a release

A release lands as two commits on `main` (release commit + version sentinel), then the tag. The canonical step list lives in [`CLAUDE.md`](CLAUDE.md) § "Release procedure" — follow it exactly.

### When to update `CHANGELOG.md`

Update only on explicit request from the project owner — AI agents and contributors should not add changelog entries autonomously, even for user-visible changes. The owner batches entries when cutting a release.

When asked to add an entry, the user-visible difference categories are:

* new, removed, or renamed skill / agent / hook
* changed slash-command form (e.g. namespace shift, new flag, removed flag)
* new, removed, or restructured artifact in the [artifact contract](docs/contract.md)
* changed install / migration steps
* changed plugin manifest fields users notice (`name`, `version`, `hooks`)

Internal cleanups (bash-helper refactor, regex tightening, comment typo, README wording polish) typically don't warrant an entry even on request — flag and confirm.

Format follows [Keep a Changelog](https://keepachangelog.com/): `Added` / `Changed` / `Removed` / `Deprecated` / `Fixed` / `Security`. Breaking changes use `Changed (breaking)` / `Removed (breaking)` and **must** include a migration note. The current development line lives under `## [Unreleased]` until the next release is cut.

**CHANGELOG entries are written in English**, regardless of any per-project `config.md` → "Language" setting. The changelog is the plugin's public release log — keeping it in one language across the whole contributor base is more important than matching the language of any single task. All repo documentation (`README.md`, `CLAUDE.md`, this file) is English as well; `config.md` → "Language" governs only the artifacts produced by the skills in a consumer project, never this repo's own docs.

## Contributing with AI Agents

This repository **is** a tool for working with AI coding agents, so dogfooding is encouraged: it is fine — preferred, even — to use the pipeline itself when contributing here — discuss the change in chat, fix it with `/task:to-task` or `/task:to-plan` into `.task/task/<slug>.md`, then tell any session `implement .task/task/<slug>.md` (which runs `/verify` + `/code-review` and commits per this file's Commit Format). AI coding agents (Claude Code, Copilot, Cursor, Codex, Gemini, etc.) are welcome to assist with contributions of any kind.

Two extra rules apply on top of the regular contribution flow:

1. **You are responsible for the change.** The agent is a tool — review the diff, manually run the affected skill in a real project, and make sure invariants in [`CLAUDE.md`](CLAUDE.md) still hold. "The agent did it" is not a defense for a broken or low-quality patch, and it is *especially* not a defense for a silently broken artifact contract.
2. **Every AI-assisted commit must be attributed via a `Co-Authored-By` trailer** (see below). This applies whether the agent wrote the whole commit or just a substantial part of it.

### `Co-Authored-By` trailer for AI-assisted commits

Add a `Co-Authored-By` line to the [commit message footer](#commit-message-footer) for any commit an AI agent helped produce. Use the **short, family-level name** of the model — not the specific version — followed by the standard vendor noreply email.

Format:

```
Co-Authored-By: <Model Family> <<vendor-noreply-email>>
```

Examples (use the family name, drop the version/tier suffix):

| Model used                                 | Trailer                                          |
|--------------------------------------------|--------------------------------------------------|
| Claude Opus / Sonnet / Haiku (any version) | `Co-Authored-By: Claude <noreply@anthropic.com>` |
| GitHub Copilot                             | `Co-Authored-By: Copilot <copilot@github.com>`   |
| OpenAI Codex / GPT                         | `Co-Authored-By: Codex <noreply@openai.com>`     |
| Google Gemini                              | `Co-Authored-By: Gemini <noreply@google.com>`    |

Full commit message example:

```
fix(validate): propagate config language to validator output

validate.sh inherits a per-call prompt template, but the language
block was being filled from a hard-coded English default instead of
`config.md` → "Language". Pass it through explicitly so findings
render in the configured language.

Fixes #42

Co-Authored-By: Claude <noreply@anthropic.com>
```

If multiple agents contributed, add one `Co-Authored-By` line per agent. Place the trailer(s) at the very end of the commit message, separated from the body by a blank line.

## Any contributions you make will be under the MIT License

In short, when you submit changes, your submissions are understood to be under the same [MIT License](https://choosealicense.com/licenses/mit/) that covers the project. Feel free to contact the maintainer if that's a concern.

## Report bugs using GitHub [issues](https://github.com/SpaiR/task-pipeline/issues)

We track bugs in the GitHub project's issue tracker. Report a bug by opening a new issue.

## Write bug reports with detail, background, and a reproducer

**Great Bug Reports** tend to have:

- A quick summary and/or background
- The slash-command sequence you ran (e.g. `/task:to-plan api-v2-migration#2` → `implement .task/task/<slug>.md`, or `/task:roadmap-to-workflow api-v2-migration`)
- The relevant slice of `.task/task/<slug>.md` or `.task/roadmap/<slug>.md` that triggers the bug, when the bug is about artifact handling
- The output of `bash skills/validate/validate.sh all` when the bug is about validation
- What you expected would happen
- What actually happened
- Notes (possibly including why you think this might be happening, or things you tried that didn't work)

People *love* thorough bug reports. Truly.
