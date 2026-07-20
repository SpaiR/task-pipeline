# Configuration

All project policy lives in `.task/config/config.md`, written inline on the first use of a capture skill. You never run a separate setup command.

## First-run setup

On a fresh project, the first `to-task` / `to-plan` / `to-roadmap` / `to-spec`:

1. reads `CLAUDE.md` and your commit conventions, detects language/stack, build/test commands, and a testing policy;
2. shows the detected values and poses one `AskUserQuestion` confirmation:
   > Detected — Language: follow task.md Description; Testing policy: on-demand.

   with **Accept / Edit / Decline** chips;
3. on Accept, writes `config.md`, records `git config --local task.root`, and excludes `.task` via `.git/info/exclude`.

This is the one place a capture asks before writing — it's confirming *auto-detected* environment that was never part of your discussion, not distilled content.

## What config.md holds

| Setting | Meaning |
|---|---|
| **Language** | By default the Description is in your language; everything parser-stable (headers, the `## Execution` block, commit trailers) stays English. |
| **Testing Policy → Mode** | `always` / `on-demand` *(default)* / `never`. In `on-demand`, `## Tests` is written only if the Description explicitly asks for it ("needs tests", "with tests", "cover with tests"). |
| **Commit Format** | Either a pointer to your existing `CONTRIBUTING.md`, or rules derived from `git log`. |
| **Code Navigation / Code Editing** | Tool priority — which MCP tools or built-ins the executing session prefers. |
| **Project Conventions** | Short pointers into your `CLAUDE.md` where it already documents a section. |

## Idempotency

`config.md` is regenerated in full whenever setup runs again — so re-running a capture in a project where the git-exclude or `task.root` anchor went missing simply repairs it. After an interruption mid-capture, implementation picks up from the task file as it stands; there's no partial state to reconcile.

## Language policy in practice

The split is deliberate: **content** follows your language, **contract strings** stay English. That means your `## Description` and Plan prose can be in any language, while `## Description`, `### Step N:`, `Roadmap:`, `Spec:`, the `## Execution` block, and commit trailers are always English — because parsers and the executing session key on them.
