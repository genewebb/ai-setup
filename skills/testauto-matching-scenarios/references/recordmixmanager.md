# RecordMixManager — Service Contract, CRUD Mix, and Integration Tests

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## RecordMixManager — Service Contract, CRUD Mix, and Integration Tests

### Service Contract (`IRecordMixManager`)

File: `TestAuto.Matching/Interfaces/IRecordMixManager.cs`

| Method / Property | Signature | Notes |
|---|---|---|
| `InitializeAsync` | `Task InitializeAsync(ScenarioConfiguration, CancellationToken)` | Must be called before any data operation; calculates partition, initializes keyset starting points |
| `GetNextBatchAsync` | `Task<List<(Record, string RecordType)>> GetNextBatchAsync(int batchSize, CancellationToken)` | Primary streaming method; dispatches to mode-specific private method |
| `GetRecordsBySourceModeAsync` | `Task<List<(Record, string RecordType)>> GetRecordsBySourceModeAsync(int count, CancellationToken)` | Thin delegate to `GetNextBatchAsync`; retained for call-site clarity |
| `GetRecordsByTypeAsync` | `Task<List<Record>> GetRecordsByTypeAsync(string recordType, int count, CancellationToken)` | Legacy single-type fetch; maps `RecordType_*` constants to source system |
| `GetProgress` | `MatchingRecordProgress GetProgress()` | Snapshot of partition boundaries, `_recordsProcessed`, keyset last codes, throughput |
| `HasMoreRecordsAsync` | `Task<bool> HasMoreRecordsAsync(CancellationToken)` | Returns `_recordsProcessed < _partitionSize`; controls the `ScenarioBase.ForEachIterationAsync` loop |
| `GetPoolStatisticsAsync` | `Task<RecordPoolStatistics> GetPoolStatisticsAsync(CancellationToken)` | Queries all source system row counts via `IRecordPoolRepository` |
| `CurrentDistribution` | `RecordMixDistribution CurrentDistribution { get; }` | Exposes parsed percentages and source system codes |
| `CurrentRecordSourceMode` | `string CurrentRecordSourceMode { get; }` | Returns `ExistingMatchedOnly`, `NewValuesOnly`, or `Mixed` |

**Lifecycle**: not thread-safe — one instance per Hangfire job execution. `EnsureInitialized()` guards all data methods.

### CRUD Mix Operations

`GetNextBatchAsync` dispatches to one of four private methods based on `_recordSourceMode` and `HasSourceSystemDistribution`:

| Dispatch condition | Private method | Scenario | RecordType tag |
|---|---|---|---|
| `HasSourceSystemDistribution == true` | `GetPerSourceSystemBatchAsync` | Scenario 1 (explicit counts per source) | `RecordType_New` |
| `RecordSource_ExistingOnly` | `GetExistingRecordsBatchAsync` | Scenario 3A | `RecordType_NoChange` |
| `RecordSource_NewOnly` | `GetHoldoutRecordsBatchAsync` | Scenario 3B | `RecordType_New` |
| `RecordSource_Mixed` | `GetMixedRecordsBatchAsync` | Scenarios 2 and 3C | `RecordType_Changed` / `RecordType_New` |

**`GetMixedRecordsBatchAsync`** (Scenarios 2 / 3C):
- Splits `fetchCount` into `changedCount = round(fetchCount × ChangedPercent / 100)` and `newCount = fetchCount - changedCount`
- Fetches Changed records via `_repository.GetRecordsByKeysetAsync(UpdateRecordSourceSystem, lastChangedCode, changedCount)` — or `FetchFromMultipleSourcesAsync` if `HasMultiSourceChanged`
- Fetches New records from `NewRecordSourceSystem` — or `FetchFromMultipleSourcesAsync` if `HasMultiSourceNew`
- Shuffles result with `OrderBy(_ => random.Next())` to avoid systematic patterns
- Updates `_lastCodes[sourceSystem]` with `records.Last()["Code"]` after each fetch

**`GetExistingRecordsBatchAsync`** (Scenario 3A):
- Uses `_recordsRestClient.GetRecordsAsync` (Profisee REST), not SQL
- Filters by `MatchStatusFilter` codes (default `["20","30","40","50"]`) on the `MatchStatusAttribute` column
- Stable pagination via `OrderBy=[Code]`; increments `_currentPageNumber` each batch

