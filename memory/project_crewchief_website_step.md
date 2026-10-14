---
name: crewchief-website-step
description: WebSiteStep added 2026-08-06 — IIS site/app start/stop/delete with orphaned-app-pool cleanup; box-prep family is now SEVEN; executor census 22; AppPoolStep.Validate delete-drift fixed
metadata: 
  node_type: memory
  type: project
  originSessionId: 1d4ab271-ff72-45c2-adef-439a2c473190
  modified: 2026-08-07T02:42:41.785Z
---

Task #9 completed 2026-08-06: CrewChief `WebSiteStep` ("WebSiteStep"/"WebSite"/"Site") — Start/Stop a
whole IIS site, or **Delete** a site or msdeploy-style `Site Name/AppName` web application, with
`deleteAppPools` (default TRUE) removing the pools the target used once **nothing else references
them** (never `DefaultAppPool`). Replaces `msdeploy -verb:delete -dest:apphostconfig=...` teardown.
Delete is idempotent (absent = success). Start/Stop on an app path is refused (sites only).

Ripple counts to remember (all updated, suite 2880 green):
- **Box-prep family is SEVEN** — WorkloadRunAsInheritance, StepCapabilityRequirements,
  EffectiveIdentity, CreateStepForAuthoring (Auto auth), plus the reflection census
  `WorkloadRunAsInheritanceTests` now asserts 7.
- **Executor census is 22** (`EngineRegistrationTests.cs`; the stale "nineteen" doc-comment fixed).
- New seam: `IWebSiteRunner`/`DefaultWebSiteRunner` (ServerManager) + `RemoteWindowsOps.BuildWebSiteControlScript`
  / `ParseWebSiteControlResult` (handles ConvertTo-Json one-element array flattening on `removedPools`).
- Doc guide `48_StepGuideWebSite.md`, help slug `web-site`; index + 5 ops docs updated six→seven.

Also fixed same session: `AppPoolStep.Validate()` rejected Delete/Remove while the executor accepted
them (dual-validator drift) — now delegates to `AppPoolExecutor.TryParseAction`, same pattern as
ServiceControlStep. Regression tests added.

Related: [[project_crewchief_workload_runas_inheritance_carveout]], [[crewchief-adding-a-step-type]] (skill counts now stale: executor census 22 not 21, box-prep 7).
