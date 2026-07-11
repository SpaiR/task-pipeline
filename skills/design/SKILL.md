---
name: design
description: 'Open a task and plan it — write the Description (quick-draft or `--idea` brainstorm), then build the implementation plan. Auto-resumes the right phase from artifact state; `--phase <open|idea|blueprint|refine>` overrides.'
disable-model-invocation: true
user-invocable: true
---

Open a task, write its Description, build the implementation plan, and optionally refine the plan. This orchestrator auto-detects which phase to run based on the current state of `.task/workspace/<task-id>/`; pass `--phase <name>` to force a specific phase.

**Input:** `$ARGUMENTS` — forwarded to the dispatched phase verbatim. Common forms:
- `<free-form context>` — manual-mode open (ticket id / title / sentence about the task). Open's Step 2a writes a quick-draft `## Description` in the same call for any non-empty **paraphrasable** context — a filled `task.md` one-shot, and the next `/task:design` call auto-enters blueprint. (A bare ticket id with no prose has nothing to paraphrase → header-only, then the idea phase.)
- (empty) — if no task is in flight, treated as `--idea` with no context (the orchestrator asks for the idea, then opens the header and enters idea phase in architect mode). If a task is already in flight, continue with the next auto-detected phase.
- `--idea [<free-form context>]` — explicit brainstorm over `## Description`. With no task yet: the header is written (Description left empty) and idea phase runs **architect mode** (the context, if any, seeds round 0). With an existing task whose Description is filled: idea phase runs **Socratic mode** (refinement). Mutually exclusive with `--from`, `--phase`, `--refine`.
- `--from <roadmap>[#<N>]` — open from a roadmap file (auto-picks first un-checked item if `#<N>` omitted).
- `--phase <open|idea|blueprint|refine>` — force a specific phase (override auto-detect). `refine` is a repair-level phase (critically review an existing `plan.md`), not part of the routine flow — see [docs/troubleshooting.md](../../docs/troubleshooting.md).

**Phase companion files** live at `skills/design/phases/<phase>.md`. The orchestrator reads them and follows their instructions verbatim — they contain the full prompt for each phase. Treat each file as the authoritative contract for its phase.

**Preconditions, tool tier, language:** see [docs/spec/invariants.md](../../docs/spec/invariants.md#tier-a--no-code-navigation) for the open-phase Tier; idea is [Tier C](../../docs/spec/invariants.md#tier-c--shallow-scan); blueprint and refine are [Tier B](../../docs/spec/invariants.md#tier-b--mcp-first-tooling). Per-phase tier applies inside each companion file; the orchestrator itself only does config gate + phase detection + dispatch, which is Tier A.

## Step 0: Config gate

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" all`. Branch on the outcome:

- **(a) exits non-zero specifically with a `config.md not found` message → auto-setup.** `/task:design` is an intake-capable entry point: in a fresh, unconfigured project it runs setup inline rather than dead-ending the user. Execute `/task:bootstrap` inline by reading `${CLAUDE_PLUGIN_ROOT}/skills/bootstrap/SKILL.md` and following its Steps **verbatim** — the full flow (Steps 0–4), no shortcuts, so auto-setup performs the same environment-guarding steps as the explicit command. Then re-run `validate.sh all`. If `config.md` is now present → continue to Step 1 with the original `$ARGUMENTS` unchanged. If `config.md` is still absent (the user chose `decline`) → surface bootstrap's own message and **stop**; do not proceed to Step 1.
- **(b) exits non-zero for any other reason** (config present but a malformed artifact) → **stop** and report the validator output, as before.
- **(c) exits zero** → proceed to Step 1.

Auto-setup is a **prompt-layer response** to the bash gate's failure followed by re-validation — it does **not** relax or bypass the gate. `validate.sh` still fails authoritatively when config is absent; the skill only proceeds once config exists. The `all` subcommand tolerates a missing active-task pointer (needed for the open-phase fresh-start path).

## Step 1: Phase detection

Parse `$ARGUMENTS`:
- If contains `--idea`, validate mutual exclusion first: it must not co-occur with `--from`, `--phase`, or `--refine`. On collision — stop with: "`--idea` is mutually exclusive with `--from`, `--phase`, `--refine`. Pick one." Otherwise → `PHASE=idea`; keep `--idea` in the forwarded `$ARGUMENTS`. (open.md consumes `--idea` in Step 1 / Step 2a as the quick-draft opt-out signal **only on the fresh-start branch where open.md runs**; on the task-in-flight branch open.md is not invoked and idea.md derives its mode from Description content, so the flag is inert there.) The fresh-start open→idea chain is handled in Step 2's idea-phase dispatch.
- If contains `--phase <name>` → use `<name>` as `PHASE`, skip auto-detect.
- If contains `--refine` (alone or as the only flag besides positional context) → `PHASE=refine`.
- If contains `--from` (anywhere) → `PHASE=open`. The from-roadmap path always enters open.md — either initial-open (no active-task pointer) or continuation (existing pointer with empty Description and matching `Roadmap:` header per open.md Mode 2 → Step 3). Auto-detect would otherwise route an empty-Description continuation to idea, which then hard-stops with a roadmap-mode guard telling the user to do exactly what they did.
- Otherwise → run `PHASE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/phase-detect.sh" design)`. **Empty-call brainstorm:** if this returns `open` (no task in flight) **and** `$ARGUMENTS` carries no positional context → treat the call as `--idea` with no context: set `PHASE=idea` and follow Step 2's idea-phase fresh-start dispatch (which asks the user to describe the idea first). A non-empty positional context with no flags stays `PHASE=open` (quick-draft).

Possible auto-detect outputs:
- `open` — no active-task pointer or no `task.md` in resolved workspace.
- `idea` — `task.md` exists, `## Description` body empty (whitespace + HTML comments only).
- `blueprint` — Description filled, no `plan.md`.
- `refine-prompt` — `plan.md` exists. Orchestrator should NOT auto-enter refine. Instead, tell the user:
  > Plan already exists at `.task/workspace/<task-id>/plan.md`. The design phase appears complete — next is `/task:build` to start implementation. To start a different umbrella, close the current one first: `/task:ship`. (If the plan itself needs a critical rework, `--phase refine` is a repair-level option — see docs/troubleshooting.md.)
  >
  > → Next: `/task:build`

  (Canonical footer per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar).) Then stop without dispatching. Only continue to Step 2 if the user explicitly asked for `--refine`.

