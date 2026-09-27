---
paths:
  - ".claude-plugin/**"
---

# Editing the plugin manifests

- **`version` in `plugin.json` changes only in the release commit** (`CLAUDE.md` § Release procedure), and only when the user asks. The repo hook asks before any edit of `plugin.json`.
- **Every declared path starts with `./`.** The manifest schema requires it; a bare relative path fails validation, and a rejected manifest stops the whole plugin from loading, skills and reviewer agent included.
- **Validate both manifests.** `claude plugin validate --strict .` checks `marketplace.json`. `claude plugin validate .claude-plugin/plugin.json` checks the plugin itself and passes with one expected warning, that the root `CLAUDE.md` is not loaded as plugin context; that warning is why the same check fails under `--strict`.
- **The registration triangle.** The manifest `name` (`task`), the `"workflows"` entry `./skills/_lib/roadmap-driver.js` and the driver's `meta.name` together make `task:roadmap-driver`, the name the roadmap-to-workflow skill invokes. `tests/driver-registration.test.sh` pins all three.
- **`name` is the namespace.** It prefixes every `/task:` command and the `task:code-reviewer` agent type, and `marketplace.json` lists the plugin under the same name. Renaming it is a breaking change.
