---
name: testauto-connex-provider-templates
description: >
  ConnEx artifact template library for TestAuto. Use when configuring ConnEx
  Import/Export steps in MultiStepUtilityScenario, looking up token names for
  a provider (SqlServer, Databricks, Snowflake, Synapse, OneLake, Profisee,
  File), understanding artifact vs record format, following the three-resource
  ordering rule, or adding a new provider template.
---

Repo: speed-merchants (paths below are repo-relative)

# ConnEx Artifact Template Library

> **Scope**: speed-merchants (TestAuto.Utilities/Scripts/ConnEx/)
> **Source**: `TestAuto.Utilities/Scripts/ConnEx/README.md` + provider READMEs

Pre-built tokenized JSON templates for importing ConnEx resources via `ConnExStep` in `MultiStepUtilityScenario`. Each template uses `{{token}}` placeholders resolved at runtime by `ConnExExecutor`.

---

## ⚠️ Step JSON is FLAT — there is no nested `ConnExStep` object

`ConnExStep` is a plain `UtilityStepBase` subclass (`TestAuto.Utilities/Common/DTOs/ConnExStep.cs`); every property carries a camelCase `[JsonProperty]` **directly on the step object**. Wrapping the properties in a `"ConnExStep": { ... }` sub-object silently produces a step with all-default values (`operation` defaults to `"Import"` with no artifact → the executor rejects it).

```json
// ✅ CORRECT — flat
{ "Type": "ConnEx", "Operation": "Import", "ArtifactFile": "..." }

// ❌ WRONG — no such nesting exists
{ "Type": "ConnEx", "ConnExStep": { "Operation": "Import", "ArtifactFile": "..." } }
```

Confirmed by the shipped samples (`TestAuto.Utilities/Samples/ConnEx_*_SampleConfig.json`) and by `ConnExScenarioFactory.BuildConfig` (`TestAuto.Web/Services/ConnExScenarioFactory.cs:308-330`), which stores steps as `JArray.FromObject(steps)` — a flat serialization of the DTO — into `CustomParms["Steps"]`.

Property names are matched case-insensitively by Newtonsoft, so `"Operation"` and `"operation"` both bind.

---

## Artifact Format vs Record Format

ConnEx test resources use **record format**. The REST gateway import endpoint requires **artifact format** — a different wrapper structure. The templates in this library are already in artifact format.

```
Record format (ConnEx tests):        Artifact format (REST gateway import):
{                                    {
  "Configuration": { ... },            "$type": "...Artifact, ...",
  "Id": "...",                         "artifactVersion": "1.7.1.0",
  "Name": "...",                       "integrationStrategyRecord": {
  "Type": "Database"                     "$type": "...Record, ...",
}                                        "Configuration": {
                                           "$type": "...Configuration, ...",
                                           ...
                                         },
                                         "Id": "...",
                                         "Name": "...",
                                         "Type": "Database"
                                       }
                                     }
```

The `$type` annotations enable Newtonsoft `TypeNameHandling.All` deserialization on the server. **Never use record format with the import endpoint** — it returns a 400/422.

---

## Three-Resource Ordering Rule

Always import in this order — each resource depends on the prior:

| Order | Resource Type | Purpose | Root JSON Key |
|-------|--------------|---------|---------------|
| 1 | **ServiceProvider** | Registers the provider type (SqlServer, Databricks, etc.) | *(none in the shipped templates — see below)* |
| 2 | **ServiceConfiguration** | Connection credentials for a specific server/database | `serviceConfigurationRecord` |
| 3 | **IntegrationStrategy** | Data flow definition (import/export); references ServiceConfig | `integrationStrategyRecord` |

ServiceProvider import is **idempotent** — re-importing an existing provider is safe. ServiceProvider files have **no tokens**.

