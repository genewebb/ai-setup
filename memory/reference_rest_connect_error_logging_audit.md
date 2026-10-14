---
name: reference-rest-connect-error-logging-audit
description: "Audit of outbound REST/Connect error handling in speed-merchants — which layers log failures, which silently swallowed them, and what was fixed 2026-07-31"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f1b61155-526e-4a83-8b2c-aa27ab714829
  modified: 2026-08-01T02:29:21.488Z
---

Full review of outbound REST + Connect error handling (2026-07-31). Verdict per layer:

**Already correct — use as reference implementations:**
- `TestAuto.Shared.Http/Facades/HttpClientFacade.GetGatewayResponseAsync` — reads the body and logs
  `HTTP {StatusCode} error calling {RequestUri}. Response body:` on non-success. The non-generic
  overload also returns the error as `{status, error}` so callers can surface it.
- `TestAuto.Matching/Helpers/MatchingApiStatusPoller` — the best example in the codebase: checks
  `IsSuccessStatusCode`, logs status + body per poll, and catches with logging.
- `TestAuto.Web/Services/ConnExApiClient` — reads body, logs on non-success, catches with logging.
- `TestAuto.Utilities/Executors/ConnExExecutor` — reads the body, runs `ConnExErrorParser`, and fails
  with the parsed detail. Its seven bare `catch` blocks are benign (parse helpers returning null, or
  deliberate dry-run best-effort), NOT silent failures.
- `TestAuto.Utilities/Executors/MonitorStepExecutor` — fine.

**Was broken, now FIXED:**
1. `TestAuto.Connect/Services/ConnectRestClient.GetAsync` — **logged nothing** on failure. Five public
   methods route through it (`GetBatchStatusAsync`, `FindLatestBatchByStrategyNameAsync`,
   `GetJobActivitiesByBatchCodeAsync`, `GetServiceProviderByName/UidAsync`), so every failing Connect
   GET was completely silent. The six POSTs always logged. Added the matching `!IsSuccess` log.
2. `ConnectRestClient.ParseResponseAsync` — its doc comment claimed parity with
   `HttpClientFacade.GetGatewayResponseAsync` but it is `static`, has no logger, and **dropped the
   logging**. Comment corrected to say callers must log.
