---
name: reference-scenariomgt-rest-writes-prod-4000-limit
description: "ScenarioMgt REST https://profiseecloud.dev/speedmerchantstest/rest/ writes the PROD TestAuto DB; config >4000 chars stored NULL silently; CrewChief {% %} escape for TestAuto tokens"
metadata:
  node_type: memory
  type: reference
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T15:47:40.856Z
---

Facts verified 11/05/2026 while building matching pack workflow 10000371:

- `https://profiseecloud.dev/speedmerchantstest/rest/` is the REST front of the PROD TestAuto DB (wus2-pc-profisee-sqlserver-0). Same newest workflow via REST and via PROD SQL. `.../speedmerchants/rest/` returns 404. The name "test" misleads; Gene said that instance "is not even up" but the REST answers.
- `TestAutoWorkflowDetail.ScenarioConfiguration` holds 4000 chars. A longer value PATCHed via REST returns success and is stored **NULL** (no error). Compact the JSON or use TestAuto's CHUNKREF path. Matching pack generator asserts <=4000.
- A CrewChief workload that writes TestAuto step configs must not let CrewChief resolve TestAuto runtime tokens (`{{$config:...}}`, `{{STEP:n}}`): CrewChief would substitute its own secret. Matching pack writes them as `{%...%}` and the PowerShell step swaps back to `{{ }}` before upsert.

Related: [[feedback_no_machine_names_in_comments]], [[reference_testauto_prod_sql_server]].
