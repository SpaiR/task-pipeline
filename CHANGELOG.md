# Changelog

All notable changes to this project are documented here. Format — [Keep a Changelog](https://keepachangelog.com/), versioning — [SemVer](https://semver.org/).

This file is maintained in **English** — see [CONTRIBUTING.md](CONTRIBUTING.md#versioning-policy).

## [3.5.1] — 2026-09-01

A patch release for the roadmap autopilot's mark stage, which could stop a wave on an item it had just ticked successfully.

### Fixed
- **The auto-mark stage is idempotent and reports its own result** — a `roadmap-to-workflow` run could stop after an item with `auto-mark matched no unique '### - [ ] N.' heading` even though the checkbox was flipped and the commit had landed. The flip printed nothing, so the mark agent, asked to branch on an exit code it could not see, re-ran the same command to observe it; the second pass found `[x]`, matched nothing, and reported failure. The heading is now matched on the full declared 5-state class `[ x~>-]`, so the hit count means "item N exists" rather than "item N is unchecked" — an already-ticked item becomes a no-op that reports OK, while a missing, renumbered or duplicated heading still stops the wave, which is the property worth stopping on. Both branches echo `MARK-OK` / `MARK-FAIL` and the digest is mapped off stdout, so success is never invisible and no agent has to infer it — this also covers an `agent()` retry after a transient API error, which would have failed identically with a perfectly obedient agent. The rewrite is anchored to `^### - \[ \]`, since with the widened match class the line may already read `[x]` and an unanchored substitution would rewrite a literal `[ ]` inside the item's own title. The driver's stop message now names the remaining failure cause and tells the operator to tick the box by hand and rerun, the item's work being committed by then.
- **Docs realigned with the new semantics** — `CLAUDE.md`, `docs/contract.md`, `roadmap-to-workflow`'s SKILL.md, the `validate.sh` comment, and the autopilot, troubleshooting and reference pages on the docs site all asserted the old unchecked-only match.

## [3.5.0] — 2026-08-27

Cross-artifact references become Markdown links, so a `.task/` file is navigable in a viewer instead of dead-ending on a bare slug, and the per-invocation prompt cost of the capture skills and `roadmap-to-workflow` drops sharply. Non-breaking — every consumer still accepts the bare form, and existing artifacts keep validating.

### Added
- **`Roadmap:` / `Spec:` headers, `### Spec references` citations and the `## Execution` pointer are written as Markdown links** — `Roadmap: [<slug>](../roadmap/<slug>.md)`. The label carries the identity: every consumer rebuilds `$AI_DIR/<kind>/<slug>.md` from the label and never follows the href, which would resolve against the agent's cwd (the project root) rather than the artifact's own directory. The href exists for humans and plan-review tools. Producers emit the link form; consumers, `validate.sh` included, still accept a bare slug, and the unwrap tolerates backticks and trailing text around the link.
- **`validate.sh` warns when a `Spec:` header's target disagrees with its label** — nothing else catches a stale href, since every agent follows the label and works regardless.
- **`validate.sh` flags a near-miss roadmap item heading** (`[X]`, a double space, `####`, a missing `- `). No consumer treats such a heading as an item, so the file used to validate clean while an item quietly dropped out of an autopilot run. `**Dependencies:**` is now checked against the same file too, so a hand-written `1 2` (whitespace-stripped to item 12) or a number with no matching item is caught at capture time instead of hard-stopping a run mid-flight — self-dependencies and CRLF included.

### Changed
- **A roadmap's `Spec:` headers moved under `# <Title>`**, so line 1 of every artifact is its own H1. Files in the old shape still validate.
- **`## Executing a task` now names `## Tests`** — `to-plan` wrote the section and `validate.sh` enforced its shape, but no consumer had ever been told to act on it.
- **First-run setup moved out of the capture skills** into `skills/_lib/setup.md`, read only when `.task/CLAUDE.md` is actually absent. `to-task` had carried roughly 5KB of setup sub-steps plus the template on every invocation, for a procedure that runs once per project; `to-plan` / `to-roadmap` / `to-spec` now point at the same file instead of at "exactly as `to-task` Step 0 does", leaving all four gates near-identical. The template moved byte-identical — its headings are load-bearing for the reviewer's and `to-plan`'s by-heading lookups.
- **The capture skills' Step 0 no longer runs `validate.sh all`** — the full scan was advisory by design (report, never block) while costing a bash run whose output grows with every artifact. The gate keeps only the `.task/CLAUDE.md` existence check; each capture still validates the artifact it just wrote and still reports the result in its digest. `roadmap-to-workflow` keeps its `validate.sh all` gate, whose held-roadmap-error logic depends on the sweep.
- **`roadmap-to-workflow` ships a static driver** — `skills/_lib/roadmap-driver.js`, invoked via `scriptPath` + `args`, instead of re-authoring a ~150-line Workflow script every run; `resumeFromRunId` now caches completed stages cleanly. Per-item plan agents read `skills/_lib/plan-driver.md` rather than the full `to-plan` SKILL.md, dropping roughly 25KB of interactive-only prose, and the planner scales with the item's `**Model:**` hint — a `haiku` item plans on sonnet at low effort instead of opus. The checkbox flip became the driver's own serial mark stage, since the Workflow sandbox cannot write files itself; the exactly-one-match rule still stops the wave.

### Fixed
- **Root resolution no longer claimed a neighbouring project's `.task/`** — the ancestor walk was unbounded, so a checkout with no `.task/` of its own climbed out of the working tree and wrote every artifact into another project's flat namespace, silently: the setup gate found a `CLAUDE.md` there and skipped setup. The walk is now ceilinged at the highest directory that still belongs to this project — its top level, the main worktree root, or a submodule's superproject, whichever is highest and still an ancestor of `$PWD`. Sibling worktrees still reach the shared root through step 3.
- **Three narrower resolution faults behind the same walk** — the ceiling could not be the checkout's top level alone (that broke submodules, landing `AI_DIR` inside `.git/modules`, and any linked worktree whose pipeline root sits above it); step 3 trusted `dirname(git-common-dir)` blindly, which under `--separate-git-dir` names whatever directory holds the git dir, often a neighbouring project; and the walk is now logical with a `$PWD` fallback, so a project entered through a symlink finds its own `.task/` and a deleted cwd no longer degrades to a relative root plus a `getcwd` error on stderr.
- **A drifted heading donated its `Dependencies` and `Model` to the item above it** in `roadmap-to-workflow`'s collector, inventing a phantom dependency or the wrong model with no signal. The collector now resets on any heading, excluding the `### Spec references` citation that legitimately sits inside an item, and terminates only on a drifted item-heading attempt — terminating on any `#` line ate an item's own `Dependencies` and `Model` when it carried a sub-heading or a fenced code comment.
- **A slug collision could overwrite a Plan** — `to-task`'s from-roadmap write is now guarded: the same item rewrites in place, the same item carrying a Plan goes through the Step 2.1 chip, and an unrelated task disambiguates instead of being silently overwritten. `to-plan`'s no-Description promote fork uses that same sanctioned overwrite guard rather than a free-text exchange.
- **`validate.sh` anchors tightened** — `### Step N:` / `### Test N:` require the colon the producers already emit; the `---` separator is accepted only in the header block, so a thematic break in the body no longer masks a deleted separator; `Spec:` headers are scanned only in the header block, so a Spec-shaped line quoted in a body no longer emits a spurious dangling-reference WARN; and a legacy bare `Spec: <slug>` carrying a copied template annotation is no longer mangled into a garbage slug — the trailing-text tolerance had lived only in the Markdown-link branch, contradicting what the contract promised.
- **`roadmap-to-workflow`'s positional-slug branch hard-stopped on a valid slug** — each bash call is a fresh shell, and that branch skips the picker block, the only other place sourcing `roadmap.sh`, so `resolve_artifact_path` was undefined. It sources the helper itself now.
- **`to-plan`'s promote fallbacks cover a missing `---`**, and the two roadmap-resolution stops carry the `→ Next:` footer — a promoted hand-written file otherwise failed the skill's own post-write validate call. `to-plan`'s Step 2b also numbered two consecutive items `3.`, which reads as two phrasings of one step rather than the ordered pair Step 7's write consumes.
- **A zero-match checkbox flip reported OK** — the baked mark command's `|| rm -f tmp` swallowed `awk`'s non-zero exit, so a run that ticked nothing exited 0 and the agent reported success on an unticked box, the exact silent miss the exactly-one-match rule exists to stop. The cleanup branch exits 1 now, and the flip is anchored with `0*` so a hand-written `### - [ ] 07.` heading — which `validate.sh` sanctions as numerically equal to 7 — still matches, while the `\.` anchor keeps 7 from matching item 70.
- **Docs realigned with what ships** — the reviewer's phase 0 not 1, the reviewer listed as a spec consumer, one term for the capture skills, no `hooks` commit scope for a file that never ships, and the site's stale version and artifact paths.

## [3.4.0] — 2026-08-21

Project settings move from a bespoke config file to a nested `CLAUDE.md` the platform loads on its own, and `grill` stops counting questions. **Contains a breaking change** — see Migration.

### Changed
- **`config.md` is replaced by a nested [`.task/CLAUDE.md`](docs/contract.md)** — the platform auto-loads a nested `CLAUDE.md` into any session that reads a file under `.task/`, so the executing session and `task:code-reviewer` pick up Language, Testing Policy, Build and Tests and Commit Format without being told to open a config file. Two limits are load-bearing and shape the rest of the change: the auto-load fires only for file-read tools (never for `cat` or `sed`), and a nested `CLAUDE.md` is **not** re-injected after `/compact`.
- **The file is the user's, not the pipeline's** — setup writes it once, without a confirmation chip, and never rewrites or section-repairs it. Only `task.root` and the git-exclude line are repaired on later runs, so hand edits survive every capture. To regenerate it, delete it and re-run any capture.
- **The stamped `## Execution` block collapsed to a one-line pointer** at `.task/CLAUDE.md` → `## Executing a task`. The execution instructions now exist in exactly one copy, so editing them reaches tasks captured earlier. The pointer stays stamped in every artifact regardless — it is what survives `/compact` and a `cat`-based read.
- **`grill` scales depth to the decision** — the "typical 3–7 questions" anchor is gone, replaced by a functional stopping rule. Forks are asked in descending blast-radius order so an early stop loses the least, a wrap-up-or-keep-going checkpoint hands the stop decision to the user rather than the model, and the pre-mortem is skippable when no answer to it would change the ledger (Step 2's no-manufactured-questions rule, applied to the finale).

### Fixed
- **The docs site build no longer fails on the changelog's own links** — `changelog.md` inlines `CHANGELOG.md` verbatim, so every repo-relative link in it must be exempt from the dead-link check. The v3.3.0 entry added a `README.md` link the exemption list did not cover, and the Pages deploy had failed on it since. `README` now sits alongside the CONTRIBUTING / CLAUDE / contract / agents patterns.

### Migration

`.task/config/config.md` is no longer recognised. Before the next capture:

```bash
git mv .task/config/config.md .task/CLAUDE.md 2>/dev/null || mv .task/config/config.md .task/CLAUDE.md
rmdir .task/config
```

Until you do, the setup gate reports the project as unconfigured and writes a fresh `.task/CLAUDE.md`, orphaning any hand-edited settings; where `.task/` sits in a subdirectory, root resolution falls through to the parent and creates a second `.task/` beside the real one. Existing task files keep working — re-run `/task:to-plan` on one to re-stamp its `## Execution` pointer.

## [3.3.0] — 2026-08-11

The pipeline stops borrowing the platform's review commands and ships its own review agent. Non-breaking — no artifact-shape changes; existing task files keep working, though re-running `/task:to-plan` on one re-stamps its `## Execution` block with the new sequence.

### Added
- **`task:code-reviewer` — the pipeline's own review pass** ([`agents/code-reviewer.md`](agents/code-reviewer.md), the plugin's first and only agent). It runs in explicit phases with a mandatory output each: read the task file and its `Touches` / `Spec:` anchors → gather the committed diff → collect candidate defects (fanning out where the diff warrants it) → **prove or refute each one independently** → fix only what it confirmed, inside `Touches` plus regressions the same diff introduced outside them → run `config.md` → Build and Tests → `git commit --amend` the implementation's commit. An unproven candidate is dropped, never fixed; `0 findings` is a declared state; and a report that doesn't enumerate what was checked per `Touches` file counts as a failed review, not a passed one. It never pushes, never touches a commit other than `HEAD`, and writes nothing under `.task/`.

### Changed
- **`/verify` and `/code-review` are no longer part of the pipeline** — Claude Code 2.1.217 marked both `disable-model-invocation`, and that gate treats every subagent as "the user didn't type this". Worse, a command in that state isn't listed to the model at all, so nothing errored: `roadmap-to-workflow`'s per-item agent and every plain `implement .task/task/<slug>.md` session **silently skipped the review step and still reported `OK`**. The pipeline's review gate had been quietly absent rather than loudly broken, and there is no settings escape hatch. Both execution paths now spawn `task:code-reviewer` instead — a plain session per the `## Execution` block, and `roadmap-to-workflow`'s driver as its own stage in the per-item serial loop.
- **The stamped `## Execution` block carries the new sequence** — implement → commit per `config.md` → Commit Format → spawn `task:code-reviewer` on the diff → tick the roadmap checkbox once the review returns OK. Existing task files keep working; re-run `/task:to-plan` on one to re-stamp it (they only ever named commands that weren't running anyway). Verification is relocated, not dropped: it rides inside the reviewer via `config.md` → **Build and Tests**, which fails the item on a red run and reports an explicit "skipped" when no command is declared.
- **Implement commits, the reviewer amends** — the implement step commits as before and the reviewer folds its fixes into that same commit, so work is durable immediately and one item stays one commit. If the implementation was never committed, the reviewer leaves its fixes in the working tree rather than rewriting an unrelated commit.
- **`roadmap-to-workflow` is now three agents per item** — opus-plans / sonnet-implements / `task:code-reviewer`-reviews. The review runs inside the existing per-item serial loop (not as a `pipeline()` stage), so the shared working tree keeps exactly one writer; auto-mark still belongs to the driver, now after the review; a failed review stops the wave exactly as a failed implement does. The item's `**Model:**` hint no longer reaches the review — the reviewer pins its own model, so a `haiku` item can't get a `haiku` review.
- **Requirements dropped a prerequisite** — no platform slash command has to be available any more; the reviewer only needs the `task` plugin enabled in the session doing the work. Since the `## Execution` block names the agent directly with no fallback, a disabled or missing plugin is now the failure mode to know about — documented on the site's troubleshooting page.
- Two declared invariants were rewritten rather than silently violated: "orchestration, verification, review, and commits are delegated to the platform" ([`CLAUDE.md`](CLAUDE.md)) and "there is no `agents/` directory in v3" ([`CONTRIBUTING.md`](CONTRIBUTING.md)). The commit-scope list gains **`agents`**. Skill count is unchanged at six — the reviewer is an agent, not a skill.

### Fixed

Two full self-audit passes over the skills, the agent, and the bash layer. The findings below are the ones that could cost you work or lie to you about what happened.

- **A stale `task.root` could overwrite a live `config.md`** — the anchor is an absolute path in `.git/config`, so it survives a moved or copied repo and then names where the repo used to live. `find_ai_dir` trusted it on the variable alone (step 4 already demanded evidence), resolved to an `AI_DIR` with no config, reported the project unconfigured, and let intake setup regenerate `config.md` over the real one — losing hand-tuned Build and Tests, Language and tool priority silently. Such an anchor is now ignored and the ancestor walk takes over; the next capture rewrites it.
- **Captures wrote to a cwd-relative `.task/`** — `validate.sh` resolves `$AI_DIR` independently, so a capture run from a subdirectory or a linked worktree wrote into a second `.task/` the validator never looked at. All four capture skills now anchor writes on the root they resolve in Step 0 (`to-roadmap` and `to-spec` did not source `resolve-ws.sh` at all), using `${CLAUDE_PLUGIN_ROOT}` — a bare `skills/_lib/resolve-ws.sh` path does not exist relative to a user project's cwd.
- **`roadmap-to-workflow` reported success where it had guessed** — an unresolved positional slug reached the item scan as an empty path and `awk 'prog' ""` reads stdin, so a typo came back as a fully completed roadmap; the plan digest was consumed with `split(" ")[2]`, so any drift in that LLM-authored line launched the next agent against `task/undefined.md` after the wave's planning was already paid for; and the auto-mark `awk` never checked that it matched, so a drifted heading left the box unticked while the commit landed and the next run redid the work. Each now fails loudly. The wave sorter also read `**Dependencies:** none` as a dependency on a missing item and hard-stopped.
- **The driver's own writes ran in the wrong shell** — the auto-mark `awk` referenced `"$ROADMAP"` from inside the JS Workflow body, where no shell exists. `ROADMAP`, `AI_DIR` and the item paths are now baked literals. Collected `Spec:` paths were dropped instead of being passed to the plan agent, and the paths were stamped into `Spec:` headers the contract defines as bare slugs — a derived `SPEC_SLUGS` now feeds the header while the paths feed the read.
- **`to-plan`'s handoff footer broke the driver** — Step 8 told every run to close with `→ Next: …`, but the driver lifts the item slug out of the plan agent's last line, so it fed the implement stage `.task/task/<a-word-from-the-footer>.md`. Driver mode is now carved out of Step 8 and restated in the driver's own prompt.
- **A proven build failure could not be fixed** — phase 5 of `task:code-reviewer` said "go back to phase 4" on a red build while phase 3 banned fixing anything it had not CONFIRMED, and a failure surfaced by the test run was never a phase-3 candidate. A Build and Tests failure traced to this diff is now the one sanctioned entry point (the failing run is its own evidence), with the trace stated either way. Unattended, that ambiguity turned a one-line break into a FAIL that stopped a whole wave.
- **`to-task` / `to-plan` branch and overwrite gaps** — the overwrite chip offered a flat "Accept" without saying what the colliding file held, though the natural `to-task` → `to-plan` → `to-task` flow derives the same slug and `.task/` is git-excluded, so a Plan lost that way is gone; it now reads the file's headings first and recommends deepening. `to-plan`'s case 1 matched any bare token vacuously and swallowed the roadmap branch; promote mode had no fallback without a `## Execution` anchor and could replace an unrelated same-slug task's Plan with no chip; and free-form `$ARGUMENTS` hit "nothing to capture yet".
- **The pre-draft recap read as a confirmation gate** — `to-roadmap` and `to-spec` opened Step 3 with "once the decision list is confirmed", directly against Step 2 and interaction convention (b). `grill`'s four routing bullets were unordered and its first test was satisfied by every ledger; the tests are now ordered and the spec test narrowed to anchors more than one future task must honor.
- **Hard-stops and footers** — the roadmap-validation, complete-roadmap, too-small-for-a-roadmap and nothing-to-pin stops now carry the `→ Next:` footer convention (a) requires, and both "too small" stops say plainly that nothing was written.
- **`validate.sh`'s precondition error carries its own fix** — a missing `config.md` stated a raw absolute path and no remedy, though the README and reference page both send first-run operators to `validate.sh all` by hand. It now names the four capture skills that write the file, keeping the literal `config.md not found` substring three skills branch on.
- **Commit Format's last resort** — with no project doc and no usable `git log` convention, `to-task` left `config.md` pointing nowhere; it now names the bundled `_lib/templates/conventional-commits.md` the contract had always declared the fallback.

### Docs

- **Version-diff framing removed everywhere** — [`docs/contract.md`](docs/contract.md), [`README.md`](README.md), [`CLAUDE.md`](CLAUDE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), the website, the skill prompts and the bash headers described the pipeline as a diff against v2 ("Removed in v3", "no build/ship step to run", "the mechanism that used to be two separate skills"), naming entities a reader has never had. All restated in present tense; no step, template or hard-stop changed. `CHANGELOG.md` is left alone — it is the record of that history.
- **Corrections in the docs of record** — the producer/consumer table claimed `config.md` is consumed by "every skill" (`grill` reads nothing under `.task/`) and that every `to-*` skill stamps `## Execution` (only `to-task` / `to-plan` do), and omitted `validate.sh` from every "Consumed by" cell; `resolve-ws.sh`'s comments credited worktrees `roadmap-to-workflow` never spawns and documented step 4 without its evidence requirement; `CONTRIBUTING.md`'s tree was missing `skills/grill/`; the site's "config.md not found" cause implied `/task:grill` can hit the gate, and its spec-kit row listed three capture skills where the rest of the page lists four. The `§ task.md format` link pointed at a non-existent anchor.
- **Local meta-skills refreshed** — `/self-audit` and `/self-improve` still described a repo with five skills and no `agents/` directory; the Docs-sync lens now compares against `ls skills/` rather than a hardcoded roster, and covers `CONTRIBUTING.md` and `website/` too.
- **`validate.sh`'s subcommand list has one owner** — the file-header `# Usage:` block was byte-identical to the `--help` heredoc, which alone carries the `<slug>` note and the exit-code line.

## [3.2.1] — 2026-07-23

Patch release. Non-breaking — no artifact-shape changes.

### Fixed
- **`roadmap-to-workflow` wave concurrency** — the script template passed `{ isolation: "worktree" }` to `parallel()`, which the Workflow tool silently ignores, so every wave actually ran all agents concurrently in one shared tree, and true per-item worktrees have no reconciliation step anyway. Waves now plan all items in parallel (each plan agent writes only its own task file, never the tree) then implement them strictly one at a time, the sole mutator of the shared tree — a plan FAIL stops before any implement, an implement FAIL stops as before. Each implement now sees its wave-mates' already-landed commits and `/verify` runs against the integrated state.

### Docs
- **VitePress documentation site** — added a searchable guide/reference site under `website/`, deployed to GitHub Pages: getting-started and core-concepts pages, per-skill workflow guides (grill, single task, roadmaps, autopilot, specs), a comparison against similar tools (superpowers, OpenSpec, spec-kit, Task Master, Matt Pocock's skills), and a full command reference. `docs/usage.md` and `docs/troubleshooting.md` are now thin pointers to the site, which is the single owner of user-facing usage prose.

## [3.2.0] — 2026-07-20

Replaces the confirm-before-write gate with write-then-digest. Non-breaking — no artifact-shape changes.

### Changed
- **Write-then-digest replaces confirm-before-write** — convention (b)'s print-draft → Accept/Edit/Decline gate was the pipeline's most error-prone step (three prior patch releases only papered over it) and re-reviewed content the chat discussion had already settled. Every capture skill now writes its artifact immediately, runs `validate.sh` on the written file, then prints a structural digest (path, title, sections, captured decisions/pins, validate result) inviting edits against the file. `grill` drops its ledger confirmation and prints the ledger as the digest after the pre-mortem. Chips survive only where the question isn't distilled content: config Step 0 setup and the slug-collision overwrite guard. Synced across [`CLAUDE.md`](CLAUDE.md), [`docs/contract.md`](docs/contract.md), and `self-invariants-auditor`.

### Fixed
- **`to-roadmap` / `to-spec` no longer hard-stop on unrelated artifact errors** — Step 0 treated any non-zero `validate.sh` exit as "config malformed → stop", but exit 1 means one or more *existing* artifacts failed validation; `validate.sh` never inspects `config.md` content. A pre-existing broken, unrelated file could block a fresh capture. Both now hard-stop only on a missing `config.md` (exit 2), matching `to-task` and `roadmap-to-workflow`; exit-1 artifact errors surface but don't block.

## [3.1.2] — 2026-07-19

Bugfix release. Non-breaking — no artifact-shape or layout changes.

### Fixed
- **Confirmation gate hardened further** — v3.1.1's "print the draft as message text first" wording did not change model behavior: a post-release transcript showed the turn going straight from bash checks to `AskUserQuestion` with no text block, so the draft was never actually printed. Every confirmation site (`grill`, `to-task`, `to-plan`, `to-roadmap`, `to-spec`) now carries an explicit gate — never emit `AskUserQuestion` until the full draft sits printed above it in the same reply; prior chat discussion does not count. Mirrored in both docs of record ([`CLAUDE.md`](CLAUDE.md), [`docs/contract.md`](docs/contract.md)).

## [3.1.1] — 2026-07-19

Bugfix release. Non-breaking — no artifact-shape or layout changes.

### Fixed
- **Confirmation prints the draft first** — the model was routing all confirmation output through the `AskUserQuestion` call and skipping the draft, so users confirmed content they never saw. Convention (b) is hardened at both docs of record ([`CLAUDE.md`](CLAUDE.md), [`docs/contract.md`](docs/contract.md)) and at every capture-skill confirmation site (`grill`, `to-task`, `to-plan`, `to-roadmap`, `to-spec`) to mandate printing the full draft as visible message text first, then posing the question in the same reply; the question box and option `preview` never render the draft.

## [3.1.0] — 2026-07-19

Adds a pre-capture interrogation skill and tightens the capture flow. Non-breaking — no artifact-shape or layout changes.

### Added
- **`grill` skill** — a pre-capture interrogation that sits at the "discuss freely" stage: it stress-tests a plan or decision one question at a time, keeps a running decision-plus-rationale ledger, ends with a pre-mortem, and routes to the right capture skill (`to-task` / `to-plan` / `to-roadmap` / `to-spec`). It writes no artifacts and touches nothing under `.task/`, so it can run before any capture exists and needs no `config.md`. Brings the pipeline to 6 skills.

### Changed
- **Skills and docs compacted** — skill prompts and docs were trimmed to cut runtime token cost without changing behavior. `validate` is now a bash-only utility (`skills/validate/validate.sh`); its `SKILL.md` is removed.
- **`roadmap.sh` slimmed** — dropped the `resolve_roadmap_path` wrapper and a dead guard.

### Fixed
- **`roadmap-to-workflow` auto-mark** — checkbox ticking is pinned to an anchored `awk` match and its fallback path is corrected, so the driver marks the right roadmap item.
- **Capture flow hardened** — `to-task` / `to-plan` / `to-roadmap` / `to-spec` handle empty and edge-case inputs cleanly; decline and stop branches now end with the canonical `→ Next:` footer and aligned resume cues.
- **`validate` diagnostics** — a task-subcommand miss now reports the paths it searched.

### Docs
- **Contract** — documents the 5-state roadmap checkbox class in [`docs/contract.md`](docs/contract.md).

## [3.0.0] — 2026-07-18

Chat-first rewrite. The pipeline is no longer an orchestration engine with phases, locks, and a hook gate — it is a small set of capture skills. Discuss freely in chat, then fix the discussion into a fixed-format Markdown artifact under `.task/` with one short skill; capture depth is the skill name, never a flag. There is no execution skill — every artifact carries a stamped `## Execution` block that an ordinary session follows to implement, verify, review, and commit. This replaces the entire v1/v2 surface and is breaking with no automatic migration. See **Migration**.

### Added
- **Capture skills** — `to-task` (captures `## Description`), `to-plan` (adds `## Plan`: Goal / Touches / Logic steps), `to-roadmap` (a multi-task initiative), and `to-spec` (a standalone load-bearing technical decision under `.task/spec/<slug>.md`, referenced by tasks/roadmaps via a `Spec:` header). Depth of capture is the skill, not a flag.
- **`roadmap-to-workflow` launcher** — authors and invokes a dynamic Workflow over a roadmap's unchecked items in dependency-ordered waves, opus-plans / sonnet-implements per item by default. The driver ticks each roadmap checkbox after its agent returns OK (never inside the per-item agent).
- **Stamped `## Execution` block** — every artifact carries an English, parser-stable Execution block that a plain session told `implement .task/task/<slug>.md` follows: implement the plan, run `/verify` + `/code-review`, apply review fixes within **Touches**, commit per `config.md` → Commit Format, and tick the roadmap item when `Roadmap:` / `Source item:` are present.
- **Single artifact contract** — [`docs/contract.md`](docs/contract.md) documents the full artifact shapes, producer/consumer table, and bash-layer contract in one place.

### Changed (breaking)
- **Flat `.task/` layout** — `.task/config/config.md`, `.task/task/<slug>.md`, `.task/roadmap/<slug>.md`, `.task/spec/<slug>.md`. No `<task-id>/` subfolders, no `workspace/`, no `log/`, no archive — git history is the record. The **slug** (kebab-case, derived from the title) is the identity; task-ids and `[TASK-ID]` brackets are gone.
- **Bash layer shrunk** — `resolve-ws.sh` is now a pure `.task/`-root finder (no workspace resolution, no pointer read/write/self-heal). Only `validate.sh` and `roadmap.sh` remain alongside it.
- **Orchestration delegated to the platform** — verification, review, and per-item fan-out use `/verify`, `/code-review`, and dynamic Workflows instead of hand-rolled skill logic.

### Removed (breaking)
- **Skills** — `bootstrap`, `design`, `build`, `ship`, `roadmap`, and `auto-roadmap` are removed, along with all phase companion files and the nine audit/runner subagents.
- **Bash machinery** — the lock protocol (`auto-locks.sh`), phase detection (`phase-detect.sh`), fail-log (`fail-log.sh`), touches-gate (`touches-gate.sh`), `derive-task-id.sh`, `preamble.sh`, and the auto-roadmap helpers are all gone.
- **Layout markers** — the active-task pointer, `TASK_ID_OVERRIDE`, per-worktree pointer files, and the roadmap `.spec.md` sidecar are removed. Pipeline markers are exactly `git config task.root` plus the `.task` exclude entry.
- **`docs/spec/*`** — replaced by the single `docs/contract.md`.

### Migration
- No automatic migration from a v1/v2 `.task/` workspace — this is a clean cut. Start fresh: discuss in chat, then run `to-task` / `to-plan` / `to-roadmap` / `to-spec`.
- Replace `/task:design` + `/task:build` + `/task:ship` with: capture via `to-task` / `to-plan`, then tell a session `implement .task/task/<slug>.md` and let it follow the stamped `## Execution` block.
- Replace `/task:auto-roadmap` with `roadmap-to-workflow` over a `.task/roadmap/<slug>.md`.
- Replace `/task:bootstrap` — the four capture skills auto-run setup inline in a fresh project.

## [2.0.0] — 2026-07-13

Interactive-first release. The pipeline now carries a task through each phase with structured questions, so a single bare command replaces most flag fiddling; the advanced flags stay fully functional but move off the everyday surface into a documented "Escape hatches" registry. This release also removes several redundant flags/modes and reworks the multi-worktree `.task/` model — both are breaking. See **Migration**.

### Added
- **Interactive structured-choice layer** — discrete path forks are now asked as `AskUserQuestion` chips in interactive runs: design's fresh-start entry fork and `--from` item picker, build's implement→audit advance, `/task:auto-roadmap`'s roadmap picker and item-scope question (all remaining / only next / pick range). Interactive-only — the autopilot runners still pass explicit flags.
- **Design phase-advance loop** — after each design phase the skill re-detects state and asks once before chaining (Description-ready → build the plan; plan-ready → invoke `/task:build`), so one `/task:design` invocation walks the whole design half instead of needing repeated calls.
- **Bootstrap language + testing-policy detection** — `/task:bootstrap` now detects the repo's language policy and testing-policy mode and presents both as a single accept/decline/edit proposal instead of asking cold.
- **Roadmap decision harvest** — `/task:roadmap` can harvest decisions already settled in the prior conversation into a confirmed Decision Inventory before drafting, converging with the cold-start path on one pre-draft decision list.
- **Roadmap light self-check** — after authoring, `/task:roadmap` runs a report-only three-lens self-check (Coverage / Decomposition / Clarity) over the saved file and offers `--refine` inline only when findings warrant escalation.

### Changed
- **Question-driven cycle; advanced flags hidden** — `--idea` / `--from` / `--auto` / `--next` / `--refine` / `--phase` are removed from README signatures, skill `description` frontmatter, examples, and every user-facing next-step footer. The surviving flags remain functional and are documented once in `docs/troubleshooting.md` § "Escape hatches", each paired with its interactive equivalent; `/task:auto-roadmap`'s own flags stay a documented power surface.
- **Clean build proposes ship; ship commit composed from artifacts** — a clean interactive build flows into ship's single accept/decline/edit confirmation, and the commit header+body are composed from `summary.md` (fallback `task.md`) rather than free-text authoring. The audit tail is quieted to a one-line `### Result` summary (full detail stays in `audit.md`; blocking findings are always shown in full).
- **Bootstrap auto-runs on first design/roadmap** — the first `/task:design` or `/task:roadmap` in an unconfigured project auto-runs `/task:bootstrap` inline, then continues the original request (stops only if you decline).
- **Roadmap `Size` computed, `Class` inferred** — `Size` is derived from the `### Outcomes` count and `**Class:**` is a best-effort inferred, user-overridable hint; a codified archive path replaces ad-hoc naming.
- **Stale active-task pointer self-heals** — a provably-stale pointer (empty / missing workspace subfolder) is cleared with a one-line notice instead of hard-stopping.
- **Canonical next-step footer + one interaction grammar** — every core command ends with a `→ Next:` footer (or `→ Done.`), and content confirmations use one accept/decline/edit grammar.
- **Faster `/task:auto-roadmap` per item** — per-item token load and interactive validate round-trips trimmed; per-item time cut via the model split and lighter audit.

### Changed (breaking)
- **Multi-worktree `.task/` model reworked** — the `.task` symlink and `/task:bootstrap` join-mode are removed. All worktrees of a repo now share one `.task/` resolved via `git config --local task.root` (written by bootstrap; `dirname(git-common-dir)` fallback), and the per-worktree active-task pointer moved from the worktree-root `.task-current` into git's per-worktree dir (`git rev-parse --git-path task-current`). Bootstrapped repos migrate automatically on the next command.

### Removed (breaking)
- **`/task:ship --full` and the hand-supplied commit slug** — `/task:ship` has one mode (full close); the slug is always auto-derived. Both removed forms now fail loud.
- **`/task:ship --next` subtask-transition mode** — removed. This also fixed a bug where `--next` wiped a subtask's Description without archiving `task.md`; every close now archives `task.md`.
- **`/task:build --auto`** — removed; the interactive implement→audit advance question replaces it (the audit ≤2-iteration bound is unaffected).
- **`/task:design --idea` and the design idea phase** — removed; brainstorm a task in chat, then run `/task:design "<description>"`.
- **`--full chore-finalize` recovery convention** — collapsed to a bare `/task:ship`.
- **`validate.sh todo` legacy intake name** — removed; use `validate.sh roadmap <path|slug>`.

### Migration
- Run bare `/task:ship` (default full close, slug auto-derived) instead of `/task:ship --full` or `/task:ship <slug>`.
- Clean up an aborted `/task:auto-roadmap` run with a bare `/task:ship` instead of `/task:ship --full chore-finalize`.
- Replace `/task:build --auto` with a normal `/task:build` and accept the implement→audit advance question when prompted.
- Replace `/task:design --idea` by discussing the task in chat first, then `/task:design "<description>"`; work a multi-item roadmap by re-running `/task:design --from <roadmap>` per item.
- Reach design's plan-refine via `/task:design --phase refine` (repair-level, documented in `docs/troubleshooting.md`).
- Use `validate.sh roadmap <path|slug>` in place of `validate.sh todo`.
- Multi-worktree setups: standalone per-worktree `.task/` is no longer supported — all worktrees share one `.task/` via `git config task.root`, migrated automatically on the next command. To point the pipeline at an existing `.task/` yourself: `git config --local task.root /abs/path/containing/dot-task`.

## [1.1.0] — 2026-07-11

### Added
- **Bootstrap onboarding primer** — after writing `config.md`, `/task:bootstrap` now prints a fixed-template primer that teaches the mental model at first value: the four `.task/` artifacts and what each holds, phase auto-detect on re-run, the umbrella/subtask model, and the exact next command. Static template (localizable per `config.md` → Language).

### Changed
- **`/task:auto-roadmap` collapses the per-item cycle into one item-runner subagent** — now that nested subagents are supported, each item's design → implement → audit → ship runs inside a single disposable `auto-roadmap-item-runner`, returning only a compact report-card digest to the driver. Driver context stays flat, lifting the previous ~15/~25-item auto-compact ceiling on long runs. The per-stage model split, fail-stop, sentinel, and cross-worktree contracts are preserved; `is_last` is now computed via checkbox look-ahead, fixing a latent dangling-umbrella case when a trailing item was already done.
- **Skill descriptions rewritten as trigger→result** — the six user-invocable skill descriptions drop the internal `[N·phase]` prefix codes (which collided across skills) in favor of a when-to-use then what-it-does form, so the `/` menu reads as guidance rather than pipeline taxonomy.
- **Design open names the plan-building next step** — the quick-draft next-step hint now names the action and the artifact (review `task.md`, then run `/task:design` again to build `plan.md`) instead of the opaque "auto-enters blueprint", removing the most common stall before a first ship.
- **README and troubleshooting reworked for new users** — a copy-paste quickstart leads the README (the dense flag list is demoted to a "Command reference"), a new safety section states upfront what the pipeline touches in your code and git, and the troubleshooting page is rewritten around first-run symptoms keyed on the literal strings the tool prints.

## [1.0.1] — 2026-07-10

### Changed
- **Tool-agnostic references** — the authoring guidance and heuristic lists no longer privilege specific products or language stacks. The pipeline already resolved all tooling from `config.md` at runtime; now bootstrap's config-authoring guidance and the README use role-based phrasing, the roadmap per-task verification reminder and the commit fallback template defer to `config.md`, and `touches-gate` path extensions plus `audit-context` lockfile excludes broaden to a language-agnostic superset (a missing entry only skips a fast-path, never yields a wrong result).

### Fixed
- **Pipeline root discovery** — `.task` is now located by a git-style upward walk (`find_ai_dir` in `_lib/resolve-ws.sh`) instead of being assumed at the current working directory. Skill bash helpers (`validate.sh`, `phase-detect.sh`, the context scripts, `close.sh`, `auto-roadmap-context.sh`) previously failed with `config.md not found` whenever the shell had drifted out of the project root; they now resolve `.task` from any subdirectory. Linked-worktree `.task` symlinks are preserved (so the local `.task-current` is still found), and a call from outside any project still fails cleanly with the same message.
- **Roadmap sidecar enumeration** — `/task:auto-roadmap` and `/task:roadmap --refine` no longer list `<slug>.spec.md` / `<slug>.refine.md` sidecars as spurious "[malformed]" or empty roadmaps when enumerating `.task/roadmap/`. Both enumerators now skip the sidecars, matching what `validate.sh` already carved out.

## [1.0.0] — 2026-06-23

First public release. A linear task pipeline for Claude Code — design → build → ship — with explicit, file-backed checkpoints and an off-cycle roadmap track.

### Added
- **Pipeline skills** — `/task:bootstrap` (one-time per-project config), `/task:design`, `/task:build`, `/task:ship`, plus the off-cycle `/task:roadmap` and the `/task:auto-roadmap` autopilot. Phase-decomposed orchestrators (`design` → open / idea / blueprint / refine; `build` → implement / audit) dispatch to companion phase files.
- **Artifact contract** — every stage reads and writes plain Markdown under `.task/` (`task.md`, `plan.md`, `audit.md`, `summary.md`), reviewable without the agent and enforced by a PreToolUse validator hook.
- **Read-only audit lenses** — six auditor-class subagents (Reuse / Simplicity / Clarity for the build audit phase; Coverage / Decomposition / Clarity for `/task:roadmap --refine`) fan out in parallel; build audit runs a bounded, scope-gated auto-fix loop.
- **Roadmap autopilot** — `/task:auto-roadmap` drives a whole roadmap item by item in the interactive session, with a per-item model split (cheaper model for the implement stage via `plan.md → Implement-Model:`).
