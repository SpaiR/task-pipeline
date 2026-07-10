# Conventional Commits — Rules

## Format

```
<type>(<scope>): <description>

<body>

<footer>
```

## Types

| Type | When to use |
|------|-------------|
| `feat` | New functionality |
| `fix` | Bug fix |
| `refactor` | Internal change that does not add a feature or fix a bug (rename, restructure, extract) |
| `docs` | Documentation only — README, in-code comments, contributor guides |
| `chore` | Build, dependencies, configuration, CI/CD, tests, formatting — anything not covered above |

## Scope

**Do NOT invent new scopes.** Use one of:
1. **Existing scopes from git history** — run `git log --oneline -50` and use scopes already present in commits.
2. **Reserved scopes for obvious cases:**
   - `docs` — documentation changes only
   - `deps` — dependency updates only

If no existing scope fits and neither reserved scope applies — omit scope entirely.

## Description

- Imperative, present tense: "add", "fix", "update" (not "added", "fixed").
- Lowercase after `:`.
- No period at end.
- Entire first line under 72 characters.
- Language — English.

## Body

- List of specific changes (2-5 bullet points).
- Each bullet starts with `- `.
- Explain **what** and **why**, not **how**.

## Footer

- Breaking changes: `BREAKING CHANGE: <description>` (if applicable).
- Footer is optional — add only for breaking changes.

## Examples

```
feat(editor): add preset drag-and-drop reordering

- implement drag-and-drop for the preset list
- fix tab focus loss during drag operations
- add visual feedback for drop target position
```

```
fix(api): resolve null dereference in resize handler

- add null check for viewport dimensions before the resize callback
- guard against a race condition during initialization
```

```
chore(deps): update http-client to 1.86.13
```
