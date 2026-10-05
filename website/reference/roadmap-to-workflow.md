# roadmap-to-workflow

The one launcher. Fans an approved `.task/roadmap/<slug>.md` out to a dynamic Workflow running the plugin's shipped driver script (`skills/_lib/roadmap-driver.js`) — parallel planning, serialized implementation, dependency-ordered waves, ticking off the roadmap as items land. The skill reports the roadmap's unchecked items and your chosen scope; the driver sorts them into waves itself, and the script never changes between runs.

See the [autopilot guide](/guide/autopilot) for the full walkthrough.

## Usage

```text
/task:roadmap-to-workflow [<roadmap-slug>]
```

**Input** — `$ARGUMENTS`, optional. A single `<roadmap-slug>` (or its path under `.task/roadmap/`; a roadmap anywhere else is refused) to skip the picker. No flags — item scope and the recovery mode are chosen interactively.

## What it does

1. **Scope and recovery mode** — asks (via chips) how much to run: all remaining items, just the next dependency-wave, or a picked range like `1,3-5,8`. In the same prompt it asks what to do **if the run stops**: **Stop and ask**, or **Recover and continue** (see [Recovery](#recovery)). The recovery question is asked even when only one item is open.
2. **Existing plans** — an unchecked item that already has its task file (an earlier run stopped after planning it, or you captured it with `/task:to-task <slug>#N`) gets a question of its own: **Implement this plan**, **Review only — its work is committed**, or **Re-plan from the roadmap item**. The first two skip the plan stage for that item.
3. **Waves** — the driver topologically sorts the unchecked items on `**Dependencies:**` into waves, before it spawns anything. A dependency cycle among scoped items is a hard stop, and so is a scope that leaves a dependency neither ticked nor included; both come back as one line naming the items.
4. **Per item, three agents** — the last of which also ticks the checkbox (step 6). The default shape is **opus-plans / sonnet-implements / reviewer-reviews**: a first agent plans the item (per `skills/_lib/plan-driver.md`, on sonnet at low effort when the item's `**Model:**` hint is `haiku`); a second implements and commits, using the item's `**Model:**` hint if present; a third is `task:code-reviewer`, which reviews that commit, proves each finding, fixes the confirmed ones inside the plan's `Touches`, runs `.task/CLAUDE.md` → Build and Tests, commits those fixes on top, and ticks the item's checkbox. Context passes via the on-disk task file, not chat. The reviewer pins its own model, so the item's `**Model:**` hint never downgrades the review.
5. **Parallel plans, serialized implement-then-review** — within a wave, all items are planned in parallel (plan agents only write their own task files), then each item is implemented and reviewed strictly one at a time in the shared working tree, both inside the same serial loop. A barrier separates waves, so each implement sees its already-landed wave-mates' reviewed commits.
6. **The review auto-marks** — once an item's review passes, `task:code-reviewer` ticks its checkbox as its last phase; the driver hands it the item number and roadmap path. Never the plan or implement agents, and the review runs one item at a time, so parallel wave-mates never race on the roadmap file. The flip is idempotent: an already-ticked item is the desired end state, not a failure. It fails the review — and stops the wave — only when the roadmap holds no unique `### N.` heading with a `- [ ] Done` status line for that item: renumbered, status line lost, or duplicated.

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

The `→ Done.` footer appears only when nothing is left unchecked. A run scoped to **Only next wave** or a picked range also ends on "all items shipped", but with unchecked items outside its scope, so the footer points at the rest instead:

```text
Ran `api-v2-migration`: 1 of 1 items landed and ticked, 1 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
→ Next: `/task:roadmap-to-workflow api-v2-migration` to run the remaining 1 item(s)
```

`Commits:` is the range of commits the run made, read from `git log`; a stop before anything was committed prints `Commits: none`. In a repository with no commit yet, every commit counts as the run's.

On failure, the items that landed before the stop are still listed:

```text
roadmap-to-workflow stopped in wave 2, item #3: FAIL #3 <item-slug> <what failed>
STATE recover=off scope=all attempts=none
STOPPED #3 <item-slug> stage=implement
#1 … — …; review: …
#2 … — …; review: …
Ran `api-v2-migration`: 2 of 5 items landed and ticked, 3 still unchecked.
  Commits: a1b2c3d..e4f5a6b.
Stopped at #3 <item-slug> in wave 2. Its work is left in the working tree —
  inspect it with `git status` and `git log --oneline -3`.
→ Next: rerun `/task:roadmap-to-workflow api-v2-migration` and pick
  **Implement this plan** for #3 to continue from what is committed, or edit the
  item in `.task/roadmap/api-v2-migration.md` and pick **Re-plan from the roadmap
  item** — already-ticked items stay ticked, only the unchecked remainder reruns.
```

A stop during **planning** (the headline says `(planning)`, for example two items that plan to the same task slug) happens before any implement of that wave ran, so nothing of it is in the tree. The footer relays the headline's own remedy, or says to edit the item in the roadmap, then rerun.

Under the headline, the `STATE` and `STOPPED` lines say which recovery mode the run had, which items it covered (`all`, or the item numbers it kept), how many recovery attempts each item has used, and where the stopped item stopped. The skill reads them to recover. They are not for you to act on.

Three stops get a different footer, because re-planning the item would be wrong there, or because rerunning it has stopped helping:

- **The checkbox was not flipped** (the review's flip reported `MARK-FAIL`, or no `MARK-OK` at all) — the item's reviewed work is already committed. The footer says to rerun and pick **Review only** for it, after fixing the cause when the flip reported `MARK-FAIL`: the item's heading in the roadmap, or a roadmap directory that cannot be written.
- **The implementation was never committed** — the footer says to rerun and pick **Implement this plan**: the implement stage commits the work that is already in the tree.
- **The item used its two recovery attempts** — the footer says to decide how the item should change: edit it in the roadmap and pick **Re-plan from the roadmap item**, or fix the code yourself and pick **Review only**.

Resuming a stopped run from its run id replays the cached failing stage and stops at the same place; that is only for a run interrupted before it returned.

## Recovery

Every stop goes through a recovery step before the skill prints a footer. It reads the driver's return, `git log` and `git status` since the run started, and the workflow journal when there is one. Then it decides how the stopped item should run again:

- **from implement** — a failed implement, a failed review, or an implement that never reported back. The implement agent gets a note about what stopped and what is already committed, and builds on that work instead of redoing it.
- **from review** — the work is committed and complete, and only the review or the checkbox is missing.
- **from plan** — the item stopped while it was being planned. It is planned again from the roadmap, and the attempt counts like any other.

Some stops always come back to you: two items that plan to the same task slug, a roadmap heading the checkbox flip cannot find or a roadmap it cannot write, a run that died with no item in flight, a fix that needs a decision only you can make, a failure outside the item (such as a red build the review traced to code the item did not touch), and an item that has used its two recovery attempts.

What happens next depends on the mode you picked at launch:

- **Stop and ask** — the skill prints its diagnosis and offers the rerun it would make as a chip: **Rerun from implement** (or review), or **Stop here**.
- **Recover and continue** — the skill reruns the driver itself and prints one `Recovering #N …` line per recovery.

Either way the repair is done by the driver's own implement and review stages, so it is reviewed and ticked like any other item. The skill never edits code, the roadmap, a spec or a task file itself. Each item gets at most two recovery attempts per invocation.

A resumed implement may depart from the item's plan, and from a spec it cites as long as no invariant of that spec breaks. It has to declare each departure, the reviewer checks each one against the spec's invariants and fails the item when one breaks, and the run report lists them under the item:

```text
#3 retry-queue — retries capped, tests green; review: 0 findings, tests green, ticked
  deviation: kept the v1 queue table instead of plan step 2's new one — the migration is out of scope
Decisions made during recovery:
- #3 retry-queue: kept the v1 queue table instead of plan step 2's new one — the migration is out of scope
```

If the item stops again before its review passes, its deviations are kept with the stop and handed to the next attempt, so none is lost. A run that ends stopped lists them as declared but not yet reviewed, except after a stop at the checkbox flip: the review had already accepted them, so they are listed as decisions. When a departure changed what a spec says, the footer points at `/task:to-spec` so you can fold it back into the spec.

If the Workflow call itself errors or is interrupted, there is no headline and no run summary. Recovery tries resuming the run from its run id once in the same session. When it stops instead, the skill quotes the tool's error, prints the `Commits:` range the run made before it died, and closes with a footer that resumes the run in the same session or reruns `/task:roadmap-to-workflow <slug>`.

## No Workflow tool

If the Workflow tool isn't available in your environment, the skill hard-stops instead of running anything itself — it prints the unchecked items and a by-hand recipe: run `/task:to-task <slug>#<N>` for one item in this chat, then say `implement .task/task/<item-slug>.md` in a fresh session. That session's `## Execution` pointer carries plan → commit → `task:code-reviewer` on its own, and the reviewer ticks the roadmap checkbox once its review passes, so there's nothing further to do per item — just repeat for the next one, in dependency order.

A driver that doesn't resolve is a different case and does **not** get this treatment. The driver ships with the plugin and is registered as `task:roadmap-driver`, so a name that fails to resolve means a stale or unreloaded plugin, not an environment without automation — the skill stops and says to update the plugin and restart, rather than putting you through the by-hand path for an install defect. See [Troubleshooting](/guide/troubleshooting#roadmap-driver-not-registered).

## Does not

- Run setup on a missing `.task/CLAUDE.md` — it hard-stops and redirects.
- Loop items in the main session, or re-author the Workflow script inline, instead of invoking the shipped driver — including when the Workflow tool is unavailable, which is a hard stop, not a cue to run the items itself.
- Run an item whose dependencies are still unchecked.
- Auto-mark a checkbox from inside a plan or implement agent — strictly the reviewer's job, once its review passes.
- Modify project code or any file itself — all implementation happens inside the per-item implement agents, run one at a time in the shared working tree.
- Repair a stopped item with an agent of its own — recovery only reruns the driver, with the item resumed at implement or review.
