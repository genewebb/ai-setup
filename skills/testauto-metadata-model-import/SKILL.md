---
name: testauto-metadata-model-import
description: >
  Metadata model-import-as-a-workflow-step subsystem. Use when working on the model import pipeline,
  harvesting a Profisee model's entities/attributes from a source REST instance, the dependency
  graph, mapping Profisee types to SQL DDL, generating CREATE/DROP/INSERT scripts, emitting the six
  independently-runnable model scenarios in dependency order, adding a model-import step, or the
  EntityModelImport Blazor page.
---

## When to Use

Load this skill when you are:
- Adding, fixing, or reviewing any file under `TestAuto.Web/Services/MetadataImport/`
- Working on `EntityModelImport.razor` or `EntityModelImport.razor.cs`
- Implementing a new `ITargetDataStoreScriptGenerator` (e.g. Snowflake, Oracle)
- Debugging why a model import scenario is too large / hitting the 4000-char limit
- Explaining how BFS closure selection or the create/delete dependency ordering works
- Cross-referencing with the workflow 10000150 (steps 10/11) precedent

> **Distinction**: This subsystem emits `MultiStepUtilityScenario` records that *recreate the model* (entities + attributes). It is **not** `MetadataManagementScenario` — that is a CRUD load-test scenario handled by [[testauto-metadata-scenario]]. Do not conflate the two.

---

## Overview

The pipeline is triggered from the `/metadata/entities` Blazor page. It:

1. **Harvests** entity + attribute JSON from a source Profisee REST instance (any configured `RestClients:<Section>` with BaseUrl + ApiKey), preserving original GUIDs.
2. **Builds a dependency graph** over the harvested entities; the user selects a subset via cascade-select / deselect.
3. **Maps Profisee attribute types to SQL** for optional target-data-store DDL generation.
4. **Emits up to SIX independently-runnable `MultiStepUtilityScenario` records** so a workflow can sequence them à la carte — split across two factory calls:
   - **Create side** (`CreateImportScenariosAsync`): `Create Entities` (POST Entities → Attributes), `Create Table DataStore` (CREATE TABLE), `Import Entity Reference Data` (POST v1/Records), `Import SQL Reference Data` (INSERT into the DBA/FK tables).
   - **Delete side** (`CreateDeleteScenariosAsync`): `Delete Entities` (DELETE), `Drop Table DataStore` (DROP TABLE).
   - **Ordering is directional**: creates run **dependencies-first** (domain/FK before primary); deletes run **referrers-first** (primary before domain/FK). The data-store and reference-data scenarios only appear when `CreateTargetDataStore` / `IncludeDomainData` are set. Reference-data scenarios emit **one step per domain entity even when the source has no records** — an empty `[]` POST body / a commented INSERT template — so they exist as fillable placeholders (they collapse to nothing only if the model has no domain entities at all).
5. **Persists** each scenario through `IScenarioConfigStore` — small configs are stored inline, large ones are transparently chunked across the `TestAutoScenarioConfiguration` entity (no disk offload; see [[testauto-scenario-config-store]]).

All steps use `{{$config:RestClients:Profisee:BaseUrl}}` / `{{$config:RestClients:Profisee:ApiKey}}` tokens by default (overridable per-run).

---

## 1 — Harvest: `IModelMetadataHarvester` / `ModelMetadataHarvester`

**File**: `TestAuto.Web/Services/MetadataImport/IModelMetadataHarvester.cs`, `ModelMetadataHarvester.cs`

### Interface

```csharp
public interface IModelMetadataHarvester
{
    Task<IReadOnlyList<EntityRef>> ListEntitiesAsync(string restClientSection, CancellationToken ct = default);
    Task<HarvestedModel> HarvestClosureAsync(string restClientSection, string primaryEntityId, CancellationToken ct = default);
    Task<JArray> GetEntityRecordsAsync(string restClientSection, string entityName, CancellationToken ct = default);
}

public readonly record struct EntityRef(string Id, string Name);
```

### How it works

`ModelMetadataHarvester` builds an `HttpClient` from `RestClients:<section>:BaseUrl` + `RestClients:<section>:ApiKey` (header `x-api-key`). The client is named `"metadata-source"`.