3. `TestAuto.Connect/Scenarios/ConnectStrategyPollingScenario.PollUntilTerminalAsync` — read
   `ProcessingState` off the response **without checking `IsSuccess`**. A failure envelope has no
   ProcessingState → state null → classified unrecognized → warned ONCE (the warned-states HashSet
   dedupes) → loop spun to the deadline and reported **TimedOut**. Net effect: a 500-ing status
   endpoint looked like a slow batch, with zero log evidence (see #1). Now logs each failed poll with
   status + truncated body, and the give-up message states it was an endpoint failure. Outcome is
   still `TimedOut` deliberately — changing the enum would alter caller control flow.

**Envelope asymmetry — FIXED.** `ResponseBase` now carries `RawErrorBody`, populated by BOTH
`GetGatewayResponseAsync` overloads, so the typed envelope can surface a failure even though
`ResponseContent` must be null on error. Note `GetGatewayResponseAsync<T>` has **zero call sites** —
the asymmetry was latent. The live sibling was worse: `RecordDataFacade.PutMatchAsync` ran the error
body straight through `DeserializeObject<MatchResponse>` with no status check and no logging above
Verbose, so a failed match looked like a match with no results. It now returns early on non-success
with `RawErrorBody` set and logs at Error. (`PutMatchAsync` also has no production callers — only
`RestClient.PutMatchAsync` delegating, plus a test stub.)

**207 partial-success — FIXED (2026-07-31).** Scan of all 426 stored configs:
- **No ConnEx step whitelists 207** (they use `200,202`) — that risk was theoretical.
- **34 HTTP steps across 9 workflows DO whitelist 207** (`10000137/141/143/144/145/149/151/152/156`).
  `DetermineSuccess` did a bare `Contains(207)` → a half-completed bulk delete reported green.
  Now `HasMultiStatusFailures` parses the body via `ConnExErrorParser` and fails the step when any
  per-item error is present. **Gated on status 207 alone** — running the parser over every 2xx would
  misread healthy bodies carrying a `message` field and turn working steps red.
- Also added `WarnOnErrorStatusWhitelist`: warns when `expectedStatusCodes` contains a 4xx/5xx beyond
  the legitimate 404 delete-if-exists idiom.

**CRITICAL GOTCHA — TestAuto cannot currently observe a 207.** `TestAuto.Utilities` issues
`Invoke-RestMethod`, which does NOT surface the status code on success. A 207 is 2xx → no throw →
no status marker → `ParseHttpStatusCode` returns null → `DetermineSuccess` falls to exit code 0 →
pass. **So `ExpectedStatusCodes` is unenforceable for ANY success response in TestAuto, and those 34
entries are decorative there.** CrewChief uses `Invoke-WebRequest` + an `HTTP_STATUS_CODE:` marker,
so the check engages there today. Porting that marker to TestAuto would activate it — but would also
make `ExpectedStatusCodes` enforceable for 2xx for the first time, changing pass/fail for every HTTP
step. Deliberately NOT done; needs its own decision.

**Two self-inflicted bugs the new tests caught** (worth remembering): (1) the `HTTP_STATUS_CODE:`
marker line prefixes stdout, making the body invalid JSON so the parser silently returned no errors —
needed `StripStatusMarker`; (2) `ExtractErrorMessage` overwrote the 207 detail with
"HTTP 207 error (no details available)" — the assignment is now guarded on `ErrorMessage` being empty.

**TRANSPORT STATUS ≠ SEMANTIC STATUS (2026-08-01) — the most reusable lesson here.** Deleting a
Connect service configuration that does not exist returns **HTTP 400** on the wire, while the body
says:
```json
[ {"errors":{"<guid>":["ID \"[<guid>]\" not found"]},"type":".../CNX00006",
   "title":"Request Failed","status":404,"detail":"Service Configuration not found"},
  {"errors":{"error0":["8602 : Cannot perform this operation because the member does not exist. RecordCode: <guid>"]},
   "type":".../CNX00019","title":"Data Access Failure","status":400,
   "detail":"One or more errors occurred during a data Delete operation."} ]
```
Two fixes, in BOTH products:
1. `ConnExErrorParser` was blind to this shape — root is a JSON **array** and `errors` is an
   **object** (key → messages). It only handled a JObject root with `errors` as an array, so it
   returned EMPTY and callers dumped raw JSON. Now parses both, and the RFC7807 `title`/`detail`
   fallback fires only when an object yielded nothing more specific, so "Request Failed" can never
   displace the real `8602`. New `TryGetSemanticStatusCodes` returns the body's declared statuses.
2. `MatchesSemanticStatus` in both `PowerShellRestExecutor`s: when the transport status is NOT
   whitelisted, the body's own status is checked against `ExpectedStatusCodes`. A step tolerating 404
   now passes on a transport-400-with-body-404, and always logs the reconciliation. This is
   deliberately narrower than whitelisting 400, which would swallow every genuine malformed request.

**REGRESSION I CAUSED AND FIXED — read before applying blanket status rules.** The Layer 3 rule
"drop 400, a 400 is never a partial success" broke workflow step 4
("Delete Connect Service Configuration for Model Source"): it had passed in execution `10000164` and
failed in `10000165`, because for that endpoint **400 IS how not-found is reported**. The 400 was
whitelisted deliberately, not by mistake. Resolution was the semantic-status reconciliation above,
NOT re-adding 400. Lesson: a status code's meaning is endpoint-specific — verify why a code is
whitelisted before removing it.

**Bad configs repaired (data, 2026-07-31):** dropped `400` from 4 inline step configs
(`10000145 ord 4`, `10000149 ord 4`, `10000151 ord 15`, `10000156 ord 4` — all
"Delete Connect Service Configuration for Model Source"), `[200,201,204,207,400,404]` →
`[200,201,204,207,404]`. Done with a **surgical text edit inside a transaction**, NOT parse-and-
re-serialize — re-serializing a whole config to change four characters is how silent corruption
happens; the script proves only `expectedStatusCodes` differs before writing
(`scratchpad/fix-expected-status.ps1`).
**STILL OPEN:** 3 steps whitelist **only 404**, so a *successful* delete FAILS them —
`10000143 / 10000144 / 10000152` ord 1 substep 2. They are CHUNKREF-backed and must be fixed through
the step editor, not a direct write.

Regression tests added: `Poll_WhenStatusEndpointReturnsError_KeepsPollingToDeadline_ThenTimesOut` and
`Poll_WhenStatusResponseIsNull_DoesNotThrow_AndTimesOut` in
`Testing.SpeedMerchants.Unit/Tests/Connect/ConnectStrategyPollingScenarioTests.cs`.

Verified: 768 passed / 1 skipped across the full TestAuto unit suite; TestAuto.Connect and
TestAuto.Web build 0/0. Companion fix: [[project_synonymlist_put_400_26r2]] (HTTP executors).
