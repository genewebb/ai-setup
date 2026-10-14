---
name: testauto-prometheus-config
description: >
  Prometheus resource collection configuration and query-tuning reference for TestAuto.
  Use when resource collection returns zero data points, configuring
  QueryStepSeconds/RateWindow/padding params, troubleshooting CPU or memory metric gaps,
  adjusting for non-default scrape intervals, or understanding PromQL query design.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Prometheus Resource Collection Configuration

> **Scope**: speed-merchants (TestAuto + TestAuto.Web)
> **Source**: `TestAuto/Documentation/PrometheusResourceCollection.md`

---

## Configuration Location

All config lives in `appsettings.json` under the `ResourceCollection` key:

```json
"ResourceCollection": {
  "DefaultTimeWindow": "00:30:00",
  "MaxTimeWindow": "24:00:00",
  "AggregationInterval": "00:00:05",
  "QueryPaddingStartSeconds": 120,
  "QueryPaddingEndSeconds": 30,
  "QueryStepSeconds": 30,
  "RateWindow": "2m",
  "DefaultServers": [...]
}
```

---

## Parameter Reference

| Parameter | Default | Purpose |
|---|---|---|
| `QueryPaddingStartSeconds` | `120` | Seconds to query **before** workload start — ensures `rate()` has enough history |
| `QueryPaddingEndSeconds` | `30` | Seconds to query **after** workload end — accounts for collection lag |
| `QueryStepSeconds` | `30` | Step interval for Prometheus `query_range` API; 2× scrape interval gives stable results |
| `RateWindow` | `"2m"` | Lookback window for `rate()`. Must be ≥ 2× scrape interval |
| `DefaultTimeWindow` | `"00:30:00"` | Default query range when no explicit window is provided |
| `MaxTimeWindow` | `"24:00:00"` | Upper cap on query range |
| `AggregationInterval` | `"00:00:05"` in `appsettings.json:131`, but the **code fallback is 15 s** (`PrometheusClient.cs:46`) | Legacy — superseded by `QueryStepSeconds`; leave as-is. The two defaults disagree; see [[testauto-resource-collection]] |

---

## Why Window Padding?

`rate()` requires **at least 2 data points** in its lookback window. Without padding:

- Workload `10:00–10:05` queried exactly → `rate()[2m]` at `10:00:00` needs data from `09:58:00` → returns NaN for the first interval
- With `QueryPaddingStartSeconds=120`: query starts at `09:58:00` → stable results throughout

---

## PromQL Queries Used

### CPU

```promql
100 - (avg by(instance)(rate(windows_cpu_time_total{mode="idle",instance="{server}:9182"}[2m]))*100)
```

- `rate()` not `irate()` — averages over the window for stable summary stats
- Rate window "2m" ≈ 8 data points at 15s scrape interval

### Memory

```promql
(windows_memory_physical_total_bytes{instance="{server}:9182"}
 - windows_memory_available_bytes{instance="{server}:9182"})
 / windows_memory_physical_total_bytes{instance="{server}:9182"} * 100
```

Memory is a gauge, not a counter — no `rate()` needed.

---

## Scrape Interval Adjustment Table

| Scrape Interval | Recommended RateWindow | Recommended QueryStepSeconds |
|---|---|---|
| 10s | `"1m"` | 20 |
| 15s (default) | `"2m"` | 30 |
| 30s | `"2m"` | 60 |
| 60s | `"5m"` | 120 |

**Rule of thumb**: RateWindow ≥ 4× scrape interval; QueryStepSeconds = 2× scrape interval.

---

## Adaptive Step for Short Workloads

For workloads shorter than `QueryStepSeconds`: step = `duration / 10` (min 1s). This ensures at least 10 samples even for very short workloads.

---

## Data Point Gating

Records are only saved to `WorkloadExecutionResourceSummary` if **CPU DataPoints > 0 OR Memory DataPoints > 0**. Both zero → row is skipped with a warning log. This prevents 0/0/0 rows in the database.

---

## Preset Configurations

### High-Precision (Short Workloads < 2 min)

```json
"QueryPaddingStartSeconds": 180,
"QueryPaddingEndSeconds": 60,
"QueryStepSeconds": 15,
"RateWindow": "2m"
```

### Low-Overhead (Long Workloads > 10 min)

