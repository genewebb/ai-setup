---
name: testauto-log-viewer
description: >
  In-app log-viewing subsystem for TestAuto (Seq + Profisee platform log). Use when
  working on the StepLogsDialog or its services, querying Seq from C#, reading the
  Profisee platform log table in-app, correlating a workflow step's Seq/platform logs,
  clearing Seq events from the Config page, or wiring LogViewerServiceExtensions.
---

# testauto-log-viewer

## When to Use

- Modifying or debugging `StepLogsDialog` (the in-app failed-step log dialog).
- Adding/changing how Seq events are fetched, filtered, or parsed in C#.
- Changing the Profisee platform log query (`logging.tSystemLog`).
- Altering the multi-source aggregation in `LogDetailService`.
- Adding a new caller of `ClearAllEventsAsync` or changing the Seq-clear flow.
- Wiring new config keys for the Seq client or platform DB connection.
- Distinguishing this subsystem from the read-only PowerShell [[seq-query]] skill (which shells out to the `seq` CLI and is for ad-hoc queries, not in-app use).

---

## 1. Overview

The log viewer is a **C#-only, in-app subsystem** (no PowerShell, no `seq` CLI) inside `TestAuto.Web`. When a user opens a failed step's "View Logs" dialog, `StepLogsDialog` calls `ILogDetailService.GetStepLogsAsync`, which fans out **in parallel** to two log sources:

| Source | Class | Transport |
|---|---|---|
| Seq structured log | `SeqQueryClient` | HTTP GET `api/events` via typed `HttpClient` |
| Profisee platform log | `PlatformLogReader` | `SqlHelper` → `logging.tSystemLog` (Profisee DB) |

The results are merged into a single `StepLogDetail` DTO and rendered in a two-tab `RadzenTabs` dialog. Each source fails independently — a Seq outage never hides the platform log and vice versa.

This subsystem is distinct from:
- [[seq-query]] — PowerShell skill for ad-hoc Seq CLI queries outside the app.
- [[profisee-logging-library]] — the **emit** side (how events are written via Serilog + Seq sink).
- [[dotnet-logging-schema]] — the `logging.tSystemLog` schema reference.

---

## 2. Seq HTTP Query Client

### 2.1 `ISeqQueryClient` / `SeqQueryClient`

**File:** `TestAuto.Web/Services/Logs/SeqQueryClient.cs`

A thin typed-`HttpClient` wrapper. The `HttpClient`'s `BaseAddress` and authentication header are injected at DI registration time (see §5).

#### `QueryAsync` — GET events

```
GET api/events?count={maxEvents}&render=true&fromDateUtc={fromUtc:o}&filter={filter}
Accept: application/json
X-Seq-ApiKey: {configured key}
```

- `fromDateUtc` is formatted as ISO-8601 round-trip (`"o"`) in UTC.
- On non-2xx: throws `HttpRequestException` with the Seq status, reason, and body. On 401, includes a hint about the API key missing `read events` permission.
- Response body is passed directly to `SeqEventParser.Parse`.

#### `ClearAllEventsAsync` — DELETE all events

```
DELETE api/events/signal
Content-Type: application/json
X-Seq-ApiKey: {configured key}

{"Filters":[]}
```

- An empty `Filters` array is Seq's signal for "match everything."
- Method: `HttpMethod.Delete`; body: literal JSON string `{"Filters":[]}` (UTF-8).
- On non-2xx: throws `HttpRequestException`. On 401 → hints `RestClients:Seq:ApiKey` missing/lacks write. On 403 → hints key lacks write permission to delete.
- Reuses the same DI-configured `HttpClient` as `QueryAsync` — authentication cannot drift between query and clear.

**Called from:** `Config.razor.cs → ClearSeqLog()` after a Radzen confirm dialog (no-op if user cancels). The UI shows a busy spinner and notifies success/error via `NotificationService`/`ErrorNotificationService`.

### 2.2 `SeqFilterBuilder`

**File:** `TestAuto.Web/Services/Logs/SeqFilterBuilder.cs`  
Pure static class — no I/O.

Single-quote escaping: replaces `'` with `''` in all string values before embedding them in the Seq filter expression.

| Method | Generated filter |
|---|---|
| `BuildForExecution(code)` | `WorkloadExecution = '{code}' and @Level in ['Error','Fatal']` |
| `BuildForScenario(name)` | `ScenarioName = '{name}' and @Level in ['Error','Fatal']` |

Both filters scope to `Error` and `Fatal` levels only.

### 2.3 `SeqEventParser`

**File:** `TestAuto.Web/Services/Logs/SeqEventParser.cs`  
Pure static class — no I/O. Uses `Newtonsoft.Json.Linq.JArray`.

Field resolution with fallbacks (handles schema variants across Seq versions):

