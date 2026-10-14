---
name: project_crewchief_preflight_twohop_token_leak
description: "CrewChief preflight probes leaked literal {{$config:...}} tokens as SQL logins because the capability seams never flattened the two-hop parameter chain; fixed 2026-09-01"
metadata: 
  node_type: memory
  type: project
  originSessionId: 63b6c0e8-d596-4d7a-b6c4-54ed5a56d356
  modified: 2026-09-01T22:03:28.099Z
---

CrewChief's Capability Advisor seams (`CapabilitySubsystemRegistration`) resolved step fields against the **raw** step parameter dictionary. `TextTemplater` is single-pass, so the shipped two-hop shape — `credentialUserId` = `{{profisee_admin_user}}`, and that parameter = `{{$config:UserCredentials:AdminUser}}` — substituted hop one and stopped. The literal `{{$config:...}}` text went into the probe's connection string as a SQL login; SQL Server echoed it back as `Login failed for user '{{$config:UserCredentials:SqlUser}}'`, which reads like a permissions problem on an account never used.

Silent because the parameter key **exists**, so `Apply()`'s unresolvable-token catch never fires. `UtilityOrchestrator.cs:216` flattens the chain via `IParameterResolver` before any executor runs — so the **run was fine and preflight hard-blocked a healthy workload** (no bypass flag exists).

**Why:** preflight and run used different resolution depths. Any pre-run analysis that reads step parameters must flatten the same chain the orchestrator does, or it probes a credential the run will never use.

**How to apply:** fixed 2026-09-01 — added `IParameterResolver.ResolveSpecialParameterValuesBestEffort` (compose-time counterpart: same flattening, resolves what it can, leaves unresolvable tokens literal, never throws) and threaded an optional `IParameterResolver?` through all seven seam methods; `Parameters(step, resolver)` now flattens a **copy**. Best-effort matters because fail-fast is all-or-nothing per dictionary — at compose time one workload-global-only token would blank every other parameter. Regression tests: `CrewChief.Tests.Unit/Engine/Capabilities/SqlProbeTargetTwoHopTests.cs` (6 tests, incl. a guard test pinning the old leak). Suite 3796 passed; the two `CurlExecutor` failures are [[reference_curlexecutor_test_port_flakiness]], pass in isolation. Uncommitted — user commits. Related: [[crewchief-capability-preflight]], [[crewchief-token-replacement]], [[reference_scenario_config_token_prefix]].
