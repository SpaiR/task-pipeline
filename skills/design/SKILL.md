---
name: design
description: 'Open a task and plan it — write the Description, then build the implementation plan, walking you through each phase with a question so one call carries the whole design. Auto-resumes the right phase from artifact state.'
disable-model-invocation: true
user-invocable: true
---

Open a task, write its Description, build the implementation plan, and optionally refine the plan. This orchestrator auto-detects which phase to run based on the current state of `.task/workspace/<task-id>/`; pass `--phase <name>` to force a specific phase.

**Input:** `$ARGUMENTS` — forwarded to the dispatched phase verbatim. Common forms:
- `<free-form context>` — manual-mode open (ticket id / title / sentence about the task). Open's Step 2a writes a quick-draft `## Description` in the same call for any non-empty **paraphrasable** context — a filled `task.md` one-shot, and the next `/task:design` call auto-enters blueprint. (A bare ticket id with no prose to paraphrase → open elicits a one-sentence description, then quick-drafts.)
- (empty) — if no task is in flight, the orchestrator presents an **entry fork** (draft directly / open from a roadmap) via `AskUserQuestion` and proceeds accordingly (Step 1; interactive-only). If a task is already in flight, continue with the next auto-detected phase.
- `--from <roadmap>[#<N>]` — open from a roadmap file (auto-picks first un-checked item if `#<N>` omitted).
- `--phase <open|blueprint|refine>` — force a specific phase (override auto-detect). `refine` is a repair-level phase (critically review an existing `plan.md`), not part of the routine flow — see [docs/troubleshooting.md](../../docs/troubleshooting.md).

