---
name: project-model-import-reserved-code-name
description: Metadata model-import attribute deploy must exclude reserved Code/Name attrs or the v1/Attributes POST 400s (gateway 10051)
metadata: 
  node_type: memory
  type: project
  originSessionId: 054e794e-2059-4739-aa5d-a3f2b2145f9b
---

The metadata model-import "Deploy Model Attributes" step (`POST v1/Attributes`) must **exclude the reserved system `Code` and `Name` attributes**. Profisee auto-creates Code+Name on every entity at creation time, and the gateway rejects any attempt to (re)create an attribute named `Code`/`Name` with **`10051 : Attribute name Code is a reserved word.`** → HTTP 400. PowerShell `Invoke-RestMethod` only surfaces the generic `(400) Bad Request`; the real `10051` line is in the **target instance's** `Profisee.Platform.Gateway.Api` system log (and `WorkloadExecution.ErrorMessage` is NULL).

Discovered via workflow `10000151` ("Entity Creation For Connect Test Execution"), step 5 "Create DBA Entities: PDATA120" (workload `100005775`): a 51-substep MultiStep where 50 entity creates succeeded and step 51 (the bulk attribute deploy) 400'd — for PDATA120 the entities' ONLY attributes are Code+Name, so the entire deploy payload was reserved words.

**Fix (branch bug/connect_testing_export):** in `TestAuto.Web/Services/MetadataImport/ModelImportScenarioFactory.cs` — (1) `BuildAttributesArray` skips attrs whose `identifier.name` is Code/Name (`IsSystemKeyAttribute`, mirroring the Code/Name skip in `SqlServerDataStoreScriptGenerator`); (2) `BuildEntityCreateSteps` omits the deploy step entirely when nothing non-system remains; (3) both `BuildEntitiesArray` and `BuildAttributesArray` call `StripHarvestNoise` to recursively remove audit/system noise the harvest preserves verbatim — fields listed in `MetadataImportConstants.HarvestNoiseFields` = `auditInfo`, `internalId`, `isReferenceValid` (single maintenance point; update it if the gateway's accepted shape changes). This brings generated payloads to parity with the hand-coded working **RetailClient** deploy (matching workflow 10000149, steps 13 "Deploy Retail Model Entities" / 14 "Deploy Retail Model Attributes") which sends minimal, clean objects and never sends Code/Name or audit data.

**PDATA120 structure (Connect Test workflow 10000151):** step 5 "Create DBA Entities" = 50 lookup/domain entities each with ONLY Code/Name → after the filter its attributes step correctly vanishes. Step 6 "Create Primary Entities" = the PDATA120 primary entity whose attribute body holds **122 attributes = 70 freeform (type 1) + 50 DBA-reference (type 2) + Code + Name**; post-fix → 120 real attributes deployed cleanly, Code/Name dropped.

Existing stored execution configs are NOT retroactively fixed — only newly generated import scenarios. See [[testauto-metadata-model-import]]. To re-test: regenerate the import via /metadata/entities, then re-run the workflow from the top (its leading Delete/Drop steps clean up the already-created entities).