> ⚠️ **ServiceProvider steps need an explicit `ResourceType`.** `ConnExExecutor.DetectResourceType` (`ConnExExecutor.cs:676-693`) auto-detects only by matching a **root property name** against `ConnExConstants.RecordKeyToResourceType` (`serviceConfigurationRecord`, `integrationStrategyRecord`, `ServiceProviderRecord`/`serviceProviderRecord`). The shipped ServiceProvider templates (e.g. `SqlServer/ServiceProviders/SqlServer.ServiceProvider.json`) are a bare `ServiceProviderConfigurationRecord` — `$type`, `Id`, `Code`, `Name`, `ConfigurationSource` at the root, with **no `serviceProviderRecord` wrapper**. Detection therefore returns `null` and the step fails with "Cannot determine resource type" (`ConnExExecutor.cs:292`) unless you set `"ResourceType": "ServiceProvider"`. ServiceConfiguration and IntegrationStrategy templates *do* carry their record root key and auto-detect fine.

---

## Directory Structure

Every provider folder also carries its own `README.md` documenting that provider's tokens.

```
TestAuto.Utilities/Scripts/ConnEx/
  README.md
  ServiceConfigurations/            <-- LEGACY, non-provider; predates the template library.
    CORPLTR94_ModelSource.json          MIXED format, MACHINE-SPECIFIC, NOT tokenized.
    ModelSource.json                    Do not treat as templates.
    RetailClient120MServiceConfig.json
    Service_Configuration_for_SMVMDB3_ModelSource.json   (the one flat/record-format file)
  IntegrationStrategies/            <-- LEGACY, non-provider; same caveats.
    CORPLTR94_Import_ModelSource1K.json
    RetailClient120MStrategy.json
    RetailClient5K.json
    SMVM3_LoadRetailClient_5K.json                       (the one flat/record-format file)
  SqlServer/                        <-- each provider folder below also has a README.md
    ServiceProviders/SqlServer.ServiceProvider.json
    ServiceConfigurations/
      SqlServer.SqlLogon.ServiceConfig.json
      SqlServer.EntraServicePrincipal.ServiceConfig.json
    IntegrationStrategies/
      SqlServer.Import.Strategy.json
      SqlServer.Export.Strategy.json
  Databricks/
    ServiceProviders/Databricks.ServiceProvider.json
    ServiceConfigurations/
      Databricks.ApiKey.ServiceConfig.json
      Databricks.OAuth2.ServiceConfig.json
    IntegrationStrategies/
      Databricks.Import.Strategy.json
      Databricks.Export.Strategy.json
  Snowflake/
    ServiceProviders/Snowflake.ServiceProvider.json
    ServiceConfigurations/
      Snowflake.BasicAuth.ServiceConfig.json
      Snowflake.KeyPairAuth.ServiceConfig.json
    IntegrationStrategies/
      Snowflake.Import.Strategy.json
      Snowflake.Export.Strategy.json
  Synapse/
    ServiceProviders/Synapse.ServiceProvider.json
    ServiceConfigurations/Synapse.SqlLogon.ServiceConfig.json
    IntegrationStrategies/
      Synapse.Import.Strategy.json
      Synapse.Export.Strategy.json
  OneLake/
    ServiceProviders/OneLake.ServiceProvider.json
    ServiceConfigurations/OneLake.ServiceConfig.json
    IntegrationStrategies/
      OneLake.Import.Strategy.json
      OneLake.Export.Strategy.json
  Profisee/
    ServiceProviders/Profisee.ServiceProvider.json
    ServiceConfigurations/Profisee.ApiKey.ServiceConfig.json
    IntegrationStrategies/
      Profisee.Import.Strategy.json
      Profisee.Export.Strategy.json
  File/
    ServiceProviders/
      NtfsFileExchange.ServiceProvider.json
      AzureDataLake.ServiceProvider.json
    ServiceConfigurations/
      NtfsFileExchange.ServiceConfig.json
      AzureDataLake.ApiKey.ServiceConfig.json
      AzureDataLake.EntraServicePrincipal.ServiceConfig.json
    IntegrationStrategies/
      NtfsFileExchange.Import.Strategy.json
      NtfsFileExchange.Export.Strategy.json
      Excel.Import.Strategy.json
      Parquet.Import.Strategy.json
```

**Naming convention**: `{Provider}.{AuthScheme|Flow}.{ResourceType}.json`

---

## Provider Token Tables

### SqlServer

**SqlServer.SqlLogon.ServiceConfig.json**

