# Recover a stopped roadmap run

What `roadmap-to-workflow` does after the driver returns a stop, or never returns at all. The skill's Output section points here at **every** stop: read this file each time, never from memory, because a long run outlives the context that last read it.

Recovery never repairs anything itself. It diagnoses the stop, then reruns the driver with the stopped item entering the pipeline again at implement or review (the driver's `resume` arg). The driver's own implement and review stages do the repair, so every change still gets the reviewer's pass and the reviewer's tick. [contract § execution shape](../../docs/contract.md#roadmap-to-workflow-execution-shape-driver-contract) owns the `resume` shape and the return.

## 1. Read the state

- **The driver's return.** The first line is the headline. Under it, `STATE recover=<on|off> attempts=<#N:k,…|none>` is always present, and `STOPPED #N <item-slug|-> stage=<plan|implement|review|mark>` names the stopped item on a stop. Take the mode and the attempt counts from these lines, not from memory: `recover=on` is **Recover and continue**, `recover=off` is **Stop and ask**, and an item missing from `attempts=` is at 0.
- **Git.** `git log --oneline <start>..HEAD` from the `HEAD` recorded before the first Workflow call, and `git status --short`. Together they show what the stopped item committed and what it left uncommitted.
- **The workflow journal**, when the task notification names the run's transcript directory: `<transcriptDir>/journal.jsonl` holds each agent's full result. The driver keeps only the last line of each one, but the reason for a stop is usually in the text above it.
- **The item's files:** `$AI_DIR/task/<item-slug>.md` (its `## Plan` and acceptance criteria) and the item's status line in `$AI_DIR/roadmap/<slug>.md`.

All of this is reading. Nothing in this file edits a file.

## 2. Classify the stop

| The stop | Rerun |
|---|---|
| `stage=plan`, a plan `FAIL`, an unparsable plan digest, or a plan agent that returned nothing | **Plain rerun**: no entry for the item. Its plan stage runs again and regenerates its task file. |
| `stage=plan`, `#A and #B both planned <slug>` | **Stop and ask**: only a roadmap edit (a more distinct title) fixes it. |
| `stage=implement`, `implement agent returned nothing` or `unparsable implement digest` | **`from: 'review'`** only when the journal and git show the item's work plainly committed and complete, and `git status` shows none of its files changed. Otherwise **`from: 'implement'`**, the note saying what is committed and what the agent's own text said. |
| `stage=implement`, a `FAIL` digest | **`from: 'implement'`**, the note quoting the failure and the agent's own diagnosis. |
| `stage=review`, a `FAIL` digest: defects it could not fix, a red Build and Tests, `implementation never committed`, a rejected deviation | **`from: 'implement'`**, the note quoting the review's *Confirmed, reported, not fixed* lines, the failing output, or the rejected deviation with the invariant it breaks. Uncommitted work is the implement agent's to commit. |
| `stage=review`, `review agent returned nothing` or `unparsable review digest` | The journal decides. A report that ends in a failure → as a review `FAIL` above. Otherwise **`from: 'review'`**: the reviewer derives its range again and builds on any fix it already committed. |
| `stage=mark`, `never reported MARK-OK` | Read the item's status line. Already `[x]` → **plain rerun**: the item is no longer unchecked and drops out of the run. Still `[ ]` → **`from: 'review'`**. The flip is idempotent, and the second review checks the committed work again. |
| `stage=mark`, a `MARK-FAIL` remedy in the headline | **Stop and ask**: the roadmap has no unique heading with a status line for the item, and the roadmap is the user's to edit. |
| `bad args` from a rerun you built | **Stop and ask**: the args are wrong, not the item. Quote the line. |
| No driver return at all | `resumeFromRunId` **once**, in the same session (the skill's Step 2 rerun paragraph). If that is not possible or fails again, use the journal or git to find the item in flight: an item with commits since the start and an unchecked box is handled as an implement stop with no digest. When nothing shows an item in flight, a **plain rerun**. |

**When in doubt between `review` and `implement`, choose `implement`.** The implement agent sees what is already done and builds on it. A review of half-finished work can pass it.

**Some stops always go to the user, whatever the mode:**

- the fix needs a product or design decision only the user can make;
- the failure lies outside the item, such as a Build and Tests failure the review traced to something this item did not touch;
- the item reached its attempt limit (section 3).

## 3. Build the rerun

The rerun goes through the skill's Step 1 and Step 2 again, with these args:

- **`items` and `done`**: rebuilt from a fresh `roadmap-items.sh` call. Items that landed are ticked now and drop out.
- **`scope`**: the stopped run's scope.
  - `'all'` stays `'all'`.
  - A picked list keeps only the numbers that are still unchecked. A ticked number in it would be refused as not runnable.
  - `'next-wave'` becomes an explicit list of the first launch's wave-1 items that are still unchecked. These are the items from the first Step 1 whose dependencies were all already marked then. A plain `'next-wave'` would pull in items whose dependencies landed during this run.
- **`recover`**: unchanged, from the `STATE` line.
- **`resume`** holds two kinds of entry:
  - **The stopped item**, unless its row above says plain rerun: `{n, slug, from, attempt, note}`. The `slug` comes from the `STOPPED` line, `from` from the table above, and `attempt` is the item's count on the `STATE` line plus one.
  - **Every other entry of the stopped run** whose item is still unchecked, carried over unchanged. Those items never ran, because the driver stops at the first failure, so their attempt does not grow.
- **The attempt limit.** An item already at `#N:2` gets no third attempt: stop and ask.
  - **A plain rerun counts too**, though it carries no `resume` entry and so no `STATE` count. Count the plain reruns of this invocation yourself: after two plain reruns for the same item's plan stop, its next plan stop is stop and ask. The same limit holds for a run that never returns: after two plain reruns that each ended without a return, stop and ask.

**The note is facts only.** Write two to five sentences:

- what stopped, quoting the digest;
- what is committed, as shas and subjects from git;
- what is uncommitted, from `git status`;
- what the agent or the review said about why.

Never write an instruction that relaxes an acceptance criterion or a test, a design decision, or a guess presented as a fact. The implement agent reads the note as context. Its own prompt already says the criteria stand.

## 4. Guardrails

- Never edit project code, the roadmap, a spec or a task file. Never commit, and never tick a checkbox.
- Never spawn an agent of your own, and never paste a stage's prompt into one. The driver's stages are the only way to plan, implement or review an item. The driver with `resume` is the only way to continue one.
- Never call `resumeFromRunId` after a stop the driver returned. It replays the cached failing stage.

## 5. Act on the mode

- **Recover and continue** (`recover=on`): print one line, `Recovering #N <item-slug> (attempt k of 2): <the stop, in a few words> → rerun from <implement|review|plan>.`, then invoke the driver again through the skill's Step 2 with the new args. Keep the start `HEAD` recorded before the first call, and handle the new return with the skill's Output again. If it stops, this file is read again from the top.
- **Stop and ask** (`recover=off`): print the headline and one short diagnosis paragraph. It says what stopped, what is in the tree, and what the rerun would do. Then ask one `AskUserQuestion`, *"Rerun #N from <stage>?"*:
  - **Rerun from <stage>** *(Recommended)*: the description names the `resume` entry and its note.
  - **Stop here**: the skill's Output stop footer.

  An accepted rerun goes ahead exactly as in Recover and continue. The next stop asks again.
- **Any stop this file sends to the user**, in either mode (section 2's always-the-user list, the stop-and-ask rows, the attempt limit): no chip. Print the diagnosis and the skill's Output stop footer for that stop.
