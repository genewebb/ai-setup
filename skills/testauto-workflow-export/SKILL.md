---
name: testauto-workflow-export
description: >
  Workflow export pipeline for TestAuto scenarios. Use when exporting a workflow,
  working with WorkflowExportService or WorkflowExportDialog, choosing between
  files-vs-scenarios export modes, understanding workflow export file naming, or
  exporting workflow scenarios as TestAutoScenarios records.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Workflow Export

> **UI terminology (2026-07)**: the web UI now labels workflows as **"Workloads"** (nav menu, page titles, help text). ALL code identifiers, routes, entities, and config keys remain `Workflow*` / `WorkloadExecution*` — "the Workloads page" = `Workflows.razor`, "Workload Builder" = `WorkflowBuilder.razor`, "Workload Execution" = `WorkflowExecution.razor`.

## When to Use

Load this skill when:
- Exporting a workflow's scenarios to JSON files on disk
- Exporting workflow scenarios as new TestAutoScenarios records
- Working on `WorkflowExportService`, `IWorkflowExportService`, or `WorkflowExportDialog`
- Debugging file naming, the `ScenarioDataDisplay` 4000-char truncation, or the scenario-mode `DisplayName` format
- Reviewing how stored config (compressed) is deserialized and re-serialized to JSON

See also:
- [[testauto-workflow-transfer]] — **different feature**: exports a whole workflow to a portable `WorkflowBundle` and re-imports it on another machine. This skill (`WorkflowExportService`) is export-only (files / scenario records); use workflow-transfer for cross-machine round-trips.
- [[testauto-scenario-config-store]] — `IScenarioConfigStore` (`LoadAsync` / `PersistAsync` / `ResolveRawAsync`), which the export service now uses for all config reads/writes; [[configuration-compression-codec]] covers the legacy Brotli/GZip prefix codec the store still reads
- [[testauto-workflow-execution]] — execution lifecycle; export is a separate, non-execution code path

---

## Overview

The export feature writes the per-scenario configurations of a single workflow out in one or both of two independent modes:

| Mode | Flag | Output |
|------|------|--------|
| **Files** | `ExportToDirectory = true` | One JSON file per scenario written to `DirectoryPath\ExportName\` |
| **Scenarios** | `ExportAsScenario = true` | One new `TestAutoScenarios` record per scenario created in the Profisee repo |

Both modes may be active simultaneously. Neither can run without the other being off — the service validates that at least one is selected.

---

## Data Shapes

### `WorkflowExportItem` (input projection)

```csharp
public record WorkflowExportItem(
    int Order,                        // 1-based execution order within the workflow
    string DisplayName,               // Friendly display name — no export prefix
    string CompressedScenarioData,    // Stored config value: raw JSON, CHUNKREF sentinel, or legacy Brotli/GZip blob
    string? Category                  // Carried through to scenario records
);
```

Populated by the caller from `TestAutoWorkflowDetail` records.

### `WorkflowExportRequest` (service input)

```csharp
public record WorkflowExportRequest
{
    string ExportName { get; init; }            // Used as subfolder name AND scenario tag/name prefix
    bool ExportToDirectory { get; init; }       // Enables Files mode
    string? DirectoryPath { get; init; }        // Parent folder for Files mode (required when ExportToDirectory = true)
    bool ExportAsScenario { get; init; }        // Enables Scenarios mode
    IReadOnlyList<WorkflowExportItem> Items { get; init; }
}
```

### `WorkflowExportResult` (service output)

```csharp
public record WorkflowExportResult
{
    int FilesWritten { get; set; }
    int ScenariosCreated { get; set; }
    string? DirectoryPath { get; set; }   // Resolved target dir (parent\exportName), if Files mode ran
    List<string> Warnings { get; }        // Per-item warnings (skipped items)
    List<string> Errors { get; }          // Fatal per-item or request-level errors
    bool Success => Errors.Count == 0;
}
```

---

## Service Validation Gates

`WorkflowExportService.ExportAsync` short-circuits with an error (not an exception) in these cases — checked in order before any I/O:

1. `request == null` → "Export request was null."
2. `ExportName` is null/whitespace → "Export name is required."
3. Neither `ExportToDirectory` nor `ExportAsScenario` is true → "Select at least one export mode."
4. `Items` is null or empty → "There are no scenarios to export."
5. *(Files mode only, checked inside)* `DirectoryPath` is null/whitespace → "Directory export selected but no folder was chosen."

Items that individually fail decompression are skipped with a **warning** (not an error), so one bad item does not abort the whole export.

---

## Serialization Pipeline

Both modes share the same config-loading step (`TryDecompressAsync`):

```
CompressedScenarioData (raw JSON, CHUNKREF sentinel, or legacy Brotli/GZip prefixed string)
    → await _store.LoadAsync(item.CompressedScenarioData)   // IScenarioConfigStore
    → ScenarioConfiguration (typed object)
