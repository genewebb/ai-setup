---
name: project-speedmerchants-uow8b-8c
description: vNext UoW-8b (run profiles/ramp/break/pause/endings) and UoW-8c (MUST RESOLVE defects) both closed 2026-09-02; next is UoW-8d fault injection
metadata: 
  node_type: memory
  type: project
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-02T16:31:38.198Z
---

**UoW-8b closed 5/5 on 2026-09-02 03:50; UoW-8c closed 5/5 on 2026-09-02 12:25.** Suite went
1250 → 1389 → **1404**. Zero rollbacks and zero Verifier failures across both (11 iterations).
All work committed by Gene; HEAD after 8c was `549ceca` "Unit Testing".

**UoW-8b shipped** (§5b of the plan): a composite run profile keeping DECLARED / CAPTURED / OBSERVED
distinct (`TargetUsers` exists on BOTH `LoadWorkload` and `RunProfile` — that overlap was the whole
hazard); every run climbing from 1 unless explicitly overridden; an `IBreakSignal` seam with only
`ErrorRate` implemented and Latency/Saturation registered-but-unavailable; manual dialing PAUSING the
ramp with the state rendered in words; and `Broke` vs `StoppedByOperator` as opposite findings carried
into a conformed `bi.DimRunEnding`.

**UoW-8c fixed all five MUST RESOLVE defects** (§1b of the plan doc):

- **M1** — the orphan sweep read `OwnerHeartbeatUtc IS NULL` as a dead owner, short-circuiting the
  staleness threshold, and TERMINATED live runs. Fixed with two arms: an owned run ages from its
  heartbeat, an unclaimed one from `StartedUtc`. Needed no new column or port.
- **M2** — `return , $x` into `@()` double-nests in PowerShell, so a proof reported one row of 20
  space-joined values and exited 0. Guarded; the idiom is now gone from `scripts/**`.
- **M3** — `tests/Tests.Chaos` held zero tests since the UoW-0/1 scaffold. Removed.
- **M4** — `FactDimMigrator` could not reshape a published view (`IF OBJECT_ID … IS NULL` skips the
  create). Now `CREATE OR ALTER VIEW`, chosen over drop-and-recreate because **a `GRANT SELECT`
  survives an ALTER and not a DROP**.
- **M5** — pause and dial were two writes. `dbo.DesiredState` gained nullable `HeldUtc`; the guard now
  lives where the write it guards lives.

**M6 (no per-item pass/fail) is deliberately UoW-7's**, with p50/p95 and R15.

**NEXT: UoW-8d, the fault-injection suite — decided, specced, not started.** Six tasks in §0 of the
plan doc, each drawn from a defect this campaign actually hit. Only **6 of 71** `Tests.Unit` files
inject a failure today. `tests/Tests.Chaos` gets re-created for it, referencing more than `Domain`
this time — its old reach was why it could never test a kill.

See [[reference-vnext-plan-doc-v3]] for which document is authoritative, and
[[project-orchestrator-worker-loop-hardening]] for the loop practices this campaign proved out.
