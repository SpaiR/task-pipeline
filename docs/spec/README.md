# Pipeline specification

Authoritative spec for the editing assistant. The root `CLAUDE.md` carries a one-line checklist of every invariant (so the active session always sees them); this directory is **the** source of truth for full reasoning, edge cases, and contracts.

| File | Topic |
|------|-------|
| [pipeline.md](pipeline.md) | Pipeline shape diagram, phase dispatch, off-cycle skills, `/task:auto-roadmap` orchestrator |
| [artifact-contract.md](artifact-contract.md) | `.task/` directory layout, producer/consumer table, identifiers, `task.md` header structure |
| [auto-roadmap.md](auto-roadmap.md) | `/task:auto-roadmap` mechanics: three Step 0 gates, `--items` grammar, lock-file invariants, failure protocol, cross-worktree safety |
| [invariants.md](invariants.md) | All invariants — universal, code-navigation tiers, agent classes, per-skill, `/task:auto-roadmap`, shared prompt preamble |
| [internals.md](internals.md) | Repo layout, bash helpers, agent classes, `.claude-plugin/` manifests, skill frontmatter shape, editing protocol |

Read the relevant file before any non-trivial edit to a skill, agent, or bash helper. The CLAUDE.md checklist lists *what* not to break; the spec explains *why* and *how* to navigate edge cases.
