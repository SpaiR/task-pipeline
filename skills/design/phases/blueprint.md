# Phase: blueprint

> **Inputs:** `$ARGUMENTS` forwarded from `/task:design` — additional context if provided.
> **Tier:** B (MCP-first tooling).
> **Workspace:** Resolved via the active-task pointer (git per-worktree dir) → `.task/workspace/<task-id>/`.

Design an implementation plan for the task. Do not modify code — analysis and plan writing only.

## Step 1: Load context

Validate `.task/workspace/<task-id>/task.md` format before parsing:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" task
```

If it exits non-zero, **stop** and report the validator output; the task header is malformed and downstream parsers will misbehave.

1. Read `.task/config/config.md` — tool configuration. Use the MCP tools described there for code navigation; build/test commands for the "Verification" section.
2. Read `.task/workspace/<task-id>/task.md` — task description.
3. Resolve `tests_required` from `config.md` → `Testing Policy` → `Mode`:
   - `always` → `tests_required = true`.
   - `never` → `tests_required = false`.
   - `on-demand` → `tests_required = true` **only** if `task.md` Description explicitly asks for tests (phrases like "with tests", "add tests", "write tests"). If the Description is silent or ambiguous → `tests_required = false`. Responsibility is on the user.
   - If ambiguous and you are uncertain, ask the user a single yes/no question before writing the plan. In non-interactive runs (`/task:auto-roadmap`, where there is no user to ask) do not block — default to `false` per the rule above.

## Step 1.5: Read pinned spec decisions (if the item references them)

If `task.md` carries a `Roadmap: <path>` header **and** `## Description` contains a `### Spec references` sub-heading citing the roadmap's spec sidecar (entries of the form `<slug>.spec.md §N`):

1. Resolve the sidecar path the **same way the Clarity auditor does** (single resolution rule across both readers): the directory is the `Roadmap:` header's directory (`.task/roadmap/`); the filename is the `<name>.spec.md` token taken **verbatim from the citation** (`<name>.spec.md §N`), not reconstructed from the roadmap basename. In the normal auto-generated case these coincide (the roadmap skill writes both with the same slug); taking the filename from the citation keeps blueprint and the auditor reading the same file even if a citation was hand-edited.
2. Read the cited `## N.` sections. They are **pre-agreed technical anchors** from the roadmap brainstorm — the load-bearing decisions (chosen protocol, cross-cutting data shape, "X over Y because…") whose loss would distort the initiative. Treat each as a fixed point: `## Steps` must honor it, not re-derive a different choice.
3. **On a missing sidecar or a referenced section that doesn't exist:** in an interactive run — **stop and ask** the user to create the sidecar or correct the reference. In a non-interactive run (`/task:auto-roadmap`) — emit a loud `WARN:` line naming the unresolved reference and **proceed** on the behavioral `## Description` alone (the Description is still a complete input; reference integrity is enforced upstream by the Clarity auditor, not here).

Skip this step entirely when there is no `Roadmap:` header or no `### Spec references` pointing at the sidecar (manual tasks, or roadmap items with no pinned decisions).

## Step 2: Analyze codebase

If `## Description` originates from a behavioral roadmap item (it describes Outcomes/Invariants/Contracts but does not name project-specific files, types, or symbols), **you are the owner of technical choice** — pick files, types, symbols, and module boundaries here in `## Steps`; do not try to reconstruct them from the Outcomes prose. The behavioral form is deliberate: it leaves the implementation surface to blueprint so blueprint can compare alternatives instead of executing names already chosen upstream. **Exception — spec anchors (Step 1.5):** decisions pinned in `<slug>.spec.md` are *not* open choices; honor them as given. Everything the sidecar does not pin stays your free choice — that residual width is the point of keeping the roadmap behavioral.

Analysis algorithm:
1. From modules/packages/files in task.md — get a structural overview.
2. Read symbol bodies selectively — only those directly affected by the task.
3. Identify dependencies and usage locations.
4. Find existing patterns in neighboring code for reuse.
5. Assess the impact of changes on adjacent modules/components.

## Step 3: Write the plan

**Decide the implementation model first.** Assess task complexity and stamp `Implement-Model: <opus|sonnet|haiku>` directly below the `# Plan:` heading. Rubric — judge by **reasoning difficulty**, not by diff volume. Step/module counts alone are not a signal: a large context window lets the executor hold a wide, straightforward plan in full; they do not help it navigate a genuinely subtle one. Do not escalate `opus` on step or module count by itself.

