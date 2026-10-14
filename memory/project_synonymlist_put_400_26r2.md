---
name: synonymlist-put-400-26r2
description: "PUT /rest/v1/SynonymList payload that worked on 26.1.0 (204) is rejected 400 by the 26R2 gateway before it forwards to the Matching service — likely a 26R2 contract change, not a payload authoring error"
metadata: 
  node_type: memory
  type: project
  originSessionId: f1b61155-526e-4a83-8b2c-aa27ab714829
  modified: 2026-08-01T00:25:25.792Z
---

Workflow **10000156 "Matching 100K Test"**, step 16 `Add SynonymLists for Retail Client`
(`CurlStep`, `PUT {{$config:RestClients:Matching:BaseUrl}}{{ApiVersion}}/SynonymList`) fails
**HTTP 400** on the 26R2 instance (2026-07-31, execution `10000164`).

**Same call demonstrably worked before the 26R2 upgrade.** From IIS `W3SVC1` logs:

```
2026-06-17 14:30:12  PUT /profisee/api/matching/v1/synonymLists  200  cs-bytes=20999  258ms
2026-06-17 14:30:12  PUT /profisee/rest/v1/SynonymList           204  cs-bytes=34384  269ms
2026-07-31 19:03:12  PUT /profisee/rest/v1/SynonymList           400  cs-bytes=34361   36ms
```

