---
name: testauto-scenario-version-history
description: >
  Scenario version history model types, service contract, and REST API for TestAuto.Web — backed today by
  an in-memory stub, not a database. Use when creating or modifying scenario versioning features, asking
  whether version history survives a restart or where to add real persistence, writing tests against
  ScenarioVersioningController or IScenarioVersioningService, working out the actual create-version wire
  shape (the controller takes the configuration FromBody with versionNotes FromQuery — CreateVersionRequest
  is a grouping DTO the controller does not bind), comparing versions, or reading VersionDifference /
  ScenarioVersionStats / ScenarioVersionComparison types.
---

Repo: speed-merchants (paths below are repo-relative)

# Scenario Version History

All version types live in `TestAuto.Shared.Common.Scenario`. They are consumed by `IScenarioVersioningService` (interface) and `ScenarioVersioningService` (stub implementation), exposed through `ScenarioVersioningController` at `api/ScenarioVersioning`.

---

## Model Types

### ScenarioVersionInfo

The primary snapshot record for a single version of a scenario.

| Field | Type | Purpose |
|---|---|---|
| `VersionId` | `string` | Unique GUID assigned at creation (`Guid.NewGuid().ToString("n")`). |
| `ScenarioId` | `string` | Owning scenario identifier (case-insensitive comparison). |
| `VersionNumber` | `int` | 1-based sequential counter; auto-incremented as `max(existing) + 1`. |
| `VersionNotes` | `string?` | Optional free-text description of what changed. |
| `CreatedBy` | `string` | Identity of the creator (`Environment.UserName` in the stub). |
| `CreatedAt` | `DateTime` | UTC timestamp of creation. |
| `Configuration` | `ScenarioConfiguration` | Full snapshot of the scenario configuration at this version. |
| `IsCurrentVersion` | `bool` | Exactly one version per scenario is current at any given time. |

**IsCurrentVersion semantics**: When a new version is created, all existing versions have `IsCurrentVersion = false` set before the new version is added with `IsCurrentVersion = true`. On delete, if the deleted version was current, the highest remaining `VersionNumber` becomes current. On revert, the target version becomes current and all others are cleared.

**ScenarioConfiguration relationship**: Each `ScenarioVersionInfo` embeds a complete `ScenarioConfiguration` snapshot. This means retrieving a version gives you the full configuration state at that point in time — there is no separate lookup needed.

---

### ScenarioVersionHistory

A lightweight audit-log entry returned by `GetVersionHistoryAsync`. Does not embed the configuration snapshot.

| Field | Type | Purpose |
|---|---|---|
| `VersionId` | `string` | Reference to the version. |
| `VersionNumber` | `int` | Sequential version number. |
| `Action` | `string` | String label for the action: `Created`, `Modified`, `Reverted`, `Deleted`. |
| `VersionNotes` | `string?` | Notes captured at the time of the action. |
| `CreatedBy` | `string` | Author of the action. |
| `CreatedAt` | `DateTime` | UTC timestamp. |

The history endpoint accepts optional `from` / `to` date filters and returns entries ordered by `CreatedAt` ascending.

---

### VersionDifference

Represents a single field-level change detected during a version comparison.

| Field | Type | Values |
|---|---|---|
| `PropertyPath` | `string` | Dotted path to the changed property (e.g., `"VersionNotes"`, `"Configuration"`). |
| `SourceValue` | `string?` | Value in the source (older) version. |
| `TargetValue` | `string?` | Value in the target (newer) version. |
| `ChangeType` | `string` | `Added`, `Removed`, or `Modified`. |

Current diff logic (in `ScenarioVersioningService`) compares `VersionNotes` as a string equality check, then treats non-`ReferenceEquals` configurations as `Modified`. Production implementations should perform a deep property walk and populate `PropertyPath` with the actual changed field path.

---

### ScenarioVersionComparison

The aggregate result of comparing two versions.

| Field | Type | Purpose |
|---|---|---|
| `SourceVersion` | `ScenarioVersionInfo` | Full source version snapshot. |
| `TargetVersion` | `ScenarioVersionInfo` | Full target version snapshot. |
| `Differences` | `List<VersionDifference>` | All detected differences. |
| `ChangeSummary` | `string` | Human-readable summary (e.g., `"3 difference(s) detected"`). |

---

### ScenarioVersionStats

Aggregate statistics across all versions of a scenario.

