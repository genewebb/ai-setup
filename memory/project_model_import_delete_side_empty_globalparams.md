---
name: model-import-delete-side-empty-globalparams
description: "Model-import DELETE/DROP scenarios shipped with empty GlobalParameters → {{<Entity> Table}} tokens never resolve → DROP silently no-ops → leftover FK table breaks the later create-table step (pass/fail code 1)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25f7dbe8-6d99-4da1-a08d-7ed23c825a54
---

Model-import workflow "Create target table X" step failed with `SQL returned pass/fail code: 1`. Root cause (verified by decompressing the stored execution config, NOT guessing):

`ModelImportScenarioFactory.CreateDeleteScenariosAsync` built its scenarios with `EmitOneAsync(steps, new JObject(), ...)` — an EMPTY GlobalParameters — while the create side (`CreateImportScenariosAsync`) passes the real `ModelGlobalParameters.Build(model, ids)`. So delete/drop scenarios stored `CustomParms.GlobalParameters = {}` (gp=0) while create scenarios had gp=102. The DROP scripts use `{{<Entity> Table}}` tokens (via `GenerateDropTableScript`/`TableNameToken`); with no params the `TextTemplater` step is skipped (`SqlScriptExecutor` line ~109 `if (sqlStep.Parameters?.Count > 0)`), so the literal `{{PDATA120 Table}}` reaches SQL. `IF OBJECT_ID(N'[dbo].[{{PDATA120 Table}}]', N'U')` → NULL → DROP skipped → **the FK-bearing primary table is never dropped** → the create-Dba-table step's own `DROP` dies on the FK → caught by the AutoWrapPassFailCode TRY/CATCH → code 1.

Pre-existing latent bug (no-op drops never errored, so the delete workflow always "passed" without dropping anything); exposed once prior runs left FK tables behind. NOT caused by the case-insensitivity sweep.

**Fix:** `CreateDeleteScenariosAsync` now builds `globalParameters = ModelGlobalParameters.Build(model, ids)` and passes it to `EmitOneAsync` (TestAuto.Web/Services/MetadataImport/ModelImportScenarioFactory.cs ~line 165-174). Regression test added in `ModelImportScenarioFactoryTests.CreateDeleteScenariosAsync_WithDataStore_SplitsDeletesAndDrops_PrimaryFirst` (asserts drop scenarios contain GlobalParameters + "<Entity> Table"). Build clean, 59 MetadataImport tests pass.

**After rebuilding the user MUST regenerate the import** — existing template 10000151 / execution 10000160 still hold the buggy gp=0 delete/drop configs, and leftover FK tables in the target DB need clearing (the regenerated, now-resolving drops will handle them).

**Diagnosability FIXED (2026-06-29):** `SqlScriptExecutor.WrapSqlWithPassFailCode` used to capture `@ErrorMessage` in the CATCH then discard it (every SQL failure showed only "pass/fail code: N"). Now the CATCH `RAISERROR(N'%s',10,1,@msg) WITH NOWAIT` (sev 10 = non-aborting → fires the wired `SqlConnection.InfoMessage` → Serilog) AND the final `SELECT` returns a 2nd column `PassFailErrorMessage`; the reader captures it (gated on `AutoWrapPassFailCode`, FieldCount>1) into `StepExecutionResult.PassFailErrorDetail`, and the failure message becomes `"...pass/fail code: 1... SQL error: <ERROR_MESSAGE()>"`. Same swallow-the-error pattern as the HTTP-400 executor (that one still swallows the gateway body — candidate for the same treatment). See [[model-import-refdata-empty-body]].
