# Data Model Reference

All objects live in the `perfDashboard` schema of the prod DB `pc-speedmr-prd-db`, reached via
the `speedmerchants-prod-mssql` MCP server.

## The pipeline

```
raw execution data
   │  EXEC perfDashboard.CreateBatchCrudSummary   (batch ops, from data.tRecordApiExecution)
   │  EXEC perfDashboard.CreateUserCrudSummary    (interactive ops, from data.tRecordInteractiveApiExecution)
   ▼
perfDashboard.BatchCrudSummary   /  perfDashboard.UserCrudSummary    (base tables)
   ▼
perfDashboard.vBatchCrudSummary  /  perfDashboard.vUserCrudSummary   (typed views — QUERY THESE)
```

Always query the **views**, not the base tables. The views `TRY_CONVERT` the nvarchar columns to
real numeric types and add derived sort columns. The two views are structurally identical for our
purposes.

## Columns used (both views)

| Column | Meaning |
|--------|---------|
| `Scenario` | e.g. `CreateRecordsByPageAndBatchScenario`. Friendly label = leading verb. |
| `Operation` | `Create` / `Update` / `Delete` / `Record Read` / `Page Read`. |
| `RuleCount` | label string: `10 Rules` or `No Rules`. |
| `PlatformVersion` | `25R1`…`26R2P`. The comparison axis. |
| `AttributeCount`, `[User Load]` | the fine-grained combo dimensions (note the space in `[User Load]`). |
| `WinsorizedAvgResponseTimeMs` | **headline metric** — outlier-trimmed mean latency. |
| `P50ResponseTimeMs`, `P95ResponseTimeMs` | percentile latencies (User table). |
| `Throughput` | records/sec (Batch table). |
| `RuleCountSort`, `AttributeCountSort`, `UserLoadSort` | numeric sort helpers. |

## The common-runs rule (why the script exists)

> This is **CRUD performance data**, not Matching data. "Common runs" = the run combinations
> shared across every compared version (a set intersection). Unrelated to Profisee Matching.


A row in the report (one Scenario + Operation + Rules) is averaged across many fine-grained
`(AttributeCount × UserLoad)` combos. To keep a version-to-version comparison fair, the script
only counts combos that **every** selected version actually ran — otherwise a version that
happened to run an extra heavy combo would look artificially slow.

Implemented as: aggregate to per-version-per-combo, then `HAVING COUNT(DISTINCT PlatformVersion) = N`
to keep only combos present in all N versions, then average those up to Scenario/Operation/Rules.

`ComboCount` in the output tells you how many fine-grained combos fed each row — useful for
spotting thin coverage (a row backed by 1 combo is less robust than one backed by 12).

## Versions present (as of last check)

`25R1, 25R2, 25R3, 25R4, 26R1, 26R2P`. Run `SELECT DISTINCT PlatformVersion FROM
perfDashboard.vBatchCrudSummary ORDER BY 1` to confirm the current set. Note `PlatformVersionSort`
in the base view does not handle the trailing `P` in `26R2P` — rely on the user's chronological
ordering, not that column.

## Prior art

`perfDashboard.vBatchCrudSummary_PVerCompare` is a hardcoded 2-version (`25R3` vs `25R4`) pivot
view. It's the static ancestor of what this skill generalizes — useful to read for the canonical
delta math, but do not depend on it (it's frozen to two specific versions).