Payload is essentially identical (34,384 vs 34,361 bytes). On 26.1.0 the gateway accepted it (204)
**and forwarded internally** to `/profisee/api/matching/v1/synonymLists` (the paired 200 — the two
IIS lines at the same second are the external call plus the gateway's internal forward). On 26R2
there is only ONE log line: the gateway **rejects at its own validation in 36ms and never forwards**,
which is why neither the Gateway nor Matching `SystemLog.log` contains any entry.

`sc-status=400, sc-substatus=0, sc-win32-status=0` = application-level rejection, not IIS filtering.
`sc-bytes=823` — the gateway returned an 823-byte body (almost certainly `ValidationProblemDetails`
naming the failing field) which `PowerShellRestExecutor` **discarded**; the step surfaced only
`(400) Bad Request`.

**DECISIVE (2026-08-01 00:19:57 UTC): the payload and the endpoint are EXONERATED.** Replaying the
byte-equivalent payload with a plain `Invoke-RestMethod` **succeeded**:
```
00:19:57  PUT /profisee/api/matching/v1/synonymLists  200  cs-bytes=20838  3128ms
00:19:57  PUT /profisee/rest/v1/SynonymList           204  cs-bytes=34390  3213ms   <- same paired
                                                                                        signature as the
                                                                                        working June runs
```
and all **7 lists were really created** — verified in `matching.tSynonymLists` (Country, DateOfBirth,
MaestroDefault, SSAN, Address, City, Email, all stamped 00:19:57). So MaestroDefault-already-exists is
conclusively NOT the cause; the gateway happily overwrites it.

**The fault is therefore in how the EXECUTOR transmits the request, not in what is being sent.**
Same endpoint, same ~34KB payload: executor → 400 in 36ms; plain IRM → 204 in 3213ms. The 36ms says
the gateway rejected it at model binding before doing any work. Remaining suspects are transmission-
level: the missing `accept` header (the step config sets only Content-Type + x-api-key), PS 5.1's
default non-UTF-8 body encoding when the ContentType carries no `charset`, or something the
generated-command path does to the body. NOT yet proven — the 823-byte error body is still the answer,
and only the executor's own request reproduces it, so the enhanced logging must run.

**TWO STORES — do not confuse them:** synonym lists live in **`matching.tSynonymLists`** (Profisee
entity, `Code` = the list UID). `meta.tMatchingSynonymType` / `meta.tMatchingSynonym` is a separate,
older structure that held only `MaestroDefault` (17 rows, untouched) and did NOT reflect the create.
Querying the meta tables to verify a synonym operation gives a false negative.

**Hypotheses tested and FALSIFIED (do not re-run these):**
1. *Token resolution* — ruled out. IIS shows the URL resolved to `/profisee/rest/v1/SynonymList`;
   `UtilityOrchestrator` merges GlobalParameters into step params (~line 171-181), so the step's
   empty `parameters: {}` is harmless and `{{ApiVersion}}`→`v1` resolved.
2. *MaestroDefault already exists / is system-owned* — ruled out. PUT is overwrite semantics; a
   conflict would be 409 and the six deleted lists would be 404, not a 36ms 400. (User raised this
   correctly.)
3. *Whitespace-only or empty `replacementTerm` failing `[Required]`* — ruled out empirically. The
   live `meta.tMatchingSynonym` rows the system already accepted include 4 whitespace-only and 13
   empty replacement terms. NOTE the column mapping is inverted vs the payload: DB `Term` = payload
   `replacementTerm`, DB `Synonym` = payload `searchTerm`.

**Still unexplained / next step:** capture the 823-byte response body (re-issuing the PUT is safe —
it 400s at validation and changes nothing). Payload oddity worth checking once the real error is
known: MaestroDefault carries **17 exactly-duplicated** `searchTerm|replacementTerm|searchInString`
keys out of 119 entries (e.g. `-`→` `, searchInString=True, seven times); the other six lists have
zero duplicates.

**Executor defect FIXED 2026-07-31** in `TestAuto.Utilities/Executors/PowerShellRestExecutor.cs`
(build clean). Root cause proven by local repro: under Windows PowerShell 5.1 `Invoke-RestMethod`
has already drained the response stream before the `catch` runs, so `$ex.Response.GetResponseStream()`
returns nothing — the old wrapper's only capture path. **The body is in `$_.ErrorDetails.Message`.**
Changes: (1) wrapper checks `ErrorDetails.Message` first, stream as fallback, and probes for a
`.Response` property instead of testing `[System.Net.WebException]` so PS7's `HttpResponseException`
also works; (2) body emitted as `HTTP_ERROR_BODY_B64:` (single-line base64) because a body with
newlines broke the line-oriented marker parsing; (3) body decoded from the UNTRUNCATED stdout before
the 4000-char metrics cap, which previously sliced it mid-payload; (4) new
`StepExecutionResult.HttpResponseBody` (in-memory only — deliberately NOT added to the persisted
metric projection, which would need a new Profisee attribute under the 4000-char ceiling);
(5) full body logged verbatim, `ErrorMessage` cap raised 500→2000; (6) the curl fallback path
previously set **no `ErrorMessage` at all** — now composes one; (7) `Elapsed: 0ms` fixed (it read
`result.ElapsedMs` before the `finally` assigned it).
**Applied to BOTH products (2026-07-31).** Four executors carried the defect and all four are fixed:
`TestAuto.Utilities/Executors/{PowerShellRestExecutor,CurlExecutor}.cs` and
`CrewChief.Engine/Executors/{PowerShellRestExecutor,CurlExecutor}.cs`, plus a `HttpResponseBody`
property on *both* (separate, same-named) `StepExecutionResult` types. The two `CurlExecutor`s were
worse than the REST ones — their HTTP failure path set **no `ErrorMessage` at all**, so a failed curl
step reported an empty reason; they now compose one via a new `BuildFailureMessage` helper (curl
writes the response to stdout, so stdout *is* the payload). CrewChief's `CurlStep` has no `Url`
property (HTTP/Curl split) — log the `Command` instead. Doc updated:
`CrewChief.Web/Documentation/11_StepGuideHttp.md`.

**Regression tests** in `CrewChief.Tests.Unit/Engine/PowerShellRestExecutorTests.cs` against the
in-process `LoopbackHttpServer`: `ExecuteAsync_ErrorResponse_CapturesServerResponseBody` and
`ExecuteAsync_MultiLineErrorResponseBody_IsCapturedWhole`. NOTE the pre-existing
`ExecuteAsync_NonSuccessStatus_ReturnsFailureWithErrorMessage` did NOT catch this bug — it asserts
only that `ErrorMessage` is non-empty, and the generic "(400) Bad Request" satisfied that. Always
assert on payload *content*.

Verified: 235 TestAuto unit + 49 CrewChief unit passing; TestAuto.Utilities, CrewChief.Engine,
TestAuto.Web and CrewChief.Web all build 0 warnings / 0 errors.

**Executor defect (recurring):** the HTTP executor's `HTTP_ERROR_BODY:` capture is not firing, so
gateway error detail is systematically lost — second occurrence in one session (see
[[project_matching100k_step14_curl_paste_body]]). SQL steps already got the equivalent fix
(`PassFailErrorDetail`); the HTTP path never did.

Related: [[reference_synonymlist_delete_and_baseurl]] (DELETE uses query-string UIDs, returns 207 —
that step still works), [[reference_matching_api_offgateway_baseurl]].