```

Files mode continues:

```
ScenarioConfiguration
    → IImportExportService.ExportToJsonAsync(config, formatting: true)
    → pretty-printed JSON string
    → IFileSystemService.SaveFileAsync(FileItem, UTF8 bytes)   // auto-creates directories
```

Scenarios mode **re-persists** the loaded config under the new record's own owner code, so the new scenario owns its chunks (or inline value) independently of the source record:

```csharp
var stored = await _store.PersistAsync(config, ConfigOwnerType.Scenario, record.Code);
// stored (inline JSON or CHUNKREF sentinel) becomes ScenarioData
```

**Display text** for `ScenarioDataDisplay` is derived via:

```csharp
var displayRaw = await _store.ResolveRawAsync(stored) ?? string.Empty;
// truncated to 4000 chars before being written to the attribute
```

---

## File Naming Convention

### Directory structure

```
DirectoryPath\
  ExportName\          ← SanitizePathSegment(ExportName) strips invalid filename chars
    PascalCaseName_001.json
    PascalCaseName_002.json
    ...
```

### `ToPascalCase` transform (internal static method on `WorkflowExportService`)

- Iterates characters of `DisplayName`
- **Letters and digits** are kept; the first letter after any non-alphanumeric character is uppercased
- All other characters (spaces, hyphens, underscores, punctuation) are dropped
- Empty result falls back to `"Scenario"`
- Null/whitespace input returns `"Scenario"`

Example: `"user crud - basic"` → `"UserCrudBasic"`

### Full file name pattern

```
{ToPascalCase(DisplayName)}_{Order:D3}.json
```

Example: `UserCrudBasic_001.json`

The dialog renders a live sample using the first item's `DisplayName` to show the user the real output before they click Export.

---

## Scenario Record Creation (Scenarios Mode)

Each item that loads successfully creates one `Record` with these attributes:

| Attribute (`TestAutoScenarios.*`) | Value |
|-----------------------------------|-------|
| `DisplayName` | `"{ExportName} {Order:D3} {item.DisplayName}"` — e.g. `"pr5 001 User CRUD"` |
| `Category` | `item.Category ?? string.Empty` |
| `Tags` | `ExportName.Trim()` — used as the grouping tag for the whole export batch |
| `ScenarioData` | `await _store.PersistAsync(config, ConfigOwnerType.Scenario, record.Code)` — re-persisted under the new record's owner code (inline or CHUNKREF) |
| `ScenarioDataDisplay` | `await _store.ResolveRawAsync(stored)`, truncated to 4000 chars |
| `Version` | `1` |
| `IsActive` | `"Y"` |

`Record.Code` = `Guid.NewGuid().ToString()`

`Record.Name` = `config.ScenarioName` if non-empty; otherwise falls back to `item.DisplayName`.

> `ScenarioName` is the C# class name of the scenario, not the display name — the fallback handles scenarios where the config does not carry the class name.

### Large configs are chunked, not skipped

There is **no 4000-char skip guard**. `PersistAsync` handles oversized configs by chunking them (CHUNKREF sentinel in `ScenarioData`), so large scenarios export fine in Scenarios mode. Only the `ScenarioDataDisplay` preview attribute is affected by the Profisee 4000-char attribute ceiling — the service truncates the resolved raw JSON to 4000 chars before writing it (avoids Profisee error 8610).

---

## `WorkflowExportDialog` (UI)

**File:** `TestAuto.Web/Components/Dialogs/WorkflowExportDialog.razor` + `.razor.cs`

### Parameters

| Parameter | Type | Purpose |
|-----------|------|---------|
| `WorkflowName` | `string` | Displayed in the dialog header for context |
| `Items` | `List<WorkflowExportItem>` | The scenarios to export (passed by the workflow page) |

### State

| Property | Default | Notes |
|----------|---------|-------|
| `ExportName` | `""` | Required; used as folder name and scenario tag |
| `FilesMode` | `true` | RadzenSwitch — defaults on |
| `ScenariosMode` | `false` | RadzenSwitch — defaults off |
| `DirectoryPath` | `{ScratchRoot}` | Editable text box; also settable via folder browser |
| `ShowBrowser` | `false` | Toggles inline `FileBrowser` component |
| `IsExporting` | `false` | Disables Export button + shows busy state |

### `CanExport` guard

```csharp
private bool CanExport =>
    !string.IsNullOrWhiteSpace(ExportName)
    && (FilesMode || ScenariosMode)
    && (!FilesMode || !string.IsNullOrWhiteSpace(DirectoryPath))
    && !IsExporting;
