# Artifact contract — the task-pipeline protocol

Single source of truth for how the task pipeline stores state and how skills hand work to each other. Maintainer-facing.

task-pipeline is a **context-serialization protocol**, not an orchestration engine. The user discusses a task freely in chat, then runs **one short skill** that distils the discussion into a fixed-format Markdown artifact under `.task/`. A fresh or isolated Claude Code session then executes that artifact directly. Orchestration and commits stay delegated to the platform (dynamic Workflows, `.task/CLAUDE.md` → Commit Format), never hand-rolled inside a skill; review is owned by the plugin, as the `task:code-reviewer` agent (`agents/code-reviewer.md`), which also carries verification via `.task/CLAUDE.md` → Build and Tests.

Enforcement is traded for **convention** (this is a solo tool): no hook gate, and `validate.sh` is an optional self-check, never a blocking gate. What you capture — one task, an initiative, or the decisions they must honor — is the **skill name**, never a flag. There are no user-facing flags anywhere: footers, descriptions and examples are flag-free.

```
discuss freely in chat
  ↓
grill                                 ← pre-capture: interrogate the decision, no artifact
  ↓
to-task | to-roadmap                  ← what you capture is the skill, not a flag
to-spec                               ← pins technical decisions, cited via Spec:
  ↓                       ↓
implement session   roadmap-to-workflow   ← the launcher fans items out to sessions
  ↓                       ↓
task:code-reviewer                    ← the plugin's own review pass, spawned by both:
                                        prove → fix within Touches → Build and Tests → commit the fixes
```

- `grill` — **pre-capture, produces no artifact.** Interrogates a plan or decision one question at a time, keeps an in-chat decision-plus-rationale ledger, ends with a pre-mortem (skipped when it would change nothing), and routes to the capture skill: a decision with a rejected alternative to `to-spec`, a multi-task initiative to `to-roadmap`, one task to `to-task`. It stops when no unanswered fork would change the capture, offering a wrap-up-or-keep-going checkpoint when only secondary forks remain. Touches nothing under `.task/`.
- `to-task` — capture chat (or a roadmap item) → `.task/task/<slug>.md`: `## Description` **and** `## Plan` (Goal / Touches / Logic), plus `## Tests` when the testing policy calls for it. Always a fresh capture.
- `to-roadmap` — capture an initiative → `.task/roadmap/<slug>.md`, `## Architecture` section included (components, interfaces between items, per-item sketches, technical ordering), drafted after the decomposition and written in the same single write. Always a fresh capture.
- `to-spec` — capture load-bearing technical decisions → `.task/spec/<slug>.md`; cited by tasks and roadmaps via `Spec:` headers, read by the executing session as a fixed anchor.
- `roadmap-to-workflow` — the one launcher. Reports the roadmap's unchecked items and the user's scope, then invokes the plugin-shipped Workflow driver (`skills/_lib/roadmap-driver.js`, registered as `task:roadmap-driver`, invoked by name with `args`), which computes the dependency waves itself.

**Execution is not a skill.** An ordinary session told `implement .task/task/<slug>.md` reads the artifact, whose `## Execution` pointer sends it to `.task/CLAUDE.md` → `## Executing a task`: implement → commit → `task:code-reviewer` reviews, fixes, commits those fixes on top, and ticks the roadmap item when the task carries one. The behavior is that one section plus the one agent the plugin ships.

---

## `.task/` layout (FLAT)

`.task/` sits **once at the pipeline root**, shared by every worktree of the repo. The layout is flat: one file per artifact, no per-task subfolders, no workspace, log or archive. A closed task is just a file that stays in `.task/task/` (or the user deletes it) — **git history is the record**.

| Path | Role |
|------|------|
| `.task/CLAUDE.md` | Project settings — Language, Testing Policy, Build and Tests, Commit Format, tool priority — plus `## Executing a task`, the one copy of the execution instructions. A **nested `CLAUDE.md`**: the platform loads it into any session that reads a file under `.task/`. Written once by the capture skills' Step 0 setup, then **user-owned**. |
| `.task/task/<slug>.md` | **One file per task.** `<slug>` is both the filename and the identity. Written by `to-task` and the driver's plan agent. |
| `.task/roadmap/<slug>.md` | One file per multi-task initiative. Item backlog with checkboxes. |
| `.task/spec/<slug>.md` | **One file per spec.** Standalone technical decisions, topic-derived slug. Written by `to-spec`. Cited by task and roadmap `Spec:` headers. |
| `.task/.gitignore` | The single pattern `*` that makes `.task/` ignore itself, the file included. Written by first-run setup, recreated by `preflight.sh` when missing, never rewritten when present. |

`.task/` is git-ignored by its own `.task/.gitignore`, not by `.git/info/exclude` or a tracked `.gitignore`. No tracked edits ever land outside `.task/`: the pipeline is invisible to the project, and `rm -rf .task` takes the ignore rule with it. One consequence: ripgrep applies that nested `*` to the folder's own children, so a search scoped to `.task/` (`rg <pat> .task`, a `Grep` whose path is `.task`) returns nothing. The pipeline never searches there — its helpers use shell globs, and every consumer is handed an explicit artifact path. A `.task` line an older install left in `.git/info/exclude` is harmless; nothing removes it.

### Slug as identifier

- The **slug** is kebab-case English, derived from the task's, roadmap's or spec's title — English whatever `.task/CLAUDE.md` → Language says, since it is a filename.
- It is **both the filename and the identity**, never a header line inside the file. There is no task-id, no bracketed `[TASK-ID]`, no umbrella grouping.
- A roadmap item's task file is `.task/task/<item-slug>.md`, where `<item-slug>` is the kebab-case of that item's title.

### Root resolution (`skills/_lib/resolve-ws.sh`)

The resolver is a **pure `.task/`-root finder**. It exports **`AI_DIR`** = the discovered `.task` directory, first hit wins:

