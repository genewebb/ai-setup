---
name: project_crewchief_connex_import_tests
description: "CrewChief ConnEx live import tests — where they live, how they self-provision and clean up, and the gated config keys they need"
metadata: 
  node_type: memory
  type: project
  originSessionId: b085d44c-6642-41f4-9aca-4ff12d6dc36e
  modified: 2026-08-16T03:03:24.033Z
---

Added 2026-08-15. `CrewChief.Tests.Integration/Engine/ConnExImportIntegrationTests.cs`, category `Integration` + **`ConnExLab`** (mirrors the existing `RemoteLab` convention). Four tests, all green against CORPLTR94, run twice back-to-back with zero residue.

- `RawPortalExport_IsRefused_AndCreatesNothingOnTheInstance` — the regression for the credential bug; also asserts the instance's config list is unchanged, so the refusal creates nothing.
- `RefusedImport_DoesNotLeakTheSecretIntoTheErrorMessage` — step errors reach run history and Seq.
- `TokenizedArtifacts_DeployEnableExecute_AndImportRecords` — the full path, asserting each of the 5 steps individually, that the batch reached terminal **Succeeded** (not merely stopped being polled), that ConnEx issued its own `vaultId` per credential, and that records actually landed in `PDATA120`.
- `Teardown_DeleteOfAnAbsentResource_IsTolerated` — the 404-tolerant teardown.

**Artifacts now live in the repo**: `CrewChief.Tests.Integration/TestData/ConnEx/ModelSource.serviceconfiguration.json` and `ModelSourceImport.integrationstrategy.json` (copied from `c:\tmp\connecttest`, csproj copies `TestData\**\*`). Tests no longer depend on a machine-local path — unlike the Unit suite's `ConnExTokenization` tests, which still read `C:\tmp\ConnectExports` and `Assert.Fail` when it is missing.

**Atomicity approach worth reusing:** each test rewrites the sample Ids/names to unique values (`_CCIT<12 hex>`), so the originals deployed on the instance are never touched. Record cleanup deletes only codes present in an **after**-snapshot but absent from a **before**-snapshot — never "everything in the entity", which would destroy rows the test did not create. ConnEx resources are registered for teardown BEFORE the run so a mid-run failure still cleans up, and are deleted strategy-then-configuration (a config with a dependent strategy is refused 403).

**Gated config** via `IntegrationConfig` (env var, else gitignored `integrationsettings.local.json`), Inconclusive when absent: `ConnExBaseUrl` / `CREWCHIEF_IT_CONNEX_BASEURL`, `ConnExApiKey` / `CREWCHIEF_IT_CONNEX_APIKEY`, `ConnExSourceUser` / `CREWCHIEF_IT_CONNEX_SOURCE_USER`, `ConnExSourcePassword` / `CREWCHIEF_IT_CONNEX_SOURCE_PW`. The source credential is required because a portal export carries no secret — without it the imported configuration cannot connect.

Helper `TestHelpers/ConnExTestGateway.cs` verifies and cleans up via REST **independently of CrewChief's own executor** — checking CrewChief's work by calling CrewChief would pass happily when both sides share a bug.

Environment facts (2026-08-15): entity `PDATA120` (`data.tPDATA120`) is the import target and its baseline on this box is **empty**; source is `ModelSource.dbo.PDATA1K`, 1000 rows; a full run imports all 1000 in a few seconds. ConnEx tables live under the `connex` schema (`connex.tServiceConfiguration`, `connex.tIntegrationStrategyConfiguration`), not `dbo`.

Related: [[project_crewchief_connex_import_three_bugs]], [[reference_profisee_gateway_record_paging_400]], [[atomic-tests]].
