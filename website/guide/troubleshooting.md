# Troubleshooting

First-run problems, then the edge cases of a solo, hook-free, pointer-free pipeline where enforcement is convention, not a gate.

## First run

### /task: commands don't appear after installing {#commands-appear}

**Symptom** — typing `/task:` shows nothing; no `/task:to-task`, `/task:to-plan`, etc.

**Cause** — the `task` plugin isn't installed/enabled in this session, or the marketplace was never added.

**Fix**

```text
/plugin marketplace add https://github.com/SpaiR/task-pipeline.git
/plugin install task@task-pipeline
```

Then reopen the `/` menu. If it was already installed, make sure it isn't disabled (`/plugin`).

### "config.md not found"

**Symptom** — a skill stops with `.task/config/config.md not found`.

**Cause** — every skill except `to-task` / `to-plan` / `to-roadmap` / `to-spec` requires `config.md`, and it hasn't been written in this project yet. There is no separate `bootstrap` command — setup is folded inline into those four capture skills.

**Fix** — run any of `/task:to-task`, `/task:to-plan`, `/task:to-roadmap`, or `/task:to-spec`. Each detects language and test policy, asks for one confirmation, writes `config.md`, records `git config task.root`, and continues into the capture. `/task:roadmap-to-workflow` is *not* setup-capable by design — if you hit this there, run a capture skill first, then retry.

### .task/ shows up in git status

**Symptom** — `.task/` appears as untracked in `git status`.

**Cause** — the local git exclusion wasn't written (e.g. `.task/` was created before setup ran, or setup ran outside a git repo).

**Fix** — run any capture skill again; the inline setup is idempotent and re-adds `.task` to `.git/info/exclude`. This uses `.git/info/exclude`, not `.gitignore`, on purpose — the pipeline stays invisible to teammates and never touches a tracked file.

### validate.sh ends with "FAIL N error(s)" {#validate-fail}

**Symptom** — `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all` ends with `FAIL <N> error(s)`, preceded by `ERROR <label>: <message>` lines.

**Cause** — a task or roadmap file drifted from the expected format: a missing `# <Title>` first line, no `---` separator, no `## Description`, a `## Plan` with zero `### Step N:` blocks, or a roadmap item missing its checkbox prefix or a required sub-heading.

**Fix** — read each `ERROR <label>:` line (it names the file and the exact problem) and fix the artifact by hand — these are plain Markdown files. Re-check with `validate.sh all`. It's an optional self-check, not a gate — only genuine structural `ERROR`s are worth fixing before you hand the file to an implementing session; a `WARN` never blocks anything.

### validate.sh warns "no such spec … (dangling reference)"

**Symptom** — a `WARN` names a `Spec: <slug>` header pointing at a `.task/spec/<slug>.md` that doesn't exist.

**Cause** — the header names a spec that was never written, was renamed, or was deleted. This is the pipeline's one cross-file check, and only ever a `WARN`.

**Fix** — capture the missing spec with `/task:to-spec` (using that slug), correct the slug in the header, or drop the header if the reference is stale.

## Working with roadmaps

### A roadmap item's checkbox never gets ticked

**Cause** — the auto-mark step is conditional on the task file carrying both `Roadmap:` and `Source item: #N` header lines, above the `---`. If the file was hand-created, those headers were edited out, or the item number doesn't match, the executing session has nothing to key the flip off of.

**Fix** — check the top of `.task/task/<item-slug>.md` for both header lines and a correct `#N`. Add them if missing (ASCII, above `---`) and re-run, or just tick the box yourself — it's a plain `- [ ]` → `- [x]` edit.

### A roadmap-to-workflow run stops on a failed item

**Cause** — by design: the driver is stop-on-FAIL. A later wave never starts if an earlier item didn't land cleanly, since a later item may depend on it.

**Fix** — read the failure digest, fix the item (edit `.task/task/<item-slug>.md`, or re-implement it by hand), tick its checkbox, then rerun `/task:roadmap-to-workflow <slug>`. Completed items stay checked, so the rerun only picks up the unchecked remainder.

### A worktree can't find .task/

**Cause** — worktrees resolve the shared `.task/` through `git config --local task.root` (fallbacks: an upward walk, then `dirname(git-common-dir)`). The anchor can be missing (repo set up by an older version) or wrong.

**Fix** — run any capture skill from the stuck worktree; its inline setup records `task.root` and every worktree then resolves the same `.task/`. To point it at an existing `.task/` yourself: `git config --local task.root /abs/path/containing/dot-task` (the directory that *contains* `.task`, not `.task` itself).

## Finding your own state

There is no active-task pointer to lose or heal — the artifact's path is the only handle.

```text
ls .task/task/
# every task file you've captured; a task stays here until you delete it

grep -L '^## Plan' .task/task/*.md
# task files with a Description but no Plan yet (to-task-only captures)

grep '^### - \[ \]' .task/roadmap/<slug>.md
# every item still unchecked in that roadmap
```

Once you've found the file, any session picks it up with `implement .task/task/<slug>.md`.

→ See also the maintainer-facing [troubleshooting notes](https://github.com/SpaiR/task-pipeline/blob/main/docs/troubleshooting.md) in the repo.
