---
name: ship
description: 'Commit the change and close the task — one commit + full close, confirmed once. Slug auto-derived from summary.'
disable-model-invocation: true
user-invocable: true
model: haiku
---

Commit the completed task, then fully close it. Commit the task changes, then archive `plan.md` / `audit.md` / `summary.md` (plus `task.md`) to `.task/log/<task-id>/<N>-<slug>/`, remove the entire workspace subfolder `.task/workspace/<task-id>/`, and delete `.task-current`. Any orchestrator state from a failed `/task:auto-roadmap` run (`auto-error.log`) is swept along with the subfolder.

**Input:** `$ARGUMENTS` — none. There is no slug argument: the commit slug is always auto-derived from `.task/workspace/<task-id>/summary.md` (primary) or `.task/workspace/<task-id>/task.md` Description (fallback).

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gates in `commit-context.sh` (Step 1) and `close.sh` (Step 4) remain authoritative.

**Precondition (hard-stop) — active-task pointer + workspace.** The per-worktree active-task pointer (git per-worktree dir) must exist and the subfolder it names must contain a `task.md`. If not — stop and tell the user. Full close allows an empty Description (used to drop a task after an aborted run).

## Step 0: Removed-forms guard

Three once-supported invocations are gone; all must fail loud, not silently misparse (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)):

- If `$ARGUMENTS` contains `--full` — stop and tell the user:
  > `--full` was removed. `/task:ship` already fully closes the task — run `/task:ship` (no flag).
- If `$ARGUMENTS` contains `--next` — stop and tell the user:
  > `--next` was removed. `/task:ship` now always closes the task (subtask-transition mode was dropped) — run `/task:ship` (no flag).
- If `$ARGUMENTS` contains any other **non-flag positional token** — stop and tell the user:
  > A hand-supplied commit slug was removed. The slug is now auto-derived from `summary.md` — run `/task:ship` with no arguments.

`/task:ship` takes no arguments. Proceed to Step 1 only when `$ARGUMENTS` is empty.

## Step 1: Gather commit context

Run the context script:

```bash
bash "${CLAUDE_SKILL_DIR}/commit-context.sh"
```

> **Run verbatim.** Don't add `CLAUDE_SKILL_DIR=…` inline before `bash` — Claude Code substitutes `${CLAUDE_SKILL_DIR}` at skill-load time, and bash same-line assignments don't take effect until *after* variable expansion (the path would resolve empty → `bash "/commit-context.sh"`). If substitution clearly failed (literal `${CLAUDE_SKILL_DIR}` visible), use `bash -c '…'`: `CLAUDE_SKILL_DIR="<abs-skill-dir>" bash -c 'bash "${CLAUDE_SKILL_DIR}/commit-context.sh"'`. Same rule for `close.sh` in Step 5.

It outputs all needed context in one block:

- `.task/config/config.md` — tool configuration (commit format).
- **Referenced commit-format doc(s)** — when `config.md` → "Commit Format" emits `**Source:** <path>` (e.g. `CONTRIBUTING.md`), the script bundles that file as `===== referenced: <path> =====`. The referenced doc is the source of truth for commit rules; any inline summary in `config.md` is a hint.
- `.task/workspace/<task-id>/summary.md` — **primary source** for commit message content. Falls back to `task.md` if missing.
- `git status`, `git diff --stat`, `git log -5 --oneline` — change overview + recent commit style.

The script enforces the hard-stop precondition (exits if `.task/config/config.md` is missing).

## Step 2: Compose commit message

Compose the commit message **mechanically from the task's own artifacts — there is no free-text authoring step**. Both parts are artifact-sourced:

- **Header** (`type` / optional `scope` / subject) — derived from `summary.md`'s `**Solution:**` line, shaped by the configured commit format.
- **Body** (the "why" bullets) — derived from `summary.md`'s `**Problem:** / **Decision:** / **Result:**` fields.

`task.md`'s `## Description` is the fallback source **only** when `summary.md` is missing. The user is never asked to write commit text from scratch; the sole place free text may enter is the optional **edit** branch of the Step 3 confirmation.

