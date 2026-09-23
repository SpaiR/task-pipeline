# Eval suite

Prompt-level cases for six of the seven skills — `to-roadmap` has no case of its own yet —
run with `claude plugin eval` (early access, see below). They cover what `tests/` cannot: the bash layer has unit
tests, but whether a *skill* actually fires, writes the artifact it promises and
prints the conventions is a property of the prompt, and only a real run shows it.

```bash
claude plugin eval .                                  # every case, this plugin
claude plugin eval --case 'to-plan*' .                # one case
claude plugin eval --tag capture .                    # by tag
```

Each case is a directory: `prompt.md` (frontmatter plus the user prompt in its
body) and one file per grader under `graders/`. Every case starts from a scratch
project with no `.task/`, so the capture cases also exercise first-run setup.

| Case | Asserts |
|------|---------|
| `to-task-from-chat` | the skill fires, an artifact is written, the footer is printed, no roadmap or spec is authored |
| `to-plan-fresh` | the artifact validates clean and carries `### Step 1:` with real `**Touches:**` paths |
| `grill-writes-nothing` | nothing is written under `.task/`, and exactly one load-bearing question is asked |
| `to-spec-pins` | the digest lists every pin, and the spec carries numbered `## N.` decisions |
| `to-architecture-fresh` | with no roadmap yet, the skill writes one plus its `## Architecture` section with `### Components`, and the digest carries the `Architecture:` line |
| `roadmap-to-workflow-unconfigured` | the launcher hard-stops and redirects instead of bootstrapping |

## Status

`to-architecture-fresh` has been executed (`claude plugin eval --case
'to-architecture*' --ablation none --allow-tools Bash Write Edit .`) and passes.
The other five cases were written against the documented case format before the
runner was available, and running this one showed three things they get wrong:

- **The Skill tool must be listed.** Runs are in don't-ask mode, so a case whose
  `allowed_tools` omits `Skill` has the skill call denied and the run stops
  before writing anything — only the `tool_used: Skill` grader passes.
- **No inline regex flags.** Patterns are JavaScript regexes: `(?m)` throws, and
  multiline goes in a `flags: m` key instead.
- **A file target takes one literal path**, relative to the run's workspace — a
  glob fails with "does not exist". Name the slug in the prompt (as
  `to-architecture-fresh` does) or grade the digest instead; `file_exists` is the
  grader that accepts a glob.

Until those are fixed, a red result on the other cases says nothing about the
prompts.

Still missing a case: `to-roadmap`. Its output is a multi-phase file whose items
each need a `**Ready description:**` blockquote, so a useful grader there is a
larger piece of work than the six above. `to-architecture-fresh` exercises its
capture flow indirectly — fresh mode runs the same shared `roadmap-capture.md`
Core — but grades only the architecture layer on top.

A red case here is not a build break — the suite is a quality signal for the
prompts, and it is not wired into CI.
