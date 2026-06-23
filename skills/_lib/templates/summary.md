# `summary.md` template — used by `/task:build implement phase`

The implement phase produces `.task/workspace/<task-id>/summary.md`. This file is the single source of truth; the skill step references it instead of restating the template.

## Template

Render in the language of `task.md` Description (`.task/config/config.md` → "Language").

```markdown
# Summary

**Problem:** {What was broken, missing, or needed — the motivation in 1-2 sentences. Not "the task was to…" but why the task existed at all.}

**Solution:** {What was built or changed and the approach taken — written as plain prose, 1-3 sentences. "Added X so that Y" or "Replaced X with Y because Z". Not a list of modified files or classes — the diff has that.}

**Decision:** *(one line; omit if everything was straightforward)*
{Why this approach over the obvious alternative — only if a reader would genuinely wonder "why not just do Y?"}

**Result:** {What the system or user can do now that it couldn't before, or what no longer happens — observable effect, 1-3 sentences. Prefer "X now works / X no longer fails" over "X was modified".}
```

## Rules

- Write for a teammate who missed the context — assume nothing is obvious.
- Lead with **why** (Problem), then **how** (Solution), then **what changed for the outside world** (Result).
- No bullet lists in Solution or Result — prose only.
- File and class names only when they introduce a new concept (e.g., "introduced a `RateLimiter`"); never as location markers ("modified `FooService`").
- **Always overwrite** the existing `summary.md` entirely — old content is irrelevant after each implement run.
