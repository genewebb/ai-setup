---
name: record-mapper-extension-methods
description: >
  RecordMapper static helper class in TestAuto.Web for safe value extraction from
  Profisee Record objects. Use when reading attribute values from a Record, converting
  Profisee's Y/N boolean convention, mapping Records to workflow DTOs (WorkflowItem,
  WorkflowExecutionItem, WorkflowExecutionDetailItem), or parsing tag strings.
---

Repo: speed-merchants (paths below are repo-relative)

# RecordMapper Extension Methods

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/BusinessLogic/Helpers/RecordMapper.cs`

`RecordMapper` provides extension methods on `Profisee.Platform.Cdp.Contracts.Record` for null-safe value extraction and DTO mapping. Prefer these over direct `Record[fieldName]` indexer access — the indexer throws on missing fields; `SafeGet*` methods return null/default.

---

## Safe Extraction Methods

All methods are extension methods on `Record`. They return null/default if the record is null, the field is missing, or the value cannot be converted.

### `SafeGetString(string fieldName) → string?`

```csharp
var status = record.SafeGetString("ExecutionStatus");
```

### `SafeGetInt(string fieldName) → int?`

```csharp
var count = record.SafeGetInt("NodeCount");
```

### `SafeGetDateTime(string fieldName) → DateTime?`

Parses the field as a string first (Profisee stores datetimes as strings), then calls `DateTime.TryParse`.

```csharp
var startTime = record.SafeGetDateTime("StartTime");
```

### `SafeGetBoolean(string fieldName) → bool`

**Profisee stores booleans as `"Y"` / `"N"` strings**, not as `true`/`false`. This method handles both:

```csharp
var isActive = record.SafeGetBoolean("Active");
// "Y" → true, "N" → false, null → false
```

- First attempts string extraction and compares to `"Y"` (case-insensitive)
- Falls back to `bool?` extraction for fields that are actual booleans

---

## DTO Mapping Methods

### `ToWorkflowItem() → WorkflowItem?`

Maps a workflow `Record` to `WorkflowItem`. Uses `TestAutoWorkflow` field constants. Returns a minimal `WorkflowItem` (Code + "Unknown" Name) if any field mapping fails — never returns null for a non-null Record.

```csharp
var item = record.ToWorkflowItem();
// item.Code, item.Name, item.Description, item.Category,
// item.Active (Y/N), item.CreatedAt, item.UpdatedAt, item.Tags
```

### `ToWorkflowExecutionItem() → WorkflowExecutionItem?`

Maps a workflow execution `Record`. Fields: Code, Name, ExecutionStatus, StartTime, EndTime, ErrorMessage, Tags, ExecutionMachine.

### `ToWorkflowExecutionDetailItem() → WorkflowExecutionDetailItem?`

Maps a workflow execution detail `Record`. Fields: Code, WorkflowExecutionCode, ScenarioDisplayName, ScenarioDisplayDescription, ExecutionOrder, ExecutionStatus, WorkloadExecutionCode, StartTime, EndTime, ErrorMessage, Category, Tags, ScenarioConfigurationCompressed, ProfiseeVersion, SimulatedUserCount, NodeCount, DqRuleCount, AttributeCount.

---

## Utility Methods

### `ParseTags(string? tagsString) → IEnumerable<string>`

Splits a comma or semicolon-delimited tag string. Both separators are supported for backward compatibility. Returns `Array.Empty<string>()` for null/empty input.

```csharp
var tags = RecordMapper.ParseTags("perf,matching,stress");
// → ["perf", "matching", "stress"]
```

### `FormatLocal(DateTime? dateTime) → string`

Formats a `DateTime?` to local time in `"yyyy-MM-dd HH:mm"` format. Returns `"Unknown"` for null.

---

## Sources

- `TestAuto.Web\BusinessLogic\Helpers\RecordMapper.cs`
