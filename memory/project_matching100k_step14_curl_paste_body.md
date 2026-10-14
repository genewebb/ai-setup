---
name: matching100k-step14-curl-paste-body
description: "Workflow 10000149 'Deploy Retail Model Attributes' step 14 body holds a pasted Swagger curl command instead of the JSON array -> gateway 400; the delete steps were innocent"
metadata: 
  node_type: memory
  type: project
  originSessionId: f1b61155-526e-4a83-8b2c-aa27ab714829
  modified: 2026-07-31T17:50:42.112Z
---

Workflow **10000149** "Matching 100K Template Full Workflow (COPY DO NOT UPDATE)" (execution
`10000182`, 2026-07-31) fails at **step 14 "Deploy Retail Model Attributes"** with
`HTTP 400: The remote server returned an error: (400) Bad Request.`

**Root cause:** the step's `body` is not a JSON array — it is an entire pasted
**Swagger "Copy as cURL" command**:

```
curl -X 'POST' \
  'https://corpltr94.corp.profisee.com/Profisee/rest/v1/Attributes' \
  -H 'accept: application/json' \
  -H 'x-api-key: <literal key>' \
  -H 'Content-Type: application/json-patch+json' \
  -d '[ ...40 attributes... ]'
```

The step is `useRestMethod: true`, so `Invoke-RestMethod` POSTs that literal text as the request
body → gateway 400. The real payload is the 52,127-char array inside `-d '...'` (parses clean,
**40 attributes**). Fix = replace `body` with only that inner array. The bug is in the **template**
(10000149), not just the execution copy, so every copy inherits it.

**The delete steps were NOT the problem** (this was the initial suspicion). Step 5 "Delete
RetailClient and Associated Entities" really did delete. Proof from the target `profisee` DB:
`data.tRetailClient` / `tGender` / `tMatchStatus` / `tSource System` all have
`sys.tables.create_date = 2026-07-31 11:58:10` — i.e. created by **step 13** ("Deploy Retail Model
Entities", 15:58:05–15:58:12 UTC), 8 minutes AFTER the deletes at 15:50. The entities visible in the
model when step 14 fails are step 13's fresh creations, not delete leftovers. `data.tRetailClient`
has only the 13 system columns, confirming zero attributes landed.

**Reading `Status: null` in PowerShellRestExecutor logs** — `Status: null` + step success is
*proof of a 2xx*, not of a skipped call: the PS wrapper catches every non-2xx, emits
`HTTP_ERROR_STATUS:<code>` and `exit 1`, so any 4xx/5xx yields a parsed status. Null status can
only reach `DetermineSuccess` via exit code 0.

**Collateral issues found in `TestAuto.Utilities/Executors/PowerShellRestExecutor.cs`** (and the
CrewChief twin `CrewChief.Engine/Executors/PowerShellRestExecutor.cs`):
- `Elapsed: 0ms` is always logged — `result.ElapsedMs` is assigned in the `finally` block (~line 211)
  AFTER the success/failure log statements (~lines 161-172) read it. Per-step timing is unusable;
  only the scenario-level `Duration: Nms` line is real.
- The gateway's 400 response body was lost (no `HTTP_ERROR_BODY:` marker), so the message is the
  generic `(400) Bad Request` — same swallow described in [[project_model_import_reserved_code_name]].
- The delete steps list **404 in `expectedStatusCodes`**, so a missing route / wrong identifier form
  would pass silently. Latent, did not bite here.

**Re-importing from production does NOT fix it (verified 2026-07-31).** Workflow **10000162
"Matching 100K Test Production"** — a fresh production import — carries the *identical* 52,364-char
curl-paste body in its step 14. A CustomParms-level diff of all 58 steps against 10000149 shows
**zero functional differences**; the only deltas are `ScenarioEnvironment` targeting
(`SMVM3`/`26R2` vs `SMVM2`/`26R2PV2`), which accounts for the uniform ~5-char length shift per step.
So production itself holds the corrupted body — this is not a stale-copy problem.

**The one clean copy is local:** the reusable library scenario `Deploy Retail Model Attributes`
(`SCN_20260319211313_b5bdfe1d`, tTestAutoScenarios ID 34) has a valid 52,125-char JSON body,
semantically identical (40 attributes) to the payload trapped inside the curl `-d '...'`. Fix any
workflow by re-pulling step 14 from that scenario rather than re-importing.

**Full-corpus sweep after the production model+data reimport (2026-07-31, 364 workflow steps +
62 library scenarios):**
- **8 workflows** carry the identical 52,364-char curl-pasted `Deploy Retail Model Attributes`
  body: `10000134, 10000135, 10000141, 10000144, 10000145, 10000149, 10000152, 10000156`.
- Production's **library scenario `Deploy Retail Model Attributes` (`SCN_20260319211313_b5bdfe1d`)
  is CLEAN** — 52,125 chars, valid, 40 attributes — and normalized-matches the copy salvaged to
  `C:\tmp\lib-attrs-body.json`. So an authoritative clean source exists in-band; the corruption is
  confined to workflow step snapshots.
- **Second, unrelated corruption found:** library scenario `Deploy Retail Client Matching Strategy`
  (`84c9f052-613a-4496-b56a-1f455cb4a0e4`) holds a pasted `curl -X 'PUT'` body (17,915 chars) for
  `v1/Matching/strategies`. Latent — no workflow references it; workflows use the clean
  `Deploy RetailClient Master Matching Strategy` (`2ad40058-ac9a-4cfd-bfd0-7d2627aa3641`,
  17,717 chars, valid). Same wrapper-vs-payload size ratio, so same paste mistake.

**Fix scope is one field.** Diffing workflow 10000156 step 14 against the clean scenario: every HTTP
step field (`url`, `method`, `headers`, `expectedStatusCodes`, `parameters`, `timeoutSeconds`,
`useRestMethod`, …) is *identical*; only `body` differs. `ScenarioEnvironment` differs by design
(workflow carries env targeting). So the repair is a single `body` string replacement — do NOT
re-pull the whole scenario or the env targeting gets clobbered.

**Writing the fix:** persist through the app (`ScenarioConfigStore.PersistAsync`), not by hand-editing
`tTestAutoScenarioConfiguration` chunks — the store's whitespace-safe chunk splitting exists to avoid
the boundary-trim corruption in [[project_chunk_boundary_whitespace_trim]].

**Secret exposure:** the pasted curl body contains a literal `x-api-key` value and a hardcoded
`corpltr94.corp.profisee.com/Profisee/` URL stored in the ScenarioMgt DB config. Rotate when fixing.

Related: [[reference_scenariomgt_db]], [[feedback_verify_no_guessing]],
[[project_metadata_model_import]].
