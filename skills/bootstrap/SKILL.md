---
name: bootstrap
description: 'Set up task-pipeline in this repo once — detects the stack, writes `.task/config/config.md`, records the pipeline root (`git config task.root`), and adds the local git exclusion. Run this first.'
disable-model-invocation: true
user-invocable: true
model: haiku
---

Create `.task/config/config.md` — the per-project configuration for all task-* skills. Interactive: detects language policy and testing policy from the repo, then confirms both in a single accept/decline/edit prompt. Each run regenerates the file in full. Sections whose information is canonically maintained in `CLAUDE.md` are emitted as short references rather than duplicated copies.

Besides explicit user invocation, this skill is **auto-invoked inline** by `/task:design` and `/task:roadmap` on their first run in an unconfigured project (their Step 0 config gate runs this skill's Steps verbatim, then re-validates and continues the original request). The explicit `/task:bootstrap` command remains available and idempotent for re-running setup on demand — a re-run simply regenerates `config.md`. An inline caller and a human caller share exactly this one flow; there is no trimmed "auto" variant.

**Input:** Additional context (if provided): $ARGUMENTS

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-c--shallow-scan) — no `config.md` precondition (this skill creates it); the Tier-C reads (manifests, top-level dirs, `CLAUDE.md`, `git log`) apply. Language inside the emitted `config.md` is detected, then confirmed (or edited) in Step 2's single confirmation.