| `SeqLogEvent` property | Primary field | Fallback field |
|---|---|---|
| `Level` | `Level` | `LevelName` |
| `Message` | `RenderedMessage` | `MessageTemplate` |
| `TimestampUtc` | `Timestamp` (parsed with `AdjustToUniversal\|AssumeUniversal`) | `DateTime.MinValue` |
| `Exception` | `Exception` | _(none — nullable)_ |

Returns `IReadOnlyList<SeqLogEvent>`. Returns an empty list on null/whitespace input without throwing.

---

## 3. Platform Log Reader

### 3.1 `IPlatformLogReader` / `PlatformLogReader`

**File:** `TestAuto.Web/Services/Logs/PlatformLogReader.cs`

Reads Profisee server-side errors from `logging.tSystemLog` over the `ProfiseeDBConnection` string (see §5).

**Sync→async bridge pattern:** `SqlHelper.ExecuteDataReader` is synchronous. `PlatformLogReader.QueryAsync` wraps the entire read in `Task.Run` to offload the blocking call from the Blazor circuit. This matches the convention used by `ConnectExecutionRepository` and `MatchingCountersService`, and enables the Seq and platform fetches to run in parallel inside `Task.WhenAll`.

```csharp
public Task<IReadOnlyList<PlatformLogEvent>> QueryAsync(DateTime fromUtc, DateTime toUtc, int max)
    => Task.Run<IReadOnlyList<PlatformLogEvent>>(() => { /* SqlHelper read */ });
```

### 3.2 `PlatformLogQuery`

**File:** `TestAuto.Web/Services/Logs/PlatformLogQuery.cs`  
Pure static class — no connection.

Generated SQL (parameterized):
```sql
SELECT TOP (@Max) [TimeStamp], [Level], [Message], [Exception], [SourceContext]
FROM logging.tSystemLog
WHERE [TimeStamp] >= @FromUtc
  AND [TimeStamp] <= @ToUtc
  AND [Level] IN ('Error','Fatal')
ORDER BY [TimeStamp] DESC;
```

Parameters: `@Max` (`SqlDbType.Int`), `@FromUtc` (`SqlDbType.DateTime`), `@ToUtc` (`SqlDbType.DateTime`).

**Important:** `tSystemLog` has **no `WorkloadExecution` column** — Profisee owns the table. Correlation is purely by UTC time window + severity. There is no exact-code filter available for the platform log.

---

## 4. Multi-Source Aggregation — `LogDetailService`

**File:** `TestAuto.Web/Services/Logs/LogDetailService.cs`

Constants:
- `MaxEvents = 100` — cap applied to both Seq and platform queries.
- `WindowPad = TimeSpan.FromMinutes(2)` — subtracted from `StartTime` and added to `EndTime`.

### 4.1 Request / Result DTOs

**`StepLogRequest`** (`TestAuto.Web/Models/Logs/StepLogRequest.cs`)

| Property | Type | Notes |
|---|---|---|
| `WorkloadExecutionCode` | `string?` | Primary correlation key; may be null/empty |
| `StartTime` | `DateTime?` | Step start (UTC or Unspecified-treated-as-UTC) |
| `EndTime` | `DateTime?` | Step end (UTC or Unspecified-treated-as-UTC) |
| `ScenarioName` | `string` | Fallback correlation key |

**`StepLogDetail`** (`TestAuto.Web/Models/Logs/StepLogDetail.cs`)

| Property | Type | Notes |
|---|---|---|
| `SeqEvents` | `IReadOnlyList<SeqLogEvent>` | Empty list on error or no results |
| `SeqError` | `string?` | Non-null if Seq fetch failed or no correlation possible |
| `SeqNote` | `string?` | Non-null when fallback filter was used (informational) |
| `SeqFilter` | `string` | Exact Seq filter used; shown in UI for manual replay |
| `PlatformEvents` | `IReadOnlyList<PlatformLogEvent>` | Empty list on error |
| `PlatformError` | `string?` | Non-null if platform fetch failed |

**`SeqLogEvent`** (`TestAuto.Web/Models/Logs/SeqLogEvent.cs`): `TimestampUtc`, `Level`, `Message`, `Exception?`

**`PlatformLogEvent`** (`TestAuto.Web/Models/Logs/PlatformLogEvent.cs`): `TimestampUtc`, `Level`, `Message`, `Exception?`, `SourceContext?`

### 4.2 Aggregation Logic

```
GetStepLogsAsync(request):
  fromUtc = (StartTime ?? UtcNow-1h) - 2 min
  toUtc   = (EndTime   ?? UtcNow)    + 2 min

  seqTask      = FetchSeqAsync(...)      ─┐
  platformTask = FetchPlatformAsync(...)  ├─ Task.WhenAll (parallel)
                                         ─┘

  return StepLogDetail from both results
```

**Seq correlation strategy (priority order):**

