# Artifact contract — the task-pipeline protocol

Single source of truth for how the chat-first task pipeline stores state and how skills hand work to each other. Maintainer-facing.

task-pipeline is **not** an orchestration engine — it is a **context-serialization protocol**. The user discusses a task freely in chat, then runs **one short skill** that distils the discussion into a fixed-format Markdown artifact under `.task/`. A fresh or isolated Claude Code session then **executes that artifact directly** — there is no execution skill. Orchestration and commits stay delegated to the platform (dynamic Workflows, `.task/CLAUDE.md` → Commit Format); **review is owned by the plugin**, as the `task:code-reviewer` agent (`agents/code-reviewer.md`), which also carries verification via `.task/CLAUDE.md` → Build and Tests.

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

- `grill` — **pre-capture, produces no artifact.** Interrogates a plan/decision one question at a time, keeps an in-chat decision-plus-rationale ledger, ends with a pre-mortem (skipped when it would change nothing), and routes to the right capture skill. Depth is an outcome, not a target — it stops when no unanswered fork would change the capture, offering a wrap-up-or-keep-going checkpoint when only secondary forks remain. Touches nothing under `.task/`; its output is a hardened discussion the `to-*` skills then serialize.
- `to-task` — capture chat → `.task/task/<slug>.md`, `## Description` only, no `## Plan`.
- `to-plan` — same, **with** a `## Plan` section (Goal / Touches / Logic).
- `to-roadmap` — capture an initiative → `.task/roadmap/<slug>.md`.
- `to-spec` — capture load-bearing technical decisions → `.task/spec/<slug>.md`; referenced by tasks/roadmaps via `Spec:` headers, and read by the executing session as a fixed anchor.
- `roadmap-to-workflow` — the one launcher. Computes dependency waves over the roadmap's unchecked items and invokes the plugin-shipped Workflow driver (`skills/_lib/roadmap-driver.js`, via `scriptPath` + `args`).

**Execution is not a skill.** An ordinary session told `implement .task/task/<slug>.md` reads the artifact, whose `## Execution` pointer sends it to `.task/CLAUDE.md` → `## Executing a task` (implement → commit → `task:code-reviewer` reviews, fixes and amends). There is **no execution skill** — the behavior is that one section plus the one agent the plugin ships.

There are **no user-facing flags** anywhere — footers, descriptions, and examples are flag-free.

---

## `.task/` layout (FLAT)

`.task/` sits **once at the pipeline root**, shared by every worktree of the repo. The layout is flat — one file per task, one file per spec, no per-task subfolders, no workspace, no log, no archive. A closed task is just a file that stays in `.task/task/` (or the user deletes it) — **git history is the record**.

| Path | Role |
|------|------|
| `.task/CLAUDE.md` | Project settings — Language, Testing Policy, Build and Tests, Commit Format, tool priority — plus `## Executing a task`, the one copy of the execution instructions. A **nested `CLAUDE.md`**: the platform loads it into any session that reads a file under `.task/`. Written once by the capture skills' inline Step 0 setup, then **user-owned** — setup never rewrites an existing one. |
| `.task/task/<slug>.md` | **One file per task.** `<slug>` is both the filename and the identity. Written by `to-task` / `to-plan`. |
| `.task/roadmap/<slug>.md` | One file per multi-task initiative. Item backlog with checkboxes. |
| `.task/spec/<slug>.md` | **One file per spec.** Standalone load-bearing technical decisions, topic-derived slug. Written by `to-spec`. Cited by task/roadmap `Spec:` headers. |

`.task/` is git-excluded via `.git/info/exclude` (pattern `.task`), written once by the capture skills' inline Step 0 setup. No tracked edits ever land outside `.task/` — the pipeline is invisible to the project.

### Slug as identifier

- The **slug** is kebab-case English, derived from the task (or roadmap) title.
- It is **both the filename and the identity**. There is no task-id, no bracketed `[TASK-ID]`, no umbrella grouping, no `derive-task-id`.
- A roadmap item's task file is `.task/task/<item-slug>.md`, where `<item-slug>` is the kebab-case of that item's title.

### Root resolution (`skills/_lib/resolve-ws.sh`)

The resolver is a **pure `.task/`-root finder**. It exports **`AI_DIR`** = the discovered `.task` directory, first hit wins:

1. `git config --local task.root` — the anchor recorded by the inline Step 0 setup, **claimed only on evidence**: accepted when `<root>/.task/CLAUDE.md` exists, ignored otherwise. The anchor is an absolute path living in `.git/config`, which travels with the repo when it is moved or copied; a stale one would resolve to an `AI_DIR` with no `CLAUDE.md`, the gate would call the project unconfigured, and capture setup would write a fresh `.task/CLAUDE.md` while the real one moved with the repo. A stale anchor therefore falls through to step 2. Repo-common, so **every worktree resolves the same `.task/` with zero setup** — no symlink, no join step. This is what lets user-created parallel worktrees of a repo share one `.task/`.
2. Upward walk from `$PWD` for a `.task/CLAUDE.md` ancestor — pre-anchor fallback, **ceilinged at the highest directory that still belongs to this project** — the highest of this checkout's top level, the repo's main worktree root, and (for a submodule) the superproject's working tree that is still an ancestor of `$PWD`. That directory is checked, the one above it is not: an unbounded walk climbs out of the working tree and claims a *neighbouring* project's `.task/`, so a checkout with no `.task/` of its own that sits under a directory which has one would write every artifact into that project's flat namespace — silently, because the setup gate finds a `CLAUDE.md` there and skips setup. A checkout with no ceiling (not a git repo, or a bare repo with no working tree) keeps the unbounded walk.
3. `dirname(git-common-dir)/.task` — main-worktree root / sibling worktrees / bare repos. This is how a **sibling** worktree still finds the shared `.task/`: the main root is not on the sibling's own ancestor chain, so it is not a usable ceiling there and step 3 supplies it directly. A **nested** worktree is the opposite case — the main root *is* an ancestor, so it is the ceiling and the walk may reach a `.task/` sitting between the two. Step 3 claims the main worktree root only when it actually holds a `.git`; with `git init --separate-git-dir=…` that path is merely wherever the git dir was parked, so the checkout's own top level is used instead.
4. `$CLAUDE_PROJECT_DIR/.task` when that path already holds a `CLAUDE.md` (evidence, not merely the variable being set), else the relative `./.task` — so a call from outside a project still fails cleanly on the setup gate.

**Producers write under the resolved `$AI_DIR`, never a cwd-relative `.task/`.** Each capture skill resolves it in its Step 0, and `validate.sh` resolves it independently in its own subprocess — so a cwd-relative write from a subdirectory or a linked worktree splits the root: the artifact lands in a second `.task/` the validator never looks at. `.task/<kind>/<slug>.md` in this document and in the skills is shorthand for `$AI_DIR/<kind>/<slug>.md`.

---

## `.task/CLAUDE.md` format

A **nested `CLAUDE.md`**, not a bespoke config format. The platform loads it into any session that reads a file under `.task/` — which is exactly the executing session, `task:code-reviewer`, and every capture skill. Two properties follow from that and are load-bearing:

- **The auto-load fires only for file-read tools.** A session that opens an artifact with `cat` or `sed` never triggers it. That is why `task.md` still carries an explicit `## Execution` pointer, and why the reviewer reads the file explicitly in its phase 0.
- **It is not re-injected after `/compact`** (a project-root `CLAUDE.md` is; a nested one is not). It reloads on the next read of a file under `.task/`.

The file is written once by first-run setup — the procedure and the authoring template live in `skills/_lib/setup.md`, which each capture skill's Step 0 reads when the file is absent. The shape below is the contract that template must keep producing:

```markdown
# task-pipeline

Rules for capturing and implementing the `.task/` artifacts. Project-wide conventions
stay in the repository's own `CLAUDE.md`.

## Language
## Testing Policy          (always | on-demand | never)
## Build and Tests         (the command(s) `task:code-reviewer` runs, or `None declared.`)
## Commit Format
## Code Navigation         (optional — omit when the built-in tools are all there is)
## Code Editing            (optional)

## Executing a task
{the numbered instructions the executing session follows: read `Spec:` anchors → keep `.task/`
 out of code and commits → implement the Plan (or Description) → commit per Commit Format →
 spawn `task:code-reviewer` → tick the roadmap checkbox when `Roadmap:` + `Source item:` are present}
```

Rules:

- **Written once, then user-owned.** Intake setup writes it on first use, with no confirmation chip, and reports what it wrote. It is **never rewritten** afterwards — an existing file is left untouched even when a section is missing or a detected value went stale. To regenerate, the user deletes the file and re-runs any capture. Only the two markers (`git config task.root`, the `.git/info/exclude` line) are repaired silently.
- **`## Language`, `## Testing Policy`, `## Build and Tests`, `## Commit Format` and `## Executing a task` are always present.** Consumers look them up by heading, and read an absent one as *nothing declared* rather than *look elsewhere* — a missing **Build and Tests** turns every review into a skipped verification run. When the project's own `CLAUDE.md` already documents one, the section stays and its body shrinks to a `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer. Only `## Code Navigation` / `## Code Editing` may be omitted outright.
- **`## Executing a task` is the single copy of the execution instructions.** Editing it reaches artifacts written earlier — the pre-`.task/CLAUDE.md` design stamped the same text into every task file, where an edit reached nothing.
- Section headings are parser-stable English; the prose inside follows `## Language`. `.task/CLAUDE.md` is git-excluded along with the rest of `.task/`.

## Cross-artifact references

Every reference from one `.task/` artifact to another is written as a **Markdown link** — an artifact is read as often by a human in a Markdown viewer (or a plan-review tool) as by an agent, and a bare slug is a dead end there. Every place this applies:

| Where | Form |
|-------|------|
| `task.md` header | `Roadmap: [<slug>](../roadmap/<slug>.md)` |
| `task.md` header | `Spec: [<slug>](../spec/<slug>.md)` |
| roadmap header | `Spec: [<slug>](../spec/<slug>.md)` |
| roadmap item citation | `### Spec references → [<slug>](../spec/<slug>.md) §N` |
| `## Execution` pointer | `> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its …` |

Hrefs are relative to the **artifact's own directory**, which is what a Markdown viewer resolves against. `.task/task/`, `.task/roadmap/` and `.task/spec/` all sit one level under `.task/`, so a sibling-kind reference is always `../<kind>/<slug>.md` and `.task/CLAUDE.md` is always `../CLAUDE.md` — no per-file depth arithmetic.

**The label carries the identity; the href is for viewers.** A consumer takes the slug from the link **label** and rebuilds the canonical `$AI_DIR/<kind>/<slug>.md` itself. It must never follow the relative href literally: an agent's cwd is the project root, not `.task/task/`, so `../spec/x.md` would resolve to a sibling of the repository. Every consumer that resolves one of these headers — `## Executing a task`, `agents/code-reviewer.md` phase 0, `to-task` Step 1a, `to-plan` Step 1/2a, `roadmap-to-workflow` Step 0 (roadmap-level header) and the driver's plan stage via `skills/_lib/plan-driver.md` (per-item citation), `validate.sh:check_spec_refs` — is written that way.

**The bare form stays readable.** `Spec: <slug>` (and `Roadmap: <slug>`) is what earlier versions wrote, and `.task/` artifacts are hand-edited. Producers emit the link form; consumers accept either, and `validate.sh` unwraps the label — tolerating backticks and trailing text around it — before checking the reference. A bare slug is never re-flagged as malformed, only as dangling if the spec genuinely does not exist.

**One consumer the change cannot reach: an existing `.task/CLAUDE.md`.** It is written once and then **never rewritten** (see the rules above), so a project set up before this change keeps a `## Executing a task` whose steps 1 and 5 say only *read each `.task/spec/<slug>.md`* / *tick item #N in `.task/roadmap/<slug>.md`*, with no label-vs-target guidance — while its captures now emit link-form headers. This resolves in practice because the link **label is exactly the slug those steps ask for**, so the instruction reads correctly against the new header. It is nonetheless the pipeline's one unreachable consumer: a user who wants the rule stated explicitly edits that file (it is theirs), or deletes it and re-runs any capture to get the current template. **Do not** add a re-stamp or section-repair path to setup for this — that invariant is load-bearing and costs more than the wording it would fix.

**The target is checked, but only against its own label.** `validate.sh` WARNs when a `Spec:` header's target is not `../spec/<label>.md` — an intra-line consistency check, not a second cross-file one. It exists because every other consumer follows the label and therefore *works*, so a target left stale by a rename fails silently and only for humans: exactly the navigation the link form was added to provide.

## `task.md` format (`.task/task/<slug>.md`)

One format, produced by **both** `to-task` and `to-plan`. `to-plan` additionally writes `## Plan`; `to-task` omits it. The slug is the **filename**, never in the title.

```markdown
# <Title>
Roadmap: [<slug>](../roadmap/<slug>.md)   (optional; roadmap items only — load-bearing)
Source item: #N                           (optional; the item number in the roadmap)
Spec: [<slug>](../spec/<slug>.md)         (optional, repeatable; each cites a spec anchor)
---
## Description
Why + what, distilled from the chat.

## Plan                  (written ONLY by to-plan)
### Step 1: <short title>
**Goal:** <the observable end state this step reaches>
**Touches:** `path/one` `path/two`
**Logic:** <optional — how, only when non-obvious>

### Step 2: ...

## Tests                 (optional; present iff Testing Policy warrants it)
### Test 1: <what is asserted>
### Test 2: ...

## Execution
> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.
```

Rules:

- **Line 1** is `# <Title>` — a plain title, no bracketed task-id.
- **`Roadmap:` / `Source item:`** are optional header lines above the `---` separator. They are load-bearing for the executing session's auto-mark step (see below). Keep them **ASCII and above `---`**.
- **`Spec:`** is an optional, **repeatable** header line above `---`. Each one names a `.task/spec/<slug>.md` the executing session reads as a fixed technical anchor before implementing (see `## Executing a task`). Load-bearing; keep it **ASCII and above `---`**. One task may carry several.
- **Cross-artifact headers are Markdown links** — see [§ Cross-artifact references](#cross-artifact-references) for the form and the one rule that keeps them safe.
- **`---`** on its own line separates the header block from the body.
- **`## Description`** is mandatory. It carries the "why + what" from the chat.
- **`## Plan`** is optional (written only by `to-plan`). When present it uses the three-layer step contract — **Goal / Touches / Logic**. `Goal` is the observable target; `Touches` lists the files (and scopes review fixes); `Logic` is optional guidance. Each step is a `### Step N:` block.
- **`## Tests`** is optional. When present, each `### Test N:` block states one assertion. `.task/CLAUDE.md` → Testing Policy governs whether the task warrants tests.
- **`## Execution`** is a **one-line pointer stamped verbatim by every `to-task` / `to-plan` run** — the exact blockquote shown above, agent-facing English, never translated and never expanded back into instructions. The instructions themselves live once in `.task/CLAUDE.md` → `## Executing a task`, so editing them there reaches artifacts written earlier. The pointer is still load-bearing: the platform auto-loads `.task/CLAUDE.md` only for file-read tools, so a session that opens the artifact with `cat` would see no instructions without it.

### Language split

Artifact prose (Description, Plan, Tests body) follows `.task/CLAUDE.md` → Language. Everything parser-stable stays English — the full inventory is enumerated once, in [§ Frontmatter](#frontmatter); do not restate it here.

One consequence is worth spelling out at the point of use: the `## Execution` blockquote carries no placeholders at all — nothing in it is substituted per task, so every artifact a given version writes gets it **byte-identical**. `validate.sh` checks only that `## Execution` is *present*, so a paraphrase would ship unflagged.

**Byte-identical per version, not across versions.** The canonical text has changed once — the pointer's `.task/CLAUDE.md` became the Markdown link `[.task/CLAUDE.md](../CLAUDE.md)` (see [§ Cross-artifact references](#cross-artifact-references)). Artifacts written before that keep the old wording indefinitely: `to-plan`'s promote and revise modes are required to leave `## Execution` untouched, and nothing re-stamps an existing file. Both forms name the same file and are read by the same instruction, so the divergence is inert — but it means a pre-existing artifact carrying the old pointer is **correct, not drifted**. Only a *newly written* pointer that departs from the current blockquote is a finding.

### `to-plan` may target an existing file (promote / revise)

`to-plan` is not create-only. When its resolved target already exists it edits in place, and which sections survive is load-bearing:

- **promote** (file has no `## Plan`) — insert `## Plan` (and `## Tests`, if newly warranted) between `## Description`'s content and `## Execution`.
- **revise** (file already has a `## Plan`) — replace the prior `## Plan` in place, same position; leave `## Tests` alone unless the current edit touched it.
- **Both** preserve the header block, the `---` separator, `## Description` and `## Execution` verbatim. If a hand-written target carries no `## Execution` to anchor on, append the Plan at end of file and stamp the pointer after it; if it carries no `---` separator, insert one above `## Description` — a missing separator is a `validate.sh` ERROR, so the promoted file would otherwise fail the skill's own post-write check. If it carries no `## Description` at all, promote **stops and asks** (via the slug-collision overwrite-guard `AskUserQuestion` — overwriting the file is a destructive action) rather than inventing one: `## Description` is the one mandatory body section, and `validate.sh` errors on its absence just as it does on the separator.

Anyone changing the `task.md` section order or the `## Execution` pointer is changing promote's insert anchor — that is why it is recorded here and not only in the skill.

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

Field labels and blockquote sub-headings (`### Context` / `### Goal` / `### Outcomes` / `### Invariants` / `### Acceptance criteria`, `**Dependencies:**`, `**Model:**`) stay English; prose follows `.task/CLAUDE.md` → Language. The same split applies to the surrounding file structure (`## Prerequisites`, phase summary table, `## Out of scope`, `## Backlinks`).

Load-bearing item fields for `roadmap-to-workflow`:

- **Checkbox state** — the item heading's checkbox is a **5-state** class, `[ x~>-]`. `[ ]` is unchecked (eligible to run); `[x]` / `[~]` / `[>]` / `[-]` all count as **already-marked / not-eligible** — for progress counting (`roadmap.sh:roadmap_progress_counts`), the driver's auto-mark, and wave dependency-satisfaction. Do **not** narrow it to `[ x]` only: `roadmap.sh`, `validate.sh`, and the wave sorter all key on the full class.
- **`**Dependencies:**`** — `—` (none) or a comma-separated list of item numbers. `—` is the form `to-roadmap` emits; the driver's parser also tolerates `-`, `none`, and `n/a` as "no dependency", since roadmaps are hand-edited. Anything else is read as a dependency on an item number, so an unrecognised word becomes a phantom dependency and a hard stop — `validate.sh roadmap` now catches both that and a number with no matching item, before a run can trip on it. The driver **topologically sorts** items into dependency-ordered **waves**: items in the same wave have no unmet dependency and run in parallel; a barrier separates waves.
- **`**Model:**`** — optional per-item hint (`haiku` / `sonnet` / `opus`). The driver passes it as `opts.model` to the per-item implement agent, and scales the plan stage down for a `haiku` hint (sonnet planner at low effort instead of opus). It is **not** validated — a missing or off-list value simply means no hint (defaults apply).

### Roadmap `Spec:` headers

A roadmap may carry optional, **repeatable** `Spec:` header lines, each naming a `.task/spec/<slug>.md` that holds load-bearing cross-item technical decisions. They sit **directly under `# <Title>`, above the intro prose**, ASCII — the same position the `task.md` header block occupies:

```markdown
# <Title>
Spec: [<slug>](../spec/<slug>.md)

<intro prose>

## Prerequisites
```

Line 1 of a roadmap is therefore always its `# <Title>`, as in every other artifact. (Earlier versions put the `Spec:` lines *above* the title, which left a Markdown viewer rendering a stray line before the document's own H1. `validate.sh` never checked a roadmap's line 1, so files in the old shape still validate — nothing needs migrating.)

Items cite specific decisions as `### Spec references → [<slug>](../spec/<slug>.md) §N` — the slug qualifier is required, since several specs may be reachable. Both the header and the citation follow [§ Cross-artifact references](#cross-artifact-references): the label is the identity, the href is for viewers.

When `roadmap-to-workflow` runs the roadmap, it passes these spec paths to each item's plan agent; when `to-plan`/`to-task` open an item by hand, they carry the relevant `Spec:` headers onto the task file so the executing session reads them per `## Executing a task`.

### Roadmap link sections

Two roadmap sections exist to point elsewhere, and both hold **Markdown links**, never bare slugs or paths:

- **`## Prerequisites`** — in-flight work this initiative depends on. A related roadmap is `[<slug>](<slug>.md)` (same directory), a spec `[<slug>](../spec/<slug>.md)`; anything outside `.task/` is a repo-relative or absolute link.
- **`## Backlinks`** — where this initiative came from and what it feeds: the discussion, issue, or doc behind it, plus sibling roadmaps and specs. Same link forms. Omit the section rather than leaving it empty.

---

## Spec file format (`.task/spec/<slug>.md`)

Produced by `to-spec`; user-edited thereafter. A **standalone** home for load-bearing technical decisions — anchors a plan or executing session treats as fixed without re-deriving. `<slug>` is the topic-derived filename and identity, independent of any roadmap; one spec may be cited by many tasks and roadmaps via their `Spec:` headers.

```markdown
# Spec: <Title>

> One-line purpose. Load-bearing technical decisions for <topic> — NOT a full
> implementation plan (the plan owns that). One numbered section per decision;
> tasks and roadmap items cite sections as
> `### Spec references → [<slug>](../spec/<slug>.md) §N`.

## 1. <decision title>
**Decision:** <what was chosen>
**Rationale:** <why — the reasoning that must survive, not be re-litigated>
**Constrains:** <what this pins for consumers; what it leaves free>

## 2. ...
```

Section labels (`## N.`, `**Decision:**` / `**Rationale:**` / `**Constrains:**`) and the `Spec:` header key stay English; prose follows `.task/CLAUDE.md` → Language.

---

## Producer / consumer table

| Artifact | Produced by | Consumed by |
|----------|-------------|-------------|
| *(none — chat only)* | `grill` — an in-chat decision ledger, never a file | the `to-*` capture skill the user runs next |
| `.task/CLAUDE.md` | capture skills' Step 0 setup, per `skills/_lib/setup.md` (once; never rewritten afterwards) + **the user**, by hand | every skill **except `grill`** + every executing session + `task:code-reviewer` — Language, Testing Policy, Build and Tests, Commit Format, tool priority, `## Executing a task`. Reaches consumers two ways: the platform auto-loads it when a session reads a file under `.task/`, and the `## Execution` pointer names it explicitly |
| `.task/task/<slug>.md` | `to-task` (header + `## Description` + `## Execution`); `to-plan` (same + `## Plan`, optional `## Tests`) — `to-plan` also **edits an existing file in place**, see § *promote / revise* above | **the executing session** (reads `## Description`, `## Plan` and `## Tests` if present, follows `## Execution` to `.task/CLAUDE.md`, reads `Spec:` for anchors and `Roadmap:` + `Source item:` for auto-mark); `roadmap-to-workflow` per-item implement agent; **`task:code-reviewer`** (reads `Touches` as fix scope + `Spec:` as fixed anchors — read-only); `validate.sh` (read-only format check) |
| `.task/roadmap/<slug>.md` | `to-roadmap` (initial); user-edited; `roadmap-to-workflow` **driver** flips `- [ ]` → `- [x]` after an item's agent returns OK | `roadmap-to-workflow` driver (loops unchecked items, reads `**Dependencies:**` + `**Model:**` + `Spec:`); `to-plan` / `to-task` (when picking up an item); `validate.sh` (read-only format check) |
| `.task/spec/<slug>.md` | `to-spec` or user | **the executing session** (via a task's `Spec:` header) + `to-plan` (technical-decision anchor) + `roadmap-to-workflow` per-item plan agent; **`task:code-reviewer`** (phase 0 — reads each cited spec as a fixed anchor, read-only); `validate.sh` (read-only format check) |

The executing session writes no separate pipeline artifacts — its implementation lands in the working tree, then in the commit, and `task:code-reviewer` reviews that diff. Auto-mark inside a single-task execution is done by the executing session itself (per `## Executing a task`, after the review returns OK); auto-mark during a roadmap run is done by the **driver**, not the per-item agent, so parallel item agents never race on the roadmap file.

### Setup-gate categories

Three categories, not two:

- **Capture skills** (`to-task` / `to-plan` / `to-roadmap` / `to-spec`) — the *intake-capable* four, in the skills' own wording — auto-run setup in a fresh project by following `skills/_lib/setup.md`: they write `.task/CLAUDE.md` on first use, without a confirmation chip, and never rewrite one that already exists.
- **Consumer skills** (`roadmap-to-workflow`, `validate`) check `.task/CLAUDE.md` and hard-stop if it is absent.
- **`grill`** is exempt from both: it neither checks nor creates `.task/CLAUDE.md`, so it can run at the discussion stage before any setup or capture exists. It never reads or writes anything under `.task/`; dialog mirrors the chat's language.

---

## Bash layer (`skills/_lib/`, `skills/validate/`)

### resolve-ws.sh (root finder only)

Sourced (not exec'd). Runs `find_ai_dir` at source time and **exports `AI_DIR`** = the discovered `.task` directory, via the four-step order in *Root resolution* above. The ancestor walk in step 2 is ceilinged as described above. The walk itself is logical (`pwd`), so a project entered through a symlinked subdir still finds its own `.task/`; the ceiling compares against git's physical paths and is therefore applied only when the logical and physical cwd agree — under a symlinked entry path the walk runs unbounded, as it did before the ceiling existed. No pointer, no `WS_DIR`, no `resolve_ws`, no `TASK_ID_OVERRIDE`. macOS-safe (no `realpath` / `readlink -f`).

### validate.sh (optional self-check, not a gate)

Keeps the `.task/CLAUDE.md` precondition and English parser-stable strings. **No hook calls it.** The skills run it narrowly: each capture validates the one artifact it just wrote (post-write, surfacing the result in its digest — there is no full-scan call at capture entry), and `roadmap-to-workflow`'s Step 0 gate sweeps `all`. Subcommands:

- **`task <slug>`** — validate `.task/task/<slug>.md`:
  - line 1 matches `^# .+` (a title);
  - a `---` separator line is present **in the header block** (before the first `## ` heading) — a thematic break inside the body does not satisfy it;
  - `## Description` is present;
  - `## Plan` is **optional** — if present, it has ≥1 `### Step N:` block;
  - `## Tests` is **optional** — if present, it has ≥1 `### Test N:` block;
  - `## Execution` is present (presence only — the pointer is stamped verbatim, so its text is not re-checked);
  - each `Spec:` header's slug resolves to an existing `.task/spec/<slug>.md` — a miss is a **`WARN`** (dangling reference), not an error (`validate.sh` is advisory, not a gate). The slug is read from the **link label**, so the canonical `Spec: [<slug>](../spec/<slug>.md)` and the legacy bare `Spec: <slug>` check identically (see [§ Cross-artifact references](#cross-artifact-references)). Only header-block `Spec:` lines are scanned — the check stops at the first `---` separator (task) or the first `## ` heading (roadmap), so a `Spec:`-shaped line quoted in a body never WARNs;
  - a `Spec:` header whose link target is not `../spec/<label>.md` is a second **`WARN`** — label/target disagreement, the drift a rename leaves behind. Intra-line only; the bare form has no target and is never flagged.
- **`roadmap <slug>`** — validate `.task/roadmap/<slug>.md`:
  - ≥1 item heading matching `^### - \[[ x~>-]\] N\. <title>` — the checkbox prefix is **required** (an item with a bare `### N.` heading and no checkbox is an error, since the driver's auto-mark and item selection both rely on it);
  - a heading that **near-misses** the canonical form is an error of its own — a checkbox-ish bracket in the wrong shape (`[X]`, a double space, `####`) or a bullet-plus-number with the checkbox deleted. Such a heading is not an item to any consumer (`roadmap_progress_counts` under-counts it, the driver's collector skips it, the block parser opens no block for it), so without this check the file validates clean while an item silently vanishes from the run. This check runs **before** the required-heading guard, so it still speaks when *every* heading has drifted. A `### Spec references → …` citation and a heading opening with a Markdown link are both structurally excluded;
  - **`**Dependencies:**` values are checked against the same file**, for **unchecked items only** (a shipped item's dependency is history no consumer reads, so erroring on it would make a completed roadmap unfixable). The value must be a no-dependency token (`—`, `-`, `none`, `n/a`) or a comma-separated list of item numbers; a number that names no item in the file, and an item that lists **itself**, are errors. The raw value is tested *before* whitespace is stripped, so a hand-written `1 2` is reported as space-separated rather than silently fused into item `12`. Item numbers compare numerically, so `01.` and a dependency written `1` are the same item;
  - **CRLF line endings** are an error: the driver's collector strips only `[ \t]`, so a trailing CR survives into its `**Dependencies:**` / `**Model:**` values, becoming a phantom dependency and a dropped model hint. Flagged once per file rather than normalized in every parser;
  - item numbers are unique, since the driver's auto-mark keys on the number — numbering runs continuously across the whole file and never restarts per phase;
  - each item block carries the `**Ready description:**` label (required — `to-plan` and the executing session key on it to find the item body) and, inside its blockquote, the sub-headings `### Context`, `### Goal`, `### Outcomes`, `### Acceptance criteria` (matched as `> ### <name>`); `### Invariants` is **optional** and not required;
  - dangling `Spec:` headers `WARN` as for `task`.
- **`spec <slug>`** — validate `.task/spec/<slug>.md`: line 1 matches `^# .+`; ≥1 `## N.` numbered decision section. (No `---` separator check — a spec has no parser-stable header block above a body, so there is nothing to separate.)
- **`all`** — validate every `.task/task/*.md`, every `.task/roadmap/*.md`, plus every `.task/spec/*.md`.

`## Execution` is a stamped pointer; `validate.sh` checks it is **present** (presence only, not its exact text). There is **no `Implement-Model:` check** — the per-item model hint lives on roadmap items and is not `validate.sh`'s concern. The dangling-`Spec:` check is the pipeline's only cross-file validation, and only ever a `WARN`; the label/target check beside it reads one line against itself, and the near-miss-heading and `**Dependencies:**` checks read a roadmap against itself, so none of them adds a second cross-file dependency.

### Helpers

| Script | Role |
|--------|------|
| `roadmap.sh` | artifact-path + roadmap parsing helpers: `resolve_artifact_path` (called by `roadmap-to-workflow` and `validate.sh`) and `roadmap_progress_counts` (called by `roadmap-to-workflow` only). The driver's per-item checkbox flip is its mark stage (see [§ execution shape](#roadmap-to-workflow-execution-shape-driver-contract)), **not** a helper here. |
| `roadmap-driver.js` | the static Workflow script `roadmap-to-workflow` invokes via `scriptPath` — dependency waves in, parallel plan / serial implement → review → mark per item; parameterized only through `args` (see [§ execution shape](#roadmap-to-workflow-execution-shape-driver-contract)) |
| `plan-driver.md` | the non-interactive mirror of `to-plan` that the driver's plan agents read instead of the full skill; mirrors [§ task.md format](#taskmd-format-tasktaskslugmd) — a change to that format or to `to-plan` Steps 3–7 changes this file in the same commit |
| `setup.md` | first-run setup: the sub-steps and the `.task/CLAUDE.md` authoring template, read by a capture skill's Step 0 when the file is absent (see [§ `.task/CLAUDE.md` format](#taskclaudemd-format)) |
| `templates/conventional-commits.md` | commit-format fallback: the capture skills' Step 0 setup points `.task/CLAUDE.md` → Commit Format at it when the project declares no convention of its own (no commit-format doc, nothing usable in `git log`) |

---

## Agent layer (`agents/`)

The plugin ships **exactly one** agent: `agents/code-reviewer.md`, resolved as the agent type **`task:code-reviewer`** (plugin `agents/` directories are auto-loaded; the type is `[plugin, ...subdirs, name].join(":")`). It is the pipeline's own review pass — the platform's `/verify` and `/code-review` commands are marked `disable-model-invocation`, so neither a subagent nor a session that was told `implement …` can run them, and the failure is silent (an unlisted command is skipped, not refused).

It is invoked identically from both execution paths, always given the task artifact's path, plus a reference string to echo in its digest when the caller has one — a roadmap run passes `#N <item-slug>`; a plain session may omit it, and the reviewer then defaults to the task slug:

- a plain session following `## Executing a task` spawns it with the `Agent` tool (depth 0 → 1);
- `roadmap-to-workflow`'s driver spawns it as its own stage in the per-item serial loop (depth 1 → 2).

Contract:

- **Find → verify → fix.** Candidates are collected from the diff, each proved or refuted independently, and only CONFIRMED defects are edited. An unproven candidate is dropped, never fixed — inside a roadmap autopilot an unverified "fix" becomes a commit nobody reviewed. The **one** later entry into the fix phase is a Build and Tests failure traced to this diff: the failing run is its own proof, so it re-enters the fix phase rather than forcing a `FAIL` on a defect the reviewer can see and repair.
- **Fix scope = `Touches` + regressions this diff introduced outside them.** `Touches` is authored before the code exists, so it is a scope hint, not an exact list; everything else confirmed goes to the report.
- **Verification rides inside the review.** The agent runs `.task/CLAUDE.md` → Build and Tests end to end, fails the item on a red run, and reports an undeclared command as an explicit skip.
- **Implement commits, the reviewer amends.** The implementation commits its own work; the reviewer stages its fixes and `git commit --amend`s, keeping the message per `.task/CLAUDE.md` → Commit Format. History stays one item = one commit. If the implementation was never committed, the reviewer leaves its fixes uncommitted rather than rewriting an unrelated commit.
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
- **(b) Capture grammar.** Every capture **writes its artifact immediately, then prints a structural digest** as visible Markdown message text — not a full draft, and never a pre-write confirmation. The chat discussion (or, for `grill`, the one-question-at-a-time interrogation) *was* the review; re-asking the user to Accept/Edit/Decline distilled content they already discussed is empty ceremony, and the print-then-confirm gate it replaced was the pipeline's most error-prone step. The digest carries: the artifact path, its title, the sections written, the load-bearing decisions/pins captured one line each (for a **spec**, *every* pin — it is read downstream as a fixed anchor, so this is the user's one glance to catch a misstatement), and the `validate.sh` result. It closes by inviting edits against the already-written file ("to change anything, just say so"), then the (a) footer. `grill` writes nothing, so its decision ledger *is* the digest. Corrections happen naturally in chat and against the file (which is git-excluded — a wrong write costs one deletion), not through a chip. **Exactly one chip survives, and it is not about distilled content:** the slug-collision overwrite guard (a pre-write safety check on a destructive action). Step 0 setup does not ask either — it writes `.task/CLAUDE.md`, then reports what it wrote.
- **(c) Path forks.** Every 2–4 option path fork that can't be inferred is presented via `AskUserQuestion` chips.

### Frontmatter

Every skill carries `disable-model-invocation: true` and `user-invocable: true`. (`validate` is a bash-only utility — `skills/validate/validate.sh`, no `SKILL.md` — so it carries no frontmatter.) Artifacts and user dialog follow `.task/CLAUDE.md` → Language — except `grill`, which by design reads nothing under `.task/` and so mirrors the chat's own language instead; parser-stable strings (header keys, section labels, commit trailers, the `## Execution` pointer, cross-artifact link labels, driver return strings) stay English.

### `roadmap-to-workflow` execution shape (driver contract)

- **The driver is a shipped file, not an authored script:** the skill computes the waves, then invokes `skills/_lib/roadmap-driver.js` via the Workflow tool's `scriptPath`, passing `{slug, aiDir, pluginRoot, specPaths, waves}` as real JSON `args` with **absolute** paths — the sandbox cannot expand env vars, and the driver asserts every arg up front, returning a `bad args` line instead of launching an agent against a garbage path. The script never changes between runs, so `resumeFromRunId` replays completed stages from cache.
- **Per-item default is OPUS-PLANS / SONNET-IMPLEMENTS / REVIEWER-REVIEWS / DRIVER-MARKS:** a first `agent()` follows `skills/_lib/plan-driver.md` — the non-interactive mirror of `to-plan` — on `{ model: 'opus', effort: 'medium' }`, or `{ model: 'sonnet', effort: 'low' }` when the item's `**Model:**` hint is `haiku`, and writes `.task/task/<item-slug>.md`, ending on the parser-stable `OK #N <item-slug> planned` the driver reads the slug from; a second `agent()` implements + commits on `{ model: item.model ?? 'sonnet' }`; a third spawns `task:code-reviewer` (`agentType`), which reviews that commit, fixes what it proves, runs Build and Tests, and amends; a fourth, cheap mark agent flips the item's checkbox (next bullet). Context passes via the on-disk task file — no chat transfer.
- **Dependency-ordered waves:** within a wave, plan agents run in `parallel()` (they write only their own task files) and then implement, review **and mark** run **strictly one at a time** per item, inside the same serial loop — the shared working tree keeps exactly one writer, and item N never starts implementing while item N−1 is still under review. A barrier separates waves. A dependency **cycle** among scoped items (no wave can be formed) is a hard stop, reported for the user to break — never run an item before its dependency lands.
- **Driver auto-marks:** after an item's review returns OK, the driver's own **mark stage** ticks that item's checkbox — a dedicated serial `agent()` (haiku, low effort) running one fully-baked `awk` command, since the Workflow sandbox cannot write files itself. Never the per-item plan/implement/review agents — that is what keeps parallel writers off the roadmap file. The flip **must verify exactly one heading exists for item N** — matching on the full 5-state checkbox class, so `hits` counts *the item exists*, not *the item is unchecked* — and stop the wave otherwise: a drifted, renumbered or duplicated heading would otherwise let the run report success while the next run redoes work already committed. Two properties are load-bearing for the mark stage specifically, because it is the one stage whose entire job is a side effect: it is **idempotent** (an already-ticked item is a no-op that reports OK, so neither an agent re-running the command nor an `agent()` retry after an API error can turn a landed item into a hard stop) and **self-reporting** (both branches echo `MARK-OK #N` / `MARK-FAIL #N`, so the agent reads the outcome off stdout instead of inferring it from an exit code it cannot see). The rewrite is anchored to `^### - [ ]`, never a bare `[ ]`, so it can never touch a literal `[ ]` inside the item's title.
- **Stop-on-FAIL;** parser-stable digest last line `OK|FAIL #N <slug> <summary>`. Digests are LLM output, so the driver **asserts the shape before consuming it** — the plan stage's `OK #N <item-slug> planned`, whose slug becomes the next agent's file path, and the mark stage's `OK #N <item-slug> marked`. A drifted line is a hard stop, not an `undefined` path handed downstream.
- **Graceful fallback:** if the Workflow tool is unavailable, run items one at a time via `to-plan` + a plain implement session, manually. Being a skill whose instructions invoke Workflow is itself the sanctioned opt-in.