- **`opus`** — genuine reasoning difficulty, regardless of size: subtle invariants the plan cannot fully spell out; cross-cutting coordination where a local mistake breaks something non-local; the plan intentionally leaves design-level judgment to the implementer. Since blueprint already did the hard design reasoning, this bucket is narrow for the implement stage — reach for it only when the *execution itself* still requires that judgment.
- **`sonnet`** — the strong default. Straightforward execution against a clear, fixed plan that still needs code-level judgment — including large multi-module changes with no subtle invariants, since a large context window holds the whole working set.
- **`haiku`** — mechanical edits with no behavioural branching and no judgment involved: textual / config / template substitution, one-to-one renames, changes against an already-fixed contract. Stay conservative on very large or broad mechanical sweeps — Haiku's lower ceiling can still be tripped by sheer breadth even when each individual edit is trivial.

When uncertain, default to `sonnet`. The stamp is parser-validated by `validate.sh` and load-bearing for `/task:auto-roadmap` — it selects the model used to spawn `auto-roadmap-build-runner` for the implement stage. Harmless in manual flows.

Write the plan to `.task/workspace/<task-id>/plan.md` strictly following this template:

```markdown
# Plan: {short title from task.md}

Implement-Model: {opus | sonnet | haiku}

## Scope

- Affected modules/directories: {list}
- New files: {list with full paths}
- Modified files: {list with full paths}
- Breaking changes: {none / description}

## Steps

### Step 1: {Action}

- File: `{full path}`
- Action: create | update | refactor | delete
- Goal: {Detailed description — what this step does, why it is needed in the context of the task, and what the result must look like after execution. Enough for the executor to understand intent and the expected final state without guessing. Do not shorten for brevity.}
- Touches: {Specific symbols affected — classes, functions, methods, interfaces, exports, dependencies. Full names, no placeholders.}
- Logic (only if non-obvious): pseudocode block clarifying branching, conditions, or non-trivial flow. Omit entirely when `Goal` + `Touches` leave no ambiguity.

### Step N: ...

## Tests

<!-- Include this section ONLY if `tests_required` is true (see Step 1). Omit it entirely otherwise — its presence is the single signal that /task:build's implement phase uses to enforce tests. -->

Red-first specs. Each test is written before its implementation; each implementation step that satisfies a test must reference the test number.

### Test 1: {Behavior under test}

- File: `{full path to test file}`
- Framework: `{e.g. JUnit 5 / Vitest / pytest}`
- Arrange: {preconditions / fixtures}
- Act: {call / event}
- Assert: {expected result}
- Expected failure before implementation: {error message or condition}

### Test N: ...

## Verification

- Build: `{command from config.md or CLAUDE.md}`
- Tests: `{command from config.md or CLAUDE.md}`
- Checklist:
  - [ ] {Specific expected behavior}

## Risks (optional)

- {Potential problems and dependencies. Informational only — no downstream consumer parses this section. Omit if there is nothing concrete to flag.}
```

## Rules

- Dry technical text, no fluff — but `Goal` must be detailed enough that the executor understands what to do, why, and what the expected result is. Do not compress `Goal` into a single line if the task has nuance.
- Use full paths from the project root.
- `Goal` describes intent and outcome in plain language — not implementation syntax.
- `Touches` lists specific symbols (classes, functions, methods, interfaces, exports) — full names, no placeholders like `...`.
- `Logic` is optional. Include it only when branching, conditions, or flow cannot be expressed clearly in plain language. Use pseudocode (not runnable code); placeholders like `...` are allowed only inside a `Logic` block.
- If a step creates a new file — `Goal` must describe its role; `Touches` must list its exports and dependencies.
- If a step modifies existing code — `Touches` must name the exact functions/methods and `Goal` must describe the nature of the change.
- Build and test commands — from `config.md`.
- If `tests_required` is true — `## Tests` must be present and non-empty, and each implementation step in `## Steps` must reference by number the tests it satisfies. If `tests_required` is false — do **not** emit `## Tests` at all.
- `Implement-Model:` is mandatory — exactly `opus`, `sonnet`, or `haiku`. Parser-validated by `validate.sh`; load-bearing for `/task:auto-roadmap` (selects the build-runner model). When unsure, emit `sonnet` (safe default).

## Forbidden

- Modify code — no file other than `.task/workspace/<task-id>/plan.md`.
- Run builds — analysis only.
- Guess — if something is unclear from task.md, note it in the "Risks" section.
- Read entire files without necessity.

## Output

- Path to the created `.task/workspace/<task-id>/plan.md` and a brief summary of the planned steps.
- The routine next step is `/task:build` to execute the plan. (If the plan itself needs a critical rework, `--phase refine` is a repair-level option — see docs/troubleshooting.md.)