**Phase companion files** live at `skills/design/phases/<phase>.md`. The orchestrator reads them and follows their instructions verbatim — they contain the full prompt for each phase. Treat each file as the authoritative contract for its phase.

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) for the open-phase Tier; blueprint and refine are [Tier B](../../docs/spec/invariants.md#tier-b--mcp-first-tooling). Per-phase tier applies inside each companion file; the orchestrator itself only does config gate + phase detection + dispatch, which is Tier A.

## Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. Branch on the outcome:

- **(a) exits non-zero specifically with a `config.md not found` message → auto-setup.** `/task:design` is an intake-capable entry point: in a fresh, unconfigured project it runs setup inline rather than dead-ending the user. Execute `/task:bootstrap` inline by reading `${CLAUDE_PLUGIN_ROOT}/skills/bootstrap/SKILL.md` and following its Steps **verbatim** — the full flow (Steps 0–4), no shortcuts, so auto-setup performs the same environment-guarding steps as the explicit command. Then re-run `validate.sh all`. If `config.md` is now present → continue to Step 1 with the original `$ARGUMENTS` unchanged. If `config.md` is still absent (the user chose `decline`) → surface bootstrap's own message and **stop**; do not proceed to Step 1.
- **(b) exits non-zero for any other reason** (config present but a malformed artifact) → **stop** and report the validator output, as before.
- **(c) exits zero** → proceed to Step 1.

Auto-setup is a **prompt-layer response** to the bash gate's failure followed by re-validation — it does **not** relax or bypass the gate. `validate.sh` still fails authoritatively when config is absent; the skill only proceeds once config exists. The `all` subcommand tolerates a missing active-task pointer (needed for the open-phase fresh-start path).

## Step 1: Phase detection

Parse `$ARGUMENTS`:
- If contains `--phase <name>` → use `<name>` as `PHASE`, skip auto-detect.
- If contains `--from` (anywhere) → `PHASE=open`. The from-roadmap path always enters open.md as an initial open.
- Otherwise → run `PHASE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/phase-detect.sh" design)`. A non-empty positional context with no flags stays `PHASE=open` (quick-draft — the intent is unambiguous, no fork). **Ambiguous fresh start → entry fork:** if auto-detect returns `open` (no task in flight) **and** `$ARGUMENTS` carries no positional context, the intent is genuinely undetermined — present the entry fork below instead of silently defaulting.

**Entry fork (ambiguous fresh start).** This is an instance of the structured-choice convention (c) in [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar) — **interactive-only**, flags are the non-interactive equivalent and override it.

- **Non-interactive carve-out.** In a non-interactive run (the `auto-roadmap-design-runner` executing this inline) the fork is never reached: the driver always passes `--from <roadmap>[#<N>]`, so a flag is present and one of the branches above already resolved `PHASE`. A bare no-context call in that context is an error (there is nothing to open) — stop with: "no context provided; pass `--from <roadmap>` or a description." Do **not** call `AskUserQuestion` outside an interactive session.
- **Interactive.** Ask one `AskUserQuestion` (single-select) — "How do you want to start this task?" — with these options; then resolve as if the matching flag had been passed:
  - **Draft it directly** → ask the user to describe the task in a sentence, **wait**, then dispatch `open.md` with that prose as positional context so its Step 2a writes a quick-draft `## Description` in one shot; the next `/task:design` call auto-detects blueprint. This is the default/first option.
  - **Open from a roadmap** → resolve the from-roadmap path: build a second `AskUserQuestion` from the `.task/roadmap/*.md` files (chips per roadmap slug), then set `$ARGUMENTS` to `--from <chosen-slug>` and re-enter Step 1 (`--from` branch above → `PHASE=open`). Item selection within the roadmap is handled downstream by `open.md` (see its from-roadmap item picker).

Possible auto-detect outputs:
- `open` — no active-task pointer or no `task.md` in resolved workspace.
- `blueprint` — Description filled, no `plan.md`.
- `refine-prompt` — `plan.md` exists. Orchestrator should NOT auto-enter refine. Instead, tell the user:
  > Plan already exists at `.task/workspace/<task-id>/plan.md`. The design phase appears complete — next is `/task:build` to start implementation. To start a different umbrella, close the current one first: `/task:ship`. (If the plan itself needs a critical rework, `--phase refine` is a repair-level option — see docs/troubleshooting.md.)
  >
  > → Next: `/task:build`

  (Canonical footer, convention (a).) Then stop without dispatching. Only continue to Step 2 if the user explicitly forced `--phase refine`.

## Step 2: Phase dispatch

Read `skills/design/phases/${PHASE}.md` (resolve via `${CLAUDE_PLUGIN_ROOT}/skills/design/phases/${PHASE}.md`) and follow its instructions verbatim. The companion file contains:
- Phase-specific preconditions (e.g. blueprint requires `task.md` and a non-empty Description; refine requires `plan.md`).
- The full Steps to execute for this phase.
- Output templates and rules.

Pass `$ARGUMENTS` through to the phase (the companion files expect access to it — e.g. blueprint may use any extra context provided by the user).

If `${PHASE}` is not one of `open`, `blueprint`, `refine` — stop with an error: "Unknown phase '${PHASE}'. Valid: open, blueprint, refine."

## Step 3: Advance loop (chain phases without re-invocation)

After the dispatched phase completes successfully, don't stop at a passive footer — offer to continue into the next phase in the **same call**, so the user runs `/task:design` once and is walked through the rest by questions rather than re-typing commands. Each transition is gated by one `AskUserQuestion` (structured-choice convention (c)) whose decline path prints the flag-free next-step footer and stops.

**Non-interactive carve-out (mandatory).** In a non-interactive run — the `auto-roadmap-design-runner` executing this inline — present **no** advance question and **never** invoke `/task:build`. Complete the dispatched phase and stop; the runner drives the next phase (open→blueprint) and the item-runner drives build separately. The advance loop below is interactive-only. (Detector: same "runner executing inline" signal as ship Step 2.5/3 and build's clean-build proposal.)

**Interactive advance.** Re-run `phase-detect.sh design` to get the next state, then:

- Next = `blueprint` (Description ready — after quick-draft or from-roadmap) → ask "Description ready — build the plan now?" — **Plan it now** / **Review the Description first** / **Stop**. *Plan it now* → dispatch `blueprint.md` inline, then continue the loop. *Review first* / *Stop* → footer `→ Next: \`/task:design\`` and stop (the user edits `task.md`, then re-runs). Default after a quick-draft: **Review first** (it may have mis-paraphrased).
- Next = `refine-prompt` (plan.md now exists — **design is complete**; this is the design→build boundary) → ask "Plan ready — start implementing now?" — **Implement it now** / **Stop**. *Implement it now* → invoke `/task:build` (the whole skill: it auto-detects implement, then runs its own implement→audit advance question, then proposes ship — the wizard continues across the skill boundary, mirroring how build flows into ship). *Stop* → footer `→ Next: \`/task:build\`` and stop.

The loop ends when the user declines a transition, a phase stops on its own precondition, or `/task:build` takes over. Never auto-enter `refine` (repair-level, explicit only).

## Forbidden

- Inline the phase instructions in this orchestrator — that defeats the decomposition. Always dispatch via reading the companion file.
- Modify any file other than what the dispatched phase's instructions specify.
- Skip the config gate (Step 0) even when re-entering mid-pipeline — `validate.sh all` is cheap and catches corrupt state early.
- Present an advance question (Step 3), or invoke `/task:build`, in a non-interactive run (the `auto-roadmap-design-runner` executing this inline) — the advance loop is interactive-only; the runner drives phases explicitly.

## Output

After each dispatched phase completes:
- Print whatever the companion phase's "Output" section specifies (paths, summary).
- Then run the Step 3 advance loop: in an interactive run, offer the next-phase question; on decline (or in a non-interactive run) end with the canonical next-step footer — a single **flag-free** `→ Next: <runnable command>` line (convention (a); never suggest a flag to the user). If the phase's own Output already emits the footer, do not duplicate it.
- When the loop advances into another phase, print that phase's Output too; when it advances into `/task:build`, that skill owns its own output from there.
