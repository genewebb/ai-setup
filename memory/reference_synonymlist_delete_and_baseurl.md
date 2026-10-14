---
name: reference_synonymlist_delete_and_baseurl
description: "How to delete Profisee SynonymLists via a MultiStep HTTP step, and the BaseUrl-already-includes-/rest/ gotcha"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f8456019-65c7-46f7-a381-c7e1862e711e
---

Deleting Profisee SynonymLists from a MultiStepUtilityScenario HTTP step (verified working on CORPLTR94 local, 2026-06-04, workflow "Cleanup Before Matching Run"):

- **Method:** `DELETE` (not PATCH/PUT). UIDs go in a **query string**, NOT a body — `?synonymListUids=<comma-separated GUIDs>`. No request body. Success = **207** Multi-Status (whitelist `[200,201,204,207]`; add `404` if you want to tolerate already-deleted lists).
- **The 6 RetailClient synonym-list UIDs:** Email `56aeb6d6-2ec7-46db-9a69-1445264cd32c`, City `5102c04f-f91b-4634-9db0-273c1d399ca0`, Address `2d4b8f18-95ce-4b9c-964d-411847d2ce3e`, SSAN `ad59dd8e-0442-4659-9fa7-572ee053ff74`, DateOfBirth `2b12e411-8911-4c9c-a827-d517a5aafcb0`, Country `9f08c78c-8f85-4c28-bb0d-fc4b296e76e7`.

**BaseUrl gotcha (cost the most time):** `{{$config:RestClients:Profisee:BaseUrl}}` resolves to a URL that **already ends in `/rest/`** (e.g. `https://corpltr94.corp.profisee.com/profisee/rest/`). So step URLs must be `{{$config:RestClients:Profisee:BaseUrl}}v1/...` — do NOT prepend `rest/` (doing so gives `/rest/rest/...` → 404). This contradicts the `testauto-multistep-steps` skill examples and the in-repo `RetailClientAddSynonymList.curl` template (both write `{{BaseUrl}}rest/v1/...`), which are inconsistent with this secret value. Always verify the resolved URL with a read-only GET probe before assuming the prefix.

**Diagnosis tips for these runs:** workflow/step results live in the MDM DB entities `data.vTestAutoWorkflowExecution` / `vTestAutoWorkflowExecutionDetail` (and step config in the compressed `ScenarioConfiguration` blob); per-step `vTestAutoUtilityExecution`/`vUtilityMetrics` are NOT populated. The executor's real per-request error (`PowerShell Invoke-RestMethod execution failed. Status: {code}...`) is in local Seq under `[SQL_SCRIPT]`, but only when the run executes locally — deployed perf-VM runs log to that VM's own Seq, and the prod SQL sink (`logging.tSystemLog`) is the Profisee platform log, not TestAuto's. See [[reference_scenariomgt_db]] and [[project_repos]].

**HTTP step editor note:** `HttpRequestStepEditorCard` only shows the Body field for POST/PUT/PATCH (`IsBodyAllowed`). For DELETE there's no body field — correct, since query-string params go in the URL field anyway. The `CurlStep.Body`/executor support a DELETE body, only the editor hides it.

Recurring trap: pasting the long single-line URL wraps and injects whitespace into a GUID (e.g. `9f08c78c` → `9f08c78  c`) → 404. Re-check the URL has zero internal whitespace before each run.
