---
name: ship
description: 'Commit the change and close the task — default closes the umbrella and cleans up; `--next` transitions to the next subtask. Slug auto-derived from summary.'
disable-model-invocation: true
user-invocable: true
model: haiku
---

Commit the completed task and close the umbrella entirely (or transition to the next subtask with `--next`).

**Two modes:**

1. **Default — fully close the umbrella.** Commit task changes, then archive `plan.md` / `audit.md` / `summary.md` (plus `task.md`) to `.task/log/<task-id>/<N>-<slug>/`. The entire workspace subfolder `.task/workspace/<task-id>/` is removed and `.task-current` deleted. Any orchestrator state from a failed `/task:auto-roadmap` run (`auto.lock`, `auto-error.log`) is swept along with the subfolder.
2. **`--next` — subtask transition.** Commit task changes, then archive `plan.md` / `audit.md` / `summary.md` to `.task/log/<task-id>/<N>-<slug>/`. Keep `.task/workspace/<task-id>/task.md` in place with **the body of `## Description`** cleared. `.task-current` stays. The next subtask of the same umbrella reuses both the header and any `## Decisions` below.

**Input:** `$ARGUMENTS` — `[--next]`. There is no slug argument: the commit slug is always auto-derived from `.task/workspace/<task-id>/summary.md` (primary) or `.task/workspace/<task-id>/task.md` Description (fallback).

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) — bash gates in `commit-context.sh` (Step 1) and `close.sh` (Step 4) remain authoritative.

**Precondition (hard-stop) — `.task-current` + workspace.** `.task-current` must exist at the worktree root and the subfolder it names must contain a `task.md`. If not — stop and tell the user. **`--next` mode** additionally requires non-empty `## Description` in `task.md` (something happened in the subtask). **Default mode (full close)** allows empty Description (used to drop the umbrella after the last subtask transition or after an aborted run).

## Step 0: Removed-forms guard

Two once-supported invocations are gone; both must fail loud, not silently misparse (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)):

- If `$ARGUMENTS` contains `--full` — stop and tell the user:
  > `--full` was removed. The default `/task:ship` already fully closes the umbrella — run `/task:ship` (no flag).
- If `$ARGUMENTS` contains any **non-flag positional token** (anything that is not `--next`) — stop and tell the user:
  > A hand-supplied commit slug was removed. The slug is now auto-derived from `summary.md` — run `/task:ship` (or `/task:ship --next`) with no slug.

Only `--next` is a valid token. Proceed to Step 1 only when `$ARGUMENTS` is empty or exactly `--next`.

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

Use the commit format from `config.md` → "Commit Format". Base content primarily on `summary.md`.

If the context block contains `===== referenced: <path> =====` sections, that doc is the source of truth — types, scope enums, description form, length limits, body structure, AI-trailer convention. Apply it directly. Inline content in `config.md` is a hint; the referenced doc wins on conflicts. Follow any project-specific `Co-authored-by` trailer format verbatim — it overrides any default trailer the harness would otherwise emit.

**Fallback:** If `config.md` does not specify a commit format and no doc is bundled, fall back to `${CLAUDE_PLUGIN_ROOT}/skills/_lib/templates/conventional-commits.md` as the default specification.

## Step 3: Staging and commit

- Stage **only** files related to the task (per `Touches` in `plan.md` and the diff).
- **Do not stage** any files from `.task/` (task.md, plan.md, audit.md, summary.md, config/) — these are working artifacts.
- **Do not stage** `.task-current` — it is the per-worktree pointer, excluded via `.git/info/exclude`; never enters a commit.
- **Do not stage** `.env`, credentials, or other secrets.
- If in doubt — show the staged file list and the composed commit, then ask for confirmation using the canonical **accept / decline / edit** grammar (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)): **accept** — commit as shown; **decline** — abort without committing; **edit** — adjust the file list or message, then commit.

Create the commit using HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
{commit message}
EOF
)"
```

## Step 4: Determine slug for close

The slug is **always** auto-derived — there is no override path. Resolve the active workspace subfolder via `<task-id>` = `cat .task-current`:

1. Read `.task/workspace/<task-id>/summary.md` first (**primary source**). If it exists and conveys what the subtask did, generate the slug from it.
2. **Only if `summary.md` is missing or insufficient** — fall back to the "Description" section in `.task/workspace/<task-id>/task.md`.

**Slug format:** `{type}-{1-4-words}`, kebab-case, English, where `{type}` is one of `feat`, `fix`, `chore`. Always English regardless of `config.md` → "Language" — the slug is a filesystem identifier, not user-facing text.

Examples:
- `feat-add-export-dialog`
- `fix-node-pin-layout`
- `chore-cleanup-dead-code`

## Step 5: Detect mode and run close

- `--next` flag (anywhere in `$ARGUMENTS`) → subtask-transition mode.
- Otherwise → full-close mode (the default).

Run:

```bash
bash "${CLAUDE_SKILL_DIR}/close.sh" [--next] <slug>
```

> Same `${CLAUDE_SKILL_DIR}` invocation rule as Step 1 — run verbatim, no inline `CLAUDE_SKILL_DIR=…` prefix.

If `close.sh` returns ERROR — relay the message to the user and stop. (The commit from Step 3 is already in git history — the user can amend or revert as needed; pipeline does not auto-rollback git operations.)

## Forbidden

- Modify project code — only `.task/workspace/<task-id>/`, `.task/log/` (via `close.sh`), `.task-current` (cleared by `close.sh` in default full-close mode; kept in `--next`), and `git` operations from Step 3.
- Stage anything inside `.task/` or `.task-current`.
- Run builds or tests in this skill — `/task:build` already verified before ship.
- Touch `task.md` directly. `close.sh` removes the entire subfolder (default full close) or clears Description (`--next`).

## Output

- Commit hash + commit message (from Step 3).
- List of committed files.
- Path to the archive subfolder (from `close.sh` output).
- Mode used (`umbrella close` or `subtask transition` / `--next`).
- End with the canonical next-step footer (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)):
  - default mode (full close) — the umbrella is complete, so use the terminal form plus a fresh-start line:
    > → Done. Umbrella closed and archived under `.task/log/`.
    > → Next: `/task:design "<your next task>"` to start a new umbrella.
  - `--next` mode — Description was cleared; the next cycle fills it (manually or via `/task:design` → idea) then plans it:
    > → Next: `/task:design`