If the context block contains `===== referenced: <path> =====` sections, that doc is the source of truth — types, scope enums, description form, length limits, body structure, AI-trailer convention. Apply it directly. Inline content in `config.md` is a hint; the referenced doc wins on conflicts. Follow any project-specific `Co-authored-by` trailer format verbatim — it overrides any default trailer the harness would otherwise emit.

**Fallback:** If `config.md` does not specify a commit format and no doc is bundled, fall back to `${CLAUDE_PLUGIN_ROOT}/skills/_lib/templates/conventional-commits.md` as the default specification.

## Step 3: Staging and commit

- Stage **only** files related to the task (per `Touches` in `plan.md` and the diff).
- **Do not stage** any files from `.task/` (task.md, plan.md, audit.md, summary.md, config/) — these are working artifacts.
- **Do not stage** the active-task pointer — it is the per-worktree pointer, living inside git's per-worktree dir (outside the work tree); it can never enter a commit.
- **Do not stage** `.env`, credentials, or other secrets.
- **Single confirmation (interactive).** On every interactive ship, present the staged file list and the composed commit message **once**, then ask **exactly once** using the canonical **accept / decline / edit** grammar (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar), section (b)): **accept** — commit as shown and run the close; **decline** — abort without committing; **edit** — adjust the file list or message, then commit and close. The prompt always fires — there is no "if in doubt" conditional.
- **Non-interactive carve-out.** When ship runs non-interactively — the `auto-roadmap-item-runner` executing these Steps inline, where there is no user to answer — skip the prompt and commit the composed message directly, mirroring that runner's "No interactive blocking" rule (`agents/auto-roadmap-item-runner.md`). The interactive checkpoint stays intact for users; the autopilot ship stays unattended.

Create the commit using HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
{commit message}
EOF
)"
```

## Step 4: Determine slug for close

The slug is **always** auto-derived — there is no override path. Resolve the active workspace subfolder via `<task-id>` = `cat "$(git rev-parse --path-format=absolute --git-path task-current)"`:

1. Read `.task/workspace/<task-id>/summary.md` first (**primary source**). If it exists and conveys what the subtask did, generate the slug from it.
2. **Only if `summary.md` is missing or insufficient** — fall back to the "Description" section in `.task/workspace/<task-id>/task.md`.

**Slug format:** `{type}-{1-4-words}`, kebab-case, English, where `{type}` is one of `feat`, `fix`, `chore`. Always English regardless of `config.md` → "Language" — the slug is a filesystem identifier, not user-facing text.

Examples:
- `feat-add-export-dialog`
- `fix-node-pin-layout`
- `chore-cleanup-dead-code`

## Step 5: Run close

The archive location is standard and chosen mechanically — **ship never asks the user where to file the closed task.** `close.sh` computes the next free numeric prefix `<N>` under `.task/log/<task-id>/` and combines it with the Step 4 slug to form the fixed path `.task/log/<task-id>/<N>-<slug>/`. There is no location prompt and no override argument.

Run:

```bash
bash "${CLAUDE_SKILL_DIR}/close.sh" <slug>
```

> Same `${CLAUDE_SKILL_DIR}` invocation rule as Step 1 — run verbatim, no inline `CLAUDE_SKILL_DIR=…` prefix.

If `close.sh` returns ERROR — relay the message to the user and stop. (The commit from Step 3 is already in git history — the user can amend or revert as needed; pipeline does not auto-rollback git operations.)

## Forbidden

- Modify project code — only `.task/workspace/<task-id>/`, `.task/log/` (via `close.sh`), `.task-current` (removed by `close.sh`), and `git` operations from Step 3.
- Stage anything inside `.task/` or `.task-current`.
- Run builds or tests in this skill — `/task:build` already verified before ship.
- Touch `task.md` directly. `close.sh` removes the entire subfolder.

## Output

- Commit hash + commit message (from Step 3).
- List of committed files.
- Path to the archive subfolder (from `close.sh` output).
- End with the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)) — the task is closed and archived:
  - If the task was roadmap-tracked and `close.sh` reports remaining items:
    > → Done. Task closed and archived under `.task/log/`.
    > → Next: `/task:design --from <roadmap-slug>` for the next roadmap item.
  - Otherwise:
    > → Done. Task closed and archived under `.task/log/`.
    > → Next: `/task:design "<your next task>"` to start a new task.
