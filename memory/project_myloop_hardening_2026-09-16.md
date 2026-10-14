---
name: project_myloop_hardening_2026-09-16
description: "The MyLoop reliability-hardening programme (rows 48.R1-48.R11 + 48.WAVE1): R1-R7, R10, R11 LANDED 2026-09-16 (chaos 27/27 vs baseline red, suite 27/27); R8/R9 PARKED; loop on HOLD for Gene's maintenance; where the review, tickets, baseline, staging copies, report and residuals live"
metadata:
  type: project
---

**State (2026-09-16 evening): DONE for R1–R7, R10, R11; R8 and R9 PARKED; the loop is PAUSED on Gene's explicit hold
("do not restart without my permission I want to do some maintenance"). Nothing dispatches until he releases it by name.**

**What landed** (each row: grader + self-test + blind opus verifier, all PASS_WITH_NOTES, every finding fixed in the next
landing or carried by name): R1 atomic temp+rename writes + quarantine; R2 `Invoke-WithLoopLock` named mutex per shared
file; R3 row `version` CAS (STALE-WRITE); R4 `claimEpoch` fencing (STALE-EPOCH, `epoch-unstated` allowed + logged);
R5 `journal.jsonl` intent/committed pairs for dispatch and close; R6 `Reconcile-Rows -Repair` (shapes A/B/C/E/G, LOST
repair, cycle diagnosis, reconstruction from journal + ticket); R7 automatic LOST (dispatchedBy pid, lead-lock pid,
heartbeat, wave-null; `lostWhy` always); R10 `lib\RowStates.ps1` transition table + `Set-RowState` sole writer of `state`
(TRANSITION-REFUSED, journal `transition` lines); R11 `tests\Test-LoopChaos.ps1` (17 crash labels via `MYLOOP_CRASH_AT`,
6 barrier races, F1/F6/F8/F9 shapes; second repair must repair nothing). Skill suite `tests\Test-MyFableNext.ps1` = 27 cases.

**Where:** live scripts `Q:\...\skills\myloop\scripts` (alias `C:\Users\agenewe\.claude\skills\myloop\scripts` — ALWAYS
use the alias for graders: their detached launches do not quote the vault path with spaces). Staging copies (cumulative,
never delete): `scripts-stage-20260916-pre-hardening` (baseline, byte-identical old scripts), 113808 R1, 120600 R2,
121300 R3, 121800 R4, 122400 R5, 123000 R6, 123800 R7, 124000 R10, 125000 R11 + fold-ins (= live). Report + companions in
vault `03 Shared/work-ai/Loops/LoopOptions/` (MyLoop-Hardening-Report.html = Artifact https://claude.ai/artifact/2Tq2Z9nwvadHrovDy9fz7M, -Architecture-Review.md,
-Row-Lifecycle.html Archify diagram). Rows `.loop\rows\48.R*.json`; adjudications in `.loop\rows\_decisions.md`; graders
`.loop\criteria\hard-N-*.ps1` + `selftest\`.

**Carried residuals (by name):** R8/R9 parked (finished workers still wait for a hand collect; `Collect-Wave.ps1` named in
the table but absent); two suites at once give load-induced false failures (hard-3 C3 collect window; hard-11 C6 race
timing) — run graders/suite ONE AT A TIME; `Set-RowField` can bypass the guard for a future caller; version compare skipped
on an absent/unparseable record; cycle detection only in Reconcile; `Add-LoopEvent` inside the lock; board tool locks
started.json under dispatched.json's name; R5 test case's unasserted close half; Close-Row logic duplicated skill vs
`.loop\tools`; chaos suite `-Tools` default hardcodes this repo; `Invoke-Command2` fails only on thrown error/exit code.

**Why:** the KEEP MYLOOP verdict measured 6 stranding shapes; Gene chose to borrow durability primitives (Superharness
version CAS; AIWorkHub epoch + reservation journal) and keep the scheduler and verification discipline. Direct
implementation by the lead in one staging chain with per-row dispatch/collect/close bookkeeping took ~7 h wall clock for
9 rows (est 465 min) instead of the ~9 h worker estimate.

**How to apply:** on the next wake, `/myloop` shows PAUSED — do only owed bookkeeping until Gene releases the hold. Then
Sync-Board, OWED list, 48.WAVE1 acceptance reads, and R8/R9 only when he names them. Every grader/self-test/suite run
solo. Heredoc backslashes still mangle: write patch scripts with the Write tool.

Related: [[project_myloop_replacement_evaluation_2026-09-16]], [[project_autoresearch_for_myloop_2026-09-16]],
[[project_myfable_foreman]], [[reference_background_worker_hangs_on_delete_guard]], [[feedback_loop_two_strike_rule]].
