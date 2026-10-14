---
name: project-orchestrator-worker-loop-hardening
description: "2026-08-02 review+fix of /myworkflow and the orchestrator-worker-loop skill — the cumulative-baseline bug that broke every multi-iteration loop, plus the gate tooling added"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5c01d683-306d-40a4-9e1b-4be20be0ef9c
  modified: 2026-08-02T17:28:12.233Z
---

Reviewed and fixed `/myworkflow` + the `orchestrator-worker-loop` skill on **2026-08-02**. Canonical
location: `MyWorkVault\03 Shared\work-ai\skills\orchestrator-worker-loop\` (command in
`work-ai\commands\myworkflow.md`; planning docs in `99 Documentation\Goals\`).

**The bug that mattered: a per-iteration predicate checked against a global snapshot.** The
constraint gate compared the worktree to a `BASELINE.json` captured once before iteration 1, but the
`-Allowed` file list is per-iteration. So from iteration 2 onward the gate reported iteration 1's
*legitimate* edits as out-of-scope violations and rolled back good work — every multi-iteration run
self-destructed. Fix: re-run `Get-Baseline.ps1 -Iteration N` after every **passing** iteration, never
after a failure (that would launder unverified changes). Generalisable rule: any allowed-list gate
must advance its reference state in lockstep with accepted work.

Two more that made gates lie: root-anchored excludes meant `bin`/`obj` were hashed, so a
`dotnet build` inside gate 5 tripped gate 3 next iteration; and `rg -c 'x' src/` **exits 1 on zero
matches**, so every "no occurrences remain" criterion written as "returns 0" could never pass.
Criteria are now preflighted before iteration 1 — a criterion that already passes is a no-op, not an
acceptance test.

**Design distinction now encoded**: `Done when` = achievements (false now, must become true — they
define termination). `regression-command` = invariants (true now, must stay true). An invariant in
Done-when verifies nothing; an achievement in regression-command burns the failure budget immediately.

Gate tooling is 9 scripts under `scripts\` sharing `LoopCommon.ps1`, with exit codes as the wire
protocol (0 clean / 1 violation / 2 script error, and **10 = stop** from `Test-Budget.ps1`). Notable:
`Initialize-Loop.ps1` is the single setup entry point (writes `.loop\state.json` with `started_at`,
which is what makes wall-clock caps enforceable); `Get-ChangedFiles.ps1` exists because
`git diff --numstat` reports +0 -0 for **new** files; `New-Checkpoint.ps1` uses `git stash create`,
which writes objects without any commit, so it respects the never-commit rule; `Invoke-Rollback.ps1`
needs `-AllowClean` to delete files the Executor *created* (`git restore` alone cannot).

Loop state lives in `<repo>\.loop\`, not the repo root. See
[[reference-powershell-script-contract-gotchas]] for the PowerShell traps hit along the way.
