---
name: matching-api-status-poller
description: >
  MatchingApiStatusPoller in TestAuto.Matching for polling the Profisee Matching API
  IdleStatus endpoint to wait for strategy completion. Use when implementing matching
  scenario wait logic, understanding the OAuth client_credentials flow for the Matching
  API, reasoning about how often a token is actually fetched across a long poll loop
  (OAuthTokenProvider's in-instance cache and its 5-minute expiry margin), configuring poll interval
  and timeout, or replacing the legacy SQL-based MatchingStrategyCompletionHelper.
---

Repo: speed-merchants (paths below are repo-relative)

# Matching API Status Poller

> **Scope**: speed-merchants (TestAuto.Matching)
> **Source**: `TestAuto.Matching/Helpers/MatchingApiStatusPoller.cs`

`MatchingApiStatusPoller` replaces the legacy SQL-based `MatchingStrategyCompletionHelper`. It polls the Profisee Matching API's `IdleStatus` REST endpoint using OAuth Bearer authentication to determine when a matching strategy has finished processing.

---

## Endpoint

```
GET {baseUrl}/api/matching/v1/strategies/{strategyName}/IdleStatus
```

Response body is plain text: `"Idle"` or `"NotIdle"`.

---

## Constructor

```csharp
var poller = new MatchingApiStatusPoller(
    baseUrl:      "https://host/Profisee",   // TrimEnd('/') applied automatically
    clientId:     matchingSubjectArea.RestApiKey,
    logger:       logger,
    scenarioName: "MyMatchingScenario"       // Optional — used for log tag context
);
```

- `clientId` is the `RestApiKey` from the **Matching subject area override** (not the global API key).
- A new `HttpClient` is created internally with a self-signed cert bypass (`DangerousAcceptAnyServerCertificateValidator`). Acceptable for internal/dev environments.
- `HttpClient.Timeout` is 30 seconds per request.

---

## `WaitForIdleAsync`

```csharp
bool isIdle = await poller.WaitForIdleAsync(
    strategyName:        "MyMatchingStrategy",
    pollIntervalSeconds: 30,    // default: 30
    maxWaitSeconds:      3600,  // default: 3600 (1 hour)
    cancellationToken:   ct
);
```

Returns `true` if the strategy reached `Idle` within `maxWaitSeconds`, `false` on timeout.

**Polling behavior:**
1. Calls `_tokenProvider.GetAccessTokenAsync(...)` on **every** poll (`client_credentials` grant, scope = `"ProfiseeAPI"`, endpoint = `{baseUrl}/auth/connect/token`) — `MatchingApiStatusPoller.cs:92-93`. This is *not* a fresh network round-trip each time: the `OAuthTokenProvider` is constructed once in the poller's constructor (`MatchingApiStatusPoller.cs:56`) and caches the token in-instance, returning it immediately while `DateTime.UtcNow < _tokenExpiry` (`TestAuto.Shared.Http/Rest/OAuthTokenProvider.cs:54-55`, re-checked under lock at `:61-62`). Expiry is set to `expires_in` **minus 300 seconds** (`OAuthTokenProvider.cs:94`), so with the default 30 s poll interval and a typical hour-long token only the *first* poll hits the token endpoint; every later poll is a cache hit until ~5 minutes before expiry.
2. Sends `GET IdleStatus` with `Authorization: Bearer <token>`
3. If response is `200 Idle` → returns `true`
4. If non-success HTTP status → logs warning, continues polling
5. On exception (non-cancellation) → logs error, continues polling
6. On timeout → logs warning, returns `false`

---

## Logging

All activity is logged under `LogTagConstants.ForScenario(scenarioName)`. Log levels:
- `Information` — poll start, Idle reached, per-poll success status
- `Debug` — per-poll token acquisition and status check
- `Warning` — non-2xx responses and the final timeout
- `Error` — exceptions during a poll attempt

---

## Integration Point

Invoked from `MatchingStrategyPollingScenario.ProcessBatchAsync`, which constructs the poller and calls `poller.WaitForIdleAsync`. The scenario resolves the `baseUrl` via `ResolveMatchingEndpoint` and the `clientId` from its matching subject area configuration.

---

## Sources

- `TestAuto.Matching\Helpers\MatchingApiStatusPoller.cs`
- `TestAuto.Shared.Http\Rest\OAuthTokenProvider.cs` (token acquisition + in-instance cache)
