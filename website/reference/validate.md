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
- each `Spec: <slug>` header resolves to an existing spec — a miss is a `WARN`, not an error.

**`roadmap <slug>`** — `.task/roadmap/<slug>.md`:
- ≥1 item heading `### - [ ] N. <title>` — the checkbox prefix is required;
- item numbers are unique;
- each item carries `### Context` / `### Goal` / `### Outcomes` / `### Acceptance criteria` (Invariants optional);
- dangling `Spec:` headers `WARN`.

**`spec <slug>`** — `.task/spec/<slug>.md`: line 1 is a `# <Title>`; ≥1 `## N.` numbered section.

**`all`** — every task, roadmap, and spec file.

## Errors vs warnings

- An `ERROR` marks a genuine structural problem worth fixing before you hand a file to an implementing session.
- A `WARN` (e.g. a dangling `Spec:` reference — the pipeline's one cross-file check) never blocks anything.
- A missing `config.md` exits 2 — the one precondition failure that stops a run.

Because it's advisory, nothing forces you to run it. Its whole purpose is to catch a hand-edit that drifted from the format. See [Troubleshooting](/guide/troubleshooting#validate-fail) for reading the output.