**`ListEntitiesAsync`** — GETs `v1/Entities`, unwraps the gateway `data` envelope, projects `(identifier.id, identifier.name)` ordered case-insensitively. Feeds the primary-entity picker.

**`HarvestClosureAsync`** — GETs `v1/Entities`, then runs `BuildClosureAsync` (static, testable) starting at `primaryEntityId`:
- BFS queue: each entity's `domainEntityId.id` attributes are extracted and enqueued.
- For each entity dequeued: fetches `v1/Entities/{name}/attributes`, records a `HarvestedEntity`.
- After BFS: entities referenced as a domain by any other harvested entity are flagged `IsDomain = true`.
- Returns `HarvestedModel` (dictionary keyed by GUID, case-insensitive).

**`GetEntityRecordsAsync`** — GETs `v1/Records/{entityName}`. Used by the page to fill `HarvestedEntity.RawRecords` before emitting domain-data steps.

**`ProjectRecordsForCreate`** (static, public) — projects raw GET records into the `POST v1/Records` create-shape. It drops, in order:
- `$`-prefixed system fields (`$RecordAvatar`, `$LastChgTypeID`, …),
- the gateway's **read-only/computed** fields (`MetadataImportConstants.Json.ReadOnlyRecordFields` — a case-insensitive `HashSet`: `internalId`, `id`, `validationStatusID`, `enterUserName`, `enterDTM`, `lastChgDTM`, `lastChgUserName`, `canUpdate`, `canDelete`) — echoing these back on create risks a 400,
- nested objects/arrays (domain references) **and JSON `null` values**.

Then keeps only records carrying a **non-empty code**. **Critical:** the gateway returns the key lowercase (`code`), so the code is detected **case-insensitively** — matching on the capitalized `"Code"` constant silently dropped every real record and produced an empty `[]` body that the gateway rejected with 400 (same bug class as the ConnEx vaultId / RefData-empty-body issues). Original property casing is preserved on output so the body matches the create wire shape. See [[external-json-case-insensitive-reads]].

> Separately, the harvester strips **audit/system "noise"** recursively at any depth before POST via `MetadataImportConstants.HarvestNoiseFields` (`auditInfo`, `internalId`, `isReferenceValid`) — the hand-coded working deploys omit these and the gateway does not want them on create.

**Static extraction helpers** (pure, unit-testable without HTTP):
- `BuildClosureAsync(primaryEntityId, entitiesById, attributesByEntityName)` — pure BFS closure builder.
- `ExtractDataArray(JToken?)` — unwraps `{ data: [...] }` or bare array.
- `ExtractEntityId(JObject)` — `identifier.id` falling back to top-level `id`.
- `ExtractEntityName(JObject)` — `identifier.name` falling back to top-level `name`.
- `ExtractDomainEntityIds(JArray)` — distinct non-empty, non-zero `domainEntityId.id` values across an attribute array.

### `HarvestedModel` / `HarvestedEntity`

**File**: `TestAuto.Web/Services/MetadataImport/HarvestedModel.cs`

```csharp
public sealed class HarvestedEntity
{
    public string Id { get; init; }
    public string Name { get; init; }
    public bool IsDomain { get; set; }          // set after BFS
    public JObject RawEntity { get; init; }
    public JArray RawAttributes { get; init; }
    public IReadOnlyList<string> DomainEntityIds { get; init; }
    public JArray RawRecords { get; set; }       // populated by page before emit, not during harvest
}

public sealed class HarvestedModel
{
    public Dictionary<string, HarvestedEntity> Entities { get; }   // keyed by GUID, OrdinalIgnoreCase
    public ModelDependencyGraph ToGraph() { ... }
}
```

`RawRecords` is **not** populated during harvest — the page calls `GetEntityRecordsAsync` for each selected domain entity and assigns `e.RawRecords` immediately before calling `CreateImportScenariosAsync`.

---

## 2 — Dependency Graph: `ModelDependencyGraph`

**File**: `TestAuto.Web/Services/MetadataImport/ModelDependencyGraph.cs`

No I/O — fully unit-testable. Manages selection state for the UI tree.

### Key members