**Worktree sharing is automatic — there is no join step.** `.task/` lives once at the pipeline root and is resolved by every worktree of the repo (nested, sibling, or a bare repo's worktrees) through the `task.root` git-config anchor this skill records (with a `dirname(git-common-dir)` fallback). No symlink, no per-worktree setup: create a worktree and `/task:design` just works. Re-running `/task:bootstrap` from any worktree targets the same shared `.task/` and simply regenerates `config.md`.

## Instructions

### Step 0: Determine the pipeline root

Before any project analysis, compute the directory that will hold `.task/` — the **pipeline root**, shared by every worktree of this repo. Run:

```bash
if git rev-parse --git-dir >/dev/null 2>&1; then
  IS_BARE=$(git rev-parse --is-bare-repository)
  EXISTING=$(git config --local --get task.root 2>/dev/null || true)
  if [[ -n "$EXISTING" ]]; then
    ROOT="$EXISTING"                                      # already bootstrapped — keep the same root
  else
    ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
  fi
else
  IS_BARE=false
  ROOT=$(pwd)                                             # non-git: bootstrap in place
fi
echo "IS_BARE=$IS_BARE"; echo "ROOT=$ROOT"
```

- **Normal git repo / non-git dir** (`IS_BARE=false`): `ROOT` is the main worktree root (or `pwd` for a non-git dir). This is deterministic — do not ask; just report it in the output. `.task/` is created at `$ROOT/.task`.
- **Bare repo** (`IS_BARE=true`): there is no main worktree, so the default `ROOT` (the bare repo's container) is a best-effort guess. **Surface it for confirmation in Step 2** (see the location line + edit option there) so the user can redirect `.task/` to wherever their worktrees actually live.

`ROOT` is carried into Step 3 (where `.task/` is created and `git config --local task.root "$ROOT"` is recorded) and Step 3a. There is no worktree "join" — sharing is automatic once `task.root` is set. Do **not** create or touch any `.task` symlink; the mechanism no longer exists.

### Step 1: Analyze project

1. Read `CLAUDE.md` in the project root (if exists). For each topic below, record whether `CLAUDE.md` already documents it and under which heading — this drives the dedup rule in Step 3:
   - Build / test commands
   - Project conventions (paths to patterns.md, guardrails.md, etc.)
   - Module / package structure
   - Ignored directories (build/, node_modules/, etc.)
   - MCP servers and tool names
2. Determine:
   - **Language/stack**: Java, TypeScript, Python, Go, Rust, etc.
   - **Build system**: Gradle, Maven, npm, cargo, make, etc.
   - **Build and test commands**: from `CLAUDE.md` or standard for the stack.
   - **Module structure**: single-module or multi-module.
   - **Convention documents**: paths to patterns.md, guardrails.md, etc. (if present).
   - **MCP servers** available — discover whichever code-navigation, code-editing, or library-documentation servers are actually connected in this session (from `CLAUDE.md` or system context). Record them by their role, not by any assumed product; name none by default.
   - **Ticket format**: if the project has one (`DT-XXXX`, `PROJ-NNN`, etc.).
   - **Detected language policy**: infer the repo's dominant natural language from the `git log` commit prose (item 3 below) plus prose in `CLAUDE.md` / `README.md`. For an English or mixed-language repo, the safe detected default is "follow the language of `task.md` Description" ("Edit menu — Language", option 2, below); for a repo whose commits and docs are clearly in one non-English language, detect that language instead. This only **seeds** the proposal shown in Step 2 — it never locks a value.
   - **Detected testing-policy mode**: reuse the test-infrastructure signals already gathered here (test framework, test directories, test command referenced in `CLAUDE.md` or lockfiles). Tests present → `on-demand`. A documented TDD / red-first convention in `CLAUDE.md` → `always`. No test infrastructure at all → still `on-demand` (never silently detect `never`). Also seeds only — never locks a value.
3. Run `git log -10 --oneline` to determine commit style and language.
4. Look for a project commit-format doc — check, in order: `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`. If one exists, record its path; the Commit Format section will emit a `**Source:**` pointer to it instead of paraphrasing rules that may drift.

### Step 2: Confirm detected setup

Regardless of whether `config.md` already exists, present the detected defaults from Step 1 as one proposal, then a single decision using the canonical **accept / decline / edit** choice grammar — see [docs/spec/invariants.md § Interaction conventions (b)](../../docs/spec/invariants.md#b-choice-grammar--accept--decline--edit) for the grammar itself; do not restate it here. Present in the user's language (fall back to English).

```
Detected — Language: <detected policy, in plain words>; Testing policy: <detected mode>.
accept / decline / edit
```

**Bare repo only** (`IS_BARE=true` from Step 0): the default `.task/` location is a guess, so add a third line to the proposal and offer it as an editable field:

```
Detected — Language: <…>; Testing policy: <…>; .task location: <ROOT>/.task.
accept / decline / edit
```

- **accept** — adopt the detected values (and, for a bare repo, the proposed `.task` location) as-is; continue to Step 3.
- **edit** — ask which field(s) to amend (language policy, testing-policy mode, and — bare repo only — the `.task` location); for each amended field show the matching option list below (for the location, ask for an absolute directory and set `ROOT` to it), apply the user's choice, then continue to Step 3.
- **decline** — do **not** write `config.md` or `task.root`; report "config.md not written — re-run `/task:bootstrap` when ready" and **STOP** (skip Steps 3–4).

**Edit menu — Language** (shown only if the user edits the language policy; for section `Language`):

```
Which language policy for task artifacts?
  1) English for all artifacts and commits
  2) Follow the language of task.md Description
     (commits still follow "Commit Format")                          [default]
  3) Custom — specify language per artifact
```

- Option **1** → record: every artifact and commit in English.
- Option **2** → use the defaults baked into the template below.
- Option **3** → ask for each of: `task.md` Description, `plan.md`, `summary.md`, `## Decisions`, commits, design idea phase dialog language, design refine phase dialog language. Record the per-artifact answers into the `Language` section.

**Edit menu — Testing Policy** (shown only if the user edits the testing-policy mode; for section `Testing Policy`):

```
How strict should the testing policy be for tasks driven by this pipeline?
  1) always     — every task writes tests; TDD red-first is enforced
  2) on-demand  — tests only when task.md Description explicitly asks for them  [default]
  3) never      — the pipeline does not write tests
```

Store the chosen mode. For modes `1` or `2`, also try to pre-fill from project analysis:

- **Test framework** — `JUnit 5`, `Vitest`, `pytest`, `go test`, …; infer from `CLAUDE.md`, lockfiles, or test commands.
- **Test command** — usually the Tests line of `Build and Tests`.
- **Required scope / Excluded scope** — optional; leave `project-default` if unclear.

### Step 3: Write `.task/config/config.md`

All `.task/` paths below are under the **pipeline root `$ROOT`** computed in Step 0 (and possibly edited in Step 2). When `$ROOT` is not the current directory (a nested/sibling/bare worktree), write to the absolute `$ROOT/.task/...` — do **not** create a second `.task/` at `pwd`.

First, **record the pipeline root** so every worktree resolves the same `.task/` (skip in a non-git dir):

```bash
git config --local task.root "$ROOT"
```

`--local` writes the repo-common config, shared by all worktrees (unaffected by `extensions.worktreeConfig`). This is what `_lib/resolve-ws.sh`'s `find_ai_dir` reads first.

Always write `config.md` from the full template, replacing any prior version. If `$ROOT/.task/config/config.md` already exists, overwrite it — note this in the output ("recreated existing config.md"). Manual edits to `config.md` will be lost; durable preferences should live in `CLAUDE.md` (which `/task:bootstrap` references) or be reproducible from the prompts.

Also pre-create the workspace container (`mkdir -p "$ROOT/.task/workspace"`) so subsequent skills (`/task:design`, `/task:auto-roadmap`) have it ready. The directory stays empty after init; each umbrella creates its own subfolder `.task/workspace/<task-id>/` when `/task:design` (or `/task:auto-roadmap`) runs, and a per-worktree active-task pointer (inside git's per-worktree dir — `git rev-parse --git-path task-current`) names the active subfolder for that worktree.

**Dedup rule.** Each section emits in one of two modes based on `CLAUDE.md` coverage from Step 1:

- **Reference mode** (when `CLAUDE.md` documents it): emit `**Source:** \`CLAUDE.md\` → \`## <Heading>\``, optionally followed by ≤3 lines of structured summary downstream skills need at a glance (e.g. the exact build command). Do not restate full prose from `CLAUDE.md`.
- **Full mode** (when `CLAUDE.md` does not cover it, or the section is pipeline-specific): emit the template content as-is.

Apply per section:

| Section | When `CLAUDE.md` covers it | Otherwise |
|---------|----------------------------|-----------|
| Code Navigation | Full mode (priority/use-case mapping is pipeline-specific even if tools are listed elsewhere) | Full mode |
| Code Editing | Full mode (same reason) | Full mode |
| Library Documentation | Full mode | Full mode |
| Project Conventions | Reference mode | Full mode |
| Build and Tests | Reference mode + the exact build/test commands as a 1–2 line summary | Full mode |
| Commit Format | Reference mode if a project commit-format doc was found in Step 1.4 — emit only `**Source:** \`<path>\`` and stop, no inline rules. Otherwise Full mode (derived from `git log`). | Full mode (derived from `git log`) |
| Language | Full mode (pipeline-specific, comes from the confirmed language policy) | Full mode |
| Testing Policy | Full mode (pipeline-specific, comes from the confirmed testing-policy mode) | Full mode |
| Directories — Do Not Search | Reference mode | Full mode |

Template:

```markdown
# AI Tools — Project Configuration

Configuration for AI task-pipeline skills. Read by skills at context loading.

This file is regenerated by `/task:bootstrap`. Sections marked with `**Source:**` are pointers into `CLAUDE.md` — edit `CLAUDE.md` and re-run `/task:bootstrap` to refresh them. Manual edits to this file are not preserved across runs.

---

## Code Navigation

Read code in ascending cost order:

| Priority | Tool | When |
|----------|------|------|
{Fill with specific MCP tools for the project or standard Claude Code tools}

## Code Editing

| Priority | Tool | When |
|----------|------|------|
{Fill with the project's editing tools in ascending cost order: a symbol-level editing MCP server (if one is connected) before the built-in `Edit`, and `Write` for new files. With no editing MCP server: `Edit` -> `Write`.}

## Library Documentation

{If a library-documentation MCP server is connected — specify its exact resolve/query commands. If not — WebSearch / official docs.}

## Project Conventions

{Reference mode if CLAUDE.md lists them; otherwise table of paths to convention documents.}

## Build and Tests

{Reference mode if CLAUDE.md has build/test instructions, plus exact Build / Tests commands as a short summary. Otherwise full table of commands.}

## Commit Format

{Reference mode (a commit-format doc was found in Step 1.4): emit just
`**Source:** \`<path>\``
— and stop. The path **must end in `.md`**: `commit-context.sh` extracts it with a regex that requires the `.md` suffix (only `CONTRIBUTING.md` / `docs/CONTRIBUTING.md` / `.github/CONTRIBUTING.md` are scanned in Step 1.4, all of which match). No inline types/scopes/description-form/length/AI-trailer/body rules: `commit-context.sh` bundles `<path>` into the skill's context and `/task:ship` reads its rules directly. Inlining would duplicate a doc that may evolve independently of `/task:bootstrap` runs.

Full mode (no commit-format doc found): determine from `git log` — format, language, presence of prefixes; if `[AI]` style — describe it; if Conventional Commits — describe briefly; else describe what the project uses.}

## Language

Rules about which language to use for each artifact produced by task-* skills. Skills reference this section instead of duplicating the rule locally.

{Emit the block that matches the confirmed language policy (detected default, or the edit-menu option chosen in Step 2):
 - Option 1: every line becomes "English".
 - Option 2 (default): emit the block below verbatim.
 - Option 3: reflect the user's per-artifact answers.}

- `task.md` Description and header fields (title, Goal, Modules, Packages, Key files) — language chosen by the user. When design's idea phase (Socratic mode) rewrites Description, preserve the original language.
- `plan.md` — same language as `task.md` Description.
- `summary.md` — same language as `task.md` Description.
- `## Decisions` in `task.md` — same language as `task.md` Description.
- `## Decisions` in `plan.md` — same language as `task.md` Description.
- Commit messages — see "Commit Format" above.
- User-facing communication during design's idea phase and design's refine phase (questions, clarifications, in-chat discussion rounds) — same language as `task.md` Description.
- All other skill outputs (status reports, verification tables, step execution notes) — English.

## Testing Policy

Controls whether `/task:design` blueprint phase and `/task:build` implement phase write tests.

- **Mode:** `{always | on-demand | never}`   <!-- the confirmed testing-policy mode -->
- **Test framework:** `{e.g. JUnit 5 / Vitest / pytest — or "project-default" if unknown}`
- **Test command:** `{exact command, usually the Tests line from "Build and Tests"}`
- **Required scope:** `{paths where tests are mandatory — or "project-default"}`
- **Excluded scope:** `{paths where tests are not required — scripts, migrations, generated code — or "none"}`

Resolution — `/task:design` (blueprint phase) computes `tests_required` once per task:

| Mode | `tests_required` |
|------|------------------|
| `always` | `true` |
| `on-demand` | `true` only if `task.md` Description explicitly asks for tests (e.g. "with tests", "add tests", "write tests"); otherwise `false`. Responsibility is on the user. |
| `never` | `false` |

When `tests_required` is `true`, `/task:design` (blueprint phase) emits a `## Tests` section in `plan.md`. All downstream skills key off the presence of that section — **it is the single source of truth** for whether tests are in scope:

- `/task:design` (blueprint phase) writes `## Tests` with red-first specs (test file path, framework, arrange/act/assert, expected failure before implementation).
- `/task:build implement phase` runs a TDD loop per test: write failing test → run (RED) → implement → run (GREEN) → refactor only on green.

## Directories — Do Not Search

{Reference mode if CLAUDE.md lists them; otherwise standard for the stack: build/, .gradle/, node_modules/, __pycache__/, target/, etc.}
```

**Rules:**
- Specify **only** actually available MCP tools. Do not guess, and do not privilege any particular product — record whatever this session has connected, by role.
- If a symbol-level code-navigation/editing MCP server is connected — list its specific tool names (e.g. `mcp__<server>__find_symbol`).
- If no such server is connected — navigation: Grep/Glob/Read; editing: Edit/Write.
- If a library-documentation MCP server is connected — list its specific resolve/query tool names.
- Build/test commands — **exact**, from `CLAUDE.md`. Do not guess.
- Commit format — determine from actual `git log`, do not impose a style.
- **No decorative XML tags.** Use Markdown headers and formatting only. XML tags are allowed only when they carry semantic metadata that Markdown cannot express.
- **Every run regenerates the file in full.** Manual edits to `config.md` are not preserved — durable preferences belong in `CLAUDE.md` (referenced via `**Source:**`) or in the prompt answers (Language, Testing Policy).
- **Pipeline is invisible to the project.** Do not modify `CLAUDE.md`, `README.md`, `.gitignore`, or any other tracked file outside `.task/`. The pipeline must leave no trace in shared project files — anyone not using it should be unable to tell from the repo that it exists. All pipeline configuration lives under `.task/`; the only sanctioned artifact that may sit at the pipeline root is `.task/` itself (git-excluded through `.git/info/exclude`, Step 3a). The per-worktree active-task pointer lives **inside git's per-worktree dir** (`git rev-parse --git-path task-current`), so it is already outside the work tree and needs no exclusion. The `task.root` anchor lives in the repo-local git config, not in any tracked file. There is no `.task` symlink — worktree sharing is via `task.root` (Step 3).

### Step 3a: Set up local git exclusion

Exclude `.task` (the pipeline working tree at `$ROOT`) locally via `.git/info/exclude` so pipeline artifacts never get staged or pushed and the project's shared `.gitignore` stays untouched. `.git/info/exclude` is repo-wide and shared across all worktrees, so this needs to run only once per clone. The active-task pointer needs no entry — it lives inside the git dir. Idempotent — skip the line if already present.

1. If the current directory is not inside a git repository (no `.git/` directory or `git rev-parse --git-dir` fails) — skip this step and warn the user that exclusion was not configured.
2. Otherwise run:

   ```bash
   EXCLUDE=$(git rev-parse --git-path info/exclude)
   mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
   grep -qxF '.task' "$EXCLUDE" || echo '.task' >> "$EXCLUDE"
   ```

3. Report whether the line was added or already present.

### Step 4: Verify

Ensure:
1. `$ROOT/.task/config/config.md` exists and contains all sections listed in the template:
   `Code Navigation`, `Code Editing`, `Library Documentation`, `Project Conventions`,
   `Build and Tests`, `Commit Format`, `Language`, `Testing Policy`,
   `Directories — Do Not Search`.
1a. `$ROOT/.task/workspace/` directory exists (empty after init — per-umbrella `<task-id>/` subfolders appear later, on first `/task:design` or `/task:auto-roadmap`).
2. All file references in the project (patterns.md, guardrails.md, etc.) exist.
3. Build/test commands match the project (whether emitted in full or as a reference summary).
4. Only actually available MCP tools are listed.
5. `Testing Policy` → `Mode` is one of `always | on-demand | never`.
6. `git config --local --get task.root` returns `$ROOT` (or the project is not a git repo and a warning was reported).
7. `.git/info/exclude` contains `.task` (or the project is not a git repo and a warning was reported).
8. No project files outside `.task/` were modified by this skill. The active-task pointer lives inside git's per-worktree dir and is created lazily by `/task:design` / `/task:auto-roadmap`, not by bootstrap.

## Output

**On decline** — report only: "config.md not written — re-run `/task:bootstrap` when ready". No file was written, `task.root` was not set, Steps 3–4 did not run, and no further bullets below apply.

**On accept or edit** — report:
- Path to the written `config.md` (the absolute `$ROOT/.task/...` when `$ROOT` is not the current directory), and whether an existing file was overwritten.
- Recorded pipeline root: `task.root = $ROOT` (or skipped — not a git repo).
- Detected Language policy and Testing Policy mode, and whether the user accepted them as-is or edited any (bare repo: include the `.task` location if edited).
- List of sections emitted in **reference mode** (pointing into `CLAUDE.md`) vs. **full mode**.
- Local git exclusion status: `.task` added to `.git/info/exclude`, already present, or skipped (not a git repo).
- Remind the pipeline: `/task:design` → [design's idea phase] → `/task:design` (blueprint phase) → [design's refine phase] → `/task:build implement phase` → [`/task:build audit phase`] → `/task:ship` → `/task:ship`. Steps in brackets are optional.

Then print this getting-started primer (translate to the `config.md` Language if it is not English; otherwise reproduce verbatim):

> **You're set up.** task-pipeline runs in three steps — **design → build → ship** — each its own command:
> - **`/task:design`** — open a task and plan it → writes `task.md` (what & why), then `plan.md` (how)
> - **`/task:build`** — implement the plan, then audit it → `audit.md` (findings)
> - **`/task:ship`** — commit and close → `summary.md` (result)
>
> Those four files are plain Markdown under `.task/` — read or edit them by hand any time. Re-running the same command resumes where you left off (phases are auto-detected from those files). One `task.md` is an *umbrella*; each design→build→ship cycle under it is a *subtask*, and `/task:ship --next` starts the next one.
>
> → Next: `/task:design "<what you want to do>"`
