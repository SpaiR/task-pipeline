---
name: bootstrap
description: 'Set up task-pipeline in this repo once — detects the stack, writes `.task/config/config.md`, and adds the local git exclusion. Run this first.'
disable-model-invocation: true
user-invocable: true
model: haiku
---

Create `.task/config/config.md` — the per-project configuration for all task-* skills. Interactive: asks the user about language and testing policy. Each run regenerates the file in full. Sections whose information is canonically maintained in `CLAUDE.md` are emitted as short references rather than duplicated copies.

**Input:** Additional context (if provided): $ARGUMENTS

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-c--shallow-scan) — no `config.md` precondition (this skill creates it); the Tier-C reads (manifests, top-level dirs, `CLAUDE.md`, `git log`) apply. Language inside the emitted `config.md` is chosen interactively via Prompt A. **Worktree join-mode (Step 0) is the exception:** when invoked from a *linked* git worktree that has no local `.task`, the skill only links the shared `.task/` from the main worktree and exits — Tier A (`git` + a `.task` symlink + `.git/info/exclude`; no project analysis, no prompts, Steps 1–4 skipped).

## Instructions

### Step 0: Worktree join-mode detection

Before any project analysis, detect whether this invocation is **joining an existing pipeline from a linked git worktree** rather than bootstrapping a fresh project. The shared `.task/` lives only in the main worktree (it is git-excluded, so a freshly created worktree has no copy); a linked worktree gets access by symlinking `.task` to the main worktree's `.task/`. This step materializes that symlink — the single sanctioned, safe way to create it. Run:

```bash
MODE="NORMAL"; MAIN_TASK=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  GIT_DIR_ABS=$(cd "$(git rev-parse --git-dir)" && pwd)
  COMMON_ABS=$(cd "$(git rev-parse --git-common-dir)" && pwd)
  if [[ "$GIT_DIR_ABS" != "$COMMON_ABS" ]]; then          # linked worktree, not main
    MAIN_ROOT=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
    MAIN_TASK="$MAIN_ROOT/.task"
    if [[ -L .task ]]; then                                # already a symlink
      if [[ -d .task && -d "$MAIN_TASK" && "$(cd .task && pwd -P)" == "$(cd "$MAIN_TASK" && pwd -P)" ]]; then
        MODE="JOIN-NOOP"                                   # valid link to main's .task
      else
        MODE="JOIN-REFUSE-LINK"                            # broken or foreign symlink
      fi
    elif [[ ! -e .task ]]; then                            # no local .task
      if [[ -d "$MAIN_TASK" ]]; then MODE="JOIN-LINK"; else MODE="JOIN-REFUSE-NOMAIN"; fi
    fi
    # else: .task is a real dir/file → standalone pipeline in this worktree → MODE stays NORMAL
  fi
fi
echo "MODE=$MODE"; echo "MAIN_TASK=$MAIN_TASK"
```

Dispatch on `MODE` (never overwrite an existing `.task` silently):

- **`NORMAL`** — not a linked worktree, or the worktree already has its own real `.task`. Skip the rest of Step 0; proceed to Step 1 (regular bootstrap).
- **`JOIN-LINK`** — linked worktree, no local `.task`, main worktree has `.task/`. Create the symlink with an **absolute** target, update the local git exclusion, report, and **STOP** (do not run Steps 1–4):

  ```bash
  ln -s "$(cd "$MAIN_TASK" && pwd -P)" .task          # absolute, physical target
  EXCLUDE=$(git rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
  grep -qxF '.task'         "$EXCLUDE" || echo '.task'         >> "$EXCLUDE"
  grep -qxF '.task-current' "$EXCLUDE" || echo '.task-current' >> "$EXCLUDE"
  ```

- **`JOIN-NOOP`** — already linked to main's `.task/`. Re-affirm the exclusion idempotently (the `EXCLUDE` block above), report "already linked", and **STOP**. Do **not** fall through to Steps 1–4 — that would regenerate the main worktree's `config.md` through the symlink.
- **`JOIN-REFUSE-LINK`** — `.task` is a broken symlink or points somewhere other than the main worktree's `.task/`. Do nothing; tell the user to resolve `.task` manually, then **STOP**.
- **`JOIN-REFUSE-NOMAIN`** — the main worktree has no `.task/`. Do nothing; tell the user to run `/task:bootstrap` in the **main** worktree first, then **STOP**.

