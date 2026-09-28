# roadmap-to-workflow

The one launcher. Fans an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow running the plugin's shipped driver script (`skills/_lib/roadmap-driver.js`) — parallel planning, serialized implementation, dependency-ordered waves, ticking off the roadmap as items land. The skill reports the roadmap's unchecked items and your chosen scope; the driver sorts them into waves itself, and the script never changes between runs.

See the [autopilot guide](/guide/autopilot) for the full walkthrough.

## Usage

```text
/task:roadmap-to-workflow [<roadmap-slug>]
```

**Input** — `$ARGUMENTS`, optional. A single `<roadmap-slug>` (or its path under `.task/roadmap/`; a roadmap anywhere else is refused) to skip the picker. No flags — item scope is chosen interactively.

## What it does

1. **Scope** — asks (via chips) how much to run: all remaining items, just the next dependency-wave, or a picked range like `1,3-5,8`.
2. **Waves** — the driver topologically sorts the unchecked items on `**Dependencies:**` into waves, before it spawns anything. A dependency cycle among scoped items is a hard stop, and so is a scope that leaves a dependency neither ticked nor included; both come back as one line naming the items.
3. **Per item, three agents** — the last of which also ticks the checkbox (step 5). The default shape is **opus-plans / sonnet-implements / reviewer-reviews**: a first agent plans the item (per `skills/_lib/plan-driver.md`, on sonnet at low effort when the item's `**Model:**` hint is `haiku`); a second implements and commits, using the item's `**Model:**` hint if present; a third is `task:code-reviewer`, which reviews that commit, proves each finding, fixes the confirmed ones inside the plan's `Touches`, runs `.task/CLAUDE.md` → Build and Tests, commits those fixes on top, and ticks the item's checkbox. Context passes via the on-disk task file, not chat. The reviewer pins its own model, so the item's `**Model:**` hint never downgrades the review.
4. **Parallel plans, serialized implement-then-review** — within a wave, all items are planned in parallel (plan agents only write their own task files), then each item is implemented and reviewed strictly one at a time in the shared working tree, both inside the same serial loop. A barrier separates waves, so each implement sees its already-landed wave-mates' reviewed commits.
5. **The review auto-marks** — once an item's review passes, `task:code-reviewer` ticks its checkbox as its last phase; the driver hands it the item number and roadmap path. Never the plan or implement agents, and the review runs one item at a time, so parallel wave-mates never race on the roadmap file. The flip is idempotent: an already-ticked item is the desired end state, not a failure. It fails the review — and stops the wave — only when the roadmap holds no unique `### - [ ] N.` heading for that item: renumbered, retitled, or duplicated.

## Config

`roadmap-to-workflow` is **not** setup-capable — a roadmap can't exist without `.task/CLAUDE.md`. On a missing one it hard-stops and redirects you to run a capture skill first. This skill *is* the opt-in for the Workflow tool — reading and running it is the authorization.

## Output

While it runs, the Workflow panel groups each item's three agents under the item's own title — `W1 · #1 Migrate auth endpoints` — labelled `1/3 plan`, `2/3 implement` and `3/3 review`. The narrator lines above the panel open with the run's shape and then carry one digest per stage:

```text
api-v2-migration: 2 item(s) in 2 wave(s)
  W1: #1 Migrate auth endpoints
  W2: #2 Update client SDK (after #1)
Wave 1/2 — planning #1
[W1 plan] OK #1 migrate-auth-endpoints planned
[W1 implement] OK #1 migrate-auth-endpoints implemented, committed
[W1 review] OK #1 migrate-auth-endpoints 2 fixes, tests green, fixes committed, ticked
Wave 2/2 — planning #2
…
```

Stop-on-FAIL: an implement *or* a review `FAIL` stops the run. When it ends, the skill reports one line per item that landed, then the run summary:

```text
#1 migrate-auth-endpoints — implemented, committed; review: 2 fixes, tests green, fixes committed, ticked
#2 update-client-sdk — implemented, committed; review: 0 findings, tests green, ticked
Ran `api-v2-migration`: 2 of 2 items landed and ticked, 0 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
→ Done. Roadmap complete — `.task/roadmap/api-v2-migration.md` fully checked.
```

On failure, the items that landed before the stop are still listed:

```text
FAIL #3 <item-slug> <what failed>
#1 … — …; review: …
#2 … — …; review: …
Ran `api-v2-migration`: 2 of 5 items landed and ticked, 3 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
Stopped at #3 <item-slug> in wave 2. Its work is left in the working tree —
  inspect it with `git status` and `git log --oneline -3`.
→ Next: fix #3 by hand and tick it, or edit the item in
  `.task/roadmap/api-v2-migration.md` so the rerun re-plans it from the new text,
  then rerun `/task:roadmap-to-workflow api-v2-migration` — already-ticked items
  stay ticked, only the unchecked remainder reruns.
```

Two stops get a different footer, because re-planning the item would be wrong there:

- **The checkbox was not flipped** (`no unique` heading, or no `MARK-OK` reported) — the item's reviewed work is already committed, so the footer says to tick it by hand and rerun.
- **The implementation was never committed** — the footer says to commit it, tick the item by hand, and rerun.

Rerun a stopped run plainly. Resuming it from its run id replays the cached failing stage and stops at the same place; that is only for a run interrupted before it returned.

## No Workflow tool

If the Workflow tool isn't available in your environment, the skill hard-stops instead of running anything itself — it prints the unchecked items and a by-hand recipe: run `/task:to-task <slug>#<N>` for one item in this chat, then say `implement .task/task/<item-slug>.md` in a fresh session. That session's `## Execution` pointer carries plan → commit → `task:code-reviewer` on its own, and the reviewer ticks the roadmap checkbox once its review passes, so there's nothing further to do per item — just repeat for the next one, in dependency order.

A driver that doesn't resolve is a different case and does **not** get this treatment. The driver ships with the plugin and is registered as `task:roadmap-driver`, so a name that fails to resolve means a stale or unreloaded plugin, not an environment without automation — the skill stops and says to update the plugin and restart, rather than putting you through the by-hand path for an install defect. See [Troubleshooting](/guide/troubleshooting#roadmap-driver-not-registered).

## Does not

- Run setup on a missing `.task/CLAUDE.md` — it hard-stops and redirects.
- Loop items in the main session, or re-author the Workflow script inline, instead of invoking the shipped driver — including when the Workflow tool is unavailable, which is a hard stop, not a cue to run the items itself.
- Run an item whose dependencies are still unchecked.
- Auto-mark a checkbox from inside a plan or implement agent — strictly the reviewer's job, once its review passes.
- Modify project code or any file itself — all implementation happens inside the per-item implement agents, run one at a time in the shared working tree.
