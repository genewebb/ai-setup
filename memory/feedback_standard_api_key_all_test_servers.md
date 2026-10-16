---
name: feedback-standard-api-key-all-test-servers
description: "ANY time a Profisee REST/API key is set or chosen for a test server, use C:\\Deploy\\Secrets\\StandardApiKey.txt (never invent/keep another test key)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 62facdb4-e40f-4ba8-8baa-0e03f6026148
  modified: 2026-10-15T02:18:53.630Z
---

Gene 10/14: "Use that key anytime you need to set a rest key." The standard API key for ALL test servers is in `C:\Deploy\Secrets\StandardApiKey.txt` (laptop). It is what every other secrets file stores as `RestKeys:ProfiseeRestKey` (and `UserCredentials:AdminClientId` on SMVMTR1).

**Why:** my connect secrets builder had carried a different "test key" into `RestKeys:ProfiseeRestKey`, so `26r3-set-apikey` / `connect-api-key-set-main` wrote a non-standard key onto SMVM1.

**How to apply:** any SetApiKey step, secrets builder, or gateway call that needs a Profisee key → read StandardApiKey.txt (never print it). `Build-ConnectSecrets.ps1` now sets ProfiseeRestKey from it and ProfiseeToProfiseeRestKey = `{{RestKeys:ProfiseeRestKey}}`. Related: [[project_crewchief_connect_restructure_2026-10-13]] [[reference_profisee_gateway_401_echoes_api_key]]
