# Changelog

All notable changes to this project are documented here. Format — [Keep a Changelog](https://keepachangelog.com/), versioning — [SemVer](https://semver.org/).

This file is maintained in **English** — see [CONTRIBUTING.md](CONTRIBUTING.md#versioning-policy).

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
