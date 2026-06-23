# Phase: refine

> **Inputs:** `$ARGUMENTS` forwarded from `/task:design` — additional context if provided.
> **Tier:** B (MCP-first tooling).
> **Workspace:** Resolved via `.task-current` → `.task/workspace/<task-id>/`.

Critically review the implementation plan — propose alternatives, discuss trade-offs, and refine the plan with the user.

**Read policy** (Tier B override): reading **relevant symbol bodies** is permitted and expected (alternatives evaluation requires checking existing patterns). Do not read entire files — symbol-scoped reads keep context focused.

## Step 1: Load context

Validate pipeline artifacts before reading them:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" plan
```

If either exits non-zero, **stop** and report the validator output.

1. Read `.task/config/config.md` — tool configuration.
2. Read `.task/workspace/<task-id>/task.md` — task description. This defines the goal and constraints.
3. Read `.task/workspace/<task-id>/plan.md` — implementation plan. This is the object of review.
4. Verify that `plan.md` is **not empty** and has a "Steps" section. If empty — stop and tell the user: "Plan is empty. Run `/task:design` first (blueprint phase will auto-detect)."

## Step 2: Identify key decisions

Read the plan and extract **architectural decisions** — places where the plan chose one approach over alternatives. Focus on:

- **Structural choices**: new class vs extending existing, new file vs modifying existing.
- **Pattern choices**: inheritance vs composition, direct call vs event/callback, sync vs async.
- **Placement choices**: which module/package/directory.
- **API choices**: method signatures, public vs internal, parameter design.
- **Scope choices**: what's included vs what's deferred.

Skip trivial decisions (variable names, import order, formatting). Only flag decisions where a realistic alternative exists.

## Step 3: Research alternatives

For each key decision, use code navigation tools to:

1. **Find analogies** — how similar problems are solved elsewhere in the codebase.
2. **Check consistency** — does the proposed approach match established patterns in the project.
3. **Assess impact** — who calls/uses the symbols being changed, what breaks or needs updating.

This step requires reading code. Use the MCP code-navigation tools listed in `config.md` (priority order) to read only the symbols relevant to each decision. Do NOT read entire files.

## Step 4: Output review

Present the review in this format:

```
## Plan Review

### Decision 1: {Short description}

**Plan proposes:** {What the plan does — 1-2 sentences}

**Alternative A:** {Concrete alternative — what to do differently}
- Pros: {specific advantages}
- Cons: {specific disadvantages}

**Alternative B (if exists):** ...

**Codebase context:** {What analogies/patterns were found — with references}

**My take:** {Which option seems better and why — but the user decides}

### Decision 2: ...

### Issues (if any)
- {Concrete problems found: missing files, wrong signatures, broken dependencies}
```

**Rules for the review:**
- Maximum **5 decisions** per review. Pick the most impactful ones.
- Each alternative must be **concrete** — not "could do it differently" but "use ExistingMapper.addProfile() instead of new PresetMapper class".
- Always include **trade-offs** — no alternative is free.
- "My take" is a recommendation, not a directive. Present it as opinion.
- If the plan is solid and no meaningful alternatives exist — say so. Do not invent critique.

## Step 5: Await user decisions

After outputting the review — **wait for the user's response**. Do not continue automatically.

The user may:
- Accept the plan as-is.
- Choose an alternative for one or more decisions.
- Ask for deeper analysis of a specific decision.
- Propose their own alternative.

## Step 6: Evaluate responses for new questions

After receiving the user's decisions, check whether any choice introduces new considerations:

- If choosing alternative A for decision 1 conflicts with decision 3 — flag it.
- If a user's custom alternative raises new questions — ask them.
- Prefix follow-up questions with `[Follow-up]`.
- Wait for answers before proceeding.

Repeat until all decisions are resolved or the user signals to move on.

## Step 7: Update the plan

After all decisions are finalized:

1. Read the current `.task/workspace/<task-id>/plan.md`.
2. Assess the scope of changes:
   - **Minor changes** (1-2 steps affected): edit only the affected steps in place.
   - **Major changes** (flow/structure changes, steps reordered/added/removed): rewrite the plan fully, preserving the template structure.
3. **Preserve the layered step structure**: every step must keep `Goal` (detailed intent and expected result), `Touches` (concrete symbols affected), and — only when logic is non-obvious — `Logic` (pseudocode sketch). Do not collapse these layers into a single flat `Details` block. When adding new steps introduced by a decision, write them in the same three-layer form.

## Step 8: Save and record

Write the file directly — no in-chat preview, no confirmation prompt. The user reviews and edits in the file itself.

1. Save the updated plan to `.task/workspace/<task-id>/plan.md`.
2. Append a section at the end of `.task/workspace/<task-id>/plan.md`:

```markdown

## Decisions

- **{Decision topic}**: {Accepted choice and reasoning — brief}
```

3. Record only decisions that **changed** the plan or **confirmed a non-obvious choice**. If the user accepted the original plan for a decision — do not record it.
4. Print the path and a brief summary of what was changed. Tell the user to open the file to review/edit.

## Forbidden

- Modify project code — only `.task/workspace/<task-id>/plan.md`.
- Run builds or tests.
- Propose alternatives without codebase evidence — every alternative must be grounded in existing patterns or concrete technical reasoning.
- Critique for the sake of critique — if the plan is good, say so.
- Change the task scope — alternatives must solve the same task, not a different one.
- Make decisions for the user — present options, let the user choose.