| Token | Description | Example |
|-------|-------------|---------|
| `{{DbServer}}` | Server hostname | `corpsql03.corp.profisee.com` |
| `{{DbUsername}}` | SQL login username | `sa` |
| `{{DbPassword}}` | SQL login password | `secret123` |
| `{{DatabaseName}}` | Database name | `TestDB` |
| `{{ServiceConfigId}}` | GUID | `11111111-1111-1111-1111-111111111111` |
| `{{ServiceConfigName}}` | Display name | `SqlServer Prod Config` |

**SqlServer.EntraServicePrincipal.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{DbServer}}` | Server hostname |
| `{{DatabaseName}}` | Database name |
| `{{DbClientId}}` | Entra app client ID |
| `{{DbClientSecret}}` | Entra app client secret |
| `{{DbTenantId}}` | Entra tenant ID |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

**SqlServer.Import/Export.Strategy.json** (scenario-level only)

| Token | Description |
|-------|-------------|
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Parent config reference |
| `{{StrategyId}}`, `{{StrategyName}}` | Strategy identity |
| `{{EntityId}}`, `{{EntityName}}` | Profisee entity |
| `{{RemoteSchema}}` | e.g., `dbo` |
| `{{RemoteObjectName}}` | Source/target table or view name |
| `{{RunAsUser}}` | Impersonation identity |
| `{{MaxRecordsPerJob}}` | Integer, **no quotes in JSON** |

---

### Databricks

**Databricks.ApiKey.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{DatabricksServer}}` | Workspace hostname |
| `{{DatabricksApiKey}}` | Personal access token |
| `{{DatabricksWarehouseId}}` | SQL warehouse ID |
| `{{DatabricksDatabase}}` | Database/schema name |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

**Databricks.OAuth2.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{DatabricksServer}}` | Workspace hostname |
| `{{DatabricksClientId}}` | OAuth2 client ID |
| `{{DatabricksClientSecret}}` | OAuth2 client secret |
| `{{DatabricksWarehouseId}}` | SQL warehouse ID |
| `{{DatabricksDatabase}}` | Database/schema name |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

Strategy tokens: same as SqlServer (ServiceConfigId/Name, StrategyId/Name, EntityId/Name, RemoteSchema, RemoteObjectName, RunAsUser, MaxRecordsPerJob).

---

### Snowflake

**Snowflake.BasicAuth.ServiceConfig.json**

| Token | Description | Example |
|-------|-------------|---------|
| `{{SnowflakeAccount}}` | Account identifier | `xy12345.east-us-2.azure` |
| `{{SnowflakeServer}}` | Server URL | `xy12345.east-us-2.azure.snowflakecomputing.com` |
| `{{SnowflakeUser}}` | Username | `SVC_PROFISEE` |
| `{{SnowflakePassword}}` | Password | `secret123` |
| `{{SnowflakeDatabase}}` | Database name | `PROFISEE_DB` |
| `{{SnowflakeWarehouse}}` | Warehouse name | `COMPUTE_WH` |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity | |

**Snowflake.KeyPairAuth.ServiceConfig.json** — replaces `{{SnowflakePassword}}` with:

| Token | Description |
|-------|-------------|
| `{{SnowflakePrivateKey}}` | PEM-encoded private key |
| `{{SnowflakePrivateKeyPassword}}` | Key passphrase |

---

### Synapse

**Synapse.SqlLogon.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{SynapseServer}}` | Dedicated SQL pool endpoint |
| `{{SynapseDatabase}}` | Database name |
| `{{SynapseUsername}}` | SQL login |
| `{{SynapsePassword}}` | SQL password |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

Strategy tokens: same standard set (StrategyId/Name, EntityId/Name, RemoteSchema, RemoteObjectName, RunAsUser, MaxRecordsPerJob).

---

### OneLake

**OneLake.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{OneLakeServer}}` | OneLake workspace endpoint |
| `{{OneLakeDatabase}}` | Lakehouse name |
| `{{OneLakeClientId}}` | Entra app client ID |
| `{{OneLakeClientSecret}}` | Entra app client secret |
| `{{OneLakeTenantId}}` | Entra tenant ID |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

---

### Profisee

**Profisee.ApiKey.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{ProfiseeBaseUrl}}` | Instance base URL |
| `{{ProfiseeApiKey}}` | API key |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

