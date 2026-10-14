---
name: project-metadata-model-import
description: "New Metadata→Entities import feature — ID-preserving model import as a workflow step (why MetadataManagementScenario can't be used)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8109969f-a9a3-49ba-a7b5-e9391c1e42a4
---

New feature (2026-06-17): **Metadata → Entities** page (`/metadata/entities`, top-level "Metadata" nav group)
that imports a primary Profisee entity + its recursively domain-related entities from any defined
`RestClients:*` source and emits ID-preserving `MultiStepUtilityScenario` HTTP-POST step(s).

**Why not `MetadataManagementScenario`:** it creates entities **by name**, so the target assigns fresh
GUIDs. Profisee **Connect** integration strategies bind to entities/attributes by **GUID**, so a
name-recreated model breaks the subsequent Connect data load. The importer must preserve the source GUIDs.

**Working precedent = the mechanism:** workflow `Connect 100K Template Full Workflow (COPY DO NOT UPDATE)`
(Code `10000150`) steps 10 & 11 — `MultiStepUtilityScenario` with one HTTP step each:
`POST {{$config:RestClients:Profisee:BaseUrl}}v1/Entities` (inline body = entity array with literal
`identifier.id` GUIDs) then `POST …v1/Attributes` (body via `bodyFilePath` because attributes are large).
So the Profisee metadata API honors caller-supplied GUIDs on create. The importer reproduces this shape.

**Discovery:** attribute JSON carries `domainEntityId.{id}` (Domain attrs, `attributeType:2`) → recurse to
build the entity closure; non-domain attrs have empty GUID `00000000-…`.

**Code:** `TestAuto.Web/Services/MetadataImport/` — `ModelDependencyGraph` (pure cascade/ref-counted
de-select), `ModelMetadataHarvester` (raw-JObject harvest via `EntityDataFacade`/raw GET +
`AttributeDataFacade`-shaped attrs), `ModelImportScenarioFactory` (builds `HttpRequestStep`s, inline body
with file fallback via `MetadataArtifactStorage` → `{{$config:DirectoryPaths:ScriptDirectory}}/JsonData/Metadata/…`,
single-combined-vs-separate toggle, target token + override), page `Components/Pages/Metadata/EntityModelImport`.
Persists standalone scenarios tagged `ModelImport,*` (added to a workflow via WorkflowBuilder, like ConnEx).
18 unit tests in `Testing.SpeedMerchants.Unit/Web/Services/MetadataImport/`.

**Enhancements shipped (2026-06-17):** page title "Import Entity"; tag renamed `ModelImport`→`EntityImport`
(combined uses bare `EntityImport`, split `EntityImport,Entities`/`,Attributes`/`,DomainData`/`,DataStore`,
delete `EntityImport,Delete`); post-import opens the scenario in the `ScenarioEditorContent` dialog + Edit
per row. **(A) Reference data** (domain entities only): `GetEntityRecordsAsync` GET `v1/Records/{name}` →
`ProjectRecordsForCreate` (strip `$`-system) → POST `v1/Records/{name}` step (step-12 shape). **(B) Target
data store** toggle: curated provider dropdown (`TargetDataStoreProviders`, only SqlServer implemented),
destination connection-**secret** dropdown (SqlStep uses `SqlDestinationConnectionSecretName`, not a config
token), one `SqlStep` per entity DROP-if-exists+CREATE TABLE via `ITargetDataStoreScriptGenerator`/
`SqlServerDataStoreScriptGenerator` + `ProfiseeTypeToSqlMapper` (uses `AttributeDataType` enum). **(C) Delete
scenario** (separate, same combined/split): per-entity `DELETE v1/Entities/{name}` in `GetDeletionOrder()`
topological (referrer-first) order, 404 tolerated — workflow = delete→create. Repeated string literals are
constants in `MetadataImportConstants` (incl. nested `Json` field names). 36 unit tests.

**Global params (2026-06-18):** per-entity name + table-name params promoted to each scenario's
`CustomParms.GlobalParameters` (like ConnEx import), keyed by the **actual model entity name** — entity-name
key = the name verbatim (`RetailClient`, `Source System`), table-name key = `{Name} Table`; both seed to the
name, independent. `ModelGlobalParameters` builds them; the factory tokenizes `identifier.name` (entities),
`identifier.entityId.name` + `domainEntityId.name` (attributes) to `{{Name}}` (GUID ids preserved), and the
SQL table name to `{{Name Table}}`. Records URL stays Uri-encoded literal (token regex has no URL-encoding,
would break spaced domain names). Connection-secret picker is now Section→Item (SqlStep resolves
`ConnectionStrings:{item}`). SQL tables emit as a SEPARATE datastore scenario group (combined→1, split→per
entity), never mixed with the import.

**ConnEx parity (2026-06-17/18):** the Connect import pages got the same treatment — source REST picker
(`ConnExApiClient` builds a client from any `RestClients:<section>`), target token default/override, and an
auto-generated delete scenario (`ConnExScenarioFactory.CreateDeleteScenarioAsync`, gateway
`DELETE …?{Type}Uids={id}`, tag `ConnEx,Delete,{type}`). NOTE: ~28 pre-existing ConnEx unit tests are red
(stale test-vs-impl drift: `GetRelativePath` Scripts/ prefix, `ExportResource` artifact wrapping) — NOT from
these changes. Plans in Obsidian `99 Documentation/speed-merchants/planning/2026-06-1{7,8}-*.md`.

**Still deferred:** live-GET shape confirmation (does `GET v1/Entities` return all POST fields); confirming
the exact destination connection-secret section/item the page should list.
Design spec: `docs/superpowers/specs/2026-06-17-metadata-model-import-design.md`;
plan: Obsidian `99 Documentation/speed-merchants/planning/2026-06-17-metadata-model-import.md`.
Related: [[project_connect_import_sequence_race]], [[reference_scenariomgt_db]].