```

The Export button is disabled until all conditions are met — no toast/validation needed before the click.

### Folder browser

- Toggle button labeled "Browse…" / "Close" opens an inline `FileBrowser` with `FolderSelectionMode="true"`
- Browser root = drive portion of the current `DirectoryPath` (fallback `C:\`)
- `OnFolderPicked` sets `DirectoryPath` and collapses the browser

### Post-export behavior

- On `result.Success` with no warnings → `NotificationSeverity.Success`
- On `result.Success` with warnings → `NotificationSeverity.Warning` (8 s)
- On errors → `NotificationSeverity.Error` (10 s), errors + warnings concatenated
- `DialogService.Close(result.Success)` — caller receives `true` on success, `false` on failure or cancel

---

## Key Source Files

| File | Purpose |
|------|---------|
| `TestAuto.Web/Interfaces/IWorkflowExportService.cs` | `IWorkflowExportService`, `WorkflowExportRequest`, `WorkflowExportResult`, `WorkflowExportItem` |
| `TestAuto.Web/Services/WorkflowExportService.cs` | Implementation: `ExportAsync`, `ExportToDirectoryAsync`, `ExportAsScenariosAsync`, `ToPascalCase`, `SanitizePathSegment` |
| `TestAuto.Web/Components/Dialogs/WorkflowExportDialog.razor` | UI template: dual RadzenSwitch, ExportName text box, folder browser toggle, live sample file name |
| `TestAuto.Web/Components/Dialogs/WorkflowExportDialog.razor.cs` | Code-behind: `CanExport`, `ExportAsync`, `OnFolderPicked`, `SampleFileName`, `BrowserRoot` |
| `TestAuto.Web/BusinessLogic/Constants/FieldNames.cs` | `TestAutoScenarios.*` attribute name constants |

---

## Sources

- `TestAuto.Web\Interfaces\IWorkflowExportService.cs`
- `TestAuto.Web\Services\WorkflowExportService.cs`
- `TestAuto.Web\Components\Dialogs\WorkflowExportDialog.razor`
- `TestAuto.Web\Components\Dialogs\WorkflowExportDialog.razor.cs`
- `TestAuto.Web\BusinessLogic\Constants\FieldNames.cs`