---

### File (NTFS and Azure Data Lake)

**NtfsFileExchange.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{FileRepositoryFolder}}` | UNC or local folder path |
| `{{FileRepositoryUsername}}` | Network share username |
| `{{FileRepositoryPassword}}` | Network share password |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

**AzureDataLake.ApiKey.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{AdlsFolderPath}}` | Container/folder path |
| `{{AdlsApiKey}}` | Storage account key |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

**AzureDataLake.EntraServicePrincipal.ServiceConfig.json**

| Token | Description |
|-------|-------------|
| `{{AdlsFolderPath}}` | Container/folder path |
| `{{AdlsClientId}}` | Entra app client ID |
| `{{AdlsClientSecret}}` | Entra app client secret |
| `{{AdlsTenantId}}` | Entra tenant ID |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}` | Identity |

**File strategy tokens** (NTFS/Excel/Parquet)

| Token | Description |
|-------|-------------|
| `{{FileType}}` | `Csv`, `Excel`, `Parquet`, `Json` |
| `{{FileNamingPattern}}` | e.g., `Product_*.csv` |
| `{{ServiceConfigId}}`, `{{ServiceConfigName}}`, `{{StrategyId}}`, `{{StrategyName}}`, `{{EntityId}}`, `{{EntityName}}`, `{{RunAsUser}}`, `{{MaxRecordsPerJob}}` | Standard set |

---

## Full Example: Three-Step SqlServer Import

```json
{
  "Steps": [
    {
      "Type": "ConnEx",
      "Description": "Import SqlServer ServiceProvider",
      "Operation": "Import",
      "ResourceType": "ServiceProvider",
      "ArtifactFile": "Scripts/ConnEx/SqlServer/ServiceProviders/SqlServer.ServiceProvider.json"
    },
    {
      "Type": "ConnEx",
      "Description": "Import SqlServer ServiceConfig",
      "Operation": "Import",
      "ArtifactFile": "Scripts/ConnEx/SqlServer/ServiceConfigurations/SqlServer.SqlLogon.ServiceConfig.json",
      "Parameters": {
        "DbServer": "corpsql03.company.com",
        "DbUsername": "sa",
        "DbPassword": "secret123",
        "DatabaseName": "TestDB",
        "ServiceConfigId": "11111111-1111-1111-1111-111111111111",
        "ServiceConfigName": "SqlServer TestDB Config"
      }
    },
    {
      "Type": "ConnEx",
      "Description": "Import SqlServer Import Strategy",
      "Operation": "Import",
      "ArtifactFile": "Scripts/ConnEx/SqlServer/IntegrationStrategies/SqlServer.Import.Strategy.json",
      "Parameters": {
        "ServiceConfigId": "11111111-1111-1111-1111-111111111111",
        "ServiceConfigName": "SqlServer TestDB Config",
        "StrategyId": "22222222-2222-2222-2222-222222222222",
        "StrategyName": "SqlServer Import Product",
        "EntityId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "EntityName": "Product",
        "RemoteSchema": "dbo",
        "RemoteObjectName": "Product_Import",
        "RunAsUser": "admin@company.com",
        "MaxRecordsPerJob": "100000"
      }
    }
  ]
}
```

> The ServiceProvider step above sets `ResourceType` **explicitly** — see the auto-detection note under [Three-Resource Ordering Rule](#three-resource-ordering-rule).

> `MaxRecordsPerJob` is an integer field inside the JSON template — pass it as a string in `Parameters` without JSON quotes around the value, or the template substitution will embed it quoted.

---

## Export and Delete

**Export** an existing resource by GUID:

```json
{
  "Type": "ConnEx",
  "Operation": "Export",
  "ResourceType": "ServiceConfiguration",
  "ResourceId": "11111111-1111-1111-1111-111111111111",
  "OutputFile": "Scripts/ConnEx/exports/SqlServer.TestDB.ServiceConfig.json"
}
```

**Delete** a resource by GUID:

```json
{
  "Type": "ConnEx",
  "Operation": "Delete",
  "ResourceType": "ServiceConfiguration",
  "ResourceId": "11111111-1111-1111-1111-111111111111",
  "ExpectedStatusCodes": [200, 204]
}
```

---

## Strategy Mapping Workflow

IntegrationStrategy templates have **empty `mappings` blocks**. Mappings contain entity-specific attribute GUIDs and must be populated per entity:

1. Import the strategy template with empty mappings
2. Configure mappings in the Profisee UI
3. Export the configured strategy with `Operation: "Export"` + the strategy's GUID
4. Copy the `mappings` section from the exported JSON into your template or use `ArtifactJson` inline

Alternatively, pass a pre-populated `ArtifactJson` string directly in the step if the mapping structure is known.

---

## DryRun Validation

`DryRun: true` validates file resolution, JSON parsing, token replacement, resource type auto-detection, and endpoint URL construction — **without** calling the HTTP API.

```json
{
  "Type": "ConnEx",
  "Operation": "Import",
  "DryRun": true,
  "ArtifactFile": "Scripts/ConnEx/SqlServer/ServiceConfigurations/SqlServer.SqlLogon.ServiceConfig.json",
  "Parameters": { "DbServer": "...", "ServiceConfigId": "...", "ServiceConfigName": "..." }
}
```

DryRun output reports resolved tokens, unresolved tokens, endpoint URL, and resource type. Use before the first real run.

---

## Adding a New Provider

1. Create `Scripts/ConnEx/{Provider}/` with `ServiceProviders/`, `ServiceConfigurations/`, `IntegrationStrategies/` subdirectories
2. Copy the nearest existing template; update:
   - `$type` on the `Configuration` object (`DatabaseServiceConfiguration` vs `FileServiceConfiguration`)
   - `databaseType` or `fileProviderType` value
   - Auth-specific settings in the `settings` block
   - `{{token}}` names
3. Add `README.md` documenting tokens
4. Follow naming convention: `{Provider}.{AuthScheme|Flow}.{ResourceType}.json`
5. **No csproj change is needed.** `TestAuto.Utilities.csproj` already copies the whole tree with a single wildcard `None Update` rule (`TestAuto.Utilities.csproj:22-26`), so any new file under `Scripts\` ships automatically:
   ```xml
   <!-- Automatically copy ANY scripts under Scripts\ (all subfolders) -->
   <ItemGroup>
     <None Update="Scripts\**\*">
       <CopyToOutputDirectory>Always</CopyToOutputDirectory>
       <CopyToPublishDirectory>Always</CopyToPublishDirectory>
     </None>
   ```
   Note it is `None Update` (not `Content Include`) and the mode is **`Always`**, not `PreserveNewest`. Do **not** add a second `Content Include` rule for `Scripts\ConnEx\**\*.json` — that duplicates the item and produces MSBuild NETSDK1022 "duplicate items" errors. You still must rebuild for the file to land in `Plugins/` on the hosts (see [[testauto-utilities-module]]).

---

## Sources

- `TestAuto.Utilities\Scripts\ConnEx\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\SqlServer\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\Snowflake\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\Databricks\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\OneLake\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\Profisee\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\Synapse\README.md`
- `TestAuto.Utilities\Scripts\ConnEx\File\README.md`
- `TestAuto.Utilities\Common\DTOs\ConnExStep.cs` — flat DTO; proof there is no nested `ConnExStep` object
- `TestAuto.Utilities\Samples\ConnEx_ImportServiceConfiguration_SampleConfig.json` (and sibling `ConnEx_*_SampleConfig.json`) — canonical flat step JSON
- `TestAuto.Web\Services\ConnExScenarioFactory.cs` — `BuildConfig` stores `JArray.FromObject(steps)` into `CustomParms["Steps"]`
- `TestAuto.Utilities\Executors\ConnExExecutor.cs` — `DetectResourceType` root-key auto-detection
- `TestAuto.Utilities\Common\ConnExConstants.cs` — `RecordKeyToResourceType`
- `TestAuto.Utilities\TestAuto.Utilities.csproj` — the single `None Update="Scripts\**\*"` copy rule
