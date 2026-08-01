# roadmap-to-workflow

The one launcher. Fans an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow — parallel planning, serialized implementation, dependency-ordered waves, ticking off the roadmap as items land.

See the [autopilot guide](/guide/autopilot) for the full walkthrough.

## Usage

```text
/task:roadmap-to-workflow [<roadmap-slug>]
```

**Input** — `$ARGUMENTS`, optional. A single `<roadmap-slug>` (or path) to skip the picker. No flags — item scope is chosen interactively.

## What it does

1. **Scope** — asks (via chips) how much to run: all remaining items, just the next dependency-wave, or a picked range like `1,3-5,8`.
2. **Waves** — topologically sorts the unchecked items on `**Dependencies:**` into waves. A dependency cycle among scoped items is a hard stop.
3. **Per item, three agents** — the default shape is **opus-plans / sonnet-implements / reviewer-reviews**: a first agent runs `to-plan` for the item; a second implements and commits, using the item's `**Model:**` hint if present; a third is `task:code-reviewer`, which reviews that commit, proves each finding, fixes the confirmed ones inside the plan's `Touches`, runs `config.md` → Build and Tests, and amends. Context passes via the on-disk task file, not chat. The reviewer pins its own model, so the item's `**Model:**` hint never downgrades the review.
4. **Parallel plans, serialized implement-then-review** — within a wave, all items are planned in parallel (plan agents only write their own task files), then each item is implemented and reviewed strictly one at a time in the shared working tree, both inside the same serial loop. A barrier separates waves, so each implement sees its already-landed wave-mates' reviewed commits.
5. **Driver auto-marks** — after an item's *review* returns OK, the **driver** ticks its checkbox — never the per-item agent, so parallel wave-mates never race on the roadmap file.

## Config

`roadmap-to-workflow` is **not** setup-capable — a roadmap can't exist without config. On a missing `config.md` it hard-stops and redirects you to run a capture skill first. This skill *is* the opt-in for the Workflow tool — reading and running it is the authorization.

## Output

One digest line per stage as each wave lands; stop-on-FAIL (an implement *or* a review `FAIL` stops the run):

```text
OK #1 migrate-auth-endpoints implemented, committed
OK #1 migrate-auth-endpoints reviewed — 2 fixes, tests green, commit amended
OK #2 update-client-sdk implemented, committed
OK #2 update-client-sdk reviewed — 0 findings, tests green
→ Done. Roadmap complete — `.task/roadmap/api-v2-migration.md` fully checked.
```

On failure:

```text
FAIL #3 <item-slug> <what failed>
→ Next: fix the item, then rerun `/task:roadmap-to-workflow` — completed items
  stay checked, only the unchecked remainder reruns.
```

## Fallback

If the Workflow tool isn't available, it falls back to running items one at a time by hand, in the same wave order — `to-plan` then a plain `implement` session, ticking the checkbox before moving on.

## Does not

- Run setup on a missing `config.md` — it hard-stops and redirects.
- Loop items in the main session instead of authoring a Workflow (except the documented serial fallback).
- Run an item whose dependencies are still unchecked.
- Auto-mark a checkbox from inside a per-item agent — strictly the driver's job.
- Modify project code itself — all implementation happens inside the per-item implement agents, run one at a time in the shared working tree.
