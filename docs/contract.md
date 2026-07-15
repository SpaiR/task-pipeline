# Artifact contract — the v3 task-pipeline protocol

Single source of truth for how the chat-first task pipeline stores state and how skills hand work to each other. Maintainer-facing.

v3 is **not** an orchestration engine — it is a **context-serialization protocol**. The user discusses a task freely in chat, then runs **one short skill** that distils the discussion into a fixed-format Markdown artifact under `.task/`. A fresh or isolated Claude Code session then **executes that artifact directly** — there is no execution skill. Orchestration, verification, review, and commits are delegated to the platform (`/verify`, `/code-review`, dynamic Workflows, the Tasks API).

Enforcement is traded for **convention** (this is a solo tool): there is **no hook gate**, and `validate.sh` is an optional self-check, never a blocking gate. Depth of capture is the **skill name**, never a flag.

```
discuss freely in chat
  ↓
to-task | to-plan | to-roadmap        ← capture depth is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
```

- `to-task` — capture chat → `.task/task/<slug>.md`, `## Description` only, no `## Plan`.
- `to-plan` — same, **with** a `## Plan` section (Goal / Touches / Logic).
- `to-roadmap` — capture an initiative → `.task/roadmap/<slug>.md`.
- `to-spec` — capture load-bearing technical decisions → `.task/spec/<slug>.md`; referenced by tasks/roadmaps via `Spec:` headers, and read by the executing session as a fixed anchor.
- `roadmap-to-workflow` — the one launcher. Authors + invokes a dynamic Workflow that runs the roadmap's unchecked items.

**Execution is not a skill.** An ordinary session told `implement .task/task/<slug>.md` reads the artifact and follows its `## Execution` block (implement → `/verify` → `/code-review` → commit). There is **no `build` skill and no `ship` skill** in v3 — both are deleted; their behavior is the stamped `## Execution` boilerplate plus the platform skills.

There are **no user-facing flags** anywhere — footers, descriptions, and examples are flag-free.

---

## `.task/` layout (FLAT)

`.task/` sits **once at the pipeline root**, shared by every worktree of the repo. The v3 layout is flat — one file per task, one file per spec, no per-task subfolders, no workspace, no log, no archive.

| Path | Role |
|------|------|
| `.task/config/config.md` | Project settings — Language, Testing Policy, Commit Format, tool priority. Written by the intake skills' inline Step 0 setup (the folded-in `bootstrap`). Format unchanged from v2. |
| `.task/task/<slug>.md` | **One file per task.** `<slug>` is both the filename and the identity. Written by `to-task` / `to-plan`. |
| `.task/roadmap/<slug>.md` | One file per multi-task initiative. Item backlog with checkboxes. |
| `.task/spec/<slug>.md` | **One file per spec.** Standalone load-bearing technical decisions, topic-derived slug. Written by `to-spec`. Cited by task/roadmap `Spec:` headers. |

What is **gone from v2**: `.task/workspace/`, `.task/log/`, any `<task-id>/` subfolder, the active-task pointer, and the whole archive concept. A closed task is just a file that stays in `.task/task/` (or the user deletes it). **git history is the record** — there is no archive.

`.task/` is git-excluded via `.git/info/exclude` (pattern `.task`), written once by the intake skills' inline Step 0 setup. No tracked edits ever land outside `.task/` — the pipeline is invisible to the project.

### Slug as identifier

- The **slug** is kebab-case English, derived from the task (or roadmap) title.
- It is **both the filename and the identity**. There is no task-id, no bracketed `[TASK-ID]`, no umbrella grouping, no `derive-task-id`.
- A roadmap item's task file is `.task/task/<item-slug>.md`, where `<item-slug>` is the kebab-case of that item's title.

### Root resolution (`skills/_lib/resolve-ws.sh`)

v3 shrinks the resolver to a **pure `.task/`-root finder**. It exports **`AI_DIR`** = the discovered `.task` directory, first hit wins:

