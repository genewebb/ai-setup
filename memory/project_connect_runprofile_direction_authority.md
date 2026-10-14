---
name: project_connect_runprofile_direction_authority
description: "ConnectApiExecution now sources OperationName + HttpRequestType from the RunProfile's ConnectStrategyType (I/E), not connex job.Type — the connex job is last-resort fallback; also lists which RunProfile attributes may and may not be copied onto a metric row"
metadata:
  node_type: memory
  type: project
  originSessionId: de927cca-c7d9-4280-916c-efa0f4700d44
  modified: 2026-08-12T20:50:38.236Z
---

**Rule (user directive 2026-08-12): the RunProfile is the authority for every ConnectApiExecution attribute
that maps to it. The connex job is not.**

Implemented in `ConnectPostRunCollectionScenario.BuildDetail`: `OperationName` and `HttpRequestType` both
derive from one resolved direction — `ConnectRunProfileInfo.ConnectStrategyType` (`I`→`DatabaseImport`+POST,
`E`→`DatabaseExport`+GET, via `ConnectOperationName.FromStrategyType`). Precedence: explicit `OperationName`
CustomParm → RunProfile → `connex.tJob.Type` (last resort only, because `ConnectRunProfileReader` is
never-fatal and degrades to `Unresolved`). `ProfiseeVersion` likewise prefers the profile over
`ScenarioEnvironment`. `ConnectRunProfileInfo` gained `ConnectStrategyType` and `ProfiseeVersion` as defaulted
trailing members; the reader requests both attributes over ScenarioMgt REST.

**Why:** the two used to come from `job.Type` in the same pass, and a step pointed at the wrong strategy made
them silently disagree. Live proof — production WorkloadExecution 100007502 (2026-08-12) carried
`RunProfile = 26R2-SQLSERVER-PROFISEE-E-…-8` and `OperationName = DatabaseExport` while every row was a POST
carrying import key ranges. A mismatched profile now yields wrong-but-consistent labels (a visible config
error) instead of two columns contradicting each other.

**Mapping decisions to keep:**
- Map: `Code`→RunProfile, `ConnectStrategyType`→OperationName/HttpRequestType, `TotalAttributesCount`→
  AttributeCount+RequestAttributeCount, `DBACount`→DbaCount, `RuleCount`→DqRuleCount, `ProfiseeVersion`.
- **Never map `SourceRecordCount`/`TargetRecordCount`** — they are the PLANNED volume and the shipped 1M
  profiles still say 100,000; writing them would overwrite a measurement with a stale plan.
- `WorkerThreadCount`, `FreeformCount`, `ConnectStrategyName`, the two service-provider DBAs have **no column
  on ConnectApiExecution**. `RunProfile` is a Domain attribute there, so reporting joins to them instead.
  Adding `WorkerThreadCount` needs a production model change — open question with the user.

`ConcurrentThreads` in the collection step's CustomParms is the collector's own mapping parallelism
(SemaphoreSlim), NOT the Connect worker count — it does not need to match the workload's thread count.

Related: [[reference_connex_recordcount_is_keyrange_width]], [[reference_scenariomgt_db]]