## Step 2: Phase dispatch

Read `skills/design/phases/${PHASE}.md` (resolve via `${CLAUDE_PLUGIN_ROOT}/skills/design/phases/${PHASE}.md`) and follow its instructions verbatim. The companion file contains:
- Phase-specific preconditions (e.g. blueprint requires `task.md` and a non-empty Description; refine requires `plan.md`).
- The full Steps to execute for this phase.
- Output templates and rules.

Pass `$ARGUMENTS` through to the phase (the companion files expect access to it — e.g. blueprint may use any extra context provided by the user).

**Idea-phase dispatch (`PHASE=idea`).** The idea phase brainstorms `## Description`. Branch on whether a task is in flight (the active-task pointer exists and points at a `task.md`):
- **No task in flight (fresh start).** This needs a header before the brainstorm can run. (a) If `$ARGUMENTS` carries no positional context, ask the user to describe the idea in a sentence and **wait** for the answer; use that answer as the context. (b) Dispatch `open.md` with `--idea` plus the context (header-only — open's Step 2a sees `--idea` and leaves Description empty). (c) Then dispatch `idea.md`, **forwarding the context as its `$ARGUMENTS`** so architect mode uses it as the round-0 seed and does **not** re-prompt for the idea (idea.md's Step A.0 elicitation is a fallback for when no seed was forwarded). idea.md finds an empty Description and runs **architect mode**. Header creation stays owned by open.md — do not duplicate task-id derivation here.
- **Task already in flight.** Dispatch `idea.md` directly; it auto-detects architect (empty Description) vs Socratic (filled Description) from the current content. Do **not** re-run open.

For every other phase, read its companion file and follow it directly.

If `${PHASE}` is not one of `open`, `idea`, `blueprint`, `refine` — stop with an error: "Unknown phase '${PHASE}'. Valid: open, idea, blueprint, refine."

## Step 3: Chain hint

After the dispatched phase completes successfully, suggest the next logical step:
- After `open` (manual mode, Description filled by quick-draft) → `/task:design` again (auto-detects blueprint).
- After `open` (manual mode, header-only because the input had no paraphrasable prose — a bare ticket id) → `/task:design` again (auto-detects idea → architect mode). This is the only `open` path that does **not** chain into idea in the same call; the `--idea`/empty-call paths already ran idea inline.
- After `open` (from-roadmap mode, Description filled from roadmap) → `/task:design` again (auto-detects blueprint).
- After `idea` (architect mode, Description just brainstormed) → `/task:design` again (auto-detects blueprint).
- After `idea` (Socratic mode, Description refined) → `/task:design` again (auto-detects blueprint).
- After `blueprint` → `/task:build` (to start implementation).
- After `refine` → `/task:build`.

## Forbidden

- Inline the phase instructions in this orchestrator — that defeats the decomposition. Always dispatch via reading the companion file.
- Modify any file other than what the dispatched phase's instructions specify.
- Skip the config gate (Step 0) even when re-entering mid-pipeline — `validate.sh all` is cheap and catches corrupt state early.

## Output

After the dispatched phase completes:
- Print whatever the companion phase's "Output" section specifies (paths, summary, next-step hint).
- Add the orchestrator's chain hint (Step 3) on top of that.
- End with the canonical next-step footer — a single `→ Next: <runnable command>` line matching the chain hint above (per [`docs/spec/invariants.md § Interaction conventions`](../../docs/spec/invariants.md#interaction-conventions-next-step-footer--choice-grammar)). If the phase's own Output already emits the footer, do not duplicate it.
