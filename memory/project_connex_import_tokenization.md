---
name: project-connex-import-tokenization
description: ConnEx import tokenization was rebuilt — per-provider transformers retired in favor of a scanner/tokenizer + selection dialog
metadata: 
  node_type: memory
  type: project
  originSessionId: 1fdd2d24-5126-4fac-b298-30eeaad1493b
---

The ConnEx import flow (TestAuto.Web) was rebuilt 2026-05-29 on branch `bug/matching_15m/genewebb`.

**Retired (DELETED):** `IServiceConfigTransformer` + `SqlServerConfigTransformer`/`SnowflakeConfigTransformer`/`DatabricksConfigTransformer`/`SynapseConfigTransformer`/`OneLakeConfigTransformer` + `ServiceConfigTransformerResolver`, and `ConnExScenarioFactory.TransformServiceConfigExport`/`TransformIntegrationStrategyExport`.

**Replaced by** (in `TestAuto.Web/Services/ConnExTokenization/`): `ArtifactTokenScanner` (structural discovery by `assignmentType` + `{id,name}` Identifier shape — no provider-specific code), `ArtifactTokenizer` (applies selections → tokenized JSON + parameters; credential vault→LocalVault reshape lives here now), `SecretCatalog` (Section→Item from IConfiguration, masked). UI: `ConnExTokenSelectionDialog`. `ConnExResourcePageBase.ImportResourceAsync` now does export→scan→dialog→tokenize→save→create; `CreateImportScenarioAsync` takes a parameters dict and promotes ALL of them to `GlobalParameters`.

**Why:** import now discovers all tokenizable fields and lets the user check/uncheck, pick secrets (stored as `{{$config:Section:Item}}` refs), pick reference targets, and regenerate GUIDs — instead of hardcoded tokenization.

**How to apply:** The skill was UPDATED + RENAMED 2026-05-31 — `connex-config-transformer-strategy` → **`connex-import-tokenization`** (folder, frontmatter, linker, README, junction all updated). Body now matches the tokenization system and the phantom `ConnExReferenceCatalog` references were removed (it never shipped; reference rows are editable GUID text boxes). Point to the scanner/tokenizer, not the deleted transformer classes.

Reference rows (entityId / serviceConfigurationId) are plain editable **text boxes showing the current GUID** — the dropdown pickers were removed because the ConnEx list API doesn't return the GUID. `IConnExReferenceCatalog`/`ConnExReferenceCatalog` (+ DI registration and tests) were **deleted**; the `ReferenceType` enum was kept (scanner/model still use it). Known gaps: dialog rendering is not bUnit-tested (only `Validate()` logic); 24 pre-existing ConnEx test failures are unrelated. Spec: `C:\devopslocal\Documentation\speed-merchants\planning\Design_ConnExImportTokenSelection_2026-05-29.md`. See [[project_repos]] [[project_swarm_pipeline]].
