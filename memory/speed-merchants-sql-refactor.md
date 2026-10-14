# speed-merchants SQL Refactor — MultiStepUtility (2026-03-26)

## Design Decisions

### Why direct SqlClient (not SqlHelper)

SqlHelper cannot support:

1. `SqlConnection.InfoMessage` event — needed for real-time PRINT/RAISERROR WITH NOWAIT progress streaming from multi-hour scripts
2. Per-command `CommandTimeout = 0` (infinite) — required for scripts loading 100M+ records
3. Multi-batch transactions across N GO-separated batches

Documented with class-level `<remarks>` in `SqlScriptExecutor.cs`.

### Connection Split: Source vs Destination

- **Source connection**: batch 0 when `CaptureScalarResult = true` (or `AutoWrapPassFailCode = true` → `effectiveCaptureScalar`). Uses `ExecuteReaderAsync` to traverse result sets and capture last scalar.
- **Destination connection**: all write batches. Transaction management lives here.
- Both connections opened upfront, both get `InfoMessage` hooked.

### effectiveCaptureScalar (no step mutation)

Old code did `sqlStep.CaptureScalarResult = true` when `AutoWrapPassFailCode` was set.
New: local `bool effectiveCaptureScalar = sqlStep.CaptureScalarResult || sqlStep.AutoWrapPassFailCode`.

### CommandTimeout = 0 → infinite

`SqlConnectionStringBuilder.CommandTimeout = sqlStep.SqlCommandTimeoutSeconds` baked into connection string.
`SqlCommand.CommandTimeout = sqlStep.SqlCommandTimeoutSeconds` also set per command (belt + suspenders).
Users set `"sqlCommandTimeoutSeconds": 0` in step config for infinite timeout.

## DatabaseName Removed (2026-03-26)

`SqlStep.DatabaseName` was removed. Connection strings from secrets are expected to be fully
qualified (server, database, auth). `SqlCommandTimeoutSeconds` is the only override applied
via `SqlConnectionStringBuilder` before opening connections.
Old: `SqlConnectionSecretName` (single field, was never actually used for source)
New: `SqlSourceConnectionSecretName` + `SqlDestinationConnectionSecretName` (both `Required.Always`)

## Files Changed

- `TestAuto.Utilities/Common/DTOs/SqlStep.cs`
- `TestAuto.Utilities/Executors/SqlScriptExecutor.cs`
- `TestAuto.Utilities/Services/UtilityOrchestrator.cs` (line ~375 validation)
- `TestAuto.Utilities/Scenarios/MultiStepUtilityScenario.cs` (sample config)
- `TestAuto.Utilities.Tests/` — 5 test files, all `SqlConnectionSecretName` → split
- `TestAuto.Utilities/Samples/*.json` — all sample files updated
- `TestAuto.Utilities/Documentation/` — HowToUseUtility.md, README.md, USAGE_GUIDE.md
