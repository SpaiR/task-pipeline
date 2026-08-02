# Artifact contract — the task-pipeline protocol

Single source of truth for how the chat-first task pipeline stores state and how skills hand work to each other. Maintainer-facing.

task-pipeline is **not** an orchestration engine — it is a **context-serialization protocol**. The user discusses a task freely in chat, then runs **one short skill** that distils the discussion into a fixed-format Markdown artifact under `.task/`. A fresh or isolated Claude Code session then **executes that artifact directly** — there is no execution skill. Orchestration and commits stay delegated to the platform (dynamic Workflows, `config.md` → Commit Format); **review is owned by the plugin**, as the `task:code-reviewer` agent (`agents/code-reviewer.md`), which also carries verification via `config.md` → Build and Tests.

Enforcement is traded for **convention** (this is a solo tool): there is **no hook gate**, and `validate.sh` is an optional self-check, never a blocking gate. Depth of capture is the **skill name**, never a flag.

```
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-plan | to-roadmap        ← capture depth is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
```

- `grill` — **pre-capture, produces no artifact.** Interrogates a plan/decision one question at a time, keeps an in-chat decision-plus-rationale ledger, ends with a pre-mortem, and routes to the right capture skill. Touches nothing under `.task/`; its output is a hardened discussion the `to-*` skills then serialize.
- `to-task` — capture chat → `.task/task/<slug>.md`, `## Description` only, no `## Plan`.
- `to-plan` — same, **with** a `## Plan` section (Goal / Touches / Logic).
- `to-roadmap` — capture an initiative → `.task/roadmap/<slug>.md`.
- `to-spec` — capture load-bearing technical decisions → `.task/spec/<slug>.md`; referenced by tasks/roadmaps via `Spec:` headers, and read by the executing session as a fixed anchor.
- `roadmap-to-workflow` — the one launcher. Authors + invokes a dynamic Workflow that runs the roadmap's unchecked items.

**Execution is not a skill.** An ordinary session told `implement .task/task/<slug>.md` reads the artifact and follows its `## Execution` block (implement → commit → `task:code-reviewer` reviews, fixes and amends). There is **no execution skill** — the behavior is the stamped `## Execution` boilerplate plus the one agent the plugin ships.

There are **no user-facing flags** anywhere — footers, descriptions, and examples are flag-free.

---

## `.task/` layout (FLAT)

`.task/` sits **once at the pipeline root**, shared by every worktree of the repo. The layout is flat — one file per task, one file per spec, no per-task subfolders, no workspace, no log, no archive. A closed task is just a file that stays in `.task/task/` (or the user deletes it) — **git history is the record**.

| Path | Role |
|------|------|
| `.task/config/config.md` | Project settings — Language, Testing Policy, Commit Format, tool priority. Written by the intake skills' inline Step 0 setup. |
| `.task/task/<slug>.md` | **One file per task.** `<slug>` is both the filename and the identity. Written by `to-task` / `to-plan`. |
| `.task/roadmap/<slug>.md` | One file per multi-task initiative. Item backlog with checkboxes. |
| `.task/spec/<slug>.md` | **One file per spec.** Standalone load-bearing technical decisions, topic-derived slug. Written by `to-spec`. Cited by task/roadmap `Spec:` headers. |

`.task/` is git-excluded via `.git/info/exclude` (pattern `.task`), written once by the intake skills' inline Step 0 setup. No tracked edits ever land outside `.task/` — the pipeline is invisible to the project.

### Slug as identifier

- The **slug** is kebab-case English, derived from the task (or roadmap) title.
- It is **both the filename and the identity**. There is no task-id, no bracketed `[TASK-ID]`, no umbrella grouping, no `derive-task-id`.
- A roadmap item's task file is `.task/task/<item-slug>.md`, where `<item-slug>` is the kebab-case of that item's title.

### Root resolution (`skills/_lib/resolve-ws.sh`)

The resolver is a **pure `.task/`-root finder**. It exports **`AI_DIR`** = the discovered `.task` directory, first hit wins:

1. `git config --local task.root` — the anchor recorded by the inline Step 0 setup. Repo-common, so **every worktree resolves the same `.task/` with zero setup** — no symlink, no join step. This is what lets user-created parallel worktrees of a repo share one `.task/`.
2. Upward walk from `$PWD` for a `.task/config/config.md` ancestor — pre-anchor fallback.
3. `dirname(git-common-dir)/.task` — main-worktree root / sibling worktrees / bare repos.
4. `$CLAUDE_PROJECT_DIR/.task` when that path already holds a `config/config.md` (evidence, not merely the variable being set), else the relative `./.task` — so a call from outside a project still fails cleanly on the config gate.

