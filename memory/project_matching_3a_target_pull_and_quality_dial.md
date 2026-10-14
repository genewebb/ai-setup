---
name: project_matching_3a_target_pull_and_quality_dial
description: "2026-09-12 matching changes - 3a now reads AutoApproved target records (ExistingMatchedOnly wins over the wizard's stray SourceSystemDistribution), 3b/3c get FullyPopulatedRecordPercent + PerformLookupBeforeCreate parms; NoChange added to the RecordActionType domain; Credibly->Seed config swap still in place pending first green rerun"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6f0d3904-49de-4741-a701-439ff517a35a
  modified: 2026-09-12T02:45:59.279Z
---

**Root cause of 3a's 5,827/100,000 failures (workload 100007334)**: the wizard writes a `SourceSystemDistribution` into every config it saves, and `RecordMixManager.cs:474` routed on `HasSourceSystemDistribution` BEFORE `RecordSource` mode — so a 3a config authored as `ExistingMatchedOnly` / `TargetEntity` / `MatchStatusFilter=[20]` was hijacked to ModelSource and sent sparse Credibly rows. The target path (`GetExistingRecordsBatchAsync`, `:535`) had existed all along.

**Code landed** (uncommitted at time of writing; plan `Q:\Work\Work\99 Documentation\matching\MatchCapableRecordSelectionPlan.md`, chunk backups beside it under `backups\2026-09-11-3a-chunks\`):
- `RecordMixManager.UsesSourceSystemDistribution(mode, has)` — `ExistingMatchedOnly` always wins; used at the three gates `:243/:299/:474`.
- New CustomParms: `FullyPopulatedRecordPercent` (int, default **100** = "every sent attribute non-blank", i.e. the user's "85% have values in ALL fields" semantic, NOT "would match") and `PerformLookupBeforeCreate` (bool, defaults true for `LookupThenCreate`, false otherwise). Both survive the wizard via `AdditionalCustomParms`.
- Blending is **per source system**; Apple/Seed have zero sparse rows so an 85% ask lands ~92.5% on Apple+Credibly. Populated pool per 3M: Apple/Seed 3.0M, Intuit 2.50M, Walmart 2.20M, Credibly 1.13M.
- `GetRecordsByKeysetAsync` gained two TRAILING OPTIONAL params; 26 existing call sites untouched; CRUD (`TestAuto.Records`) has zero references — verified by grep.
- Column whitelist = `RecordPoolRepository.RecordColumns` (now public) — it is the SQL-injection guard for attribute names that get interpolated into WHERE.

**Data landed**: `NoChange` added to `UnifiedMatchingRecordActionType` on the metrics instance (REST, id 5) — the target path tags rows `RecordType_NoChange` and the domain lacked it; an invalid DBA code fails the whole metric persist.

**Still pending**: (1) user rebuilds + reruns step 21; expect one row `200/2/100000`, keys in the target's `01…` range, `LookupHasMatches=Y`. (2) THEN restore the three 3a configs from `{Apple,Seed}` back to `{Apple,Credibly}` — deferred because on the OLD binary Credibly re-exposes 2219. (3) 3b/3c dial values are the user's choice; 3c sparse *creates* untested against Profisee required-attribute rules. (4) 3a's `LubcRequestAttributes` still carries `PhoneNumber` (Profisee's is `Phone Number`) — harmless, one-token fix.

Measured: target REST page 1 = 4.8 s cold, page 200 = 0.5 s, page 1900 = 2.6 s (500 rows); 963,067 AutoApproved locally (15M template wants 1,000,000 — check that environment). Populated-slice keyset page on Credibly = 5,519 logical reads vs 2,096 unfiltered (selectivity, still `Scan count 1`).

Related: [[reference_lubc_2219_is_request_validation]], [[reference_profisee_gateway_400_unexpected_character_means_microservice_down]], [[reference_profisee_matching_strategy_table_by_version]].
