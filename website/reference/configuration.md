# Configuration

All project policy lives in `.task/CLAUDE.md`, written inline on the first use of a capture skill. You never run a separate setup command.

It is a **nested `CLAUDE.md`**, not a bespoke config format. Claude Code loads a `CLAUDE.md` from a subdirectory as soon as a session reads a file in that directory — so an implementing session and `task:code-reviewer`, which both open `.task/task/<slug>.md`, get your settings without being told to.

## First-run setup

On a fresh project, the first `to-task` / `to-plan` / `to-roadmap` / `to-spec`:

1. reads `CLAUDE.md` and your commit conventions, detects language/stack, build/test commands, and a testing policy;
2. writes `.task/CLAUDE.md`, records `git config --local task.root`, and excludes `.task` via `.git/info/exclude`;
3. reports what it wrote, then continues into the capture you asked for:

   > Wrote `.task/CLAUDE.md` — Language: follow task.md Description; Testing Policy: on-demand.

There is nothing to confirm. If a detected value came out wrong, edit the file — which is also the answer to every later change.

## The file is yours

Setup writes `.task/CLAUDE.md` **once** and never rewrites it. An existing file is left untouched even when a section is missing or a value has gone stale, so hand edits survive every later capture. Only two things are repaired silently when they go missing: the `git config task.root` anchor and the `.task` line in `.git/info/exclude`.

To regenerate the file from scratch, delete it and run any capture skill again.

## What it holds

| Section | Meaning |
|---|---|
| **Language** | By default the Description is in your language; everything parser-stable (headers, the `## Execution` pointer, commit trailers) stays English. |
| **Testing Policy** | `always` / `on-demand` *(default)* / `never`. In `on-demand`, `## Tests` is written only if the Description explicitly asks for it ("needs tests", "with tests", "cover with tests"). |
| **Build and Tests** | The command(s) `task:code-reviewer` runs end to end before it commits its fixes. A red run fails the item; when nothing is declared, the reviewer reports the skip in words rather than implying a green run. |
| **Commit Format** | A pointer to your existing `CONTRIBUTING.md`; failing that, rules derived from `git log`; failing that, a pointer to the plugin's bundled Conventional Commits template. |
| **Code Navigation / Code Editing** | Tool priority — which MCP tools or built-ins the executing session prefers. Omitted when your project has nothing beyond the built-ins. |
| **Executing a task** | The instructions an implementing session follows: read `Spec:` anchors, implement the Plan, commit, spawn the reviewer, tick the roadmap checkbox. |

Language, Testing Policy, Build and Tests, Commit Format and Executing a task are always written — consumers look them up by heading, and read a missing one as *nothing declared*. When your own `CLAUDE.md` already documents one, the section stays and its body shrinks to a `**Source:**` pointer rather than repeating the content. Only Code Navigation / Code Editing are dropped outright when there is nothing to say.

## Executing a task lives here, in one copy

Each task file ends with a one-line pointer:

```markdown
## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

The instructions themselves are in `.task/CLAUDE.md`, once. Edit them and the change applies to every task — including ones captured weeks ago. Rewording the pointer inside a task file, on the other hand, changes nothing but that file.

Two limits are worth knowing, and they are why the pointer exists at all:

- The automatic load fires for file-read tools only. A session that opens a task with `cat` or `sed` never triggers it — the pointer is what still gets it to the instructions.
- A nested `CLAUDE.md` is **not** re-injected after `/compact` (a project-root one is). It reloads the next time the session reads a file under `.task/`.

## Language policy in practice

The split is deliberate: **content** follows your language, **contract strings** stay English. Your `## Description` and Plan prose can be in any language, while `## Description`, `### Step N:`, `Roadmap:`, `Spec:` (including the slug in a header's link text), the `## Execution` pointer, and commit trailers are always English — because parsers and the executing session key on them.