**Producers write under the resolved `$AI_DIR`, never a cwd-relative `.task/`.** Each capture skill resolves it in its Step 0, and `validate.sh` resolves it independently in its own subprocess — so a cwd-relative write from a subdirectory or a linked worktree splits the root: the artifact lands in a second `.task/` the validator never looks at. `.task/<kind>/<slug>.md` in this document and in the skills is shorthand for `$AI_DIR/<kind>/<slug>.md`.

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
> If `Spec:` headers are present, read each `.task/spec/<slug>.md` first and honor its
> decisions as fixed. `.task/` is pipeline-internal and invisible to the repo: never name
> `.task/` paths, spec/roadmap/task slugs, or `§` numbers in code, comments, commits, or PR
> text. Implement the Plan above (or the Description if none) with the tools in
> `.task/config/config.md` → Code Navigation / Code Editing, then commit per
> `.task/config/config.md` → Commit Format. Then spawn the `task:code-reviewer` agent on this
> file: it proves each finding, fixes confirmed defects within **Touches** plus regressions
> this diff introduced outside them, runs Build and Tests, and amends the commit; with no
> `## Plan`, scope fixes to what you changed. If `Roadmap:` + `Source item:` are present,
> tick item #N's checkbox in `.task/roadmap/<slug>.md` once the review returns OK.
```

Rules:

- **Line 1** is `# <Title>` — a plain title, no bracketed task-id.
- **`Roadmap:` / `Source item:`** are optional header lines above the `---` separator. They are load-bearing for the executing session's auto-mark step (see below). Keep them **ASCII and above `---`**.
- **`Spec:`** is an optional, **repeatable** header line above `---`. Each `Spec: <slug>` names a `.task/spec/<slug>.md` the executing session reads as a fixed technical anchor before implementing (see the `## Execution` block). Load-bearing; keep it **ASCII and above `---`**. One task may carry several.
- **`---`** on its own line separates the header block from the body.
- **`## Description`** is mandatory. It carries the "why + what" from the chat.
- **`## Plan`** is optional (written only by `to-plan`). When present it uses the three-layer step contract — **Goal / Touches / Logic**. `Goal` is the observable target; `Touches` lists the files (and scopes review fixes); `Logic` is optional guidance. Each step is a `### Step N:` block.
- **`## Tests`** is optional. When present, each `### Test N:` block states one assertion. `config.md` → Testing Policy governs whether the task warrants tests.
- **`## Execution`** is a **standard boilerplate block stamped verbatim by every `to-task` / `to-plan` run.** This is the mechanism that carries execution — there is no execution skill. The block text is the canonical text shown above (a blockquote, ~4 lines). It is agent-facing and English — do **not** translate it.

### Canonical `## Execution` block — stamp this verbatim

Every `to-task` / `to-plan` run stamps exactly this, unchanged, English regardless of config Language: stamp the `## Execution` blockquote shown in the format above, verbatim.

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

