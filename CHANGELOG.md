# Changelog

All notable changes to this project are documented here. Format — [Keep a Changelog](https://keepachangelog.com/), versioning — [SemVer](https://semver.org/).

This file is maintained in **English** — see [CONTRIBUTING.md](CONTRIBUTING.md#versioning-policy).

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
