---
paths:
  - "agents/**"
  - ".claude/agents/**"
---

# Editing an agent definition

The reviewer's invariants are in `CLAUDE.md` § Invariants and `docs/contract.md` § Agent layer; this is the how-to.

**The plugin's reviewer, `agents/code-reviewer.md`:**

- **The flip command is tested verbatim.** `tests/reviewer-mark.test.sh` extracts the block between the `roadmap-flip:start` and `roadmap-flip:end` marker comments and runs it with only its two value lines substituted. Change the block, its markers or phase 7 together with that test.
- **Its report is parsed.** The digest last line (`OK|FAIL <reference string> <summary>`) and the repeated `MARK-OK #N` line are read by the driver's `digestPassed` and `flipReported`. Change their shape with the driver and `tests/driver-digest.test.sh`.
- **Keep `model` and `effort` pinned** in the frontmatter, so an item's `**Size:**` never lowers its review.
- **Plugin agents ignore `permissionMode`, `hooks` and `mcpServers`.** Adding one does nothing; enforce behavior in the prompt or the tool list.

**The self-audit lens agents, `.claude/agents/self-*-auditor.md`:**

- **They stay read-only by instruction.** Their tools are Read, Grep, Glob and Bash, and they never gain Edit or Write. Bash is for reading; nothing enforces that at runtime, so the rule has to stay in each file's hard rules.
- **They share one finding schema.** The `## Output format — strict` block is byte-identical in every lens file, and `/self-audit` Step 3 merges findings on `(location, category)`. Change the block in all of them and in the skill together; each lens's own paragraph after the block is the only part that differs.
- **Pin `model` in the frontmatter**, as the existing lenses do.
- **Adding a lens** touches `.claude/skills/self-audit/SKILL.md` in several places: the description and intro, the Architecture table, the step 1 roster check, the step 2 agent list, read-set table and Scope-hint oracle list, and the step 3 merge priority, plus a proof rule in the step 5 fixer prompt when its fixes remove rather than repair (as Leanness's do). It also updates the lens count in `CLAUDE.md` § Repo-local tooling and the `CONTRIBUTING.md` tree.
