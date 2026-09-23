---
name: to-roadmap
description: 'Capture a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items.'
argument-hint: '[initiative]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Fix a **multi-task initiative** (phases, dependencies, or more than a couple of atomic steps) into `.task/roadmap/<slug>.md`. Multi-task counterpart to `/task:to-task` / `/task:to-plan` (which each fix one task). Depth is fixed: one roadmap file, flag-free.

**Input:** `$ARGUMENTS` — a rough description of the initiative, or a reference back to a prior discussion in this conversation ("build a roadmap from what we discussed").

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for the output structure. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" roadmap`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the pipeline root: `.task/roadmap/<slug>.md` below means `$AI_DIR/roadmap/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent`** → this skill is intake-capable: read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template — then continue. No confirmation chip; a wrong detected value is fixed by editing the file.
3. **`CONFIG: present`** → leave the file untouched: it is user-owned, and only `task.root` and the `.git/info/exclude` line are restored when missing.
4. `ROADMAPS:` lists the roadmaps that already exist, with progress — the capture flow's context step matches structural style against them and its save step's slug-collision check reads the same list, so neither needs a listing call of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

There is no full-scan validate call here: the save step validates the one file it writes, and pre-existing artifacts are checked on demand with `validate.sh all`, never as an entry gate.

### Steps 1–5: Precondition, context, harvest, draft, save, self-check

Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-capture.md` § **Core** and follow it — its too-small precondition, then steps 1 (context) through 5 (the post-save self-check). It is the single owner of the roadmap capture flow: the harvest-or-brainstorm branch, the decision routing, the drafting self-check, the slug-collision guard, the write and the validate call. Step 0's `AI_DIR:` and `ROADMAPS:` are the inputs it expects from you; the digest below is yours.

### Step 6: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file:

```
Wrote `.task/roadmap/<slug>.md`
{Title}
Items: {N} tasks across {M} phases — recommended order: 1 → 2 → 4 → 3 → 5 …
- 1. {item title}
- 2. {…}
Specs referenced: {slug, …}   (or "none"; plus any decision flagged for a `/task:to-spec` follow-up)
validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

- On a result that is **not** clean, append `re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — `validate` is not a slash command, so it is worth spelling out. Omit it on a clean result.
- Print the self-check findings summary from Core step 5 (or "clean / minor only").
- The file is already written — to change anything, just say so.
- End with the next-step footer, naming the slug in **both** halves so either is pasteable as-is: `→ Next: \`/task:roadmap-to-workflow <slug>\` (run the whole roadmap) or \`/task:to-task <slug>#1\` (pick up the first item by hand — any item number works).`

## Forbidden

Everything in `roadmap-capture.md` § **Forbidden** — it binds every roadmap the flow writes.
