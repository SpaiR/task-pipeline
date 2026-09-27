---
paths:
  - "website/**"
---

# Editing the docs site

- **The site owns user-facing usage and troubleshooting prose.** `docs/usage.md` and `docs/troubleshooting.md` are thin pointers to it; do not regrow prose there.
- **Build before you commit:** `npm --prefix website ci && npm --prefix website run docs:build`. `.github/workflows/docs-check.yml` runs the same build on pull requests, and `docs.yml` deploys from `main`.
- **`base` is `/task-pipeline/`** (`website/.vitepress/config.mts`). Write in-site links root-relative without it, as `/reference/task-layout`; VitePress adds the base.
- **Links out of the site** to `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `docs/contract.md` and files under `agents/` are exempted by `ignoreDeadLinks` in the config. A new out-of-site link target needs a pattern there, or the build fails on it as a dead link.
- **`website/changelog.md` includes the root `CHANGELOG.md`**, so a changelog edit changes the site (and `CHANGELOG.md` is edited only when the user asks).
- **The nav version label** (`text: 'vX.Y.Z'` in the config) changes only in the release commit, per `CLAUDE.md` § Release procedure.
- **A new page** needs a sidebar entry in the config; a new skill page also needs a row in `website/reference/commands.md`.
- **Commits** are `docs(website): …`.
