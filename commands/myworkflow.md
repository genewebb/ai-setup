---
description: Start (or resume) a cost-tiered orchestrator-worker coding loop. Interviews you for the goal, scope, verifier commands, and model tiers, then runs a reasoning-tier orchestrator/verifier with a fast-tier executor that upgrades on failure.
argument-hint: "[GOAL.md path | goal-name | --resume <repo> | --defaults \"<one-sentence goal>\"]"
---

# /myworkflow — Orchestrator-Worker Coding Loop

Load the `orchestrator-worker-loop` skill and follow it. Read `SKILL.md` first, then `PROMPTS.md`,
`MODELS.md`, and `EXAMPLES.md` as needed. `TEST-PROBLEM.md` is for validating the setup on scratch
files.

**This command is only a router.** The interview, the run procedure, the gates, and the failure
policy all live in `SKILL.md` — the single source of truth. Do not restate or re-invent them here;
if this file and the skill ever disagree, the skill wins.

Invoking this command **authorizes subagent dispatch** for the Executor: one subagent per
iteration, serially, never a parallel fan-out (the Executor mutates files).

## Argument handling

Argument passed: `$ARGUMENTS`

| Form | Action |
|---|---|
| *empty* | Run the skill's INTERVIEW phase from the top. |
| path to an existing `GOAL.md` | Load it, echo a summary, ask "Ready to run this GOAL as-is?", then go to the skill's RUN phase. Skip the interview. |
| kebab-case name, no path separators, no `.md` | Seed `goal-name` and enter INTERVIEW. |
| `--resume <repo>` | Resume an interrupted loop from `<repo>\.loop\`. Follow `SKILL.md § Resuming an interrupted loop` — re-baseline, re-check criteria and budget, continue at N+1. Do NOT re-interview, do NOT edit GOAL.md. |
| `--defaults "<one-sentence goal>"` | Fast path: accept every default in the skill's interview (cwd, current branch, whole-repo scope minus generated code, default tiers, Conservative budget, dry-run mode) and go straight to the GOAL preview. Still ask for the Done-when criteria — those define termination and cannot be defaulted. |

If a `GOAL.md` path is given but the file does not exist, say so and offer the interview instead of
guessing.

## What the skill will do (orientation only — details in SKILL.md)

1. **INTERVIEW** — 7 batches: goal, target, scope, done-when criteria, constraints, model tiers,
   budget, execution mode. Ends with a GOAL.md preview and a **Ready to run / Edit manually / Cancel**
   choice.
2. **Initialize** — one call to `scripts\Initialize-Loop.ps1`, which creates `.loop\`, records
   `started_at`, captures the baseline, **preflights the Done-when criteria**, and prints the
   commands to allow-list for an unattended run.
3. **Iterate** — plan → checkpoint → dispatch Executor → six Verifier gates → re-baseline on pass →
   PROGRESS entry → budget check.
4. **Stop and report** — `.loop\LOOP_REPORT.md`, then hand the diff back for review.

Two things worth surfacing to the user before a long run:

- **Default mode is dry-run** (one iteration, then stop for review). Recommend it for any goal's
  first outing, and only lift to a full or overnight run after watching it work.
- **An unattended run stalls on the first permission prompt.** Have the allow-list from step 2 in
  place before walking away; the `permissions-yaml` skill covers the canonical file.

**Do NOT `git commit`.** The user handles all commits manually — this holds even if the goal implies
otherwise.