0. **An `AI_DIR` already set** is kept only when it holds `CLAUDE.md` — the evidence a caller's own resolution leaves; `write-task.sh` and `preflight.sh` rely on it to hand their root to the `validate.sh` child. An inherited value without a `CLAUDE.md` is ignored and steps 1–4 run.
1. **`git config --local task.root`** — the anchor first-run setup records, **claimed only on evidence**, two checks, both required: `<root>/.task/CLAUDE.md` exists, **and** `<root>` belongs to this repo — its git common dir equals ours (main worktree root, a subdir-hosted `.task/`, any linked worktree, a `--separate-git-dir` checkout), or it is exactly `dirname(git-common-dir)` (a bare repo's container). The anchor is an absolute path in `.git/config`, which travels with the repo when it is moved or copied. After a **move** the path is gone; trusting it would make the setup gate call the project unconfigured and write a fresh `.task/CLAUDE.md` while the real one moved with the repo. After a **copy** the path is the *original* repo, which still holds its `CLAUDE.md`; trusting it would have the copy read and write the original's artifacts — the identity check catches that. A stale anchor of either kind falls through to step 2, as does a submodule anchored at its superproject (whose walk ceiling reaches the same `.task/`). Repo-common, so **every worktree resolves the same `.task/` with zero setup** — this is what lets parallel worktrees share one `.task/`.
2. **Upward walk from `$PWD`** for a `.task/CLAUDE.md` ancestor, **ceilinged at the highest directory that still belongs to this project** — the highest of this checkout's top level, the repo's main worktree root (counted only when it holds a `.git`, for the `--separate-git-dir` reason step 3 gives), and for a submodule the superproject's working tree while it is still an ancestor of `$PWD`. The ceiling is checked, the directory above it is not: an unbounded walk would claim a *neighbouring* project's `.task/`, and a checkout with no `.task/` of its own would write every artifact there — silently, because the setup gate finds a `CLAUDE.md` and skips setup. A checkout with no ceiling (not a git repo, or a bare repo with no working tree) keeps the unbounded walk.
3. **`dirname(git-common-dir)/.task`** — how a **sibling** worktree finds the shared `.task/`: the main root is not on its ancestor chain, so step 2 cannot reach it. (A **nested** worktree has the main root as an ancestor, so step 2 reaches it, and a `.task/` sitting between the two.) The main worktree root is claimed only when it actually holds a `.git`; with `git init --separate-git-dir=…` that path is merely where the git dir was parked, so the checkout's own top level is used instead.
4. **`$CLAUDE_PROJECT_DIR/.task`** when that path already holds a `CLAUDE.md` (evidence, not merely the variable being set), else the relative `./.task` — so a call from outside a project still fails cleanly on the setup gate.

**Producers write under the resolved `$AI_DIR`, never a cwd-relative `.task/`.** Each capture skill reads it from the Step 0 block, and every helper resolves it for itself (or inherits a caller's, step 0) — a cwd-relative write from a subdirectory or a linked worktree would land the artifact in a second `.task/` the validator never looks at. `.task/<kind>/<slug>.md` in this document and in the skills is shorthand for `$AI_DIR/<kind>/<slug>.md`.

---

## `.task/CLAUDE.md` format

A **nested `CLAUDE.md`**, not a bespoke config format. The platform loads it into any session that reads a file under `.task/` — the executing session, `task:code-reviewer`, and every capture skill. Two properties follow and are load-bearing:

- **The auto-load fires only for file-read tools.** A session that opens an artifact with `cat` or `sed` never triggers it. That is why `task.md` carries an explicit `## Execution` pointer, and why the reviewer reads the file explicitly in its phase 0.
- **It is not re-injected after `/compact`** (a project-root `CLAUDE.md` is; a nested one is not). It reloads on the next read of a file under `.task/`.

The file is written once by first-run setup; the procedure and the authoring template live in `skills/_lib/setup.md`, which each capture skill's Step 0 reads when the file is absent. The shape below is the contract that template must keep producing:

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
 out of code and commits → implement the Plan → commit per Commit Format →
 spawn `task:code-reviewer`, which also ticks the roadmap checkbox when `Roadmap:` + `Source item:`
 are present — the session never ticks it itself}
```

Rules:

- **Written once, then user-owned.** Setup writes it on first use, with no confirmation chip, and reports what it wrote. It is **never rewritten** afterwards — an existing file is left untouched even when a section is missing or a detected value went stale. To regenerate, the user deletes the file and re-runs any capture. Do not add a re-stamp or section-repair path: the invariant costs less than any wording it would fix. Only a missing `.task/.gitignore` is recreated, by `preflight.sh`; `git config task.root` is written by setup and not restored afterwards.
- **`## Language`, `## Testing Policy`, `## Build and Tests`, `## Commit Format` and `## Executing a task` are always present.** Consumers look them up by heading and read an absent one as *nothing declared*, not *look elsewhere* — a missing **Build and Tests** turns every review into a skipped verification run. When the project's own `CLAUDE.md` already documents one, the section stays and its body shrinks to a `**Source:** \`CLAUDE.md\` → \`## <Heading>\`` pointer, and `## Commit Format` may instead point at a whole file, `**Source:** <path>`. Consumers resolve either shape — they read the named file, only the named heading when there is one, and use its value; a pointer is not an empty section. Only `## Code Navigation` / `## Code Editing` may be omitted outright.
- **`## Executing a task` is the single copy of the execution instructions**, so editing it reaches artifacts written earlier.
- Section headings are parser-stable English; the prose inside follows `## Language`.

## Cross-artifact references

Every reference from one `.task/` artifact to another is a **Markdown link** — an artifact is read as often by a human in a Markdown viewer as by an agent, and a bare slug is a dead end there:

| Where | Form |
|-------|------|
| `task.md` header | `Roadmap: [<slug>](../roadmap/<slug>.md)` |
| `task.md` header | `Spec: [<slug>](../spec/<slug>.md)` |
| roadmap header | `Spec: [<slug>](../spec/<slug>.md)` |
| roadmap item citation | `> **Spec references:** [<slug>](../spec/<slug>.md) §N` |
| roadmap `## Architecture` citation | `[<slug>](../spec/<slug>.md) §N`, inline in a bullet |
| `## Execution` pointer | `> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its …` |

Hrefs are relative to the **artifact's own directory**, which is what a Markdown viewer resolves against. `.task/task/`, `.task/roadmap/` and `.task/spec/` all sit one level under `.task/`, so a sibling-kind reference is always `../<kind>/<slug>.md` and `.task/CLAUDE.md` is always `../CLAUDE.md`.

**The label carries the identity; the href is for viewers.** A consumer takes the slug from the link **label** and rebuilds the canonical `$AI_DIR/<kind>/<slug>.md` itself. It must never follow the relative href literally: an agent's cwd is the project root, not `.task/task/`, so `../spec/x.md` would resolve to a sibling of the repository. Every consumer that resolves one of these headers is written that way: `## Executing a task`, `agents/code-reviewer.md` phase 0, `to-task` Step 1a, `roadmap-to-workflow` Step 0 (roadmap-level header), the driver's plan stage via `skills/_lib/plan-driver.md` (per-item citation), and `validate.sh:check_spec_refs`.

**The bare form stays readable.** `.task/` artifacts are hand-edited, so a consumer accepts `Spec: <slug>` (and `Roadmap: <slug>`) as well. Producers emit the link form; `validate.sh` unwraps the label — tolerating backticks and trailing text around it — before checking the reference, and never flags a bare slug as malformed, only as dangling when the spec does not exist.

**The target is checked, but only against its own label.** `validate.sh` WARNs when a `Spec:` header's target is not `../spec/<label>.md` — an intra-line consistency check, not a second cross-file one. Every other consumer follows the label and therefore *works*, so a target left stale by a rename would fail silently and only for humans: exactly the navigation the link form exists to provide.

An existing `.task/CLAUDE.md` is the one consumer no format change reaches, since it is never rewritten. A `## Executing a task` written against an older header form still reads correctly because the link label *is* the slug it asks for; a user who wants the current wording deletes the file and re-runs a capture.

## `task.md` format (`.task/task/<slug>.md`)

One format, produced by `to-task` and by the driver's per-item plan agent, both through `write-task.sh`, both always with a `## Plan`. The slug is the **filename**, never in the title.

```markdown
# <Title>

Roadmap: [<slug>](../roadmap/<slug>.md)   (optional; roadmap items only — load-bearing)

Source item: #N                           (optional; the item number in the roadmap)

Spec: [<slug>](../spec/<slug>.md)         (optional, repeatable; each cites a spec anchor)

---
## Description
Why + what, distilled from the chat.

## Plan                  (always written; see the rule below)
### Step 1: <short title>

**Goal:** <the observable end state this step reaches>

**Touches:**

- `path/one`
- `path/two` (<symbol>)

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
- **`Roadmap:` / `Source item:`** are optional header lines above the `---` separator, load-bearing for `task:code-reviewer`'s auto-mark phase. Keep them **ASCII and above `---`**.
- **`Spec:`** is an optional, **repeatable** header line above `---`. Each names a `.task/spec/<slug>.md` the executing session reads as a fixed technical anchor before implementing. Load-bearing; **ASCII and above `---`**.
- **Cross-artifact headers are Markdown links** — [§ Cross-artifact references](#cross-artifact-references) holds the form and the label rule.
- **`---`** on its own line separates the header block from the body.
- **Every header line is its own paragraph**, with a blank line after it, the title's included. A Markdown preview merges adjacent lines into one paragraph, and a line directly above `---` turns the whole header block into a setext heading. The parsers read the header line by line, so the blank lines cost them nothing.
- **`## Description`** is mandatory: the "why + what" from the chat.
- **`## Plan`** is mandatory: every producer writes it, and `validate.sh` errors on a task file without one. Each step is a `### Step N:` block with the three-layer contract **Goal / Touches / Logic**: `Goal` is the observable target; `Touches` lists the files, one bullet each, and scopes review fixes; `Logic` is optional guidance. Each field starts its own paragraph after a blank line, for the same preview reason.
- **`## Tests`** is optional. When present, each `### Test N:` block states one assertion. `.task/CLAUDE.md` → Testing Policy governs whether the task warrants tests.
- **`## Execution`** is a one-line pointer stamped verbatim by `write-task.sh` — the exact blockquote above, agent-facing English, never translated and never expanded back into instructions. Roadmaps and specs carry none. It is load-bearing because the platform auto-loads `.task/CLAUDE.md` only for file-read tools (see [§ `.task/CLAUDE.md` format](#taskclaudemd-format)).

### Language split

Artifact prose — Description, Plan and Tests bodies, roadmap and spec prose, the architecture section's intro blockquote — follows `.task/CLAUDE.md` → Language, and so does user dialog. `grill` is the exception: by design it reads nothing under `.task/`, so it mirrors the chat's own language. Everything parser-stable stays English: header keys (`Roadmap:`, `Source item:`, `Spec:`), section headings, the field labels and blockquote sub-headings of a roadmap item, spec section labels, cross-artifact link labels, commit trailers, the `## Execution` pointer, the skills' digest and footer markers, and every driver and reviewer digest line.

The `## Execution` blockquote carries no placeholders, so every task file a given version writes gets it **byte-identical**. `validate.sh` checks only that `## Execution` is *present*, so a paraphrase would ship unflagged. An artifact written by an earlier version may carry an older wording of the pointer; nothing re-stamps an existing file, and both wordings name the same file, so that is not drift — only a *newly written* pointer that departs from the current blockquote is a finding.

### A driver rerun regenerates the item's own file

Nothing edits a task file in place: `write-task.sh` only writes whole files. The driver's per-item plan agent, on a rerun after a failed implement, finds this item's own file already there and has nobody to ask (`plan-driver.md` D2). It regenerates the file the way `to-task`'s regenerate chip does — a fresh write with `--force`, the Description re-derived from the item's ready description — so an item edited since the failed run is planned from its new text.

The `--force` is earned by the header match of `roadmap-item.md` step 5: `Roadmap:` names this roadmap and `Source item:` this item. A file whose headers differ is an unrelated namesake — it gets a disambiguated slug and is never overwritten. Hand edits to the item's own file do not survive a rerun: the roadmap item, not the task file, is what a rerun plans from.

---

## Roadmap file format (`.task/roadmap/<slug>.md`)

Produced by `to-roadmap`, `## Architecture` section included, in one write; user-edited thereafter. `roadmap-to-workflow` reads it through `roadmap-items.sh` to find the unchecked items for the driver, and `task:code-reviewer`'s last phase flips one status line `- [ ] Done` → `- [x] Done` per item once its review passes (auto-mark — see [§ Agent layer](#agent-layer-agents)).

Whole-file skeleton, in this order:

```markdown
# <Title>                     ← line 1, the document's own H1
Spec: [<slug>](../spec/<slug>.md)     (0..n, directly under the title, above the intro;
                                       a blank line between two of them)

<intro prose: what the initiative is, in a paragraph or two>

## Prerequisites              (omit rather than leave empty)
## Phase summary              (a table: phase, what lands, which items)
## Architecture               (the technical layer, see § Roadmap architecture section)
## Phase 1 — <name>           (one section per phase, each holding its items)
## Phase 2 — <name>
## Out of scope
## Backlinks                  (omit rather than leave empty)
```

Item numbers run **continuously across the whole file**, never restarted per phase, since the reviewer's auto-mark keys on the number alone.

Each item:

```markdown
### 1. <Task title>

- [ ] Done

**Dependencies:** — / 1, 2, ...

**Size:** S | M | L      (optional per-item hint)

**Ready description:**

> **Context**
>
> Why this task, what it unblocks. Distinct from Goal.
>
> **Goal**
>
> The target state. Behavioral — no project file/symbol names.
>
> **Outcomes**
>
> - Observable property of the system after this task.
>
> **Invariants**          (optional — omit when the item has none)
>
> - Contract that must hold across the change.
>
> **Acceptance criteria**
>
> - Testable assertion.
>
> **Spec references:** [<slug>](../spec/<slug>.md) §N      (optional, repeatable)
```

The item is the heading **plus its status line**: the first non-blank line under `### N. <title>` is `- [ ] Done`, a checkbox a Markdown preview renders as one. The checkbox never sits in the heading itself, where a preview prints it as literal text. The Ready description's sub-headings are quoted **bold lines**, never headings, each its own paragraph between bare `>` lines; every field outside the quote is its own paragraph too, since a preview merges adjacent lines.

Load-bearing item fields for `roadmap-to-workflow`:

- **Checkbox state** — the status line's checkbox is a **5-state** class, `[ x~>-]`. `[ ]` is unchecked (eligible to run); `[x]` / `[~]` / `[>]` / `[-]` all count as **already-marked / not-eligible** — for progress counting (`roadmap.sh:roadmap_progress_counts`), the reviewer's auto-mark, and wave dependency-satisfaction. Do **not** narrow it to `[ x]`: `roadmap.sh`, `validate.sh` and `roadmap-items.sh` (whose `DONE` line feeds `computeWaves`) all key on the full class.
- **`**Dependencies:**`** — `—` (none) or a comma-separated list of item numbers. `—` is the form `to-roadmap` emits; `roadmap-items.sh`, the parser that feeds the driver, also tolerates `-`, `none` and `n/a`, since roadmaps are hand-edited. Anything else is read as a dependency on an item number, so an unrecognised word becomes a phantom dependency and a hard stop — `validate.sh roadmap` catches both that and a number with no matching item before a run can trip on it. The driver topologically sorts items into dependency-ordered **waves** (`computeWaves`): items in one wave have no unmet dependency and run in parallel; a barrier separates waves.
- **`**Size:**`** — optional per-item hint (`S` / `M` / `L`): how much judgment the work needs, not how important it is. `roadmap-items.sh` upper-cases the value and reports a missing or off-list one as `M`; the driver maps the size to each stage's model and effort ([§ execution shape](#roadmap-to-workflow-execution-shape-driver-contract)). `validate.sh` does not check it. A `**Model:**` line from an older roadmap is no longer read: it is an ordinary body line, and the item runs as `M`.

### Roadmap `Spec:` headers

A roadmap may carry optional, **repeatable** `Spec:` header lines, each naming a `.task/spec/<slug>.md` that holds cross-item technical decisions. They sit **directly under `# <Title>`, above the intro prose**, ASCII — so line 1 of a roadmap is always its `# <Title>`, as in every other artifact:

```markdown
# <Title>
Spec: [<slug>](../spec/<slug>.md)

<intro prose>

## Prerequisites
```

Items cite specific decisions as `> **Spec references:** [<slug>](../spec/<slug>.md) §N`, the last line of the Ready description — the slug qualifier is required, since several specs may be reachable. Header and citation both follow [§ Cross-artifact references](#cross-artifact-references).

`roadmap-to-workflow` passes these spec paths to each item's plan agent; `to-task`, opening an item by hand, carries the relevant `Spec:` headers onto the task file so the executing session reads them per `## Executing a task`.

### Roadmap architecture section

Every roadmap `to-roadmap` writes carries one `## Architecture` section; a hand-written roadmap may lack it and stays valid — its planners then have nothing to follow. The section holds the **technical shape** of the initiative: which components it builds or changes, what crosses between items, a module-level sketch per item, and technical ordering. It fills the gap between the items (behavioral by design, no project names) and a spec (decisions with rationale, no layout): a component map is neither, and without a home of its own it drifts into specs as restated roadmap items. It sits directly above the first `## Phase <N> — …` heading, after `## Phase summary`, or in a file without numbered phases above the `## ` section holding the first item.

```markdown
## Architecture

> Intended technical shape of this initiative — planners follow it and state a
> reason where the code forces a deviation. Decisions with rationale live in specs.

### Components                       (required)
- `<name>` — new | existing · `<module path>` — role in this initiative.

### Interfaces between items         (optional — omit when none)
- #2 → #4, #5 — `<name>`: what crosses the boundary; form pinned in [<slug>](../spec/<slug>.md) §N.

### Item sketches                    (required while unchecked items remain — one bullet per item)
- #1 — module-level sketch: which components it touches and how.

### Technical ordering               (optional)
- #3 before #6 — reason. Mirrored in item #6's `**Dependencies:**`.
```

- **Real names are expected here** — the behavioral rule binds only an item's `**Outcomes**` / `**Goal**` / `**Invariants**`. What stays out is plan-level detail: no `file:line`, no step lists, no code block over 5 lines. A choice whose *reasoning* must survive re-derivation belongs in a spec, which the section then cites.
- **Items are referenced as `#N` inside bullets, never as headings.** A `### <digits>.` sub-heading reads as a second copy of item N, which breaks the reviewer's one-heading-per-item mark gate.
- **It is intended shape, not a fixed anchor.** A spec is honored verbatim; this section is what the planner follows unless the code forces otherwise, and a deviation carries its reason in the plan.
- **Who reads it:** the planners — `to-task` on an item and the driver's per-item plan agent, both through `skills/_lib/plan-driver.md` § Core step 1. The executing session and `task:code-reviewer` do not: by then the section is embodied in the Plan's `Touches` and `Goal`s, and the reviewer's fixed anchors stay the specs. The Description stays behavioral either way; technical shape enters only through the Plan.
- No parser consumes the section: item counting, `roadmap-items.sh` and the reviewer's roadmap flip all key on `### N.` headings with a status line and pass it by. `validate.sh` checks it advisory-only (see [§ validate.sh](#validatesh-optional-self-check-not-a-gate)).

### Roadmap link sections

Two roadmap sections exist to point elsewhere, and both hold **Markdown links**, never bare slugs or paths:

- **`## Prerequisites`** — in-flight work this initiative depends on. A related roadmap is `[<slug>](<slug>.md)` (same directory), a spec `[<slug>](../spec/<slug>.md)`; anything outside `.task/` is a repo-relative or absolute link.
- **`## Backlinks`** — where this initiative came from and what it feeds: the discussion, issue or doc behind it, plus sibling roadmaps and specs. Same link forms. Omit the section rather than leaving it empty.

---

## Spec file format (`.task/spec/<slug>.md`)

Produced by `to-spec`; user-edited thereafter. A **standalone** home for technical decisions a plan or executing session treats as fixed without re-deriving. `<slug>` is the topic-derived filename and identity, independent of any roadmap; one spec may be cited by many tasks and roadmaps via their `Spec:` headers.

```markdown
# Spec: <Title>

> <One sentence of your own: which technical decisions this spec pins, and for what.>

## 1. <decision title>

**Decision:** <what was chosen>

**Rationale:** <why — the reasoning that must survive, not be re-litigated>

**Constrains:** <what this pins for consumers; what it leaves free>

## 2. ...
```

The intro is written for this spec, never this template's wording. Each section holds one numbered decision; tasks and roadmap items cite it as `**Spec references:** [<slug>](../spec/<slug>.md) §N`. Each of the three parts starts its own paragraph after a blank line — a Markdown preview merges adjacent lines into one paragraph.

**The decision test.** Every section's **Decision** names a concrete technical artifact — a type, a format, a protocol, a boundary rule — and its **Rationale** names at least one rejected alternative. A section that fails it is not a decision: a restated roadmap item or a component layout is an initiative's technical shape, which lives in the roadmap's `## Architecture` section ([§ Roadmap architecture section](#roadmap-architecture-section)) and is written by `to-roadmap`, never by `to-spec`. The section says *what goes where*, the spec says *why this form over that one*, and the section cites the spec where a shape it describes is pinned.

---

## Producer / consumer table

| Artifact | Produced by | Consumed by |
|----------|-------------|-------------|
| *(none — chat only)* | `grill` — an in-chat decision ledger, never a file | the `to-*` capture skill the user runs next |
| `.task/CLAUDE.md` | capture skills' Step 0 setup, per `skills/_lib/setup.md` (once; never rewritten) + **the user**, by hand | every skill **except `grill`**, every executing session and `task:code-reviewer` — Language, Testing Policy, Build and Tests, Commit Format, tool priority, `## Executing a task`. Reaches them two ways: the platform auto-loads it when a session reads a file under `.task/`, and the `## Execution` pointer names it explicitly |
| `.task/task/<slug>.md` | `skills/_lib/write-task.sh`, on behalf of `to-task` and the driver's plan agent, whose reruns **regenerate the item's own file whole** with `--force` (see § *A driver rerun regenerates the item's own file*). No caller assembles the file itself | **the executing session** (reads `## Description`, `## Plan`, `## Tests` if present, follows `## Execution`, reads `Spec:` for anchors); the driver's per-item implement agent; **`task:code-reviewer`** (`Touches` as fix scope, `Spec:` as fixed anchors, `Roadmap:` + `Source item:` for auto-mark — read-only); `validate.sh` |
| `.task/roadmap/<slug>.md` | `to-roadmap` (the whole file, `## Architecture` included, in one write — never edits an existing one); user-edited; **`task:code-reviewer`** flips `- [ ]` → `- [x]` as its last phase, once its review of that item passes | `roadmap-to-workflow` — `roadmap-items.sh` parses unchecked items' `**Dependencies:**` + `**Size:**` for Step 1, Step 0 reads the `Spec:` headers, and the driver consumes both only as its `args` (`items` / `done` / `specPaths`), never opening the file; `to-task` (picking up an item); `to-task` and the driver's plan agent read `## Architecture` as the intended shape, via `plan-driver.md` § Core step 1; `validate.sh` |
| `.task/spec/<slug>.md` | `to-spec` or user | **the executing session** (via a task's `Spec:` header); `to-task` and the driver's plan agent (fixed anchors); **`task:code-reviewer`** (phase 0 — reads each cited spec, read-only); `validate.sh` |

The executing session writes no separate pipeline artifacts: its implementation lands in the working tree, then in the commit, and `task:code-reviewer` reviews that diff. Auto-mark on both paths is done by **`task:code-reviewer`**, as its last phase and only once its verdict is OK — never by the executing session, a plan agent or an implement agent. In a roadmap run the review sits inside the driver's per-item serial loop, so the roadmap file has one writer at a time and parallel plan agents never touch it.

### Setup-gate categories

Every skill except `grill` opens on the same fixed block, substituted into its body by `!`-preprocessing over `skills/_lib/preflight.sh` (see [§ Helpers](#helpers)) — the gate costs no tool call, and `CONFIG: present|absent` is what the three categories below branch on. `AI_DIR:` from that block is the root every artifact path in the skill is relative to.

**Nothing else in a skill body may look like that injection.** The scan is positional — a `!` at line start or after whitespace, followed by a backticked command — and it runs over the raw body, so prose that merely *shows* the syntax is executed too: the platform runs every injection it finds and aborts the whole skill invocation when one fails. Quoting does not save it: the pass that blanks ordinary code spans exempts a span whose preceding character is a backtick or a `!`, which is exactly what wrapping the example in double backticks produces. Each of the four skills therefore holds exactly one injection, its own Step 0 call, and `tests/skill-injections.test.sh` pins that count; `grill` holds none. Describe the unexpanded-line case in words instead of reproducing it.

Three categories:

- **Capture skills** (`to-task` / `to-roadmap` / `to-spec`) auto-run setup in a fresh project by following `skills/_lib/setup.md`: they write `.task/CLAUDE.md` on first use, without a confirmation chip, and never rewrite one that already exists.
- **Consumer skills** (`roadmap-to-workflow`) and the `validate` utility check `.task/CLAUDE.md` and hard-stop if it is absent. The stop rests on the bash layer — `preflight.sh`'s `CONFIG: absent` and `validate.sh`'s precondition error (exit 2) — and a prompt edit must not relax it.
- **`grill`** is exempt from both: it neither checks nor creates `.task/CLAUDE.md`, so it runs at the discussion stage before any setup or capture exists. It never reads or writes anything under `.task/`.

---

## Bash layer (`skills/_lib/`, `skills/validate/`)

### resolve-ws.sh (root finder only)

Sourced, not exec'd. Runs `find_ai_dir` at source time and **exports `AI_DIR`** via the order in [§ Root resolution](#root-resolution-skills_libresolve-wssh), after keeping an already-set `AI_DIR` that holds a `CLAUDE.md` (step 0 there). The walk in step 2 is logical (`pwd`), so a project entered through a symlinked subdir still finds its own `.task/`; the ceiling compares against git's physical paths and is therefore applied only when the logical and physical cwd agree — under a symlinked entry path the walk runs unbounded. macOS-safe: no `realpath` / `readlink -f`. Git paths come through one helper, `_git_abs`, which asks for `--path-format=absolute` (git 2.31+) and accepts the answer only when it is a single line starting with `/`; older git echoes the flag back as output, so the helper falls back to plain `rev-parse` made absolute with `pwd -P`.

### validate.sh (optional self-check, not a gate)

Keeps the `.task/CLAUDE.md` precondition and English parser-stable strings. **No hook calls it.** The skills run it narrowly: each capture validates the one artifact it just wrote (post-write, surfacing the result in its digest), and `roadmap-to-workflow`'s Step 0 gate sweeps `all`. Exit 0 clean, 1 on any `ERROR`, 2 on a usage or precondition error; `WARN` lines are informational. Subcommands:

- **`task <slug>`** — validate `.task/task/<slug>.md`:
  - line 1 matches `^# .+` (a title);
  - a `---` separator line is present **in the header block** (before the first `## ` heading) — a thematic break inside the body does not satisfy it;
  - `## Description` is present;
  - `## Plan` is **required**, with ≥1 `### Step N:` block;
  - `## Tests` is **optional** — if present, it has ≥1 `### Test N:` block;
  - `## Execution` is present (presence only — the pointer is stamped verbatim, so its text is not re-checked);
  - each `Spec:` header's slug resolves to an existing `.task/spec/<slug>.md` — a miss is a **`WARN`** (dangling reference), not an error. The slug is read from the **link label**, so the link form and the bare `Spec: <slug>` check identically. Only header-block `Spec:` lines are scanned — the check stops at the first `---` separator (task) or the first `## ` heading (roadmap), so a `Spec:`-shaped line quoted in a body never WARNs;
  - a `Spec:` header whose link target is not `../spec/<label>.md` is a second **`WARN`** — label/target disagreement, the drift a rename leaves behind. Intra-line only; the bare form has no target and is never flagged.
- **`roadmap <slug>`** — validate `.task/roadmap/<slug>.md`:
  - ≥1 item heading matching `^### N\. <title>`, and under **each** one outside `## Architecture`, a status line `- [<state>] Done` as the first non-blank line — a heading without it is an error, since the reviewer's auto-mark and item selection both read the status line;
  - a heading that **near-misses** the canonical form is an error of its own — a checkbox-ish bracket in the heading (a heading opening with a Markdown link, `### [text](url)`, is excluded: the bracket body is capped at one character), a bullet before the number, or a `###` number without the `### N. ` spacing — and so is a `- [ ] Done` status line no item heading owns, the trace a heading drifted to another level (`#### N.`, `## N.`) leaves behind. Such a heading is not an item to any consumer (`roadmap_progress_counts` under-counts it, `roadmap-items.sh` skips it, the block parser opens no block for it), so without this check the file would validate clean while an item silently vanished from the run. This check runs **before** the required-heading guard, so it still speaks when *every* heading has drifted;
  - **`**Dependencies:**` values are checked against the same file**, for **unchecked items only** (a shipped item's dependency is history no consumer reads, so erroring on it would make a completed roadmap unfixable). The value must be a no-dependency token (`—`, `-`, `none`, `n/a`) or a comma-separated list of item numbers; a number that names no item in the file, and an item that lists **itself**, are errors. The raw value is tested *before* whitespace is stripped, so a hand-written `1 2` is reported as space-separated rather than silently fused into item `12`. Item numbers compare numerically, so `01.` and a dependency written `1` are the same item;
  - **CRLF line endings** are an error: `roadmap-items.sh` strips only `[ \t]`, so a trailing CR would survive into the `**Dependencies:**` / `**Size:**` values it hands the driver, becoming a phantom dependency and a dropped size hint. Flagged once per file rather than normalized in every parser;
  - item numbers are unique, since the reviewer's auto-mark keys on the number, and start at 1 — an item `0.` or a `0` dependency is an error, because the driver asserts `n >= 1` and would otherwise refuse a roadmap that validated clean;
  - each item block carries the `**Ready description:**` label (required — `to-task` and the driver's plan agent, both through `skills/_lib/roadmap-item.md` step 3, key on it to find the item body) and, inside its blockquote, the sub-headings `**Context**`, `**Goal**`, `**Outcomes**`, `**Acceptance criteria**` (matched as a whole quoted line, `> **<name>**`); `**Invariants**` is optional;
  - dangling `Spec:` headers `WARN` as for `task`;
  - an optional `## Architecture` section is checked **advisory-only** — every finding is a `WARN`, since no parser consumes the section and any roadmap `ERROR` stops `roadmap-to-workflow` from launching: more than one such section; a missing `### Components`, or a missing `### Item sketches` while unchecked items remain; an `#N` reference with no item heading (scanned inside the section only, code spans dropped, skipped when glued to a word, path or entity character so a link anchor like `.md#2-x` never reads as item 2, while `#2→#4` counts both). Any `## Architecture` heading counts as the section, trailing text included. The one `ERROR` inside it is the existing bare-`### N.` check, whose message there names the section and points at a `- #N —` bullet instead.
- **`spec <slug>`** — validate `.task/spec/<slug>.md`: line 1 matches `^# .+`; ≥1 `## N.` numbered decision section. No `---` check — a spec has no header block to separate from a body.
- **`all`** — validate every `.task/task/*.md`, `.task/roadmap/*.md` and `.task/spec/*.md`.

The dangling-`Spec:` check is the pipeline's only cross-file validation, and only ever a `WARN`; every other check reads a file against itself.

### Helpers

| Script | Role |
|--------|------|
| `preflight.sh` | one-call entry state for a skill's Step 0, substituted into the skill body by `!`-preprocessing rather than run as a tool call. `bash preflight.sh <capture\|workflow>` prints a fixed block — `PLUGIN_ROOT: <abs>` (the plugin root, which the Workflow driver cannot expand for itself), `AI_DIR: <abs>`, `CONFIG: present\|absent`, one `ROADMAPS: <slug> <done>/<total> unchecked=<n,n>` line per roadmap (`unchecked=none` when fully ticked — over `0/0` it means no item heading parsed, which consumers stop on as a heading problem rather than calling the roadmap complete; `<slug> ?/? unchecked=unreadable` when the file could not be read, so a failed read cannot pass for a finished roadmap; `ROADMAPS: none` when there are none), then `TASKS:` / `SPECS:` slug lists for kind `capture` (what `to-task`, `to-roadmap` and `to-spec` pass), or a `VALIDATE:` section holding `validate.sh all`'s output for kind `workflow`. Exit 0 whenever the block printed — an absent config is reported in `CONFIG:`, never as a status — and 2 only on a bad kind. The line prefixes are the contract; skills branch on them. Its one side effect: on `CONFIG: present` it recreates a missing `$AI_DIR/.gitignore` (the self-ignoring `*`), never rewriting an existing one, never writing on `CONFIG: absent` (first-run setup owns that), and swallowing a failed write so the block still prints |
| `resolve-ws.sh` | sourced, never run: the pure `.task/`-root finder that exports `AI_DIR`, sourced by `preflight.sh`, `write-task.sh`, `roadmap-items.sh` and `validate.sh`; `roadmap.sh` relies on its caller having sourced it, and `detect-project.sh` takes its directory as an argument instead. Order and evidence rules: [§ Root resolution](#root-resolution-skills_libresolve-wssh) and [§ resolve-ws.sh](#resolve-wssh-root-finder-only) |
| `roadmap.sh` | artifact-path and roadmap-parsing helpers: `resolve_artifact_path` (called by `roadmap-items.sh` and `validate.sh`; an argument holding a `/` is a path, used as given, and a bare slug resolves under `$AI_DIR/<kind>/` only — never in the cwd, where a stray file named like the slug would shadow the artifact) and `roadmap_progress_counts` (called by `preflight.sh` only; one pass prints `total:`, `done:` and `open:` — the item numbers still `[ ]` — so the heading grammar is written once). The per-item checkbox flip is `task:code-reviewer`'s last phase ([§ Agent layer](#agent-layer-agents)), **not** a helper here |
| `write-task.sh` | the single owner of `task.md` assembly: `bash write-task.sh --slug <slug> …` writes `$AI_DIR/task/<slug>.md` whole — staged beside the target and renamed into place — then validates it. Owns the header link forms, the `---` separator, the section order and the one copy of the `## Execution` pointer; section bodies arrive as `--description` / `--plan` / `--tests` files (body only, no heading), and `--plan` is required. Refuses rather than guessing: exit 2 on a usage error (a missing or blank `--plan` included, and a body file that cannot be read or is a directory; a blank `--tests` body just drops the `## Tests` section), exit 4 on an existing slug without `--force`, exit 5 when the write itself fails (unwritable `.task/`, full disk) and the old file is left as it was. Prints `WROTE:` + `VALIDATE:`; exit 0 whenever the write happened, so the caller judges WARN/ERROR from the lines, and `WROTE:` is printed only once the file is on disk. Validate's exit code never leaves the script, so the one fatal case — a missing `.task/CLAUDE.md` — reaches callers as the `ERROR precondition: CLAUDE.md not found` line in the `VALIDATE:` block, which is what they key on. Callers: `to-task`, and `plan-driver.md`, whose driver reruns regenerate the item's own file with `--force` |
| `roadmap-items.sh` | the roadmap's items as data, for the driver's args: `bash roadmap-items.sh <slug-or-path>` prints one `N<TAB>deps<TAB>size<TAB>title` line per **unchecked** item (`deps` empty for none, `size` one of `S` / `M` / `L`, defaulting to `M`) plus a trailing `DONE<TAB><n,…>` of the already-marked numbers. Sorts nothing and filters nothing — order and scope are `computeWaves`' job. Exit 1 when the roadmap does not resolve or cannot be read, so an unresolved path can never read as a completed roadmap; exit 2 on a missing argument. Callers: `roadmap-to-workflow` Step 1 (the driver's `items` / `done` args) and its Output (the after-run unchecked count) |
| `roadmap-driver.js` | the static Workflow script `roadmap-to-workflow` invokes by name as `task:roadmap-driver`: the roadmap's unchecked items in, parallel plan / serial implement → review per item out (the review ticks the checkbox). Its pure functions are marker-delimited so the tests extract them verbatim: `computeWaves(items, done, scope)` (`tests/driver-waves.test.sh`), `digestPassed(line, n, itemSlug)`, `flipReported(text, n)` and `flipFailed(text, n)` (`tests/driver-digest.test.sh`), `itemPhase(w, n, title)`, `runReport(headline, landed)` and `digestSummary(line, n, itemSlug)` (`tests/driver-display.test.sh`). Parameterized only through `args` — see [§ execution shape](#roadmap-to-workflow-execution-shape-driver-contract) |
| `plan-driver.md` | **the plan pipeline itself**, in two parts. `## Core` — anchors (specs as fixed ones, the source roadmap's `## Architecture` as the intended shape a step may depart from with a stated reason), ascending-cost codebase analysis, `tests_required`, the three-layer `### Step N:` draft, the self-check, the write via `write-task.sh` — is followed by `to-task` (its Steps 3–7 are pointers into it) *and* by the driver's per-item plan agent, so the interactive and non-interactive paths cannot drift. `## Driver mode` holds only what that agent does differently: its prompt inputs, its non-interactive rules, and the parser-stable `OK #N <slug> planned` / `FAIL …` digest the driver parses |
| `roadmap-capture.md` | **the roadmap capture flow**, one copy: context load, the decomposition's harvest-or-brainstorm branch, the module-level read of the code over the fixed items, the architecture's harvest-or-rounds branch, decision routing, drafting self-check, slug-collision guard (**Pick different slug** / **Overwrite**), the one write, validate call and the report-only post-save self-check, plus the `## Forbidden` list binding every roadmap it writes. `to-roadmap` keeps only its Step 0 setup gate and its digest; its Steps 1–7 are a pointer into this file's `## Core` |
| `roadmap-item.md` | the from-roadmap block, one copy: resolve the roadmap, pick `#N`, read the `**Ready description:**` blockquote, collect the cited and roadmap-level spec slugs, derive `<item-slug>` and decide whether an existing file with that slug is this item's earlier capture or an unrelated namesake. Read by `to-task` Step 1a (every step) and `plan-driver.md` § Driver mode (steps 3–5 — the prompt carries steps 1–2's results) |
| `detect-project.sh` | the facts first-run setup picks from: `bash detect-project.sh [dir]` prints `ROOT:`, one `COMMANDS: <source>: <names>` line per manifest that declares any (`package.json` scripts, `Makefile` targets), `COMMIT_FORMAT_DOC:`, `TEST_CONVENTION:` (a documented TDD rule, with file and line), `README_LANG:` / `COMMIT_LANG:` (ASCII vs non-ASCII prose, with a sample — evidence, not a verdict), and `PROJECT_CLAUDE_MD:`. Every line always prints, `none` included. Exit 0 unless the argument is not a directory. Sole caller: `setup.md` step 2 |
| `setup.md` | first-run setup: the sub-steps and the `.task/CLAUDE.md` authoring template, read by a capture skill's Step 0 when the file is absent (see [§ `.task/CLAUDE.md` format](#taskclaudemd-format)) |
| `templates/conventional-commits.md` | commit-format fallback: setup points `.task/CLAUDE.md` → Commit Format at it when the project declares no convention of its own (no commit-format doc, nothing usable in `git log`) |

---

## Agent layer (`agents/`)

The plugin ships **exactly one** agent: `agents/code-reviewer.md`, resolved as the agent type **`task:code-reviewer`** (plugin `agents/` directories are auto-loaded; the type is `[plugin, ...subdirs, name].join(":")`). It is the pipeline's own review pass. The platform's `/verify` and `/code-review` are marked `disable-model-invocation`, so neither a subagent nor a session that was told `implement …` can run them, and the failure is silent — an unlisted command is skipped, not refused. So **no agent, skill or `## Executing a task` text may instruct a call to either**, and verification is never a separate skill: it rides inside this agent, via `.task/CLAUDE.md` → Build and Tests.

It is invoked identically from both execution paths, always given the task artifact's path, plus a reference string to echo in its digest when the caller has one — a roadmap run passes `#N <item-slug>`; a plain session may omit it, and the reviewer defaults to the task slug. A roadmap run also names the roadmap item to tick (`#N` in the absolute roadmap path), which wins over the artifact's headers; a plain session leaves it to the artifact's `Roadmap:` + `Source item:`:

- a plain session following `## Executing a task` spawns it with the `Agent` tool (depth 0 → 1);
- `roadmap-to-workflow`'s driver spawns it as its own stage in the per-item serial loop (depth 1 → 2).

Contract:

- **The reviewed range is derived, not assumed.** Phase 1 walks back from `HEAD` while each commit's files intersect the `Touches` set, capped at 10 commits and stopped by a commit that plainly belongs to other work; the base is the parent of the oldest included commit (the empty tree when that commit is a root commit), and `HEAD~1` when there is no `## Plan` to match against. When nothing is included, the working tree decides, counting only this task's change (a `Touches` path, or one the plan plainly produces — a user's unrelated edit or a stray untracked file does not count): such a change means the implementation was never committed, so the base is `HEAD` and only the working tree is reviewed, untracked files included; without one, a `HEAD` that merely missed `Touches` is the implementation, so the base is `HEAD~1`, and a `HEAD` that is plainly another task's leaves nothing to review. An empty diff under review is a `FAIL`, never `0 candidates`. An implementation that landed as several commits is reviewed whole, and the range is reported as `reviewed range: <base>..HEAD (<K> commits)`.
- **Candidate gathering fans out on sonnet.** Phase 2's sub-agents read one file or subsystem each and report candidates; the proving in phase 3 stays on the reviewer's own model, where the judgement is. One level of fan-out, read-only, no edits.
- **Find → verify → fix.** Candidates are collected from the diff, each proved or refuted independently, and only CONFIRMED defects are edited. An unproven candidate is dropped, never fixed — inside a roadmap autopilot an unverified "fix" becomes a commit nobody reviewed. The **one** later entry into the fix phase is a Build and Tests failure traced to this diff: the failing run is its own proof.
- **Fix scope = `Touches` + regressions this diff introduced outside them.** `Touches` is authored before the code exists, so it is a scope hint, not an exact list; everything else confirmed goes to the report.
- **Verification rides inside the review.** The agent runs `.task/CLAUDE.md` → Build and Tests end to end — read from `$AI_DIR/CLAUDE.md`, never a cwd-relative `.task/`, which a linked worktree lacks — fails the item on a red run, and reports an undeclared command as an explicit skip.
- **Implement commits, the reviewer commits its fixes on top.** The reviewer stages only the files it changed and writes its own `fix(<scope>): address review findings` commit per `.task/CLAUDE.md` → Commit Format, one body bullet per fix. Nothing already committed is ever rewritten — no amend, no rebase, no reset — so history is one item = the implementation's commits plus at most one review-fix commit. A clean review commits nothing, and neither does one whose Build and Tests ended red: the fixes stay in the working tree under a `FAIL`. If the implementation was never committed, the reviewer leaves its fixes uncommitted rather than sweeping someone else's work into its own commit — and when the task has a roadmap item, the verdict is `FAIL` and nothing is ticked, since the next item's commit would absorb the work the checkbox claims.
- **Explicit phases with a mandatory output each** (intake → diff → find → prove → fix → Build and Tests → commit → tick the roadmap item). `0 findings` is a declared state, and a report that does not enumerate what was checked per `Touches` file is a failed review, not a passed one.
- **Parser-stable digest last line:** `OK|FAIL <reference string> <summary>` — the shape the roadmap driver parses for its implement stage too.
- **Auto-mark is its last phase (7).** Once the verdict is OK and a roadmap item is known — named by the driver, or read from the artifact's `Roadmap:` + `Source item: #N` — it runs one fully-baked `awk` flip, verbatim bar the two value lines, and never edits the roadmap by hand. The flip must find **exactly one** `### N.` heading for item N with a status line as the first non-blank line under it, matching that line on the full 5-state checkbox class so the count means *the item exists*, not *the item is unchecked*; zero headings, two, or one without a status line — or a roadmap whose directory cannot be written (read-only directory or filesystem, full disk) — leave the file untouched and turn the verdict into `FAIL`, since a silent miss would let the next run re-implement work already committed. It is **idempotent** (an already-ticked item is a no-op that reports OK, so a re-run or an `agent()` retry cannot turn a landed item into a hard stop) and **self-reporting** (both branches echo `MARK-OK #N` / `MARK-FAIL #N`, so the agent reads the outcome off stdout, not an exit code it cannot see). The rewrite touches only that status line, anchored to `^- [ ]`, so a literal `[ ]` in the title, or a checklist further down the item, is safe. `tests/reviewer-mark.test.sh` extracts the command between its marker comments and runs it against fixtures.
- It writes **nothing else** under `.task/`: the artifact, specs and config are read-only to it, and so is every other line of the roadmap.

Plugin agents ignore `permissionMode`, `hooks` and `mcpServers`; `model`, `effort`, `tools`, `disallowedTools`, `skills`, `maxTurns` and `isolation` are honored. `isolation` is deliberately **absent** — the reviewer must see and edit the same working tree the implementation used. `model` / `effort` are pinned in the frontmatter so an item's `**Size:**` never lowers its review: the driver passes the review stage neither.

## Hook

There is **no hook**: the plugin ships no `hooks/hooks.json`. Enforcement is convention — no `PreToolUse` gate, and `validate.sh` is opt-in.

---

## Handoff

There is **no active-task pointer**: the **artifact path is the handle**. Every `to-task` run ends with a copy-paste handoff footer naming the artifact path explicitly:

```
→ Next: implement it now, or in a fresh session run: `implement .task/task/<slug>.md`
```

---

## Marker inventory

The pipeline's only markers are `git config task.root` and `.task/.gitignore`. `task.root` lets parallel worktrees of a repo share one `.task/`; `.task/.gitignore` keeps that `.task/` out of git, and lives inside it so deleting the folder deletes the marker too. There is no active-task pointer ([§ Handoff](#handoff)) and no per-worktree file.

---

## Interaction conventions

Human-facing dialog only — parser-stable strings and artifact content are untouched.

- **(a) Next-step footer.** Every user-facing output ends with a `→ Next:` footer naming what to do next — one or more commands, each pasteable as written, or the fix to make before rerunning one — or with `→ Done.` (a short closing note may follow it) when the flow is complete. Agents with no user in the loop — the driver's plan agent, `task:code-reviewer` — end on their parser-stable digest line instead. Footers are flag-free; the handoff footer above is the canonical form for the `to-*` skills.
- **(b) Capture grammar.** Every capture **writes its artifact immediately, then prints a structural digest** as visible Markdown message text — not a full draft, and never a pre-write confirmation: the chat discussion (or, for `grill`, the interrogation) *was* the review, and re-asking the user to accept distilled content they already discussed is empty ceremony. The digest carries the artifact path, its title, the sections written, the load-bearing decisions or pins one line each (for a **spec**, *every* pin — it is read downstream as a fixed anchor, so this is the user's one glance to catch a misstatement), and the `validate.sh` result. It renders as Markdown, so a numbered list is plain `1.` lines, never `- 1.`, and a blank line follows every list. It closes by inviting edits against the already-written file ("to change anything, just say so"), then the (a) footer. `grill` writes nothing, so its decision ledger *is* the digest. Corrections happen in chat and against the file — a wrong write costs one deletion, since `.task/` is ignored — not through a chip. **Exactly one chip survives, and it is not about distilled content:** the slug-collision overwrite guard, a pre-write safety check on a destructive action. Step 0 setup does not ask either — it writes `.task/CLAUDE.md`, then reports what it wrote.
- **(c) Path forks.** Every 2–4 option path fork that can't be inferred is presented via `AskUserQuestion` chips.

### Frontmatter

Every skill carries `disable-model-invocation: true` and `user-invocable: true`. (`validate` is a bash-only utility — `skills/validate/validate.sh`, no `SKILL.md` — so it carries no frontmatter.)

Every skill also carries an `argument-hint`, the placeholder the slash-command autocomplete shows for its optional argument. Each mirrors that skill's own **Input:** line and stays flag-free:

| Skill | `argument-hint` |
|-------|-----------------|
| `grill` | `[topic]` |
| `to-task` | `[<roadmap-slug>[#N] \| context]` |
| `to-roadmap` | `[initiative]` |
| `to-spec` | `[decision area]` |
| `roadmap-to-workflow` | `[<roadmap-slug>]` |

The four skills that call bash — `to-task`, `to-roadmap`, `to-spec`, `roadmap-to-workflow` — also carry `allowed-tools`, one line identical in all four, pre-approving the plugin's own helpers one script at a time:

```yaml
allowed-tools: 'Bash(bash *skills/_lib/preflight.sh* *) Bash(bash *skills/_lib/write-task.sh* *) Bash(bash *skills/_lib/roadmap-items.sh* *) Bash(bash *skills/_lib/detect-project.sh* *) Bash(bash *skills/validate/validate.sh* *)'
```

This is **load-bearing, not a convenience**: a `!`-preprocessed command (Step 0's `preflight.sh` call) never raises a permission prompt — an unmatched one aborts the whole skill invocation — so without the first pattern those skills cannot start. `allowed-tools` **adds** permission, never restricts, and the grant is scoped to the turn that invoked the skill; the injected command always runs on that turn, so it is covered. The rules:

- **One rule per script the model actually invokes.** A single `*skills/_lib/*.sh*` rule would be shorter, but a Bash rule matches raw command text, so its wildcards would fire for *any* script under *any* directory named `skills/_lib/`, including one outside the plugin. `resolve-ws.sh` and `roadmap.sh` get no rule: they are only ever `source`d by the scripts above.
- **Wildcards around the path, not at a fixed offset.** The command is written with the path quoted (`bash "${CLAUDE_PLUGIN_ROOT}/…/preflight.sh" capture`, so project roots containing spaces work) and the pattern is matched against that literal string. Every rule opens with `*` to absorb the unknown install prefix, which the platform reports as a wildcard-before-the-command warning. `${CLAUDE_PLUGIN_ROOT}` is substituted inside `allowed-tools` rules and would anchor them properly, but switching to it is unverified against this quoting, and a rule that stops matching takes the skill down rather than prompting — so it needs one live check before it lands.

`grill` carries no `allowed-tools` — it calls no plugin helper, and its own Bash fact lookups prompt as usual.

### `roadmap-to-workflow` execution shape (driver contract)

- **The driver is a registered plugin workflow, not an authored script and not a path.** `.claude-plugin/plugin.json` declares `"workflows": ["./skills/_lib/roadmap-driver.js"]`, so the platform registers it as `<plugin name>:<meta.name>` — `task:roadmap-driver` — and the skill invokes that **name**. The leading `./` is mandatory: the manifest schema requires it, and without it the manifest fails validation and the whole plugin refuses to load, skills and reviewer agent with it. Renaming either half is a change to this contract: the skill's Step 2 must name exactly what the manifest and the driver's `meta.name` compose, which `tests/driver-registration.test.sh` pins. The Workflow tool's `scriptPath` input is not an option — it is checked for read permission against the invoking session's working directory, and a plugin's own directory is never inside it, so a path invocation fails everywhere except a checkout of the plugin itself. The call passes `{slug, aiDir, pluginRoot, specPaths, items, done, scope}` as real JSON `args` with **absolute** paths (the sandbox cannot expand env vars): `items` is every unchecked item with its `deps`, `done` the already-marked numbers, `scope` one of `'all'` / `'next-wave'` / an array of numbers; the driver derives the waves from them in `computeWaves`, so no wave order is ever passed in, and asserts every arg up front, returning a `bad args` line instead of launching an agent against a garbage path. A positional roadmap path is accepted only when it names `$AI_DIR/roadmap/<slug>.md`, because the items are read, and the checkbox ticked, through the path the driver rebuilds from `slug`.
- **The script never changes between runs, so `resumeFromRunId` replays completed stages from cache.** The skill offers it only for a run interrupted before the driver returned: after a returned stop, the failing stage is itself cached, so a resume would stop at the same place, and a plain rerun is the way on. Labels and phase names are part of each `agent()` call's options, so changing them invalidates the cache for runs started on the older script.
- **Per-item stages are PLAN / IMPLEMENT / REVIEW-AND-MARK, sized by one table.** The driver's `STAGES` constant maps the item's `size` to `{model, effort}` for the first two stages:

  | Size | plan | implement |
  |---|---|---|
  | `S` | opus / medium | sonnet / medium |
  | `M` | opus / high | sonnet / medium |
  | `L` | opus / high | opus / medium |

  Plan is never below implement: its errors reach both later agents. `xhigh` / `max` are not used. A first `agent()` follows `skills/_lib/plan-driver.md` (§ Driver mode, then § Core) on the plan cell, writes `.task/task/<item-slug>.md`, and ends on the parser-stable `OK #N <item-slug> planned` the driver reads the slug from. A second `agent()` implements and commits on the implement cell — always with an explicit `effort`, since an omitted one would inherit the session's. `size` arrives as `roadmap-items.sh` reports it, already `M` when missing or off-list; the driver has no fallback of its own and returns `bad args` for a `size` outside `S` / `M` / `L`. A third spawns `task:code-reviewer` (`agentType`), which reviews that commit, fixes what it proves, runs Build and Tests, commits those fixes on top, and ticks the item's checkbox; it gets neither `model` nor `effort` from the driver, pinning its own ([§ Agent layer](#agent-layer-agents)). Context passes via the on-disk task file — no chat transfer.
- **Dependency-ordered waves.** Within a wave, plan agents run in `parallel()` (they write only their own task files); then implement and review run **strictly one at a time** per item, inside the same serial loop — the shared working tree and the roadmap file each keep exactly one writer, and item N never starts implementing while item N−1 is still under review. A barrier separates waves. A dependency **cycle** among scoped items, or a scope that leaves a dependency unmet, is a hard stop decided in `computeWaves` **before** the first agent is spawned and returned as one explanatory line.
- **The review auto-marks.** The driver passes each review the item number and the roadmap path, and `task:code-reviewer`'s last phase ticks that checkbox once its verdict is OK ([§ Agent layer](#agent-layer-agents) holds the flip's guarantees). There is no mark stage of its own — the Workflow sandbox cannot write files, and the review already runs inside the serial loop that keeps parallel writers off the roadmap. The driver does not take an `OK` digest as proof of the tick: it also requires the flip's own `MARK-OK #N` line, which the reviewer repeats verbatim in its report (`flipReported(text, n)`), and stops the wave when a passing review lacks it — a skipped phase 7 would otherwise leave the item unchecked and have the next run re-implement it. A flip that finds no unique heading for item N (or cannot write the roadmap) comes back as a review `FAIL` and stops the wave, with the item's work already in the tree; the driver recognizes it by the report's own whole `MARK-FAIL #N` line (`flipFailed(text, n)`), never by words in the free-text digest, and only then appends the tick-by-hand remedy to the headline.
- **Stop-on-FAIL.** Digests are LLM output, so the driver **asserts the shape before consuming it**: the plan stage's `OK #N <item-slug> planned`, whose slug becomes the next agent's file path; the implement and review stages' `OK #N <item-slug> <summary>`, where only that exact head counts as a pass (`digestPassed`, so a drifted `**FAIL** #N …` can never let the next item build on one whose review failed). A drifted line is a hard stop, not an `undefined` path handed downstream.
- **Progress display and return value.** Every stage of one item shares one progress group, `W<w> · #<n> <title>` (`itemPhase` — the title cut to 32 code points with a trailing `…`, whitespace collapsed), and its three agents are labelled `1/3 plan`, `2/3 implement`, `3/3 review`. Before the first agent the driver `log()`s the run's shape — item count, wave count, each wave's items with their titles and any dependency not already marked — then one `Wave <w>/<W> — planning …` line per wave and each stage's digest prefixed `[W<w> <stage>]`. Once any agent has run, every return goes through `runReport`: the headline first and unchanged (`roadmap-to-workflow: all items shipped.` / `roadmap-to-workflow stopped in wave …`), then one `#N <item-slug> — <implement summary>; review: <review summary>` line per item whose review passed **and** reported its `MARK-OK #N` flip, in landing order — on a stop too. The headline is the parser-stable part and stays English and first. The returns issued before any agent runs (`bad args`, the `computeWaves` errors) stay one line.
- **No Workflow tool.** If the Workflow tool itself is unavailable, the skill hard-stops rather than looping the items itself: it prints a by-hand recipe (`to-task` on one unchecked item in this chat, then `implement .task/task/<item-slug>.md` in a fresh session, whose `## Execution` pointer carries plan → commit → `task:code-reviewer`, and the reviewer ticks the roadmap checkbox once its review passes) and ends with a `→ Next:` footer. Being a skill whose instructions invoke Workflow is itself the sanctioned opt-in. **An unresolved name is a different case and does not degrade:** the driver ships with the plugin, so `task:roadmap-driver` failing to resolve means a stale snapshot, an update without a restart, or a CLI that does not load plugin workflows — the skill hard-stops with that remedy, because falling back would hide a broken install behind the slowest available path.