Field labels and blockquote sub-headings (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria`, `**Dependencies:**`, `**Model:**`) stay English; prose follows `config.md` → Language. The same split applies to the surrounding file structure (`## Prerequisites`, phase summary table, `## Out of scope`, `## Backlinks`).

Load-bearing item fields for `roadmap-to-workflow`:

- **Checkbox state** — the item heading's checkbox is a **5-state** class, `[ x~>-]`. `[ ]` is unchecked (eligible to run); `[x]` / `[~]` / `[>]` / `[-]` all count as **already-marked / not-eligible** — for progress counting (`roadmap.sh:roadmap_progress_counts`), the driver's auto-mark, and wave dependency-satisfaction. Do **not** narrow it to `[ x]` only: `roadmap.sh`, `validate.sh`, and the wave sorter all key on the full class.
- **`**Dependencies:**`** — `—` (none) or a comma-separated list of item numbers. `—` is the form `to-roadmap` emits; the driver's parser also tolerates `-`, `none`, and `n/a` as "no dependency", since roadmaps are hand-edited. Anything else is read as a dependency on an item number, so an unrecognised word becomes a phantom dependency and a hard stop. The driver **topologically sorts** items into dependency-ordered **waves**: items in the same wave have no unmet dependency and run in parallel; a barrier separates waves.
- **`**Model:**`** — optional per-item hint (`haiku` / `sonnet` / `opus`). The driver passes it as `opts.model` to the per-item implement agent. It is **not** validated — a missing or off-list value simply means no hint (defaults apply).

### Roadmap `Spec:` headers

A roadmap may carry optional, **repeatable** `Spec: <slug>` header lines (above its title/intro, ASCII), each naming a `.task/spec/<slug>.md` that holds load-bearing cross-item technical decisions. Items cite specific decisions as `### Spec references → <slug> §N` (the `<slug>` qualifier is required — several specs may be reachable). When `roadmap-to-workflow` runs the roadmap, it passes these spec paths to each item's plan agent; when `to-plan`/`to-task` open an item by hand, they carry the relevant `Spec:` headers onto the task file so the executing session reads them via `## Execution`.

---

## Spec file format (`.task/spec/<slug>.md`)

Produced by `to-spec`; user-edited thereafter. A **standalone** home for load-bearing technical decisions — anchors a plan or executing session treats as fixed without re-deriving. `<slug>` is the topic-derived filename and identity, independent of any roadmap; one spec may be cited by many tasks and roadmaps via their `Spec:` headers.

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

## Producer / consumer table

| Artifact | Produced by | Consumed by |
|----------|-------------|-------------|
| *(none — chat only)* | `grill` — an in-chat decision ledger, never a file | the `to-*` capture skill the user runs next |
| `.task/config/config.md` | intake skills' inline Step 0 setup | every skill **except `grill`** + every executing session — Language, Testing Policy, Commit Format, tool priority |
| `.task/task/<slug>.md` | `to-task` (header + `## Description` + `## Execution`); `to-plan` (same + `## Plan`, optional `## Tests`) | **the executing session** (reads `## Description`, `## Plan` if present, follows `## Execution`, reads `Spec:` for anchors and `Roadmap:` + `Source item:` for auto-mark); `roadmap-to-workflow` per-item implement agent; **`task:code-reviewer`** (reads `Touches` as fix scope + `Spec:` as fixed anchors — read-only); `validate.sh` (read-only format check) |
| `.task/roadmap/<slug>.md` | `to-roadmap` (initial); user-edited; `roadmap-to-workflow` **driver** flips `- [ ]` → `- [x]` after an item's agent returns OK | `roadmap-to-workflow` driver (loops unchecked items, reads `**Dependencies:**` + `**Model:**` + `Spec:`); `to-plan` / `to-task` (when picking up an item); `validate.sh` (read-only format check) |
| `.task/spec/<slug>.md` | `to-spec` or user | **the executing session** (via a task's `Spec:` header) + `to-plan` (technical-decision anchor) + `roadmap-to-workflow` per-item plan agent; `validate.sh` (read-only format check) |

The executing session writes no separate pipeline artifacts — its implementation lands in the working tree, then in the commit, and `task:code-reviewer` reviews that diff. Auto-mark inside a single-task execution is done by the executing session itself (per the `## Execution` block, after the review returns OK); auto-mark during a roadmap run is done by the **driver**, not the per-item agent, so parallel item agents never race on the roadmap file.

### Config-gate categories

Three categories, not two:

- **Intake skills** (`to-task` / `to-plan` / `to-roadmap` / `to-spec`) auto-run setup inline in a fresh project — they write `config.md` on first use.
- **Consumer skills** (`roadmap-to-workflow`, `validate`) check `config.md` and hard-stop if it is absent.
- **`grill`** is exempt from both: it neither checks nor creates `config.md`, so it can run at the discussion stage before any config or capture exists. It never reads or writes anything under `.task/`; dialog mirrors the chat's language.

---

## Bash layer (`skills/_lib/`, `skills/validate/`)

### resolve-ws.sh (root finder only)

Sourced (not exec'd). Runs `find_ai_dir` at source time and **exports `AI_DIR`** = the discovered `.task` directory, via the four-step order in *Root resolution* above. No pointer, no `WS_DIR`, no `resolve_ws`, no `TASK_ID_OVERRIDE`. macOS-safe (no `realpath` / `readlink -f`).

### validate.sh (optional self-check, not a gate)

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
  - item numbers are unique, since the driver's auto-mark keys on the number — numbering runs continuously across the whole file and never restarts per phase;
  - each item block carries the `**Ready description:**` label (required — `to-plan` and the executing session key on it to find the item body) and, inside its blockquote, the sub-headings `### Context`, `### Goal`, `### Outcomes`, `### Acceptance criteria` (matched as `> ### <name>`); `### Invariants` is **optional** and not required;
  - dangling `Spec:` headers `WARN` as for `task`.
- **`spec <slug>`** — validate `.task/spec/<slug>.md`: line 1 matches `^# .+`; ≥1 `## N.` numbered decision section. (No `---` separator check — a spec has no parser-stable header block above a body, so there is nothing to separate.)
- **`all`** — validate every `.task/task/*.md`, every `.task/roadmap/*.md`, plus every `.task/spec/*.md`.

`## Execution` is stamped boilerplate; `validate.sh` checks the block is **present** (presence only, not its exact text). There is **no `Implement-Model:` check** — the per-item model hint lives on roadmap items and is not `validate.sh`'s concern. The dangling-`Spec:` check is the pipeline's only cross-file validation, and only ever a `WARN`.

### Helpers

| Script | Role |
|--------|------|
| `roadmap.sh` | artifact-path + roadmap parsing helpers: `resolve_artifact_path` (called by `roadmap-to-workflow` and `validate.sh`) and `roadmap_progress_counts` (called by `roadmap-to-workflow` only). The driver's per-item checkbox flip is inline `awk`, **not** a helper here. |
| `templates/conventional-commits.md` | commit-format fallback: the intake Step 0 setup points `config.md` → Commit Format at it when the project declares no convention of its own (no commit-format doc, nothing usable in `git log`) |

---

## Agent layer (`agents/`)

The plugin ships **exactly one** agent: `agents/code-reviewer.md`, resolved as the agent type **`task:code-reviewer`** (plugin `agents/` directories are auto-loaded; the type is `[plugin, ...subdirs, name].join(":")`). It is the pipeline's own review pass — the platform's `/verify` and `/code-review` commands are marked `disable-model-invocation`, so neither a subagent nor a session that was told `implement …` can run them, and the failure is silent (an unlisted command is skipped, not refused).

It is invoked identically from both execution paths, always given the task artifact's path plus a reference string to echo in its digest:

- a plain session following a task's `## Execution` block spawns it with the `Agent` tool (depth 0 → 1);
- `roadmap-to-workflow`'s driver spawns it as its own stage in the per-item serial loop (depth 1 → 2).

Contract:

- **Find → verify → fix.** Candidates are collected from the diff, each proved or refuted independently, and only CONFIRMED defects are edited. An unproven candidate is dropped, never fixed — inside a roadmap autopilot an unverified "fix" becomes a commit nobody reviewed.
- **Fix scope = `Touches` + regressions this diff introduced outside them.** `Touches` is authored before the code exists, so it is a scope hint, not an exact list; everything else confirmed goes to the report.
- **Verification rides inside the review.** The agent runs `config.md` → Build and Tests end to end, fails the item on a red run, and reports an undeclared command as an explicit skip.
- **Implement commits, the reviewer amends.** The implementation commits its own work; the reviewer stages its fixes and `git commit --amend`s, keeping the message per `config.md` → Commit Format. History stays one item = one commit. If the implementation was never committed, the reviewer leaves its fixes uncommitted rather than rewriting an unrelated commit.
- **Explicit phases with a mandatory output each** (intake → diff → find → prove → fix → Build and Tests → amend). `0 findings` is a declared state, and a report that does not enumerate what was checked per `Touches` file is a failed review, not a passed one.
- **Parser-stable digest last line:** `OK|FAIL <reference string> <summary>` — the same shape the roadmap driver already parses for its implement stage.
- It writes **nothing** under `.task/`: the artifact, roadmap, specs and config are read-only to it, and ticking a roadmap checkbox stays the caller's job.

Plugin agents ignore `permissionMode`, `hooks` and `mcpServers`; `model`, `effort`, `tools`, `disallowedTools`, `skills`, `maxTurns` and `isolation` are honored. `isolation` is deliberately **absent** — the reviewer must see and edit the same working tree the implementation used. `model` / `effort` are pinned in the frontmatter so a `haiku` roadmap item does not get a `haiku` review.

## Hook

There is **no hook** — the plugin ships no `hooks/hooks.json`; an absent file and an empty `{"hooks": {}}` are equivalent to the plugin loader. Enforcement is convention: no `PreToolUse` gate, and `validate.sh` is opt-in.

---

## Handoff

There is **no active-task pointer**. The **artifact path is the handle.** Every `to-task` / `to-plan` run ends with a copy-paste handoff footer naming the artifact path explicitly, e.g.:

```
→ Next: implement it now, or in a fresh session run: `implement .task/task/<slug>.md`
```

No pointer, no self-heal, no "which task is active" resolution anywhere.

---

## Marker inventory

The pipeline's only markers are `git config task.root` and the `.git/info/exclude` entry (pattern `.task`) — nothing else. Both are zero-cost and needed so user-created parallel worktrees of a repo share one `.task/`.

---

## Interaction conventions

All three are cheap and architecture-independent. Human-facing dialog only — parser-stable strings and artifact content are untouched.

- **(a) Next-step footer.** Every user-facing output ends with `→ Next: <runnable command>`, or `→ Done.` when the flow is complete. Footers are flag-free; the handoff footer above is the canonical form for the `to-*` skills.
- **(b) Capture grammar.** Every capture **writes its artifact immediately, then prints a structural digest** as visible Markdown message text — not a full draft, and never a pre-write confirmation. The chat discussion (or, for `grill`, the one-question-at-a-time interrogation) *was* the review; re-asking the user to Accept/Edit/Decline distilled content they already discussed is empty ceremony, and the print-then-confirm gate it replaced was the pipeline's most error-prone step. The digest carries: the artifact path, its title, the sections written, the load-bearing decisions/pins captured one line each (for a **spec**, *every* pin — it is read downstream as a fixed anchor, so this is the user's one glance to catch a misstatement), and the `validate.sh` result. It closes by inviting edits against the already-written file ("to change anything, just say so"), then the (a) footer. `grill` writes nothing, so its decision ledger *is* the digest. Corrections happen naturally in chat and against the file (which is git-excluded — a wrong write costs one deletion), not through a chip. **A chip survives only where the question is not about distilled content:** the config Step 0 setup (confirming *auto-detected* environment — language, test policy — that was never part of the discussion) and the slug-collision overwrite guard (a pre-write safety check on a destructive action).
- **(c) Path forks.** Every 2–4 option path fork that can't be inferred is presented via `AskUserQuestion` chips.

### Frontmatter

Every skill carries `disable-model-invocation: true` and `user-invocable: true`. (`validate` is a bash-only utility — `skills/validate/validate.sh`, no `SKILL.md` — so it carries no frontmatter.) Artifacts and user dialog follow `config.md` → Language — except `grill`, which by design reads nothing under `.task/` and so mirrors the chat's own language instead; parser-stable strings (header keys, section labels, commit trailers, the `## Execution` block, driver return strings) stay English.

### `roadmap-to-workflow` execution shape (driver contract)

- **Per-item default is OPUS-PLANS / SONNET-IMPLEMENTS / REVIEWER-REVIEWS:** a first `agent()` runs `to-plan` for the item on `{ model: 'opus' }` (writes `.task/task/<item-slug>.md`); that plan agent suppresses `to-plan`'s `→ Next:` footer so its last non-empty line is the parser-stable `OK #N <item-slug> planned` the driver reads the slug from; a second `agent()` implements + commits on `{ model: item.model ?? 'sonnet' }`; a third spawns `task:code-reviewer` (`agentType`), which reviews that commit, fixes what it proves, runs Build and Tests, and amends. Context passes via the on-disk task file — no chat transfer.
- **Dependency-ordered waves:** within a wave, plan agents run in `parallel()` (they write only their own task files) and then implement **and review** run **strictly one at a time** per item, inside the same serial loop — the shared working tree keeps exactly one writer, and item N never starts implementing while item N−1 is still under review. A barrier separates waves. A dependency **cycle** among scoped items (no wave can be formed) is a hard stop, reported for the user to break — never run an item before its dependency lands.
- **Driver auto-marks:** after an item's review returns OK, the driver ticks that item's checkbox in the roadmap file (never the per-item agent — avoids parallel writes racing).
- **Stop-on-FAIL;** parser-stable digest last line `OK|FAIL #N <slug> <summary>`.
- **Graceful fallback:** if the Workflow tool is unavailable, run items one at a time via `to-plan` + a plain implement session, manually. Being a skill whose instructions invoke Workflow is itself the sanctioned opt-in.
