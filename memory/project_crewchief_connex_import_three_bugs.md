---
name: project_crewchief_connex_import_three_bugs
description: "CrewChief Connect import was broken by THREE independent bugs (credential-less config, CanExecute/validator rejecting teardown Delete, delete-by-path 405) — all fixed and verified live 2026-08-15"
metadata: 
  node_type: memory
  type: project
  originSessionId: b085d44c-6642-41f4-9aca-4ff12d6dc36e
  modified: 2026-08-16T03:02:45.368Z
---

Diagnosed and fixed 2026-08-15 on CORPLTR94 with `c:\tmp\connecttest` (ModelSource service config + ModelSourceImport strategy). Symptom the user reported: "import of a connect strategy is not working correctly, some steps work others do not."

Three **independent** defects compounded. Fixing any one alone still left the flow broken — which is why it read as flaky rather than broken.

**1. Credential-less service configuration (the headline bug).** A Connect portal export strips secrets: `UsernameVault`/`PasswordVault` arrive as `assignmentType: "Credential"` with **no `value`**. ConnEx **accepts** that import (201 Created) and creates a configuration whose credential is empty. The failure surfaces on the NEXT step — the strategy import — as `400 "Username and/or password are required but were not specified."` So the failing step is never the wrong step. Fix: new `CrewChief.Engine/Helpers/ConnExCredentialGuard.cs` + a Step 5c gate in `ConnExExecutor` that refuses an Import whose credentials would land empty, naming each setting, before any HTTP call. Distinguishes three unusable shapes: no value, `vaultId` from the source vault, empty inline value. Scoped to Import only — Delete must stay allowed so teardown can clear a bad earlier import.

**2. Teardown Delete steps were rejected before running.** `ConnExStepSetBuilder` emits the first two steps of every generated Connect Import workload as `Delete` with a `resourceId` and **no artifact**. Both `ConnExExecutor.CanExecute` AND `UtilityOrchestrator.ValidateScenario` (V1/V23) demanded "exactly one of ArtifactFile or ArtifactJson" for Import **or Delete**, so the whole run was refused at validation with "Executor cannot execute this ConnExStep step". Fix: a Delete carrying a ResourceId needs no artifact (the artifact is merely the other way to get the Id — the executor's own V17 check already said so).

**3. Delete used a path segment; the gateway needs a query parameter.** Executor built `DELETE {gatewayPath}/{id}` → **405 Method Not Allowed**. Correct: `DELETE {gatewayPath}?{UidsParam}={id}` → 204. `ConnExConstants.GatewayDeleteParams` (ConfigurationUids / IntegrationStrategyUids / ServiceProviderUids) already existed but was **never used by production code** — only the constants had been added. The existing unit test `Delete_WithExplicitResourceId_Succeeds` asserted the *path* form, so it pinned the defect in place; corrected.

**Why it shipped:** `ConnectImportEmitTests` drove a `StubOrchestrator` whose `ValidateScenario` returned `IsValid = true` unconditionally, so the generated step set was never checked against the real validator. Added `BuildStepSet_EmittedSteps_PassTheRealOrchestratorValidation` driving the REAL `UtilityOrchestrator` — the one-truth agreement test that would have caught bugs 2 and 3.

**Proven working shape** (verified live — ConnEx vaults it and assigns a fresh `vaultId` of its own):
```json
"PasswordVault": { "assignmentType": "Credential",
  "value": { "providerType": "LocalVault", "configuration": { "value": "<secret or {{token}}>" } } }
```
This is exactly what `ArtifactTokenizer.ReshapeCredential` emits — the tokenizer was always correct; nothing forced you through it.

Related: [[project_connex_import_vaultid_bug]] (same root cause diagnosed 2026-06-08 on the TestAuto side; the recommended fail-loud guard was never implemented until now), [[reference_profisee_gateway_record_paging_400]], [[project_crewchief_connex_import_tests]].
