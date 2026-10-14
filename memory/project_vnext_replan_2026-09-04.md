---
name: project_vnext_replan_2026-09-04
description: "vNext TaskPlan §4 re-plan after iteration 21 (09-04 14:40) — A6 mis-sized 10x (7,345 donor lines), A7 emits a ConnEx step no executor runs, 8d criteria live in .loop-archive-uow8d, loop budget cap tripped, measured estimate model 105 Executor-min per 1,000 donor lines"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2b5eece2-9596-460b-ad30-37ca01299ba1
  modified: 2026-09-04T19:09:45.998Z
---

**2026-09-04 14:40 — vNext_TaskPlan.md §4 rewritten task-per-iteration (Gene: "item 4 too broad, make it task based like item 3").**
Queue order now: 22 A3.6b → 23 A2.3h → 24 A4a (seed gate/manifest/installer core) → 25 A4b (content seeders) → 26 A5 backup →
27 A6.0 PROBE → 28 A7a tokenize → 29 A7b step-set builder + ConversionProfile → 30–35 A6a–A6f (model/seam, identity+gate+registration,
local probers, SQL+WinRM, shares, ADO+ConnExParams) → 36 A8 (gated on Gene "load-1.0") → 37 8d.2 → 38 8d.3. 16 iterations to close 9a, 18 with 8d.

**Findings (all measured, not assumed):**
- A6 donor = **7,345 lines / 19 files** (git show HEAD | wc -l). Old plan budgeted 90 min. Twice A3 (3,669 → 8 iterations). Needs A6.0 probe:
  which of 8 capabilities has a consumer among vNext's FOUR executor types (CommandLine/PowerShell/SqlScript/Curl); Windows-only probers on Linux → `Unknown`;
  no Run-As on StepDefinition yet; PreflightGate must be an Application seam (no Web layer).
- A7 `ConnExStepSetBuilder` emits ConnEx-typed steps; vNext has NO ConnEx executor (`grep ConnEx src` = 2 unrelated hits). GOAL's seven rows cover tokenization only.
  Raised to Gene as **A7c ConnEx executor** (donor ConnExExecutor + 5 helpers ≈ 600 lines) — recommend queue inside 9a.
- 8d.2/8d.3 criteria are NOT in `.loop\criteria` — they are `.loop-archive-uow8d\criteria\g2-partial-write.ps1` / `g3-census-audit.ps1`; must copy in + re-baseline-verify (suite 1406 → 1808).
- `Test-Budget.ps1` = stop `max-duration-hit` (1665 min vs 1440 cap, started 09-03 14:43Z); 20b + 21 already ran past it. Recommend max_duration 4320, max_iterations 55 (39/40 planned).
- Estimate model: **≈105 Executor-min per 1,000 donor lines** (384 min / 3,669 lines over A3.1–A3.6a). Old per-iteration median (25m) under-ran 30–50% three times running.

**Gene decided 14:43:** A2.3f D1–D10 APPROVED (CODE task row 23); §3.10 "load-1.0" APPROVED (A8 unblocked, row 37); R27 Q2 = immutable, Q3 OPEN; **A7c ConnEx executor ADDED** row 30 (GOAL.md ratified amendment); A6.0 probe proceeds. Caps raised 14:39: duration 8000, iterations 55.
**Iteration 22 DISPATCHED 15:10** (opus, checkpoint e06d1d8, §0 Started 15:08): grader b36b baseline-verified after 3 grader defects fixed (target-typed `= new()` regex miss; case-insensitive `-match` false alarm on compose.yaml "by reference"; TransferResult.Propagate guard throw excluded). On return: gates per PLAN 22 (23 allowed files; band +1700..3400/−0..40), b36b, regression floor 1808; then re-baseline 22, PROGRESS, §0 Completed, ratchet, TaskPlan §3 row 22 / §4 drop, A3 doc §6 item 19 (ValueSpecification not persisted → structural EXCLUSION; reference import ADDITIVE). Then row 23 A2.3f CODE.
**Claude Code "Restart to Update" banner (Gene 14:51) root cause:** this session (PID started 14:24:48) launched 22 s before the auto-updater swapped claude.exe 2.1.260 → 2.1.261 (14:25:10); banner true for this process until restart; 2.1.261 is latest on the native channel (npm @latest is 2.1.260, older). Prior restarts on 09-03 each caught a real release (259 at 12:34, 260 at 19:58). Not a loop. Four orphan claude.exe from 09-03 (two `--bg-pty-host` + two `--fork-session`, parent gone) still pin the 2.1.259 binary as `claude.exe.old.*` (~700 MB) — kill candidates, not the cause.

**Why:** the §4 one-liners hid a 10x sizing error and a scope gap; Gene sequences by this doc.
**How to apply:** when planning iterations 22+, read TaskPlan §4 row for the task (files, seams, decisions taken, grader name, dependencies) before writing PLAN.md; do not re-derive A6/A7 sizing. Related: [[project_vnext_a3_decisions_pending]], [[reference_vnext_plan_doc_v3]], [[feedback_loop_practices_that_caught_defects]].