1. `git config --local task.root` — the anchor recorded by the inline Step 0 setup. Repo-common, so **every worktree resolves the same `.task/` with zero setup** — no symlink, no join step. This is what lets the worktrees spawned by `roadmap-to-workflow` share one `.task/`.
2. Upward walk from `$PWD` for a `.task/config/config.md` ancestor — pre-anchor fallback.
3. `dirname(git-common-dir)/.task` — main-worktree root / sibling worktrees / bare repos.
4. `$CLAUDE_PROJECT_DIR/.task` when set, else the relative `./.task` — so a call from outside a project still fails cleanly on the config gate.

**Removed in v3:** every bit of active-task-pointer logic (`task_current_path`, `heal_stale_pointer`, pointer read/write/self-heal), the `WS_DIR` / `resolve_ws` workspace resolution, and `TASK_ID_OVERRIDE`. There is no "which task is active" resolution anywhere — the artifact path is the handle.

---

## `task.md` format (`.task/task/<slug>.md`)

One format, produced by **both** `to-task` and `to-plan`. `to-plan` additionally writes `## Plan`; `to-task` omits it. The slug is the **filename**, never in the title.

```markdown
# <Title>
Roadmap: <slug>          (optional; present only for roadmap items — load-bearing)
Source item: #N          (optional; the item number in the roadmap)
Spec: <slug>             (optional, repeatable; each cites a .task/spec/<slug>.md anchor)
---
## Description
Why + what, distilled from the chat.

## Plan                  (written ONLY by to-plan)
### Step 1: <short title>
**Goal:** <the observable end state this step reaches>
**Touches:** `path/one` `path/two`
**Logic:** <optional — how, only when non-obvious>

### Step 2: ...

## Tests                 (optional; present iff config Testing Policy warrants it)
### Test 1: <what is asserted>
### Test 2: ...

## Execution
> If any `Spec:` headers are present, first read each referenced `.task/spec/<slug>.md`
> as a fixed technical anchor — honor its decisions, do not re-derive them. Then implement
> the plan above (or the Description if there is no Plan), reading and editing code with the
> tools in `.task/config/config.md` → Code Navigation / Code Editing (MCP tools first,
> built-ins as fallback). Then run the `/verify` skill end-to-end and `/code-review` on the
> diff; apply review fixes ONLY within the files named in **Touches** (report the rest). If
> there is no `## Plan`, and so no **Touches**, scope review fixes to the files you changed
> for the Description. Commit per `.task/config/config.md` → Commit Format. If `Roadmap:` +
> `Source item:` headers are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
```

Rules:

- **Line 1** is `# <Title>` — a plain title, no bracketed task-id. (The v2 `# [TASK-ID] Title` form is dropped.)
- **`Roadmap:` / `Source item:`** are optional header lines above the `---` separator. They are load-bearing for the executing session's auto-mark step (see below). Keep them **ASCII and above `---`**.
- **`Spec:`** is an optional, **repeatable** header line above `---`. Each `Spec: <slug>` names a `.task/spec/<slug>.md` the executing session reads as a fixed technical anchor before implementing (see the `## Execution` block). Load-bearing; keep it **ASCII and above `---`**. One task may carry several.
- **`---`** on its own line separates the header block from the body.
- **`## Description`** is mandatory. It carries the "why + what" from the chat.
- **`## Plan`** is optional (written only by `to-plan`). When present it uses the three-layer step contract — **Goal / Touches / Logic**. `Goal` is the observable target; `Touches` lists the files (and scopes review fixes); `Logic` is optional guidance. Each step is a `### Step N:` block.
- **`## Tests`** is optional. When present, each `### Test N:` block states one assertion. `config.md` → Testing Policy governs whether the task warrants tests.
- **`## Execution`** is a **standard boilerplate block stamped verbatim by every `to-*` skill.** This is the mechanism that replaces the deleted `build` / `ship` skills. The block text is the canonical text shown above (a blockquote, ~4 lines). It is agent-facing and English — do **not** translate it.

### Canonical `## Execution` block — stamp this verbatim

Every `to-task` / `to-plan` run stamps exactly this, unchanged, English regardless of config Language:

