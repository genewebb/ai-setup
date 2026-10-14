---
name: crewchief-reset-workloads-plan
description: CrewChief reset-workloads + RunWorkloadStep design settled 2026-08-20 — plan doc in vault 99 Documentation\CrewChief
metadata: 
  node_type: memory
  type: project
  originSessionId: 29361365-c37d-4780-b499-d6d0d3d35dee
  modified: 2026-08-21T16:40:34.314Z
---

Design settled 2026-08-20, plan doc:
`Q:\Work\Work\99 Documentation\CrewChief\2026-08-20-reset-workloads-and-runworkloadstep-plan.md`.
IMPLEMENTED 2026-08-20/21 via orchestrator-worker loop: 9 iterations, 5/6 criteria green, unit suite
3117/3117, ~30 files, NO commits (working tree). LOOP_REPORT: speed-merchants\.loop\LOOP_REPORT.md.
LIVE-PROVEN 2026-08-21: full atomic chain verified on CORPLTR94 — batch Succeeded, PDATA120 = 1,000,000
records. Root-cause session fixed 8 defects (5 test, 3 production): enable-by-id (gateway route id-only),
teardown deletes for rerun, runAsUser/ServerName/table retargets (artifacts bake exporting-env values),
WaitForBatch timeout layering, ConnEx HttpClient 100s default cap (now infinite; step CTS governs),
EntityResetEmitter GUID round-trip (THE root cause — fresh GUIDs orphaned strategy entityId + 122
attribute mapping keys → "Entity metadata could not be found"), per-step PollFailureLimit knob (gateway
500s status polls under import load). Import rate this box ~280-420 rec/s; e2e budget 90 min.
Implementation discoveries: strategy artifact = mapping expressions ONLY (shape comes from model
export Entities.json / live read); exports write DBA values as columns on ONE flat staging table (no
DBA lookup tables); modelId resolved live from any entity (no lookup endpoint), emitted as
{{ProfiseeModelId}} global; System.Progress<T>.Report posts async — executor uses synchronous
IProgress. Workload names kebab-case: <base>-reset-entities/-reset-datastore/-full-run.

Feature: Connect Import wizard emits reset workloads so strategy runs are atomic/repeatable.

Key decisions:
- Four workloads behind toggles: `<Strategy> — Reset Entities` (Profisee REST drop/recreate main+DBA entities), `— Reset Datastore` (SQL DDL drop/recreate tables), `— Run` (existing ConnEx set), `— Full Atomic Run` (RunWorkloadSteps).
- NEW step type `RunWorkloadStep`: runs child workload by NAME via IWorkloadFileStore (files-only). Preflight walks reference graph — fails on missing/cycle. Child steps inline, LiveStepOutput prefixed, halt-on-failure.
- Param precedence weakest→strongest: parent globals < child globals < step params. Implemented as `MergeParameters(parentGlobals, childGlobals)` before existing globals-under-step-over merge (UtilityOrchestrator.cs ~180). Parent fills gaps only — hence emission rule: connection params as tokens/globals, never baked literals.
- Entity reset order: DELETE main, DELETE DBAs, CREATE DBAs, CREATE main (DBAs must exist for domain-based attr refs). 404 = success. Recreate via REST builds backing tables — zero SQL on import side.
- `IDatastoreResetEmitter` registry keyed on datastore type (non-SQL stores coming). SQL v1: one SqlStep, DROP IF EXISTS main/DBAs then CREATE DBAs/main; DBA cols nvarchar(250) per [[profisee-dba-is-entity-code]] rule.
- Snapshot semantics: payloads baked at import time; reset reverts to import-time shape; wizard UI must state this.
- Profisee metadata REST routes/payloads = verify-at-implementation, not from memory.
- YAGNI'd: param passing beyond globals underlay, rollback, depth caps, reverse-ref index (v1: preflight error + export warning in WorkloadTransferService).

Related: [[crewchief-connect-import-apikey-globals]], [[crewchief-workload-runas-inheritance-carveout]], [[crewchief-steptype-coverage-assertions]] (new step type = INDIVISIBLE registry/parity/coverage updates).