1. **Exact execution-code match** (`WorkloadExecutionCode` present): calls `SeqFilterBuilder.BuildForExecution` → queries Seq. If events found, returns them immediately.
2. **Scenario-name fallback** (used when no `WorkloadExecutionCode`, OR when code query returns 0 results and `ScenarioName` is available): calls `SeqFilterBuilder.BuildForScenario` → queries Seq → filters results to `TimestampUtc <= toUtc` client-side → sets `SeqNote` explaining the fallback.
3. **No correlation possible** (neither code nor name): returns an empty list with `SeqError` set to an explanatory string. No HTTP call is made.

**Per-source degradation:** Each source is wrapped in its own try/catch. A transport exception sets the corresponding `*Error` string; the other source's results are unaffected. Both sources always complete before `StepLogDetail` is returned.

### 4.3 `StepLogsDialog` (Blazor component)

**Files:** `TestAuto.Web/Components/Controls/StepLogsDialog.razor` + `.razor.cs`

- Takes a `[Parameter] StepLogRequest Request`.
- Calls `ILogDetailService.GetStepLogsAsync(Request)` in `OnInitializedAsync` (on-demand — only fires when the dialog opens).
- Renders a two-tab `RadzenTabs`: "SEQ (N)" and "Platform Log (N)".
- Shows `SeqNote` as an info alert when the fallback filter was used.
- Renders `SeqFilter` as `<code>` in error alerts so users can run it manually in Seq.
- Builds a deep-link URL (`{seqBaseUrl}/#/events?filter={urlEncoded filter}`) for the "Open in SEQ" button using `WebUtility.UrlEncode`.

---

## 5. DI Wiring — `LogViewerServiceExtensions`

**File:** `TestAuto.Web/Services/Logs/LogViewerServiceExtensions.cs`

```csharp
services.AddLogViewerServices(configuration);
```

Called from `Program.cs` (Web host only — wires Web-layer types).

### Config key resolution

**Seq base URL** (in priority order):
1. `RestClients:Seq:BaseUrl` (canonical; mirrors the `RestClients:<Client>` pattern)
2. `Seq:ServerUrl` (legacy key also used by the Serilog Seq sink)
3. `http://localhost:5341` (hardcoded fallback)

A malformed value (e.g., an unresolved `{{ServerNames:...}}` token) silently falls back to `http://localhost:5341/` rather than throwing during DI setup — the Seq tab degrades gracefully.

**Seq API key** (in priority order):
1. `RestClients:Seq:ApiKey` (config)
2. `SEQ_API_KEY` env var (User scope)
3. `SEQ_API_KEY` env var (process scope)
4. _(no key — `X-Seq-ApiKey` header omitted)_

**Seq timeout:** `RestClients:Seq:TimeoutSeconds` (int; defaults to `30`).

**Platform DB connection:** `ProfiseeAppSettingsConfigurationKeys.ProfiseeDbConnection` config key. Registered as `AddScoped<IPlatformLogReader>`.

**Registrations summary:**

| Interface | Implementation | Lifetime |
|---|---|---|
| `ISeqQueryClient` | `SeqQueryClient` | `AddHttpClient` (typed) |
| `IPlatformLogReader` | `PlatformLogReader` | Scoped |
| `ILogDetailService` | `LogDetailService` | Scoped |

---

## Sources

All paths relative to `{SpeedMerchantsRepo}`:

- `TestAuto.Web/Services/Logs/ISeqQueryClient.cs`
- `TestAuto.Web/Services/Logs/SeqQueryClient.cs`
- `TestAuto.Web/Services/Logs/SeqFilterBuilder.cs`
- `TestAuto.Web/Services/Logs/SeqEventParser.cs`
- `TestAuto.Web/Services/Logs/IPlatformLogReader.cs`
- `TestAuto.Web/Services/Logs/PlatformLogReader.cs`
- `TestAuto.Web/Services/Logs/PlatformLogQuery.cs`
- `TestAuto.Web/Services/Logs/ILogDetailService.cs`
- `TestAuto.Web/Services/Logs/LogDetailService.cs`
- `TestAuto.Web/Services/Logs/LogViewerServiceExtensions.cs`
- `TestAuto.Web/Models/Logs/SeqLogEvent.cs`
- `TestAuto.Web/Models/Logs/PlatformLogEvent.cs`
- `TestAuto.Web/Models/Logs/StepLogDetail.cs`
- `TestAuto.Web/Models/Logs/StepLogRequest.cs`
- `TestAuto.Web/Components/Controls/StepLogsDialog.razor`
- `TestAuto.Web/Components/Controls/StepLogsDialog.razor.cs`
- `TestAuto.Web/Components/Pages/Config.razor` (Clear Seq Log button)
- `TestAuto.Web/Components/Pages/Config.razor.cs` (`ClearSeqLog` method)

**Cross-links:** [[seq-query]] | [[profisee-logging-library]] | [[dotnet-logging-schema]]