```markdown
## Execution
> If any `Spec:` headers are present, first read each referenced `.task/spec/<slug>.md`
> as a fixed technical anchor — honor its decisions, do not re-derive them. Then implement
> the plan above (or the Description if there is no Plan), reading and editing code with the
> tools in `.task/config/config.md` → Code Navigation / Code Editing (MCP tools first,
> built-ins as fallback). Then run the `/verify` skill end-to-end and `/code-review` on the
> diff; apply review fixes ONLY within the files named in **Touches** (report the rest). If
> there is no `## Plan`, and so no **Touches**, scope review fixes to the files you changed
> for the Description. Commit per `.task/config/config.md` → Commit Format. If `Roadmap:` +
> `Source item:` headers are present, tick item #N's checkbox in `.task/roadmap/<slug>.md`.
```

Artifact prose (Description, Plan, Tests body) follows `config.md` → Language. Structural labels (`## Description`, `## Plan`, `### Step N:`, `## Tests`, `### Test N:`, `## Execution`), header keys (`Roadmap:`, `Source item:`, `Spec:`), and the `## Execution` block text stay English — they are parser / contract strings.

---

## Roadmap file format (`.task/roadmap/<slug>.md`)

Produced by `to-roadmap`; user-edited thereafter. The `roadmap-to-workflow` driver reads it to loop unchecked items and flips one `- [ ]` → `- [x]` per completed item (auto-mark, done by the driver — see below).

Each item:

```markdown
### - [ ] 1. <Task title>

**Dependencies:** — / 1, 2, ...
**Model:** haiku | sonnet | opus      (optional per-item hint)

**Ready description:**

> ### Context
> Why this task, what it unblocks. Distinct from Goal.
>
> ### Goal
> The target state. Behavioral — no project file/symbol names.
>
> ### Outcomes
> - Observable property of the system after this task.
>
> ### Invariants          (optional — omit when the item has none)
> - Contract that must hold across the change.
>
> ### Acceptance criteria
> - Testable assertion.
```

