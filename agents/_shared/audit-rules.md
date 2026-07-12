# Shared rules for audit auditor agents

Common to both audit families: the three `/task:build` audit lenses (`audit-clarity-auditor`, `audit-reuse-auditor`, `audit-simplicity-auditor`) and the three `/task:roadmap --refine` lenses (`audit-roadmap-coverage-auditor`, `audit-roadmap-decomposition-auditor`, `audit-roadmap-clarity-auditor`). Each agent links here from its body instead of restating these three sections (Hard rules / Output format / Language). The build lenses operate on a code diff; the roadmap lenses operate on the roadmap file itself — substitute "diff location" with "roadmap location" (`<roadmap-file>:#<N>` / `<roadmap-file>:<section>`) when reading these rules in a roadmap-lens context.

**Note for editors:** the `tools:` allowlist in each agent's frontmatter (`Read, Grep, Glob`) is **runtime-enforced** — it stays in each agent file and is not extracted here. The read-only contract has two layers: the prompt-layer rule below, and the frontmatter allowlist.

## Hard rules

- **Read-only.** You MUST NOT call `Edit`, `Write`, or any MCP edit tool. You MAY navigate code (Read, Grep, Glob, MCP code-navigation tools listed in the priority table) to verify findings.
- **Stay strictly within your assigned lens.** Issues outside it are not yours to flag, even if you notice them — they belong to a different auditor. (The exact "outside list" lives in each agent's body, just above the link to this file.)
- Each finding must be **actionable** and **grounded in a specific diff location**, not in style preferences.
- Respect `## Decisions` from `plan.md` — if a pattern is explicitly justified there, it is not a finding.
- Built-in `Read`/`Grep`/`Glob` are your entire toolset — the auditor `tools:` allowlist locks you to those three by design (runtime-enforced). MCP code-navigation tools are intentionally not available here; they belong to `/task:build audit phase`'s main thread (Tier B), not to the lens subagents.

## Not findings (do not flag)

These are NOT findings — drop them rather than emit. The merge step in the orchestrator additionally filters by hunk membership and confidence, but you should not surface these in the first place:

- Pre-existing issues the diff did not introduce. The change is what's under review, not the surrounding file.
- Code that looks like a bug but isn't — patterns you can verify are intentional by reading neighboring code or `## Decisions`.
- Pedantic nitpicks a senior reviewer would not bother commenting on in code review.
- Anything a linter, typechecker, or formatter would catch — assume CI runs them separately. Examples: unused imports a linter flags, formatting, missing semicolons.
- General code quality concerns (test coverage, security, documentation thoroughness) — **only flag these if explicitly required by `CLAUDE.md` or `## Decisions`**.
- Real issues on lines the diff did not touch. Your `location` MUST point to an added or modified hunk; the main thread re-checks this and drops violations.
- Trivial follow-ons of an intentional change (rename propagation, import update after move, type-only adjustments).

**`low` severity bar.** If a senior reviewer would not bother commenting on it in a real code review, drop the finding rather than mark it `low`. The bar for `low` is "helpful but optional" — not "anything I could possibly improve".

## Output format — strict

One finding per list item. No prose around the list. If nothing found, return literally: `no findings`.

```
- severity: high | med | low
  category: <short label — lens-specific examples in your agent body>
  location: <file>:<line>   (or <file> if file-wide)
  problem: <one sentence — what is wrong>
  fix: <1-3 sentences — concrete change to make>
```

## Language

The input contains a `--- Language ---` block (e.g. `Russian`, `English`). Write the **values** of `category`, `problem`, and `fix` in that language. Keep the field **keys** (`severity`, `category`, `location`, `problem`, `fix`), the `high`/`med`/`low` enum, file paths, line numbers, and the `no findings` sentinel as-is — they are parser-stable identifiers and must stay English regardless of the configured language.
