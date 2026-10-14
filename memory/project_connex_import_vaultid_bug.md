---
name: project_connex_import_vaultid_bug
description: "ConnEx import \"service provider shows no entities\" root cause — raw export artifact with vaultId credentials was never tokenized"
metadata: 
  node_type: memory
  type: project
  originSessionId: df74bf7b-6453-4a7b-be5d-cc30f76c3a42
---

Investigated 2026-06-08 (branch bug/connect_testing/genewebb). Symptom: ConnEx ServiceConfiguration import on SMVMTR2 creates the config but the credential doesn't work (no entities); manually retyping the password in the ConnEx UI fixes it.

**Root cause (CONFIRMED + FIXED 2026-06-08):** a **case-sensitivity bug in the tokenizer**. The ConnEx *gateway* export (`v1/Connect/Configurations`) uses lowercase `configuration`/`id`/`name`; older/raw exports use uppercase `Configuration`. `ArtifactTokenScanner` finds nodes case-INsensitively (so the dialog shows candidates) but stamps each candidate's `JsonPath` with hardcoded uppercase `Configuration`. `ArtifactTokenizer.ReplaceValue`/`ReshapeCredential` then resolved those paths with Newtonsoft `root.SelectToken(path)` which is **case-SENSITIVE** → returned null on a lowercase export → both silently no-opped → the "tokenized" artifact was byte-for-byte the raw export (vaultId creds, hardcoded server/db/id/name) while `GlobalParameters` (DbPassword=`{{$config:SQL Server Service Provider:ConnectReadOnlyPassword}}`, etc.) were populated but **had no `{{tokens}}` to fill**. On import to SMVM2 the source vaultId didn't exist → ConnEx created a NEW empty credential (created config had a different vaultId than the artifact) → no usable password → no entities. That untokenized artifact is what `ModelSource_-_SMVMDB2.json` was.

**Fix applied (branch bug/connect_testing/genewebb):**
- `ArtifactTokenizer` — added `SelectTokenCaseInsensitive` (walks dotted path segments case-insensitively) used by both `ReplaceValue` and `ReshapeCredential`. Regression test: `ArtifactTokenizerTests.Apply_Credential_LowercaseConfigurationExport_StillReshapes`.
- `ConnExScenarioFactory` + `IConnExScenarioFactory` + `ConnExResourcePageBase.ImportResourceAsync` — import now embeds the tokenized artifact **inline** (`ConnExStep.ArtifactJson`) by default; only falls back to a saved file (`ArtifactFile`) if compressed scenario data would exceed 4,000 chars. Factory now takes `IConnExArtifactStorage`. Preview reads inline first. (See [[feedback_connex_artifact_inline_over_file]].)
- All 29 ConnEx unit tests pass; TestAuto.Web builds clean. Still TODO/optional: fail-loud guard in `ConnExExecutor` on a vaultId credential in an Import artifact.

**The correct shape** is the tokenized template `TestAuto.Utilities/Scripts/ConnEx/ServiceConfigurations/ModelSource.json`: credential = `value:{ name, providerType:"LocalVault", configuration:{ value:"{{DbPassword}}" } }`. `ArtifactTokenizer.ReshapeCredential` converts export `vaultId` → that inline-token shape. See [[connex-import-tokenization]].

**Proven facts (don't re-investigate):**
- `ConnectReadOnly`/`Profisee1` authenticates against SMVMDB2.ModelSource and sees 33 tables — secret value is correct.
- The full pipeline (orchestrator `ResolveSpecialParameterValues` → `ConnExExecutor` → ConnEx) works end-to-end on CORPLTR94: `{{$config:...}}` resolves to Profisee1, inline `configuration.value` import makes ConnEx vault it and assign a vaultId. So inline-token credentials DO work; `$type` discriminators are NOT needed on the `v1/Connect/Configurations` gateway.
- ConnEx credentials are write-only (can't read the stored password back), so the only field test is "retype it and see if it connects."

**Secondary bug:** `GlobalParameters.DbServer` = `{{$config:ServerNames:ApplicationServerName}}` (→ SMVM2, the app server) but a SQL connection needs `DatabaseServerName` (→ SMVMDB2).

**Recommended code fix:** `ConnExExecutor` (TestAuto.Utilities/Executors/ConnExExecutor.cs) should detect a `vaultId` credential in an Import artifact and FAIL LOUD ("credential is a vaultId reference; won't resolve on target — tokenize it") instead of silently importing an empty credential.

**Diagnostics that worked:** SMVM2 ConnEx is reachable from CORPLTR94 read-only via `https://SMVM2.corp.profisee.com/profisee/rest` + `x-api-key` (ProfiseeRestKey); `GET v1/Connect/Configurations[/{id}]` lists/exports. Integration test class `ConnExServiceConfigImportTests` (has diagnostic tests added: Export_WorkingConfig_DumpShape, Import_InlineCredential_ThenExport_ShowsWhetherVaulted, Import_RealModelSourceShape_..., Import_FullOrchestratorPath_ShowsResolvedCredentialValue). Inspect stored scenario config with [[reference_scenariomgt_db]] / scenario-config-inspector.
