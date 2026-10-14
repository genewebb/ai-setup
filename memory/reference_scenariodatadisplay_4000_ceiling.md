---
name: scenariodatadisplay-4000-ceiling
description: ScenarioDataDisplay is a 4000-char preview attribute; every write site must truncate or Profisee 8610s on large/chunked configs
metadata: 
  node_type: memory
  type: reference
  originSessionId: 39f903e1-ad97-4632-a44a-faa30dd283ca
---

`TestAutoScenarios.ScenarioDataDisplay` (and `TestAutoTemplate.ScenarioDataDisplay`) is a **preview-only** attribute capped at **4000 chars**. The real config lives in `ScenarioData` (inline JSON, or a `CHUNKREF:` to the `TestAutoScenarioConfiguration` chunk table — unbounded). Since chunk-spillover removed the size ceiling on `ScenarioData`, the display attribute is the ONLY thing still length-limited.

**Every write site that sets `ScenarioDataDisplay` from resolved/serialized JSON MUST truncate to ≤4000** (`raw.Length > 4000 ? raw[..4000] : raw`, or `TemplateStorage.GetDisplayText` which caps at `MaxDisplayLength = 4000`). Writing the full resolved JSON throws Profisee **8610: "value is incompatible with the attribute length — Member Attribute: scenarioDataDisplay"** for any config large enough to chunk.

This bit production (2026-06-25): a clean-prod reconvert reported "595/622 converted, errors: 27" — all 27 were large scenarios (Connect automation, Matching-strategy deploys, MetadataManagementScenario) failing 8610. Three write sites wrote full raw and were fixed to truncate: `ConfigurationMigrationJob.ConvertOneRecordAsync`, `WorkflowExportService` (export-as-scenario), `ModelImportScenarioFactory`. The editor sites (`ScenarioEditorContent`) already truncated. Regression test: `ConfigurationMigrationJobChunkTests.ConvertConfigs_LargeResolvedConfig_TruncatesDisplayTo4000`.

Note: in the convert summary, `errors` (real per-record failures, logged Error-level "Error converting {Code}") is disjoint from `unresolved` (file refs whose files aren't present on the server — benign, record still converts). Related: [[project_file_reference_retirement]].

**The 4000 ceiling is a `ScenarioDataDisplay`-ONLY concern — do NOT re-warn about it on config/body input.** `HttpRequestStepEditorCard` (the "Edit Custom Parameters" → Request Body editor) used to show a `Body exceeds 4000 character storage limit` alert + a `chars - exceeds 4000 limit` badge + import-preview `will use file mode` text, plus two code-behind `if (BodyLength > 4000) Warning = "...will switch to file mode..."` assignments. All 5 were removed 2026-06-25: they were double-stale — the body is part of the config, which the chunked store (`IScenarioConfigStore`) spills transparently, and "file mode" no longer exists (`CurlExecutor.cs` "Request Body — inline only; BodyFilePath has been retired"). If a future session is tempted to add a 4000 warning on a body/script/config text box, that's the bug, not the fix. Genuinely-real char limits that look similar but must STAY: cmd.exe `8191`, PowerShell EncodedCommand `~12000`, Profisee string-attribute create max `1–4000`, and the `SecretsBootstrap` encrypted-blob 4000 (separate subsystem, not chunked). See [[testauto-scenario-config-store]].
