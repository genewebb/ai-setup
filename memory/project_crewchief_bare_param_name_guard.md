---
name: crewchief-bare-param-name-guard
description: "Configure ran literal 'profisee_configuration_manager_path' as the exe — field held a param NAME without {{ }}; guard added (executors fail fast, editor warns) 2026-07-26"
metadata: 
  node_type: memory
  type: project
  originSessionId: e6d8e5b1-4044-498b-a938-4de456f8a54e
  modified: 2026-07-27T00:49:51.065Z
---

A Configure step's ConfigurationExePath held a parameter NAME with no `{{ }}` braces
(`profisee_configuration_manager_path`). To the templater that is an ordinary literal, so it
survived resolution untouched and the remote runner executed the bare name as the exe —
surfacing only as "Remote command ... exited with code unknown". NOT a resolver regression:
`ApplyTokens`/`ReplaceTokens` either resolve or throw; they never strip braces. The same bare
first line was visible in the user's pre-audit screenshot, confirming the stored value predated
the duplication-audit changes.

**Guard shipped (suite 1750 green):**
- `ParameterReconciler.TryMatchBareParameterName(value, parameterKeys, out key)` — whole-value,
  trimmed, OrdinalIgnoreCase match to a merged param name, skipped when the value contains any
  token. The ONE detector both layers share.
- `ConfigureExecutor` (exe path) + `InstallExecutor` (MSI path): fail fast BEFORE any runner with
  "…is the parameter name 'X' without {{ }} braces … Use {{X}}"; honors ContinueOnError.
- `StepEditorCard`: field-level `invalid-feedback` under both path inputs + entries in
  `StepReadinessIssues()` (warning badge), checked against `BuildResolutionParameters()` so the
  editor and run guard always agree.

**Deliberately NOT in the reconciler badge JSON walk:** a whole-field == param-name match on
arbitrary switch values could false-positive on legit literals (e.g. switch value "profisee" vs a
param named profisee); detection is limited to the two executable-path fields + run-time guard.

Related: [[crewchief-duplication-audit]], [[project_crewchief_param_in_param]].