**`GetHoldoutRecordsBatchAsync`** (Scenario 3B):
- Uses keyset SQL via `_repository.GetRecordsByKeysetAsync(holdoutSourceSystem, lastCode, count)`
- Default `HoldoutSourceSystem` = `"3"` (largest ModelSource pool, ~20M records)
- Supports `HoldoutSourceSystems` dict for multi-source proportional distribution

**`GetPerSourceSystemBatchAsync`** (Scenario 1):
- Reads `_sourceSystemDistribution` (from `SourceSystemDistribution` or `NewRecordDistribution.SourceSystems` CustomParms)
- Distributes batch proportionally across sources by remaining count; last source gets remainder
- Tracks per-source progress in `_sourceSystemProgress`

**`FetchFromMultipleSourcesAsync`** (shared helper for multi-source):
- Accepts `Dictionary<string, int> sourcePercentages` — source system code → percent
- Sorts by descending percent; last source absorbs remainder to guarantee exact count
- Calls `GetRecordsByKeysetAsync` per source; updates `_lastCodes` for each

### Integration Test Patterns

File: `Testing.SpeedMerchants.Integration/Tests/Matching/RecordMixManagerIntegrationTests.cs`

Class: `RecordMixManagerIntegrationTests : BaseTest`
Categories: `[TestCategory("Integration")]`, `[TestCategory("Matching")]`

**Setup (`TestInitialize`)**:
1. Reads `SourceRecordDB` connection string from secrets; marks test `Inconclusive` if missing
2. Creates `RecordPoolConfiguration { DatabaseName="ModelSource", BaseTableName="RetailClient", ClonedTableName="RetailClientCloned" }`
3. Constructs `RecordPoolRepository(_connectionString, poolConfig, Logger)`
4. Creates a `StubRestClient` for the REST parameters (not used by SQL-based scenarios)

**Test factory helpers** — each constructs a `ScenarioConfiguration` and calls `manager.InitializeAsync(config)`:

| Helper | Mode | Key CustomParms |
|---|---|---|
| `CreateAndInitializeManagerAsync(totalRecords, serverIndex, totalServers)` | `NewValuesOnly` | `HoldoutSourceSystem="1"` |
| `CreateMixedSourceManagerAsync(totalRecords, serverIndex, totalServers)` | `Mixed` | `ChangedPercent=85`, `NewPercent=15`, `NewRecordSourceSystem="1"`, `UpdateRecordSourceSystem="20"` |
| `CreateManagerWithOffsetAsync(totalRecords, serverIndex, totalServers, newRecordOffset, changedRecordOffset, mode)` | configurable | `NewRecordStartingOffset`, `ChangedRecordStartingOffset` |

**Test method groups**:

| Group / Method | What it validates |
|---|---|
| `ProcessPartition_100Records_SingleServer_Works` | Minimal smoke test — 100 records, exact count |
| `ProcessPartition_1000Records_SingleServer_Works` | Basic streaming — batch loop, count assertion |
| `ProcessPartition_Incremental100to1000_PerformanceAnalysis` | 100→1000 in steps; logs setup vs execution time; writes to `$TEMP` |
| `ProcessPartition_PerformanceTest` (`DataTestMethod`) | 12 combos of batch size (1K/25K/50K) × total (10K/50K/100K/1M); writes markdown reports to `.cursor/documentation/matching/TestResults/` |
| `ProcessPartition_MixedSource_85Changed_15New_PerformanceTest` | Mixed mode; asserts actual Changed% within ±5% of 85 |
| `ProcessPartition_WithNewRecordOffset_StartsAtCorrectPosition` | NewOnly mode with offsets 0–100K; asserts `progress.NewRecordStartingOffset` matches config |
| `ProcessPartition_MixedWithOffset_AppliesBothOffsets` | Mixed mode with independent new/changed offsets; asserts both `EffectiveNewStartPosition` / `EffectiveChangedStartPosition` |
| `ProcessPartition_InvalidOffset_ThrowsArgumentException` | Negative offsets → `ArgumentException` |
| `TestResultsFolderCreation_ShouldCreateFolder` | Utility — confirms test output directory creation |

**Standard streaming loop pattern used in every test**:
```csharp
while (await manager.HasMoreRecordsAsync())
{
    var batch = await manager.GetNextBatchAsync(BatchSize);
    if (batch.Count == 0) break;
    foreach (var (record, _) in batch) { allRecords.Add(record); }
}
Assert.AreEqual(totalRecords, allRecords.Count, ...);
```

**Prerequisite**: `SourceRecordDB` connection string must be set via `SetSecrets.ps1` before running. Tests are skipped (`Inconclusive`) if missing, not failed.

---