`.task-current` is **never** symlinked — it stays a real per-worktree file (each worktree points at its own active umbrella).

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
3. Run `git log -10 --oneline` to determine commit style and language.
4. Look for a project commit-format doc — check, in order: `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `.github/CONTRIBUTING.md`. If one exists, record its path; the Commit Format section will emit a `**Source:**` pointer to it instead of paraphrasing rules that may drift.

### Step 2: Interactive prompts

Always ask both prompts, regardless of whether `config.md` already exists. Present prompts in the user's language (fall back to English).

**Prompt A — Language** (for section `Language`):

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

**Prompt B — Testing Policy** (for section `Testing Policy`):

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

Always write the file from the full template, replacing any prior version. If `.task/config/config.md` already exists, overwrite it — note this in the output ("recreated existing config.md"). Manual edits to `config.md` will be lost; durable preferences should live in `CLAUDE.md` (which `/task:bootstrap` references) or be reproducible from the prompts.

Also pre-create the `.task/workspace/` directory (`mkdir -p .task/workspace`) so subsequent skills (`/task:design`, `/task:auto-roadmap`) have the container ready. The directory stays empty after init; each umbrella creates its own subfolder `.task/workspace/<task-id>/` when `/task:design` (or `/task:auto-roadmap`) runs, and the per-worktree pointer file `.task-current` (at the worktree root) names the active subfolder.

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
| Language | Full mode (pipeline-specific, comes from Prompt A) | Full mode |
| Testing Policy | Full mode (pipeline-specific, comes from Prompt B) | Full mode |
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

{Emit the block that matches Prompt A:
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

- **Mode:** `{always | on-demand | never}`   <!-- from Prompt B -->
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
- **Pipeline is invisible to the project.** Do not modify `CLAUDE.md`, `README.md`, `.gitignore`, or any other tracked file outside `.task/`. The pipeline must leave no trace in shared project files — anyone not using it should be unable to tell from the repo that it exists. All pipeline configuration lives under `.task/config/`; two sanctioned artifacts may sit outside `.task/`: (1) `.task-current` (one-line per-worktree pointer at the worktree root, written by `/task:design` (initial mode), by manual umbrella recovery (restoring a closed umbrella from `.task/log/`), and — transitively, via the first subagent's `/task:design --from` — by `/task:auto-roadmap`); (2) a `.task` **symlink** to the main worktree's `.task/`, materialized only by Step 0 join-mode in a linked worktree (a passive artifact — no executable code). Both `.task` and `.task-current` are git-excluded through `.git/info/exclude` (Step 3a / Step 0), which is per-clone and never committed.

### Step 3a: Set up local git exclusion

Ensure both `.task` (pipeline working tree) and `.task-current` (the per-worktree pointer file written by `/task:design` / manual umbrella recovery / `/task:auto-roadmap`'s first subagent) are excluded locally via `.git/info/exclude` so pipeline artifacts never get staged or pushed and the project's shared `.gitignore` stays untouched. The pattern is `.task` **without a trailing slash** on purpose: a slash (`.task/`) matches only a directory, so it would miss the `.task` **symlink** a linked worktree carries (see Step 0) and the symlink would surface in `git status`; the slash-less form matches both the real directory (main worktree) and the symlink. `.git/info/exclude` is repo-wide and shared across all worktrees, so this step needs to run only once per clone. Idempotent — skip lines that are already present.

1. If the current directory is not inside a git repository (no `.git/` directory or `git rev-parse --git-dir` fails) — skip this step and warn the user that exclusion was not configured.
2. Otherwise run:

   ```bash
   EXCLUDE=$(git rev-parse --git-path info/exclude)
   mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
   grep -qxF '.task'         "$EXCLUDE" || echo '.task'         >> "$EXCLUDE"
   grep -qxF '.task-current' "$EXCLUDE" || echo '.task-current' >> "$EXCLUDE"
   ```

3. Report whether each line was added or already present.

### Step 4: Verify

Ensure:
1. `.task/config/config.md` exists and contains all sections listed in the template:
   `Code Navigation`, `Code Editing`, `Library Documentation`, `Project Conventions`,
   `Build and Tests`, `Commit Format`, `Language`, `Testing Policy`,
   `Directories — Do Not Search`.
1a. `.task/workspace/` directory exists (empty after init — per-umbrella `<task-id>/` subfolders appear later, on first `/task:design` or `/task:auto-roadmap`).
2. All file references in the project (patterns.md, guardrails.md, etc.) exist.
3. Build/test commands match the project (whether emitted in full or as a reference summary).
4. Only actually available MCP tools are listed.
5. `Testing Policy` → `Mode` is one of `always | on-demand | never`.
6. `.git/info/exclude` contains both `.task` and `.task-current` (or the project is not a git repo and a warning was reported).
7. No project files outside `.task/` were modified by this skill (`.task-current` is created lazily by `/task:design` / manual umbrella recovery / `/task:auto-roadmap`'s first subagent, not by bootstrap).

## Output

**Join-mode (Step 0 short-circuited Steps 1–4)** — report only. Each report ends with the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)) naming the exact next action; the `JOIN-*` status tokens themselves are parser-facing and unchanged:
- `JOIN-LINK`: created `.task` → `<main>/.task` (absolute target), and the `.git/info/exclude` status. Footer: `→ Next: \`/task:design "<what you want to do>"\``.
- `JOIN-NOOP`: `.task` already linked to the main worktree; exclusion re-affirmed. Footer: `→ Next: \`/task:design "<what you want to do>"\``.
- `JOIN-REFUSE-LINK`: `.task` is a broken or foreign symlink; nothing was changed. Footer names the recovery action: `→ Next: resolve \`.task\` manually (remove or repoint it), then re-run \`/task:bootstrap\``.
- `JOIN-REFUSE-NOMAIN`: the main worktree has no `.task/`; nothing was changed. Footer: `→ Next: \`/task:bootstrap\` in the main worktree first`.

**Normal mode** — report:
- Path to the written `config.md`, and whether an existing file was overwritten.
- Chosen Language policy and Testing Policy mode.
- List of sections emitted in **reference mode** (pointing into `CLAUDE.md`) vs. **full mode**.
- Local git exclusion status: both `.task` and `.task-current` added to `.git/info/exclude`, already present, or skipped (not a git repo).
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
