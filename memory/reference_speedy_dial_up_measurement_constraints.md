---
name: reference_speedy_dial_up_measurement_constraints
description: "Gene's 3-5% IaaS floor is EXPERIENCE not a recording (perfDashboard holds zero same-config repeats); the three constraints on a shorter CRUD run; where the 18h data actually lives"
metadata: 
  node_type: memory
  type: reference
  originSessionId: dab7e805-1f7d-4599-a8f9-7e54417973f7
  modified: 2026-09-12T14:17:23.726Z
---

**Gene's number, 2026-09-12 09:46:** the 18-hour CRUD suite runs on **IaaS** and shows **3–5%
variance on the same test repeated**. That is the tolerance band — ≤5% is noise, no verdict — and it
fixes X: a short run must resolve **>5%**. Matching the existing floor IS "the same level of
confidence"; the bar is *improving* the ability to answer faster/slower AND why (09:49).

**VERIFIED 2026-09-12 10:30 (Fable review): the 3–5% has NEVER been recorded.** The 18h results live in
`pc-speedmr-prd-db` → `perfDashboard.BatchCrudSummary` (batch CRUD, rebuilt from
`data.tRecordApiExecution`) and `perfDashboard.UserCrudSummary` (stewardship, from
`data.tRecordInteractiveApiExecution`). Batch: 84 executions, 7 platform versions (25R1→26R2P), 6
builds, Feb–Jun 2026, 1M records, IaaS, per Operation (Create/Update/Delete/Record Read), RuleCount
10 Rules / No Rules, Throughput + P50/P95/winsorized. A full-identity
`GROUP BY Scenario, BuildNumber, RuleCount, UserLoad, Operation, RecordVolume, AttributeCount, Nodes,
EntityName HAVING COUNT(*) > 1` returns **no rows in either table**. The stewardship "groups of 4"
are attribute-count sweeps (15/30/60/120 attrs at different volumes), not repeats. Every number is
N=1 per configuration. So the floor cannot be mined from history; **the first same-config repeat is
Stage 1's first and cheapest action**, and until it exists no sweep in the store (rules-on/off 3×,
attribute-count curve) can be called signal vs noise. Data wrinkle: `BuildNumber` is NULL on 6 rows
and `CURRENT` on 8.

**Real "why" axes already in the store (sweeps, not repeats):** same build `25.4.0.1038`, Create, 1M:
10 rules 3h52 (71.7/s) vs No rules 1h17 (216.6/s) — 3×. Rules on/off = FIRST Tier 2 axis (Gene
10:20, O6 closed). Attribute count = second (P50 792→2,484 ms across 15→120 attrs).

### Three constraints that silently invalidate a shorter run

1. **The floor is a property of the 18-HOUR RUN, not of the suite.** At 100K/10min it could be 15%.
   Must be measured, never extrapolated.
2. **Dataset size and duration are two dials; only duration is safe.** Cutting records changes the
   system under test (buffer pool, index depth, cache hit). Move dials independently, watch ABSOLUTE
   throughput; a jump when records drop = that dial is compromised there.
3. **An axis can only attribute a change if its own noise floor is below it.** Variance-test every
   decomposition; EXCLUDE failures from the dashboard.

### What exists in vNext (verified against src, 10:15)

- **Ramp is BUILT and PROVEN, not "decided":** `ramp` verb separate from `launch`;
  `RampSchedule.OpeningUsers = 1`, defaults 4 rungs × 20 s to ceiling 8, max 64 rungs / 3,600 s hold;
  `IRunDial` + `IRunDialHold` (operator hold + level in one statement). Proofs: `Invoke-RampProof`,
  `Invoke-BreakRuleProof` (ErrorRate / approx p50-p95 Latency / Saturation, breakpoint ATTRIBUTED to
  the signal), `Invoke-PauseResumeProof`, `Invoke-PauseDialAtomicProof`. Stage 2 has its executor.
- **`RunProfile` is a COMPARABILITY RECORD, not launchable** — `capture-profile` freezes
  ProfiseeVersion/DqRuleCount/attribute counts/TargetUsers/observed users/Machines/Environment/
  WorkloadCommitHash with a content hash, insert-if-absent. Tier 2 = re-launch the same workload
  (ordinary launch) then prove like-for-like by matching hashes.
- **`Invoke-LaunchReplayProof.ps1` proves IDEMPOTENT LAUNCH** (a replayed POST returns the SAME run,
  never a second) — the opposite of re-execution. Do not cite it for replay.
- **Zero CDP code in `src/`.** Donor CRUD scenarios record elapsed per SCENARIO (operation-separated by
  folder) but the update mix (UpdateRecordPercent / NewRecordPercent / survivors) is decided and
  logged, NOT metered — Stage 1(c) gap. vNext warehouse operation-type dimension unverified (O7).

Parent: [[project_speedy_guiding_document_2026-09-12]]. Store: [[project_perfdashboard]].