| Member | Description |
|---|---|
| `AddEntity(key)` | Registers a node (idempotent). |
| `AddDependency(from, to)` | Adds directed edge `from → to` ("from has a Domain attribute pointing to to"). Self-edges are silently ignored. |
| `CascadeSelect(key)` | Adds key as a root; recomputes `Selected` as the transitive out-closure of all roots. |
| `Deselect(key)` | Removes root; recomputes — dependencies no longer reachable from any root are automatically dropped. |
| `Clear()` | Clears roots and selected set. |
| `Selected` | `IReadOnlyCollection<string>` — roots + their transitive dependencies. |
| `Roots` | `IReadOnlyCollection<string>` — what the user explicitly checked. |
| `Nodes` | All known entities. |
| `IsSelected(key)` | In the selected set (root or pulled-in). |
| `IsRoot(key)` | Explicitly checked. |
| `GetDeletionOrder()` | Selected entities ordered referrers-first (safe deletion — see below). |
| `GetCreationOrder()` | Selected entities ordered dependencies-first (safe creation). Exactly the reverse of `GetDeletionOrder()`. |
| `GetDependencies(key)` | Direct out-edges (the entities this key depends on). |

### Selection model

The `_selected` set is always the transitive out-closure of `_roots`, computed by an iterative DFS (`Recompute`). A domain entity is kept selected only while at least one still-checked root can reach it. There is no explicit reference counter — the closure recompute handles it.

### Deletion vs creation ordering

