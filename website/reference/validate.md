# validate

An optional formal validator of `.task/` artifact formats. It is **not** a slash command, **not** a gate, and **never** invoked automatically — no hook calls it. Use it as a manual self-check.

## Usage

```text
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" [ all | task <slug> | roadmap <slug> | spec <slug> ]
```

## What it checks

**`task <slug>`** — `.task/task/<slug>.md`:
- line 1 is a `# <Title>`;
- a `---` separator is present;
- `## Description` is present;
- `## Plan` is optional — if present, it has ≥1 `### Step N:` block;
- `## Tests` is optional — if present, it has ≥1 `### Test N:` block;
- `## Execution` is present (presence only);
- each `Spec:` header's slug resolves to an existing spec — a miss is a `WARN`, not an error. The slug is read from the link text, so `Spec: [<slug>](../spec/<slug>.md)` and a bare `Spec: <slug>` check identically;
- a `Spec:` header whose link target isn't `../spec/<slug>.md` is a second `WARN` — the label and the target disagree, which is what a rename leaves behind.

**`roadmap <slug>`** — `.task/roadmap/<slug>.md`:
- ≥1 item heading `### - [ ] N. <title>` — the checkbox prefix is required;
- a heading that *nearly* matches is an error too — `[X]` uppercase, a double space around the checkbox, `####`, or a bullet-plus-number with the checkbox deleted. Such a heading is invisible to the autopilot, so catching it here is what stops an item from silently dropping out of a run. It is reported even when *every* heading has drifted;
- item numbers are unique;
- `**Dependencies:**` on an *unchecked* item is a no-dependency token (`—`, `-`, `none`, `n/a`) or a comma-separated list of item numbers; each number must name an item in the same file, and an item may not list itself. A space-separated `1 2` is reported as such, rather than being read as item `12`;
- the file uses LF line endings — with CRLF the driver keeps the trailing CR and loses `**Model:**` hints;
- each item carries `### Context` / `### Goal` / `### Outcomes` / `### Acceptance criteria` (Invariants optional);
- dangling `Spec:` headers `WARN`.

**`spec <slug>`** — `.task/spec/<slug>.md`: line 1 is a `# <Title>`; ≥1 `## N.` numbered section.

**`all`** — every task, roadmap, and spec file.

## Errors vs warnings

- An `ERROR` marks a genuine structural problem worth fixing before you hand a file to an implementing session.
- A `WARN` (e.g. a dangling `Spec:` reference — the pipeline's one cross-file check) never blocks anything.
- A missing `.task/CLAUDE.md` exits 2 — the one precondition failure that stops a run. The message names the path it looked at and points you at the four capture skills, each of which writes `.task/CLAUDE.md` inline on first use.

Because it's advisory, nothing forces you to run it *directly*. One caveat: `/task:roadmap-to-workflow` runs `validate.sh all` in its own setup gate and refuses to start when an `ERROR` is reported against the roadmap you picked — so for that command a roadmap `ERROR` is effectively blocking, and fixing it is the way forward. Errors on any other artifact never stop it. Its whole purpose is to catch a hand-edit that drifted from the format. See [Troubleshooting](/guide/troubleshooting#validate-fail) for reading the output.

## Does not

- Run automatically — no hook or skill invokes it; you call it by hand.
- Fix or rewrite files — it reports, never edits.
- Gate committing — a FAIL blocks nothing; the implementing session commits regardless. (`/task:roadmap-to-workflow` is the one command that does stop on a roadmap `ERROR`, before it starts — see above.)
