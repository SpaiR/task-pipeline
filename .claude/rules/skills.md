---
paths:
  - "skills/*/SKILL.md"
  - "skills/_lib/*.md"
---

# Editing a skill or a shared prompt file

The invariants these files must keep are in `CLAUDE.md` § Invariants; this is the how-to.

- **Renumbering a step moves every citation.** Steps are cited across files: the contract, `README.md`, the website pages, other skills and `skills/_lib/*.md` (for example "to-task Steps 3–7", "to-roadmap Steps 1–7"). Search the repo for the skill name next to the old number before you commit. `tests/xref.test.sh` checks only a capitalised `Step N` against the headings of the same `SKILL.md`, so write a reference to another file's steps in lowercase ("to-task's step 3") and check those by hand.
- **A new helper the model runs gets an `allowed-tools` rule** in all four bash-calling skills, keeping the four lines identical, and in the copy under `docs/contract.md` § Frontmatter. A helper that is only ever `source`d gets none.
- **Injection mechanics.** Before the model sees a skill body, the platform runs every `!` that sits at line start or after whitespace and is followed by a backticked command, and every fenced block opened with three backticks and a `!`. A failing one aborts the whole invocation. Double backticks do not quote it. Describe the syntax in words instead. Files under `skills/_lib/*.md` are read at run time, not preprocessed, but the same wording keeps them safe to paste.
- **Point at the single owner, never inline its content.** A skill that needs the `task.md` shape calls `write-task.sh`; one that needs setup, the plan core, the from-roadmap block or the roadmap capture flow points into `setup.md`, `plan-driver.md` § Core, `roadmap-item.md` or `roadmap-capture.md` § Core.
- **`argument-hint` mirrors the skill's `**Input:**` line.** Change both together, and the table in `docs/contract.md` § Frontmatter.
- **Run the skill's eval case when it has one** (`claude plugin eval --case '<name>*' .`, see `evals/README.md`).