`GetDeletionOrder()` returns selected entities ordered so that **referrers come before their dependencies** (a referrer's attributes must be deleted before the domain entity can be deleted). Algorithm: DFS post-order over the selected sub-graph, then reversed. Cycle-safe via a visited set. Operates only on the current `_selected` set.

`GetCreationOrder()` is the **exact reverse** — **dependencies before referrers** — so a domain/FK entity (and its table) exists before the primary entity that points at it. Implemented as `GetDeletionOrder()` reversed (one traversal, two orderings). The factory feeds create-side scenarios the creation order and delete-side scenarios the deletion order.

---

## 3 — Type Mapping: `ProfiseeTypeToSqlMapper`

**File**: `TestAuto.Web/Services/MetadataImport/ProfiseeTypeToSqlMapper.cs`

Static class. Maps a raw attribute JSON object's `dataType` int (cast to `AttributeDataType` from `Profisee.Platform.Cdp.Contracts`) and `dataTypeInformation` int to a SQL Server column type string.

```csharp
public static string MapColumnType(JObject attribute)
```

| `AttributeDataType` | SQL type |
|---|---|
| `Number` | `DECIMAL(38, <scale>)` where scale = `dataTypeInformation` clamped to `[0, 18]` |
| `Date` | `DATE` |
| `DateTime` | `DATETIME2` |
| `Text` | `NVARCHAR(<len>)` where len = `dataTypeInformation` if > 0, else `MAX` |
| Any other (Link, NotSpecified, unknown) | `NVARCHAR(MAX)` |

Domain attributes are `Text`-typed in Profisee (they store the referenced record's Code), so they naturally fall through the `Text` branch.

---

## 4 — Target Data Store DDL

**Files**: `TestAuto.Web/Services/MetadataImport/TargetDataStore/`

### `ITargetDataStoreScriptGenerator`

```csharp
public interface ITargetDataStoreScriptGenerator
{
    string ProviderKey { get; }
    string GenerateCreateTableScript(HarvestedEntity entity, string schema, string tableName);
    string GenerateDropTableScript(HarvestedEntity entity, string schema, string tableName);
    string GenerateInsertScript(HarvestedEntity entity, string schema, string tableName, JArray records);
}
```

`tableName` may be a `{{token}}` (e.g. `{{RetailClient Table}}`) resolved at runtime by the MultiStep orchestrator. When `records` is empty, `GenerateInsertScript` returns a **commented, fillable placeholder** (never an empty string) — see the SQL Server implementation below — so the SQL reference-data scenario always has a per-table step.

### `SqlServerDataStoreScriptGenerator`

`ProviderKey = "SqlServer"`. All identifiers are bracket-escaped with `]` → `]]`.

- **`GenerateCreateTableScript`** — a `DROP IF EXISTS` block (shared `DropIfExists` helper) + CREATE TABLE: fixed `Code NVARCHAR(250) NOT NULL` and `Name NVARCHAR(250) NULL` key columns first, then one column per `RawAttributes` entry via `ProfiseeTypeToSqlMapper.MapColumnType`, skipping Code/Name duplicates.
- **`GenerateDropTableScript`** — just the shared `DropIfExists` block (standalone teardown for the `Drop Table DataStore` scenario; the create script still drops first for idempotency).
- **`GenerateInsertScript`** — `INSERT INTO [schema].[table] (cols) VALUES …`, columns ordered exactly like the create script (`OrderedColumnNames`), batched at `RowsPerInsert` (500) row constructors per statement (SQL Server's hard cap is 1000). Values are formatted as SQL literals by `FormatValue`: `NULL`, raw number/bool, ISO-8601 `N'…'` date, or quote-escaped `N'…'` string. **When `records` is empty it returns a commented, fillable placeholder** (`-- No source reference data … -- Populate later, e.g.: INSERT …`) — never an empty string — so the SQL reference-data scenario always has a per-table step.

### `TargetDataStoreProviders`

Registry of selectable providers. `Implemented = false` items appear in the UI dropdown but are disabled (`IsDisabled = !Implemented`).

| Key | DisplayName | Implemented |
|---|---|---|
| `SqlServer` | SQL Server | true |
| `Snowflake` | Snowflake | false |
| `Oracle` | Oracle | false |
| `PostgreSql` | PostgreSQL | false |

To add a new provider: flip `Implemented = true` and register a new `ITargetDataStoreScriptGenerator` implementation in DI. No other changes needed.

---

## 5 — Scenario Factory: `IModelImportScenarioFactory` / `ModelImportScenarioFactory`

**Files**: `TestAuto.Web/Services/MetadataImport/IModelImportScenarioFactory.cs`, `ModelImportScenarioFactory.cs`

### Interface

```csharp
public interface IModelImportScenarioFactory
{
    Task<ServiceResult<IReadOnlyList<string>>> CreateImportScenariosAsync(
        HarvestedModel model,
        IReadOnlyCollection<string> selectedEntityIds,
        string modelDisplayName,
        ModelImportOptions options,
        CancellationToken ct = default);

    Task<ServiceResult<IReadOnlyList<string>>> CreateDeleteScenariosAsync(
        HarvestedModel model,
        IReadOnlyCollection<string> selectedEntityIds,
        string modelDisplayName,
        ModelImportOptions options,
        CancellationToken ct = default);
}
```

Returns scenario `Code` strings (the Profisee record Code, a new GUID per scenario). `CreateImportScenariosAsync` returns the create-side codes; `CreateDeleteScenariosAsync` the delete-side codes. The UI calls both.

### `ModelImportOptions`

```csharp
public sealed record ModelImportOptions
{
    public bool IncludeDomainData { get; init; }                 // emit Entity + SQL reference-data scenarios
    public bool CreateTargetDataStore { get; init; }             // emit Create/Drop Table + SQL reference-data scenarios
    public string? TargetDataStoreProviderKey { get; init; }     // default "SqlServer"
    public string? DestinationConnectionSecretName { get; init; }// required if CreateTargetDataStore
    public string SqlSchema { get; init; } = "dbo";
    public string? TargetBaseUrlToken { get; init; }             // overrides default Profisee token
    public string? TargetApiKeyToken { get; init; }
}
```

> There is **no `SingleCombinedScenario` / per-step split anymore** — entities and attributes are always one scenario. The six scenarios *are* the split, so a workflow can run any of them independently.

### Emit flow — Create side (`CreateImportScenariosAsync`)

1. **Validate closure** — every selected entity's domain dependencies must also be selected (throws `InvalidOperationException` otherwise).
2. **Resolve data store** (`ResolveDataStore`) — if `CreateTargetDataStore`, look up the `ITargetDataStoreScriptGenerator` by `TargetDataStoreProviderKey`; fail fast if not implemented or connection secret missing. `(null, null)` when no data store requested.
3. **Build GlobalParameters** — via `ModelGlobalParameters.Build`, one entity-name param + one table-name param per entity (see §6).
4. **Compute `CreationOrder`** — cascade-select all ids, `GetCreationOrder()` (dependencies-first). Every create-side scenario iterates this order.
5. **Emit scenarios** (each via `EmitOneAsync`, which **skips silently only when there are zero steps**):
   - **`Create Entities: {name}`** — `BuildEntityCreateSteps` (POST v1/Entities then v1/Attributes). Tag `EntityImport,Create`. Always emitted.
   - **`Create Table DataStore: {name}`** — `BuildSqlCreateSteps` (one CREATE TABLE per entity). Tag `EntityImport,DataStore`. Only when a data store is configured.
   - **`Import Entity Reference Data: {name}`** — `BuildRecordSteps` (one POST v1/Records per **domain** entity; empty `[]` body when no records). Tag `EntityImport,DomainData`. Only when `IncludeDomainData`. Emitted as long as the model has at least one domain entity (placeholders for empty ones).
   - **`Import SQL Reference Data: {name}`** — `BuildSqlInsertSteps` (one INSERT per **domain** entity; commented placeholder when no records). Tag `EntityImport,DataStore,DomainData`. Only when both `CreateTargetDataStore` **and** `IncludeDomainData`.

### Emit flow — Delete side (`CreateDeleteScenariosAsync`)

1. Resolve data store (same as create). Compute `DeletionOrder` (`GetDeletionOrder()`, referrers-first).
2. **`Delete Entities: {name}`** — one `DELETE v1/Entities/{name}` step per entity, referrers-first. Expected status codes `[200, 201, 204, 404]` (404 tolerated). Tag `EntityImport,Delete`. Always emitted.
3. **`Drop Table DataStore: {name}`** — `BuildSqlDropSteps` (one DROP TABLE per entity, referrers-first). Tag `EntityImport,DataStore,Delete`. Only when a data store is configured.

### Persistence and the 4000-char limit (`EmitOneAsync`)

There is **no disk offload anymore** — the old `SizeAsync` / `IMetadataArtifactStorage` / `BodyFilePath` mechanism is retired. `EmitOneAsync` builds the `ScenarioConfiguration` and persists it through the chunk store:

```csharp
var config = BuildConfig(steps, globalParameters);
var code = Guid.NewGuid().ToString();
var stored = await _store.PersistAsync(config, ConfigOwnerType.Scenario, code, ct);
// ScenarioDataDisplay is a preview attribute capped at 4000 chars; truncate the resolved
// config so a large (chunked) model-import config doesn't overflow it (Profisee 8610).
var resolvedJson = await _store.ResolveRawAsync(stored, ct) ?? string.Empty;
var displayJson = resolvedJson.Length > 4000 ? resolvedJson[..4000] : resolvedJson;
```

`PersistAsync` returns inline JSON when small or a `CHUNKREF:` sentinel when large — the oversize case is handled transparently by chunking, so step bodies (HTTP `Body`, SQL scripts) all stay inline regardless of size. Step content is always inline now (see [[testauto-multistep-steps]]). The `ScenarioDataDisplay` preview is the only thing truncated to 4000.

`ModelImportScenarioFactory` takes `IScenarioConfigStore _store` as a constructor dependency (replacing the former artifact-storage dependency). See [[testauto-scenario-config-store]] for the store mechanics.

### Static pure builders (unit-testable)

| Method | Description |
|---|---|
| `BuildEntitiesArray(model, selectedIds)` | Deep-clones `RawEntity` per entity; replaces `identifier.name` with `{{EntityName}}` token. GUIDs preserved. |
| `BuildAttributesArray(model, selectedIds)` | Deep-clones each attribute; tokenizes `identifier.entityId.name` (owner entity) and `domainEntityId.name` (domain reference, only if in selected set). |
| `BuildEntityCreateSteps(model, orderedIds, options)` | The two `Create Entities` HTTP steps (POST Entities then Attributes). |
| `BuildRecordSteps(model, orderedIds, options)` | One `POST v1/Records` step per **domain** entity (empty `[]` body when `RawRecords` is null/empty — a fillable placeholder). |
| `BuildSqlCreateSteps(model, orderedIds, generator, schema, conn)` | One CREATE TABLE `SqlStep` per entity. |
| `BuildSqlDropSteps(model, orderedIds, generator, schema, conn)` | One DROP TABLE `SqlStep` per entity. |
| `BuildSqlInsertSteps(model, orderedIds, generator, schema, conn)` | One INSERT `SqlStep` per **domain** entity (commented placeholder when no records). |

All `SqlStep`s use `UseTransaction = true`, timeout 120 s. The callers pass `CreationOrder` (create side) or `DeletionOrder` (delete side); the builders just iterate the order given.

---

## 6 — Constants & Global Parameters

### `MetadataImportConstants`

**File**: `TestAuto.Web/Services/MetadataImport/MetadataImportConstants.cs` (internal)

| Constant | Value |
|---|---|
| `EntitiesEndpoint` | `"v1/Entities"` |
| `AttributesEndpoint` | `"v1/Attributes"` |
| `RecordsEndpoint` | `"v1/Records"` |
| `DefaultTargetBaseUrlToken` | `"{{$config:RestClients:Profisee:BaseUrl}}"` |
| `DefaultTargetApiKeyToken` | `"{{$config:RestClients:Profisee:ApiKey}}"` |
| `RestClientsConfigRoot` | `"RestClients"` |
| `MaxCompressedScenarioChars` | `4000` |
| `DefaultSqlSchema` | `"dbo"` |
| `EmptyGuid` | `"00000000-0000-0000-0000-000000000000"` |
| `ApiKeyHeader` | `"x-api-key"` |
| `ScenarioNameMultiStep` | `"MultiStepUtilityScenario"` |
| `HarvestNoiseFields` | `string[]` { `auditInfo`, `internalId`, `isReferenceValid` } — stripped recursively at any depth before POST |
| `Json.ReadOnlyRecordFields` | case-insensitive `HashSet` { `internalId`, `id`, `validationStatusID`, `enterUserName`, `enterDTM`, `lastChgDTM`, `lastChgUserName`, `canUpdate`, `canDelete` } — read-only fields excluded on record create |
| `Tag` | `"EntityImport"` (base — every scenario's tag contains it; the UI filters on it) |
| `TagCreate` | `"EntityImport,Create"` (Create Entities) |
| `TagDelete` | `"EntityImport,Delete"` (Delete Entities) |
| `TagDataStore` | `"EntityImport,DataStore"` (Create Table DataStore) |
| `TagDataStoreDelete` | `"EntityImport,DataStore,Delete"` (Drop Table DataStore) |
| `TagDomainData` | `"EntityImport,DomainData"` (Import Entity Reference Data) |
| `TagDataStoreData` | `"EntityImport,DataStore,DomainData"` (Import SQL Reference Data) |
| `TagEntities` / `TagAttributes` | `"EntityImport,Entities"` / `"EntityImport,Attributes"` (legacy split tags, no longer emitted) |
| `DomainAttributeType` | `2` (int, unused in mapper — mapper uses `AttributeDataType` enum cast) |

### `ModelGlobalParameters`

**File**: `TestAuto.Web/Services/MetadataImport/ModelGlobalParameters.cs`

Promotes per-entity editable params to `CustomParms.GlobalParameters` (same pattern as Connect import). Two params per entity:

| Param key | Default value | Token form |
|---|---|---|
| `{EntityName}` (the entity name itself) | Entity's current name | `{{RetailClient}}` |
| `{EntityName} Table` | Entity's current name | `{{RetailClient Table}}` |

Steps reference these as `{{RetailClient}}` and `{{RetailClient Table}}` — the MultiStep orchestrator resolves them at runtime. The token regex supports spaces in key names.

```csharp
public static string EntityNameKey(string entityName)   => entityName;
public static string TableNameKey(string entityName)    => $"{entityName} Table";
public static string Token(string key)                  => "{{" + key + "}}";
public static string EntityNameToken(string entityName) => Token(EntityNameKey(entityName));
public static string TableNameToken(string entityName)  => Token(TableNameKey(entityName));
public static JObject Build(HarvestedModel model, IEnumerable<string> selectedIds)
```

---

## 7 — UI: `EntityModelImport.razor` / `.razor.cs`

**Route**: `/metadata/entities`

### Injected services

| Property | Type |
|---|---|
| `Configuration` | `IConfiguration` |
| `Harvester` | `IModelMetadataHarvester` |
| `ScenarioFactory` | `IModelImportScenarioFactory` |
| `ScenarioService` | `IScenarioService` |
| `SecretCatalog` | `ISecretCatalog` |
| `NotificationService` | Radzen `NotificationService` |
| `DialogService` | Radzen `DialogService` |
| `Logger` | `Serilog.ILogger` |

### User flow

1. **OnInitializedAsync** — populates `SourceSections` from `RestClients:*` children that have a `BaseUrl`; populates `ConnectionSections` from `ISecretCatalog`; loads existing `EntityImport`-tagged scenarios.
2. **Source changed** (`OnSourceChanged`) — calls `Harvester.ListEntitiesAsync` to fill the primary-entity picker.
3. **Discover** (`DiscoverAsync`) — calls `Harvester.HarvestClosureAsync`; builds `ModelDependencyGraph` via `model.ToGraph()`; builds `TreeRows` (DFS-indented, visited-guarded); auto-selects the primary entity via `Graph.CascadeSelect`.
4. **Node toggle** (`OnNodeToggled`) — delegates to `Graph.CascadeSelect` or `Graph.Deselect`.
5. **Import** (`ImportAsync`):
   - If `IncludeDomainData`: calls `GetEntityRecordsAsync` for each selected domain entity, assigns `e.RawRecords`.
   - Calls `ScenarioFactory.CreateImportScenariosAsync` then `CreateDeleteScenariosAsync`.
   - On success: shows notification, reloads list, opens first import scenario in `ScenarioEditorContent` dialog.
6. **Existing imports** — paged load (page size 50) of all scenarios; client-side filtered to those whose `Tags` attribute contains `"EntityImport"`.

### `TreeRow` record

```csharp
protected sealed record TreeRow(string Id, string Name, int Depth, bool IsDomain);
```

Rendered as indented rows with `margin-left: {Depth * 1.5}rem`. Domain entities show a light `"domain"` badge. The checkbox binds to `Graph.IsSelected(row.Id)`.

---

## Cross-links

- [[testauto-metadata-scenario]] — MetadataManagementScenario (CRUD load tests, different subsystem)
- [[testauto-multistep-steps]] — MultiStepUtilityScenario step types (HttpRequestStep, SqlStep, etc.)
- [[testauto-scenario-config-store]] — `IScenarioConfigStore` chunked persistence (replaces the retired artifact-storage offload)
- [[configuration-compression-codec]] — legacy BROTLI/GZIP codec, still read on legacy values

---

## Sources

| File | Purpose |
|---|---|
| `TestAuto.Web/Services/MetadataImport/IModelMetadataHarvester.cs` | Harvester interface + `EntityRef` |
| `TestAuto.Web/Services/MetadataImport/ModelMetadataHarvester.cs` | Harvester implementation + static helpers |
| `TestAuto.Web/Services/MetadataImport/HarvestedModel.cs` | `HarvestedModel`, `HarvestedEntity` |
| `TestAuto.Web/Services/MetadataImport/ModelDependencyGraph.cs` | Cascade-select / deletion-order graph |
| `TestAuto.Web/Services/MetadataImport/ProfiseeTypeToSqlMapper.cs` | Profisee → SQL type mapping |
| `TestAuto.Web/Services/MetadataImport/TargetDataStore/ITargetDataStoreScriptGenerator.cs` | DDL generator interface |
| `TestAuto.Web/Services/MetadataImport/TargetDataStore/SqlServerDataStoreScriptGenerator.cs` | SQL Server DDL generator |
| `TestAuto.Web/Services/MetadataImport/TargetDataStore/TargetDataStoreProviders.cs` | Provider registry |
| `TestAuto.Web/Services/MetadataImport/IModelImportScenarioFactory.cs` | Factory interface + `ModelImportOptions` |
| `TestAuto.Web/Services/MetadataImport/ModelImportScenarioFactory.cs` | Factory implementation (persists via `IScenarioConfigStore`) |
| `TestAuto.Web/Services/MetadataImport/MetadataImportConstants.cs` | All constants (internal) |
| `TestAuto.Web/Services/MetadataImport/ModelGlobalParameters.cs` | GlobalParameters token builders |
| `TestAuto.Web/Components/Pages/Metadata/EntityModelImport.razor` | UI markup |
| `TestAuto.Web/Components/Pages/Metadata/EntityModelImport.razor.cs` | UI code-behind |
