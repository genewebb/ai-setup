---
name: seq-query
description: >
  Query the local Seq log server (http://localhost:5341) for structured speed-merchants
  log events via its HTTP API. Use when investigating logs, looking up [TAG] events
  (LogTag), a RequestId/TraceId, errors/warnings, or a time window in Seq instead of
  asking the user to paste log dumps. Also covers clearing/deleting Seq events via the
  write API. Pairs with dotnet-logging-schema and testauto-log-tags.
---

# Seq Query

> **Scope**: speed-merchants — local Seq instance at `http://localhost:5341` (Seq 2025.2).
> **Script**: `{PowershellScriptsDir}\seq-query.ps1`

speed-merchants logs to Seq (Serilog Seq sink). This skill queries Seq's `GET /api/events`
endpoint so log investigation happens directly instead of via pasted dumps.

## Prerequisite (one-time): a read-only API key

Seq requires an API key for queries (a bare request returns **401**). Create one:

1. Open `http://localhost:5341`, sign in as **Admin**.
2. **Settings → API Keys → Add API Key**. Give it a name (e.g. `claude-read`) and grant
   only the **Read events** permission (no ingestion needed).
3. Copy the token and set it as an environment variable:

```powershell
setx SEQ_API_KEY "<the-token>"
```

(Open a new shell after `setx`.) Optionally set `SEQ_SERVER_URL` to override the default
`http://localhost:5341`.

## Usage

Run the script with the parameter set that matches the investigation:

```powershell
pwsh -File "{PowershellScriptsDir}\seq-query.ps1" -Tag HTTP_REQUEST -LastMinutes 30 -Count 20
```

```powershell
pwsh -File "{PowershellScriptsDir}\seq-query.ps1" -Level Error -LastMinutes 120
```

```powershell
pwsh -File "{PowershellScriptsDir}\seq-query.ps1" -RequestId "0HNLTS26E27BF:00000009"
```

```powershell
pwsh -File "{PowershellScriptsDir}\seq-query.ps1" -Filter "MachineName = 'CORPLTR94' and @Level = 'Warning'" -Count 50
```

### Parameters

| Param | Purpose | Default |
|---|---|---|
| `-Tag` | Shortcut filter on `LogTag = '<value>'` (see testauto-log-tags) | — |
| `-Level` | Shortcut filter on `@Level` (Information/Warning/Error/Fatal/…) | — |
| `-RequestId` | Shortcut filter on `RequestId = '<value>'` | — |
| `-Filter` | Raw Seq filter expression (combined with the shortcuts via `and`) | — |
| `-LastMinutes` | Time window back from now (sets `fromDateUtc`) | 60 |
| `-Count` | Max events returned | 50 |
| `-ServerUrl` | Seq base URL | `$env:SEQ_SERVER_URL` or `http://localhost:5341` |
| `-ApiKey` | Read API key | `$env:SEQ_API_KEY` |
| `-Raw` | Emit raw event JSON instead of the formatted summary | off |

## Seq filter syntax (quick reference)

- Property equality: `RequestId = '...'`, `MachineName = 'CORPLTR94'`, `LogTag = 'HTTP_REQUEST'`
- Level: `@Level = 'Error'` (or `@Level in ['Error','Fatal']`)
- Message text: `@Message like '%timeout%'`
- Combine: `LogTag = 'MATCHING' and @Level = 'Warning'`

## Clearing events (write operation)

To delete events call `DELETE {seqUrl}/api/events/signal` with a JSON body. Seq **requires** the
body — a bodyless request returns HTTP 400 ("The body of the request should contain a JSON object").

### Body shape

| Body | Effect |
|---|---|
| `{"Filters":[]}` | Matches **all** events — clears everything |
| `{"Filters":[{"Filter":"@Level = 'Debug'"}]}` | Matches only events that satisfy the filter |

### Optional query params to scope by time

| Param | Purpose |
|---|---|
| `fromDateUtc` | ISO-8601 UTC lower bound (inclusive) |
| `toDateUtc` | ISO-8601 UTC upper bound (exclusive) |

A window that matches nothing (e.g. `fromDateUtc=1990-01-01T00:00:00Z&toDateUtc=1990-01-02T00:00:00Z`)
is a safe non-destructive probe to test auth/body shape without deleting real events.

### Permission gotcha

There is no "Erase" permission in Seq. The API key needs **Write**; a read-only key returns 403.
The `claude-read` key created above (Read events only) **cannot** clear events — a separate key
with Write permission is required.

### PowerShell example

```powershell
$headers = @{ "X-Seq-ApiKey" = $env:SEQ_WRITE_API_KEY; "Content-Type" = "application/json" }
Invoke-RestMethod -Method Delete -Uri "http://localhost:5341/api/events/signal" `
    -Headers $headers -Body '{"Filters":[]}'
```

### In-app C# path

`ISeqQueryClient.ClearAllEventsAsync()` — `TestAuto.Web/Services/Logs/SeqQueryClient.cs`.
Sends `DELETE api/events/signal` with body `{"Filters":[]}` (empty Filters = all events).
Surfaced in the UI on the **Config / Settings** page as the "Clear Seq Log" button.
See also: [[testauto-log-viewer]].

## Notes

- The script bounds the scan with `fromDateUtc` (the `-LastMinutes` window) + `count`, so
  filtered queries don't scan the entire store.
- On `401` it prints guidance to create/fix the read API key; on other failures it surfaces
  the HTTP status and the filter used.
- The PS query script is read-only. Clearing events is a separate, explicit, key-gated operation
  (documented above) that requires a Write-permission API key distinct from the read-only query key.
