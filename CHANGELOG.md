# Changelog

All notable changes to this project are documented here. Format — [Keep a Changelog](https://keepachangelog.com/), versioning — [SemVer](https://semver.org/).

This file is maintained in **English** — see [CONTRIBUTING.md](CONTRIBUTING.md#versioning-policy).

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
