---
name: reference_recordsaresameshape_first_record_contract
description: "Profisee batch record create with recordsAreSameShape=true adopts the FIRST record's attribute set as the whole batch's contract and silently drops attributes the first record lacks — proven live 2026-08-11 with a 2-record probe; TestAuto metric writes (null-skipping mapper = heterogeneous shapes) now pass false"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9d537d7b-a54e-4995-8efc-f3b929d627b8
  modified: 2026-08-11T23:29:43.052Z
---

**Symptom:** first live ConnectPostRunCollection run wrote 1000 metric rows with `PageKeyRange` NULL on every row, while the scenario's Hangfire result provably carried 999 correct values. No error anywhere — clean 201.

**Mechanism (proven, not inferred):** `RestClient.CreateRecordsAsync` hardcoded `WithRecordsAreSameShape(true)`. With that flag the gateway takes the FIRST record's attribute set as the contract for the entire batch and silently discards attributes later records carry that the first lacks. `BaseMetricDetailPersistenceHandler.MapDetailToRecord` null-skips, so metric batches are heterogeneous by design — and the ConcurrentBag ordering put the one detail (job 1000, the open-ended final page) without a PageKeyRange first. Probe: POST `[{A no attr},{B with attr}]` sameShape=true → B stored NULL; identical POST sameShape=false → B stored the value.

**Why:** the flag is a real optimisation, valid only for genuinely uniform batches. Combined with a null-skipping mapper it makes batch ORDER decide which columns survive — the worst kind of nondeterminism, and it predates 2026-08 (any nullable metric column on any entity was exposed; sparse historical metric columns may be artifacts of it).

**How to apply:** `IRestClient.CreateRecordsAsync` now has trailing `bool recordsAreSameShape = true`; the metric persistence path passes `false`. Any new batch-create caller whose records can have null-skipped attributes must pass false. Diagnosing "value written but lands NULL, no error": check this flag before anything else, and remember the Hangfire result JSON (`testautojobs.State` Succeeded Data) is the ground truth of what a scenario produced.

Related: [[project_connect_perpage_hangfire_timing]]
