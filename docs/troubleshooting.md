# Troubleshooting

First-run problems you may hit as a new user, then edge cases in a v3 world — a solo, hook-free, pointer-free pipeline where enforcement is convention, not a gate.

## First run

### `/task:` commands don't appear after installing

**Symptom** — typing `/task:` shows nothing; no `/task:to-task`, `/task:to-plan`, etc.

**Cause** — the `task` plugin isn't installed/enabled in this session, or the marketplace was never added.

**Fix** —

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

Then reopen the `/` menu. If it was already installed, make sure it isn't disabled (`/plugin`).

### `ERROR: …/config.md not found.`

**Symptom** — a skill stops with `.task/config/config.md not found`.

**Cause** — every skill except `to-task` / `to-plan` / `to-roadmap` requires `.task/config/config.md`, and it hasn't been written in this project yet. There is no separate `bootstrap` command in v3 to run first — setup is folded inline into the three capture skills.

**Fix** — run any of `/task:to-task`, `/task:to-plan`, or `/task:to-roadmap`. On a fresh project each detects language and test policy, presents both for one accept/decline/edit confirmation, writes `.task/config/config.md`, records `git config task.root`, and continues straight into the requested capture. If you specifically hit this from `/task:roadmap-to-workflow`, that skill is *not* intake-capable by design (a roadmap can't exist without config, so a missing config there means something upstream is broken) — run a capture skill first, then retry.

### `.task/` shows up in `git status`

**Symptom** — `.task/` appears as untracked in `git status`.

**Cause** — the local git exclusion wasn't written, e.g. `.task/` was created before the inline setup ran, or setup ran outside a git repo.

**Fix** — run any capture skill again; the inline setup step is idempotent and re-adds `.task` to `.git/info/exclude`. This uses `.git/info/exclude`, not `.gitignore`, on purpose — the pipeline stays invisible to teammates and never touches a tracked file. There's no active-task pointer to worry about either way — v3 has none.

### `validate.sh` ends with `FAIL N error(s)`

**Symptom** — `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` (or `task <slug>` / `roadmap <slug>`) ends with `FAIL <N> error(s), <M> warning(s)`, preceded by `ERROR <label>: <message>` lines.

**Cause** — a `task.md` or roadmap file drifted from the expected format: a missing `# <Title>` first line, no `---` separator, no `## Description`, a `## Plan` present with zero `### Step N:` blocks, or a roadmap item missing its checkbox prefix or a required `### Context`/`### Goal`/`### Outcomes`/`### Acceptance criteria` sub-heading.

**Fix** — read each `ERROR <label>:` line (it names the file and the exact problem) and fix the artifact by hand — these are plain Markdown files. Re-check with `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. `validate.sh` is an optional self-check, not a gate — nothing stops you from continuing with a `WARN`, only genuine structural `ERROR`s are worth fixing before you hand the file to an implementing session.

## Working with roadmaps

### A roadmap item's checkbox never gets ticked

**Symptom** — you ran `implement .task/task/<item-slug>.md` and it completed, but `.task/roadmap/<slug>.md` still shows `- [ ]` for that item.

**Cause** — the auto-mark step in `## Execution` is conditional on the task file carrying both `Roadmap:` and `Source item: #N` header lines, above the `---` separator. If the file was hand-created, or `Roadmap:`/`Source item:` were edited out, or the item number doesn't match, the executing session has nothing to key the checkbox flip off of.

**Fix** — check the top of `.task/task/<item-slug>.md` for both header lines and a correct `#N`. If they're missing, add them (ASCII, above `---`) and re-run the implementing session, or just tick the box yourself — it's a plain `- [ ]` → `- [x]` edit in a Markdown file, no script involved.

### A `roadmap-to-workflow` run stops on a failed item

**Symptom** — the run prints a `FAIL #N <item-slug> <what failed>` digest line and stops instead of continuing to the next wave.

**Cause** — this is by design: the driver is stop-on-FAIL. A later wave is never started if an earlier item didn't land cleanly, since a later item may depend on it.

**Fix** — read the failure digest, fix the item (edit `.task/task/<item-slug>.md`, or just re-implement it by hand with `implement .task/task/<item-slug>.md`), tick its checkbox once it's done, then rerun `/task:roadmap-to-workflow <slug>` — completed items stay checked, so the rerun only picks up the unchecked remainder. If the Workflow tool itself isn't available in your environment, `roadmap-to-workflow` falls back to running items one at a time by hand instead of failing outright.

### A worktree can't find `.task/`

**Symptom** — in a second git worktree, a skill stops with `config.md not found` even though the repo is set up elsewhere.

**Cause** — worktrees resolve the shared `.task/` through `git config --local task.root` (fallback: the upward walk, then `dirname(git-common-dir)`). This normally needs no setup, but the anchor can be missing (the repo was set up by an older version) or wrong (a bare repo whose `.task/` lives somewhere non-default).

**Fix** — run any capture skill (`to-task` / `to-plan` / `to-roadmap`) from the worktree that's stuck; its inline setup records `task.root` and every worktree then resolves the same `.task/`. To point the pipeline at an existing `.task/` yourself, set it directly: `git config --local task.root /abs/path/containing/dot-task` (the directory that *contains* `.task`, not `.task` itself).

## No pointer — finding your own state

### "How do I find my in-flight task?"

There is no active-task pointer in v3 to lose or heal — the artifact's path is the only handle. To see what's captured and not yet implemented:

```text
ls .task/task/
# every task file you've captured; a task stays here until you delete it —
# git history is the record, there is no archive to dig through

grep -L '^## Plan' .task/task/*.md
# task files with a Description but no Plan yet (to-task-only captures)
```

To see where a roadmap stands:

```text
grep '^### - \[ \]' .task/roadmap/<slug>.md
# every item still unchecked in that roadmap
```

Once you've found the file you want, any session picks it up with `implement .task/task/<slug>.md` — no pointer to re-point, nothing to restore from an archive.
