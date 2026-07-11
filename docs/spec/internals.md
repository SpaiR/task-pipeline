# Internals

Repository layout, bash helpers, agent classes, plugin manifests, skill frontmatter contract, and editing protocol. Consolidates what was `architecture.md` + `frontmatter.md` + `editing-protocol.md` in 0.2.x.

## Architecture

A collection of user-invocable Claude Code skills implementing a linear "task pipeline" — intake → design → build → ship. Skills live in `skills/<name>/SKILL.md`. The three operational skills (`design`, `build`, `ship`) are **orchestrators** — thin SKILL.md files that detect the current phase from artifact state and dispatch to **phase companion files** at `skills/<name>/phases/<phase>.md`. The companion files carry the dense per-phase prompt; SKILL.md keeps the dispatch + control flow scannable.

Several skills ship sibling bash helpers:

- `ship/close.sh` — archives a subtask. In the default full-close mode it sweeps the per-umbrella workspace subfolder and `.task-current`; `--next` keeps `task.md` and clears only the Description body.
- `ship/commit-context.sh`, `build/audit-context.sh` — gather skill context (files, iteration counter, diff bundle) in one call. Each sources `_lib/preamble.sh` (which in turn sources `_lib/resolve-ws.sh` via `source_resolve_ws`) to set `WS_DIR` from `.task-current`.
- `auto-roadmap/auto-roadmap-context.sh` — read-only context gatherer for `/task:auto-roadmap`. Enforces all three Step 0 hard-stop preconditions (config.md, no `.task-current`, no stale `workspace/*/auto.lock`) and emits roadmap validation / available-roadmaps listing / unchecked-items list for the wizard. No `WS_DIR` resolution — the orchestrator operates on the workspace ROOT (umbrella container).
- `validate/validate.sh` — formal artifact-format validator; called by every context script after the `config.md` check, and inline at Step 0 of orchestrator skills. `task` / `plan` subcommands resolve through `_lib/resolve-ws.sh`; `all` tolerates a missing `.task-current` (used by the PreToolUse hook and orchestrator Step 0).
- `_lib/preamble.sh` — shared bash preamble for context scripts and helpers. Exposes `require_config_md`, `source_resolve_ws`, `run_validator <subcmd> [target]`, `set_workspace_root`, and the `emit_section` / `emit_file` output helpers. Sources `_lib/resolve-ws.sh` at load and runs `find_ai_dir` so `AI_DIR` is resolved via the upward walk before any gate below reads `.task` (idempotent with the later `source_resolve_ws`). Caller MUST bootstrap `SCRIPT_DIR` itself (4-line symlink-resolving idiom) before sourcing. `require_config_md` is the first gate a freshly created worktree hits; when `.task` is absent and cwd is a *linked* git worktree it emits a `/task:bootstrap` join-mode hint (the check is duplicated, not shared with `resolve-ws.sh`, per the fail-closed bash-gate invariant).
- `_lib/resolve-ws.sh` — shared workspace resolver: reads `$TASK_ID_OVERRIDE` > positional arg > `.task-current`, exports `TASK_ID` and `WS_DIR=$AI_DIR/workspace/<task-id>/`, fails loud on missing / stale state. `AI_DIR` itself is resolved by **`find_ai_dir`** (run at source time, and callable explicitly): a git-style upward walk from `$PWD` to `/` that sets `AI_DIR` to the first ancestor's `.task` whose `.task/config/config.md` exists (fallback: nearest ancestor with a `.task-current`, then `$CLAUDE_PROJECT_DIR/.task`; else the relative `.task` — identical to the historical default so calls from outside any project still fail cleanly). The discovered `AI_DIR` is an **absolute** `<root>/.task` path with the `.task` component appended literally (never `cd`'d into), so a linked-worktree `.task` symlink is preserved and `dirname "$AI_DIR"` still points at the worktree root where the local `.task-current` lives. `find_ai_dir` only acts when `AI_DIR` is unset, so a caller that pins it keeps control. macOS-safe (no `realpath`/`readlink -f`). On its error paths the `_linked_worktree_without_task` helper swaps the generic message for the same `/task:bootstrap` join-mode hint (git subprocesses stay off the happy path — gated behind `! -e "$AI_DIR"`).
- `_lib/phase-detect.sh` — detects the next pipeline phase by inspecting workspace state. Used by `/task:design` and `/task:build` orchestrator SKILL.md to dispatch to the right companion phase file without forcing the user to pass `--phase`.
- `_lib/touches-gate.sh` — files-level scope gate for `/task:build` audit auto-fix. Reads `File:` and `Touches:` lines from each `### Step N` block in `plan.md`, sanitizes values (strips backticks, parenthesized descriptions, and trailing prose after em-dash `—` / en-dash `–` / ` -- ` / `:`), and resolves them to a whitelist — `File:` paths added directly when they exist on disk; `Touches:` tokens either added as paths (extension/`/` heuristic) or symbol-searched via `git grep -l -Fw`. Tokens that resolve to zero files emit a stderr `WARN:` line so malformed entries are diagnosable instead of silently shrinking the whitelist. Exit 0 = in scope; exit 1 = out of scope (violating files on stderr); exit 2 = usage error or no `File:`/`Touches:` entries found.
- `_lib/roadmap.sh` — shared roadmap utilities: `resolve_roadmap_path`, `roadmap_mtime`, `roadmap_progress_counts`, `list_roadmap_items`. NOT auto-sourced from `preamble.sh` — most context scripts never touch roadmaps.
- `_lib/derive-task-id.sh` — single source of truth for the task-id derivation algorithm used by `/task:design --from` (Mode 2 Step 2).
- `_lib/auto-locks.sh` — shared read/write for the orchestrator sentinel `workspace/<task-id>/auto.lock`. Exposes `read_lock_field <file> <key>` and `write_lock <path> kv1 kv2 ...` (atomic `set -o noclobber`).
- `_lib/fail-log.sh` — shared writer for the `auto-error.log` block protocol. Functions: `append_fail_log`, `append_orchestrator_fail_log`. Dual-mode (source vs. `bash fail-log.sh {fail|orchestrator-fail}`).
- `_lib/templates/summary.md` — shared `summary.md` template + rendering rules consumed by `build/phases/implement.md`.
- `_lib/templates/conventional-commits.md` — fallback commit-format spec consumed by `ship/SKILL.md` when `config.md` → "Commit Format" does not specify a project-specific format.

