---
name: to-roadmap
description: 'Capture a multi-task initiative into `.task/roadmap/<slug>.md` — a phase-grouped backlog of ready-to-pick-up items together with its `## Architecture`: components, interfaces between items, per-item sketches.'
argument-hint: '[initiative]'
disable-model-invocation: true
user-invocable: true
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
---

Fix a **multi-task initiative** (phases, dependencies, or more than a couple of atomic steps) into `.task/roadmap/<slug>.md` — the behavioral items **and** the technical layer every item's planner follows: an `## Architecture` section naming the components the initiative builds or changes, what crosses between items, a module-level sketch per item and the technical ordering. Multi-task counterpart to `/task:to-task` (which fixes one task). Always a new file, always with its architecture, flag-free.

**Input:** `$ARGUMENTS` — a rough description of the initiative, or a reference back to a prior discussion in this conversation ("build a roadmap from what we discussed").

**Format contract:** [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the single source of truth for the output structure, and [§ Roadmap architecture section](../../docs/contract.md#roadmap-architecture-section) for the section inside it. This file describes the authoring flow that produces it.

## Instructions

### Step 0: Setup gate

The entry state, gathered before this skill reached you — no tool call of your own:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" capture`

[docs/contract.md § Helpers](../../docs/contract.md#helpers) owns that block's shape. Read it, then act:

1. `AI_DIR:` is the `.task` directory: `.task/roadmap/<slug>.md` below means `$AI_DIR/roadmap/<slug>.md`, **never a cwd-relative path** ([contract § Setup-gate categories](../../docs/contract.md#setup-gate-categories)).
2. **`CONFIG: absent`** → this skill is intake-capable: read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/setup.md` and follow it — it owns the sub-steps and the `.task/CLAUDE.md` template — then continue.
3. **`CONFIG: present`** → leave the file untouched: never rewrite it, re-detect its values or "repair" a missing section ([contract § `.task/CLAUDE.md` format](../../docs/contract.md#taskclaudemd-format)).
4. `ROADMAPS:` lists the roadmaps that already exist, with progress — the capture flow's context step matches structural style against them and its save step's slug-collision check reads the same list. `SPECS:` lists the specs its architecture may cite. Neither needs a listing call of its own.

If that block arrived unexpanded — the command line itself rather than its output — the preprocessing did not fire: run that command yourself and continue exactly as above.

### Steps 1–7: Context, decomposition, technical context, architecture, draft, save, self-check

Read `${CLAUDE_PLUGIN_ROOT}/skills/_lib/roadmap-capture.md` § **Core** and follow it — steps 1 (context) through 7 (the post-save self-check). It is the single owner of the roadmap capture flow: the decomposition's harvest-or-brainstorm branch, the module-level read of the code, the architecture's harvest-or-rounds branch, the decision routing, the drafting self-check, the slug-collision guard, the one write and the validate call. Step 0's `AI_DIR:`, `ROADMAPS:` and `SPECS:` are the inputs it expects from you; the digest below is yours.

### Step 8: Output — digest

Print the structural digest of what was written (convention (b)) as message text — enough for the user to judge at a glance whether to open the file:

```
Wrote `.task/roadmap/<slug>.md`
{Title}
Items: {N} tasks across {M} phases — recommended order: 1 → 2 → 4 → 3 → 5 …
1. {item title}
2. {…}

Architecture: {C} components, {I} interfaces, {S} item sketches
- `{component}` — {new | existing}, {role in a few words}

Interfaces: {#2 → #4, #5 `Name`; … | none}

Specs referenced: {slug, …}   (or "none"; plus any decision flagged for a `/task:to-spec` follow-up)

validate: {OK — 0 errors, N warning(s) | the FAIL lines}
```

- One line per component: the component map is what every later planner follows, so this is the user's one glance to catch a misplaced boundary.
- On a result that is **not** clean, append `re-check after editing: bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — `validate` is not a slash command, so it is worth spelling out. Omit it on a clean result.
- Print the self-check findings summary from Core step 7 (or "clean / minor only").
- The file is already written — to change anything, items or architecture, just say so.
- End with the next-step footer, naming the slug in **both** options so each is pasteable as-is: `→ Next: \`/task:roadmap-to-workflow <slug>\` (run the whole roadmap — every item's planner follows this architecture) or \`/task:to-task <slug>#1\` (pick up one item by hand — any item number works).`

## Forbidden

Everything in `roadmap-capture.md` § **Forbidden** — it binds every roadmap the flow writes.
