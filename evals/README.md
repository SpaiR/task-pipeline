# Eval suite

Prompt-level cases for the six skills, run with `claude plugin eval` (early
access — see below). They cover what `tests/` cannot: the bash layer has unit
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
| `roadmap-to-workflow-unconfigured` | the launcher hard-stops and redirects instead of bootstrapping |

## Status

Written against the documented case format, **not yet executed**: on this machine
`claude plugin eval` reports "currently in early access" and refuses to run, so
the suite is unverified end to end. Two things to re-check once it is enabled:

- the absence-of-files graders (`no-artifact`, `wrote-nothing`) use a `files`
  target with `match: not_contains`, because the reference documents no
  dedicated "no such file" grader;
- whether `target: {source: file, path: …}` accepts a glob, which the file-content
  graders rely on to find the artifact without knowing the slug the run chose.

A red case here is not a build break — the suite is a quality signal for the
prompts, and it is not wired into CI.