| Field | Type | Purpose |
|---|---|---|
| `TotalVersions` | `int` | Total number of versions stored. |
| `CurrentVersionNumber` | `int` | `VersionNumber` of the version where `IsCurrentVersion = true`; `0` if no current version. |
| `FirstVersionDate` | `DateTime` | `Min(CreatedAt)` across all versions. |
| `LastVersionDate` | `DateTime` | `Max(CreatedAt)` across all versions. |
| `MostActiveContributor` | `string` | `CreatedBy` value with the highest count across all versions. |
| `AverageVersionsPerMonth` | `double` | `TotalVersions / months_spanned`, rounded to 2 decimals. Months are inclusive (first month counts as 1). |

---

### CreateVersionRequest

Request body for `POST api/ScenarioVersioning/{scenarioId}/versions`. Note: The controller accepts the configuration directly as `[FromBody] ScenarioConfiguration` with `versionNotes` as a `[FromQuery]` parameter — `CreateVersionRequest` is the logical grouping but the controller splits the fields.

| Field | Validation | Purpose |
|---|---|---|
| `Configuration` | `[Required]` | Full `ScenarioConfiguration` snapshot to store. |
| `VersionNotes` | optional | Human-readable description of what changed. |

---

## Service Contract (IScenarioVersioningService)

```csharp
Task<IReadOnlyList<ScenarioVersionInfo>> GetScenarioVersionsAsync(string scenarioId);
Task<ScenarioVersionInfo?> GetVersionAsync(string scenarioId, string versionId);
Task<string> CreateVersionAsync(string scenarioId, ScenarioConfiguration configuration, string? versionNotes);
Task<bool> DeleteVersionAsync(string scenarioId, string versionId);
Task<bool> RevertToVersionAsync(string scenarioId, string versionId);
Task<ScenarioVersionComparison> CompareVersionsAsync(string scenarioId, string sourceVersionId, string targetVersionId);
Task<IReadOnlyList<ScenarioVersionHistory>> GetVersionHistoryAsync(string scenarioId, DateTime? fromDate, DateTime? toDate);
Task<ScenarioVersionStats> GetVersionStatsAsync(string scenarioId);
```

`CreateVersionAsync` returns the new `VersionId` (GUID string). `DeleteVersionAsync` and `RevertToVersionAsync` return `false` if the target was not found.

---

## REST API Endpoints (ScenarioVersioningController)

Base route: `api/ScenarioVersioning`

| Method | Route | Description |
|---|---|---|
| `GET` | `{scenarioId}/versions` | List all versions |
| `GET` | `{scenarioId}/versions/{versionId}` | Get single version (404 if not found) |
| `POST` | `{scenarioId}/versions?versionNotes=...` | Create new version; body = `ScenarioConfiguration` |
| `DELETE` | `{scenarioId}/versions/{versionId}` | Delete a version |
| `POST` | `{scenarioId}/versions/{versionId}/revert` | Revert to a version |
| `GET` | `{scenarioId}/history?from=&to=` | Get audit-log history (optional date range) |
| `GET` | `{scenarioId}/stats` | Get aggregate statistics |
| `GET` | `{scenarioId}/compare?sourceVersionId=&targetVersionId=` | Compare two versions |

All responses are wrapped in `ApiSuccessResponse<T>` on success or `ApiErrorResponse` on error.

---

## Persistence

The current `ScenarioVersioningService` implementation is an **in-memory stub** backed by `Dictionary<string, List<ScenarioVersionInfo>>`. It is scoped to the process lifetime and has no database persistence. The comment in the source is: `// Replace with repository/data store as needed.`

When implementing a real persistence layer, inject a repository through `IScenarioVersioningService` and replace the in-memory dictionary. The service is registered in DI via `services.TryAddScoped<IScenarioVersioningService, ScenarioVersioningService>()` in `TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs`.

---

## Sources
- `TestAuto.Shared\Common\Scenario\ScenarioVersionInfo.cs`
- `TestAuto.Shared\Common\Scenario\ScenarioVersionHistory.cs`
- `TestAuto.Shared\Common\Scenario\VersionDifference.cs`
- `TestAuto.Shared\Common\Scenario\ScenarioVersionStats.cs`
- `TestAuto.Shared\Common\Scenario\ScenarioVersionComparison.cs`
- `TestAuto.Shared\Common\Scenario\CreateVersionRequest.cs`
- `TestAuto.Web\Interfaces\IScenarioVersioningService.cs`
- `TestAuto.Web\Services\ScenarioVersioningService.cs`
- `TestAuto.Web\Controllers\ScenarioVersioningController.cs`