### Phase companion files

The three operational skills decompose their phase logic into companion files (`skills/<name>/phases/<phase>.md`):

- `skills/design/phases/{open,idea,blueprint,refine}.md` — 4 phases of the design stage.
- `skills/build/phases/{implement,audit}.md` — 2 phases of the build stage.

The orchestrator SKILL.md detects the right phase via `_lib/phase-detect.sh`, then reads the companion file and follows its instructions verbatim. The companion file is the load-bearing prompt for that phase; the orchestrator owns only dispatch and (for build's audit phase) the bounded auto-fix loop.

`/task:ship` does NOT use companion files — commit + close fit comfortably in a single SKILL.md.

### `agents/` — auditor-class + executor-class

Nine named subagents:

- **Auditor-class — build-audit lenses** (`audit-{reuse,simplicity,clarity}-auditor.md`) — read-only `tools:` allowlist (no `Edit`/`Write`), used by `/task:build` audit phase on non-trivial diffs. The read-only contract is runtime-enforced from the frontmatter, not just the prompt.
- **Auditor-class — roadmap-refine lenses** (`audit-roadmap-{coverage,decomposition,clarity}-auditor.md`) — read-only `tools:` allowlist (same as build-audit lenses), used by `/task:roadmap --refine` in a parallel three-lens fanout over the roadmap file itself (not a code diff). Same runtime-enforced read-only contract; shares `agents/_shared/audit-rules.md` with the build-audit lenses.
- **Executor-class — item cycle** (`auto-roadmap-item-runner.md`) — spawned once per item by the `/task:auto-roadmap` driver loop; runs the whole per-item cycle in its own context. It spawns the design + build runners below, fans out the three build-audit lenses itself, runs `/task:build` audit + `/task:ship` inline, and returns a compact report-card digest. `tools:` and `model:` intentionally undeclared — inherits both from the parent interactive session (and overrides only its build-runner spawn's model).
- **Executor-class — design half** (`auto-roadmap-design-runner.md`) — narrow-scope executor spawned by `auto-roadmap-item-runner`. Runs `/task:design` (open → blueprint phases) for one roadmap item inline in its own subagent context, returning with `plan.md` (including the `Implement-Model:` stamp) on disk. `tools:` and `model:` intentionally undeclared — inherits both from the item-runner (parent-session model).
- **Executor-class — build half** (`auto-roadmap-build-runner.md`) — narrow-scope executor spawned by `auto-roadmap-item-runner` immediately after design-runner OK. Runs `/task:build` implement phase only for one roadmap item, leaving the diff uncommitted for the item-runner's audit + ship. `tools:` intentionally undeclared (inherits parent toolset); `model:` intentionally undeclared in frontmatter — the item-runner sets it per spawn via `Agent.model` override, sourced from each item's `plan.md → Implement-Model:` (`opus|sonnet|haiku`). This is the mechanism for the per-stage model split — implement can run cheaper than design + audit.

Rules inherited from nested phase files (one quick-fix max, append-only artifacts, mandatory verification, MCP-first tooling) live in `agents/_shared/runner-rules.md` as the canonical registry; the registry distinguishes which runner each rule applies to. Edits to a source-of-truth file (`build/phases/implement.md` / `docs/spec/invariants.md`) must update the shared file in the same commit.

Agents ship bundled with the `task` plugin (under `agents/` in this repo). `subagent_type` values in `Agent(...)` calls MUST carry the `task:` plugin prefix (e.g. `task:audit-reuse-auditor`, `task:audit-roadmap-coverage-auditor`, `task:auto-roadmap-item-runner`, `task:auto-roadmap-design-runner`, `task:auto-roadmap-build-runner`) — without the prefix the runtime cannot resolve the agent and silently routes to the catch-all `claude` agent, producing a "0 tool uses Done" no-op.

The design and build runners are deliberately kept as **leaves** — design-runner covers open + blueprint, build-runner covers implement, and neither spawns anything. Audit's lens fanout and ship live one level up, in `auto-roadmap-item-runner`. Nested subagent spawning is supported by the runtime (depth cap of 5; this cycle reaches depth 2); keeping the runners scoped is a design choice that lets their heavy per-phase context be discarded on return, not a platform limitation.

## `.claude-plugin/` — two manifests, single-plugin layout

- `plugin.json` — plugin `task` (name, version, metadata; consumed by Claude Code at install/load).
- `marketplace.json` — marketplace `task-pipeline` (single-entry catalog with `source: "./"`, so the same repo serves as both marketplace root and plugin source).

`version` lives only in `plugin.json`.

The standard `hooks/hooks.json` at the plugin root is auto-discovered — **do not** add a `hooks` field to `plugin.json` pointing at it.

No build/test/lint. Work here is editing markdown (occasional bash) and reasoning about pipeline semantics.

## Skill frontmatter

```yaml
---
name: <slug>
description: '<one line — when to use → what it does>'
disable-model-invocation: true
user-invocable: true
model: <claude-tier | inherit>   # optional; see deviations below
---
```

### `description` style

Each user-invocable skill's `description` is one line, written for the person scanning Claude Code's `/` menu: lead with when to reach for the skill, then what it does, and name the literal command / flags where they matter. Keep it third-person and free of internal codes or phase taxonomy — the `/` menu is the first structural signal a new user sees, so it must read as "when do I need this", not as pipeline bookkeeping. `validate` is the only skill without a user-facing description (it is not user-invocable).

### Deviations from the template

Kept in sync with the actual `skills/*/SKILL.md` frontmatter:

- `model: haiku` — mechanical skills (`bootstrap`, `ship`); tight templates with near-deterministic output.
- `model: inherit` — `validate` only.
- `validate` is the **single exception** to `user-invocable: true` — it runs `user-invocable: false` because it's only invoked by context scripts and the PreToolUse hook, never typed by the user. Its slash form `/task:validate` does not exist.
- No `model:` — `auto-roadmap/SKILL.md` and reasoning-heavy orchestrators (`design`, `build`, `roadmap`); they inherit the parent session's model. For `auto-roadmap` the driver and the `auto-roadmap-item-runner` it spawns (plus that item-runner's design-runner, audit orchestration, and ship) stay on the user's session model, while `auto-roadmap-build-runner` is spawned by the item-runner with a per-item `Agent.model` override read from `plan.md → Implement-Model:` (`opus|sonnet|haiku`) — see [auto-roadmap.md § Per-stage model split](auto-roadmap.md).

## Editing protocol

- Treat each `SKILL.md` as a prompt contract for a future Claude instance in a target project. Output templates, section headers, and step numbering are part of the contract — downstream skills key off `## Description`, `## Decisions`, `## Iteration N`, `### Issues`, the `# [task-id] ...` header pattern, the `---` separator, etc.
- Treat each phase companion file (`skills/<name>/phases/<phase>.md`) the same way — the orchestrator reads them verbatim, so step numbering and section headers there are also load-bearing.

### Coordinating template changes to `task.md` header/separator

Four files share the contract — coordinate any template change across all four:

- `ship/close.sh` parses line 1 with `sed` (`[TASK-ID]` extraction) **and** scans the header above the first `---` with `awk` to locate `^Roadmap: ` + `^Source item: #<N>` for auto-mark; on a `--next` (subtask-transition) close it then rewrites with another `awk` filter that clears the body of `## Description` only.
- `validate/validate.sh` checks the same shape with regex (line-1 / `---` / `## Description` ERRORs; `Roadmap:`-without-`Source item:` WARN).
- `design/phases/open.md` — the create-template for the file. Both manual-mode and from-roadmap-mode templates must stay in sync.

A template change to that header line (e.g. translating the word) breaks both `close.sh`'s awk filter and `validate.sh`'s regex at once.

### Coordinating `/task:auto-roadmap` artifact changes

The autopilot owns two artifacts whose schemas are split across multiple files — coordinate any change to either:

- **`workspace/<task-id>/auto.lock` sentinel schema** (`roadmap`, `roadmap_mtime`, `start_item`, optional `items_filter`, `started`, `orchestrator=auto-roadmap`). Producer: `auto-roadmap-item-runner.md` Step 2 (first item only) via `skills/_lib/auto-locks.sh write`, from run-level fields the driver passes in the spawn prompt. Spec: `docs/spec/artifact-contract.md`. Adding or removing a field touches **all** of: the item-runner's `auto-locks.sh write` call, the driver's Step 2 in-memory variable list + the run-level fields in its Substep 3.3 spawn prompt, and the field-list in the spec.
- **Runner return-line contracts** — exact OK / FAIL strings for the three roadmap runners. Each producer must change together with its consumer's parser:
  - `auto-roadmap-item-runner.md` — OK (last line): `OK: item #<N> shipped (--next|full) — <sha>`, preceded by the report-card digest (fields incl. `task_id:` always, `roadmap_mtime:` on `--next`). FAIL: `FAIL at <stage>: <reason>. …` with `<stage>` ∈ `design | lock | model-extract | implement | audit | ship` and the post-open (`See <path>.`) / pre-open (`No workspace was created …`) tails. **Consumer: `auto-roadmap/SKILL.md` Substep 3.4 regexes + digest greps.**
  - `auto-roadmap-design-runner.md` — OK: `OK: item #<N> "<title>" — plan.md ready, awaiting implement`. FAIL (post-open): `FAIL at <stage>: <reason>. Artefacts remain in .task/workspace/<task-id>/. See <error-log-path>.`. FAIL (pre-open): `FAIL at <stage>: <reason>. No workspace was created — nothing to clean up.`. **Consumer: `auto-roadmap-item-runner.md` Step 1 regexes.**
  - `auto-roadmap-build-runner.md` — OK: `OK: item #<N> "<title>" — diff uncommitted, ready for audit`. FAIL (post-open only — workspace is guaranteed): `FAIL at implement: <reason>. Artefacts remain in .task/workspace/<task-id>/. See <error-log-path>.`. **Consumer: `auto-roadmap-item-runner.md` Step 4 regexes.**

### Coordinating worktree join-mode / `.git/info/exclude`

`/task:bootstrap` is the single sanctioned writer of `.git/info/exclude`, and it touches that file in two places — keep them consistent:

- **Step 3a** (normal bootstrap, in the main worktree) and **Step 0 join-mode** (linked worktree) both write the two exclusion lines `.task` + `.task-current`. The pattern is `.task` **without a trailing slash** on purpose: a slash matches only a directory and would let the `.task` symlink in a linked worktree surface in `git status`. Both blocks resolve the file via `git rev-parse --git-path info/exclude` (correct from any worktree — the file is shared in the common git dir).
- **Step 0 join-mode** creates the `.task` symlink (absolute, physical target via `cd … && pwd -P`; `realpath`/`readlink -f` are avoided — not built-in on macOS) and refuses rather than overwriting a broken/foreign symlink or a real `.task`. The user-facing hint that points people at join-mode lives in `_lib/preamble.sh` (`require_config_md`) and `_lib/resolve-ws.sh` (`_linked_worktree_without_task`) — if the join command name or trigger changes, update both hints and `docs/spec/artifact-contract.md` (the `.task` symlink artifact entry) in the same commit.

### Coordinating phase file changes

When editing a phase companion file (`skills/design/phases/<phase>.md` or `skills/build/phases/<phase>.md`):

- The orchestrator SKILL.md's phase auto-detect logic (in `_lib/phase-detect.sh`) keys off artifact-state signals (file existence, `## Description` emptiness, `pending fix` markers). If a phase file changes what artifacts it produces or consumes, update `phase-detect.sh` in the same commit.
- Phase output templates (`task.md` template in `open.md`, `summary.md` references in `implement.md`, `audit.md` table schema in `audit.md`) are part of the artifact contract — see `docs/spec/artifact-contract.md`.

### Style

Prefer Markdown headers + **bold** over decorative XML. XML is reserved for genuine semantic metadata Markdown can't express.

### Keep `README.md` and the spec in sync with the skills

Whenever a skill is added/removed/renamed or changes its contract, update both in the same commit:

- `README.md` — pipeline diagram, per-skill summary, artifact list, typical scenarios, comparison tables.
- `docs/spec/*.md` — artifact contract table, three-tier nav list, relevant invariants. The root `CLAUDE.md` checklist gets touched only if a *new invariant* is added or an existing one is removed.

`README.md` is in Russian and aimed at humans; the spec is in English and aimed at the editing assistant. Both are part of every skill change, not a follow-up.

### CHANGELOG

**`CHANGELOG.md` is updated only on explicit user request** — never autonomously, even for user-visible changes. When the user asks for a changelog entry, apply the rules below; otherwise leave the file alone.

Eligible changes for an entry (when requested): new/removed/renamed skill, changed slash-command form, new/removed artifact in the contract, new install/migration step, changed plugin manifest, hook addition/removal. Internal cleanups typically don't need an entry even when requested.

Format: Keep a Changelog (`Added` / `Changed` / `Removed` / `Deprecated` / `Fixed` / `Security`); breaking changes go under `Changed (breaking)` / `Removed (breaking)` and need a migration note. The current development line lives under `## [Unreleased]` until a tag is cut.

**CHANGELOG entries are written in English**, regardless of any project's `config.md` → "Language" — it is the plugin's public release log.

Commit-format and versioning rules for *this* repo also live in `CONTRIBUTING.md` (root) — keep its commit-format and versioning sections in sync with `skills/_lib/templates/conventional-commits.md` and with `.claude-plugin/plugin.json`'s version field.

### Version-bump rule

**Never change `.claude-plugin/plugin.json`'s `version` field without explicit user confirmation.** This is the plugin's public release identifier — bumping it is a release decision, not an editorial one. Surface a proposal to the user (current version, suggested next version, why), and only edit after confirmation.

The same rule applies to cutting an `## [Unreleased]` section into a numbered release in `CHANGELOG.md`. Moving entries *into* `## [Unreleased]`, or editing existing entries inside it, is fine without confirmation.
