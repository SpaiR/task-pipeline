---
paths:
  - "tests/**"
---

# Editing the test suite

- **Use the `tests/lib.sh` API.** `t_case`, `assert_eq`, `assert_exit`, `assert_contains`, `t_tmpdir`, `make_repo [--config]`, and `t_summary` at the end of every file (its exit status is the file's verdict). No bats, no npm: bash, awk and git only, with node and jq as optional extras.
- **Paths are physical on purpose.** `t_tmpdir` and `make_repo` return `pwd -P` paths: on macOS `mktemp -d` hands back a path under the `/var` → `/private/var` symlink, and `resolve-ws.sh` applies its ancestor-walk ceiling only when the logical and physical cwd agree. A logical path would test the unbounded-walk branch by accident.
- **Resolution state is yours to set.** `lib.sh` unsets `AI_DIR` and `CLAUDE_PROJECT_DIR`, so set them explicitly per case or per call. Run a helper from inside a `make_repo` fixture, never from the repo root: this checkout's `git config task.root` points at the live dogfood `.task/`.
- **Optional tools skip loudly.** A case file that needs `node` (the driver cases) or `jq` checks `command -v`, prints a `<file>: SKIP — …` line and exits 0. `tests/run.sh` counts that file as passed, so a SKIP line in the output means those checks did not run.
- **Naming.** One `tests/<helper>.test.sh` per `skills/_lib/*.sh` helper, `validate.sh` and `.claude/hooks/*.sh` script (`tests/xref.test.sh` fails a helper without one); driver cases are `tests/driver-*.test.sh`. `bash tests/run.sh <substring>` runs the files whose names contain it.
- **Some tests read text out of other files**, so renaming what they read breaks them:
  - `reviewer-mark.test.sh` runs the flip between the `roadmap-flip` marker comments in `agents/code-reviewer.md`;
  - `driver-waves`, `driver-digest` and `driver-display` extract the driver's pure functions between their `// --- <name>` and `// --- end <name>` markers;
  - `driver-registration.test.sh` matches the manifest `name`, its `"workflows"` path, the driver's `meta.name` and the skill's invocation;
  - `skill-injections.test.sh` counts injections in every `skills/*/SKILL.md` and `.claude/skills/*/SKILL.md`;
  - `xref.test.sh` checks links, anchors, backticked paths, `§` citations, `Step N`, helper coverage and rule globs over the repo's Markdown.
- **Portable scripts.** bash 3.2 safe, POSIX awk (BSD awk and mawk both run the suite).