Field labels and blockquote sub-headings (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria`, `**Dependencies:**`, `**Model:**`) stay English; prose follows `config.md` → Language. Surrounding file structure (`## Prerequisites`, phase summary table, `## Out of scope`, `## Backlinks`) carries over from the prior grammar.

Load-bearing item fields for `roadmap-to-workflow`:

- **`**Dependencies:**`** — `—` (none) or a comma-separated list of item numbers. The driver **topologically sorts** items into dependency-ordered **waves**: items in the same wave have no unmet dependency and run in parallel; a barrier separates waves.
- **`**Model:**`** — optional per-item hint (`haiku` / `sonnet` / `opus`). The driver passes it as `opts.model` to the per-item implement agent. It is **not** validated — a missing or off-list value simply means no hint (defaults apply).

### Roadmap `Spec:` headers

A roadmap may carry optional, **repeatable** `Spec: <slug>` header lines (above its title/intro, ASCII), each naming a `.task/spec/<slug>.md` that holds load-bearing cross-item technical decisions. Items cite specific decisions as `### Spec references → <slug> §N` (the `<slug>` qualifier is required — several specs may be reachable). When `roadmap-to-workflow` runs the roadmap, it passes these spec paths to each item's plan agent; when `to-plan`/`to-task` open an item by hand, they carry the relevant `Spec:` headers onto the task file so the executing session reads them via `## Execution`.

---

## Spec file format (`.task/spec/<slug>.md`)

Produced by `to-spec`; user-edited thereafter. A **standalone** home for load-bearing technical decisions — anchors a plan or executing session treats as fixed without re-deriving. `<slug>` is the topic-derived filename and identity, independent of any roadmap; one spec may be cited by many tasks and roadmaps via their `Spec:` headers. (This replaces the v2 roadmap-scoped `<slug>.spec.md` sidecar — the sidecar concept is gone.)

```markdown
# Spec: <Title>

> One-line purpose. Load-bearing technical decisions for <topic> — NOT a full
> implementation plan (the plan owns that). One numbered section per decision;
> tasks and roadmap items cite sections as `### Spec references → <slug> §N`.

## 1. <decision title>
**Decision:** <what was chosen>
**Rationale:** <why — the reasoning that must survive, not be re-litigated>
**Constrains:** <what this pins for consumers; what it leaves free>

## 2. ...
```

Section labels (`## N.`, `**Decision:**` / `**Rationale:**` / `**Constrains:**`) and the `Spec:` header key stay English; prose follows `config.md` → Language.

---

## Producer / consumer table (v3)

| Artifact | Produced by | Consumed by |
|----------|-------------|-------------|
| `.task/config/config.md` | intake skills' inline Step 0 setup (folded-in `bootstrap`) | every skill + every executing session — Language, Testing Policy, Commit Format, tool priority |
| `.task/task/<slug>.md` | `to-task` (header + `## Description` + `## Execution`); `to-plan` (same + `## Plan`, optional `## Tests`) | **the executing session** (reads `## Description`, `## Plan` if present, follows `## Execution`, reads `Spec:` for anchors and `Roadmap:` + `Source item:` for auto-mark); `roadmap-to-workflow` per-item implement agent |
| `.task/roadmap/<slug>.md` | `to-roadmap` (initial); user-edited; `roadmap-to-workflow` **driver** flips `- [ ]` → `- [x]` after an item's agent returns OK | `roadmap-to-workflow` driver (loops unchecked items, reads `**Dependencies:**` + `**Model:**` + `Spec:`); `to-plan` / `to-task` (when picking up an item) |
| `.task/spec/<slug>.md` | `to-spec` or user | **the executing session** (via a task's `Spec:` header) + `to-plan` (technical-decision anchor) + `roadmap-to-workflow` per-item plan agent |

The executing session writes no separate pipeline artifacts — its implementation lands in the working tree, and `/verify` / `/code-review` run against the live diff. Auto-mark inside a single-task execution is done by the executing session itself (per the `## Execution` block); auto-mark during a roadmap run is done by the **driver**, not the per-item agent, so parallel item agents never race on the roadmap file.

---

## Bash layer (`skills/_lib/`, `skills/validate/`)

### resolve-ws.sh (rewritten — root finder only)

Sourced (not exec'd). Runs `find_ai_dir` at source time and **exports `AI_DIR`** = the discovered `.task` directory, via the four-step order in *Root resolution* above. No pointer, no `WS_DIR`, no `resolve_ws`, no `TASK_ID_OVERRIDE`. macOS-safe (no `realpath` / `readlink -f`).

### validate.sh (rewritten — optional self-check, not a gate)

Keeps the `config.md` precondition and English parser-stable strings. **No hook calls it.** Subcommands:

- **`task <slug>`** — validate `.task/task/<slug>.md`:
  - line 1 matches `^# .+` (a title);
  - a `---` separator line is present;
  - `## Description` is present;
  - `## Plan` is **optional** — if present, it has ≥1 `### Step N:` block;
  - `## Tests` is **optional** — if present, it has ≥1 `### Test N:` block;
  - `## Execution` is present (presence only — the block is stamped verbatim, so its text is not re-checked);
  - each `Spec: <slug>` header resolves to an existing `.task/spec/<slug>.md` — a miss is a **`WARN`** (dangling reference), not an error (`validate.sh` is advisory, not a gate).
- **`roadmap <slug>`** — validate `.task/roadmap/<slug>.md`:
  - ≥1 item heading matching `^### - \[[ x~>-]\] N\. <title>` — the checkbox prefix is **required** (an item with a bare `### N.` heading and no checkbox is an error, since the driver's auto-mark and item selection both rely on it);
  - item numbers are unique, since the driver's auto-mark keys on the number;
  - each item block carries the sub-headings `### Context`, `### Goal`, `### Outcomes`, `### Acceptance criteria` inside its `**Ready description:**` blockquote (matched as `> ### <name>`); `### Invariants` is **optional** and not required;
  - dangling `Spec:` headers `WARN` as for `task`.
- **`spec <slug>`** — validate `.task/spec/<slug>.md`: line 1 matches `^# .+`; ≥1 `## N.` numbered decision section. (No `---` separator check — a spec has no parser-stable header block above a body, so there is nothing to separate.)
- **`all`** — validate every `.task/task/*.md`, every `.task/roadmap/*.md`, plus every `.task/spec/*.md`.

`## Execution` is stamped boilerplate; `validate.sh` now checks the block is **present** (presence only, not its exact text). There is **no `Implement-Model:` check** — that field is gone; the per-item model hint lives on roadmap items and is not `validate.sh`'s concern. The dangling-`Spec:` check is the pipeline's only cross-file validation, and only ever a `WARN`.

### Keep

| Script | Role |
|--------|------|
| `roadmap.sh` | artifact-path + roadmap parsing helpers (`resolve_artifact_path` and its `resolve_roadmap_path` wrapper, `roadmap_progress_counts`), used by `roadmap-to-workflow` and `validate.sh`. The driver's per-item checkbox flip is inline `sed`/`awk`, **not** a helper here. |
| `templates/conventional-commits.md` | commit-format fallback for the executing session |

### Removed in v3 (already deleted)

The v2 helpers are gone from `skills/_lib/` — `close.sh` and `commit-context.sh` (both were `ship`'s), `derive-task-id.sh` (no task-id in v3), plus the orphaned `phase-detect.sh`, `touches-gate.sh`, `auto-locks.sh`, `auto-roadmap-helpers.sh`, `fail-log.sh`, and `templates/summary.md`. Only `resolve-ws.sh`, `roadmap.sh`, and `templates/conventional-commits.md` remain (`preamble.sh` too was dropped — it had no live callers; `validate.sh` carries its own `require_config`).

---

## Hook (`hooks/hooks.json`)

The `PreToolUse` matcher is **removed**. Enforcement becomes convention — `build` / `ship` no longer exist to gate, and `validate.sh` is opt-in. The file reduces to:

```json
{"hooks": {}}
```

---

## Handoff (replaces the pointer)

There is **no active-task pointer**. The **artifact path is the handle.** Every `to-task` / `to-plan` run ends with a copy-paste handoff footer naming the artifact path explicitly, e.g.:

```
→ Next: implement it now, or in a fresh session run: `implement .task/task/<slug>.md`
```

No pointer, no self-heal, no "which task is active" resolution anywhere.

---

## Marker inventory

- **Keep:** `git config task.root` and `.git/info/exclude` (pattern `.task`). Both are zero-cost and needed so the parallel worktrees spawned by `roadmap-to-workflow` share one `.task/`.
- **Drop:** the active-task pointer (`task-current`) and `TASK_ID_OVERRIDE`.

---

## Interaction conventions

All three are cheap and architecture-independent. Human-facing dialog only — parser-stable strings and artifact content are untouched.

- **(a) Next-step footer.** Every user-facing output ends with `→ Next: <runnable command>`, or `→ Done.` when the flow is complete. Footers are flag-free; the handoff footer above is the canonical form for the `to-*` skills.
- **(b) Confirmation grammar.** Every content-confirmation is posed via `AskUserQuestion` with **Accept** / **Edit** / **Decline** chips. Accept proceeds as drafted; Edit triggers a focused follow-up for what to change, then re-shows the content and repeats until accepted; Decline writes nothing and stops with that call site's stop message.
- **(c) Path forks.** Every 2–4 option path fork that can't be inferred is presented via `AskUserQuestion` chips.

### Frontmatter

Every skill carries `disable-model-invocation: true` and `user-invocable: true` (exception: `validate`, `user-invocable: false`). Artifacts and user dialog follow `config.md` → Language; parser-stable strings (header keys, section labels, commit trailers, the `## Execution` block, driver return strings) stay English.

### `roadmap-to-workflow` execution shape (driver contract)

- **Per-item default is OPUS-PLANS / SONNET-IMPLEMENTS:** a first `agent()` runs `to-plan` for the item on `{ model: 'opus' }` (writes `.task/task/<item-slug>.md`); a second `agent()` implements + verifies + reviews + commits on `{ model: item.model ?? 'sonnet' }`. Context passes via the on-disk task file — no chat transfer.
- **Dependency-ordered waves:** items in a wave run via `parallel()` with `{ isolation: 'worktree' }`; a barrier separates waves. A dependency **cycle** among scoped items (no wave can be formed) is a hard stop, reported for the user to break — never run an item before its dependency lands.
- **Driver auto-marks:** after an item's agent returns OK, the driver ticks that item's checkbox in the roadmap file (never the per-item agent — avoids parallel writes racing).
- **Stop-on-FAIL;** parser-stable digest last line `OK|FAIL #N <slug> <summary>`.
- **Graceful fallback:** if the Workflow tool is unavailable, run items one at a time via `to-plan` + a plain implement session, manually. Being a skill whose instructions invoke Workflow is itself the sanctioned opt-in.