```json
"QueryPaddingStartSeconds": 60,
"QueryPaddingEndSeconds": 30,
"QueryStepSeconds": 60,
"RateWindow": "5m"
```

### Standard (Default)

```json
"QueryPaddingStartSeconds": 120,
"QueryPaddingEndSeconds": 30,
"QueryStepSeconds": 30,
"RateWindow": "2m"
```

---

## Troubleshooting

### Zero data points

**Symptoms**: `WorkloadExecutionResourceSummary` rows skipped; Seq shows the Warning
`Skipping WorkloadExecutionResourceSummary for server … : No data points (CPU=0, Memory=0)`
(note: the `…pts` suffix appears only on the *success* template, so don't search for it here).

| Cause | Check | Fix |
|---|---|---|
| Server not scraped | Prometheus targets page: `http://CORPVM17:9090/targets` — is server UP? | Verify instance label matches (e.g., `"SMVM3:9182"`) |
| Time zone mismatch | Logs show non-UTC timestamps | Ensure `WorkloadExecution` `StartTime`/`EndTime` stored as UTC |
| Workload too short | Duration < 10s | Increase `QueryPaddingStartSeconds` |
| Rate window too large | `rate()[5m]` on 2-min workload | Use default `"2m"` rate window |

### Incorrect CPU/Memory values

| Cause | Verify |
|---|---|
| Wrong metric names | Query Prometheus UI: `windows_cpu_time_total{instance="SMVM3:9182"}` |
| Instance label case mismatch | `"SMVM3:9182"` vs `"smvm3:9182"` (case-sensitive in PromQL) |
| Query syntax error | Check logs for Prometheus API error messages |

### High Prometheus load

Increase `QueryStepSeconds` (e.g., 60) and reduce `QueryPaddingStartSeconds` (e.g., 60). Stagger workload executions.

---

## Log Patterns

> **The Serilog templates carry NO emoji.** Older versions of this skill quoted `✅ Created …` and
> `⚠️ Skipped server …` — those strings do not exist. Search Seq for the plain text below.
> Emoji *do* appear in `PrometheusQueryHelper.cs`, but only in `Console.WriteLine` operator output
> (`🔍`/`📊`/`📈` at `:31,39,45,49,78,86,92,96,125`), which never reaches Seq — don't grep the log
> store for them.

All of these are tagged `LogTagConstants.ResourceCollection` and live in `ResourceCollectionService.cs`:

**Window setup** (Debug, `:250-253`) — verbatim templates:
```
Padded Time Window (for rate() stability):
  Start: {PaddedStartTime:yyyy-MM-dd HH:mm:ss} UTC (padded -{PaddingStartSeconds}s)
  End: {PaddedEndTime:yyyy-MM-dd HH:mm:ss} UTC (padded +{PaddingEndSeconds}s)
  Duration: {PaddedDurationSeconds}s ({PaddedDurationMinutes} minutes)
```

**Successful collection** (Information, `:476`):
```
Created WorkloadExecutionResourceSummary for server {ServerName}: CPU={CpuMin}/{CpuAvg}/{CpuMax} ({CpuDataPoints}pts), Memory={MemMin}/{MemAvg}/{MemMax} ({MemDataPoints}pts)
```

**Skipped server — the zero-data-point gate** (Warning, `:451`):
```
Skipping WorkloadExecutionResourceSummary for server {ServerName}: No data points (CPU={CpuDataPoints}, Memory={MemoryDataPoints})
```

**Run summary** (Information, `:489`):
```
Resource collection summary for WorkloadExecution {WorkloadExecutionCode}: Processed={ServersProcessed}, Created={RecordsCreated}, Skipped={ServersSkipped}
```

**Placeholder seeding summary** (Information, `:408`):
```
Placeholder record creation summary: Created={RecordsCreated}, Failed={RecordsFailed}, Skipped(no server)={RecordsSkipped}, Total={Total}
```

---

## Sources

- `TestAuto\Documentation\PrometheusResourceCollection.md`
- `TestAuto.Scenarios\Services\ResourceCollectionService.cs` — the live Serilog templates quoted above
- `TestAuto.External\Prometheus\PrometheusQueryHelper.cs` — emoji `Console.WriteLine` output (console only, not Seq)
- `TestAuto.External\Prometheus\PrometheusClient.cs` — `AggregationInterval` / `QueryStepSeconds` reads; see [[testauto-resource-collection]] for the 15 s-vs-5 s discrepancy
