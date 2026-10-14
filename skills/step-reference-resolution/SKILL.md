---
name: step-reference-resolution
description: >
  IStepReferenceResolver service in TestAuto.Web for resolving {{STEP:N}} placeholder
  tokens in CustomParms to actual WorkloadExecution codes. Use when working with
  cross-scenario linking in workflow executions, understanding how step N's output code
  is passed to step N+1 via CustomParms, or diagnosing unresolved step reference warnings.
---

Repo: speed-merchants (paths below are repo-relative)

# Step Reference Resolution

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/BusinessLogic/Services/StepReferenceResolver.cs`

Workflow executions can link scenario steps together so that the output `WorkloadExecution` code of step N becomes a CustomParms input for step N+1. The `{{STEP:N}}` token syntax enables this cross-scenario linking without hardcoding codes at design time.

---

## `{{STEP:N}}` Token Syntax

In a `CustomParms` dictionary, any value can contain a step reference:

```json
{
  "UpstreamWorkloadCode": "{{STEP:1}}",
  "OtherParam": "static-value"
}
```

- `N` is the **ExecutionOrder** (1-based) of the step whose `WorkloadExecution` code to inject.
- Only plain string values are resolved — nested JSON and non-string tokens are skipped.
- Tokens are resolved **after** all WorkloadExecution codes are pre-created but **before** the scenario is dispatched.

---

## Interface (`IStepReferenceResolver`)

Registered in DI as `IStepReferenceResolver`. Inject it into services that orchestrate workflow dispatch.

```csharp
public interface IStepReferenceResolver
{
    // Resolves all {{STEP:N}} tokens in a CustomParms dict.
    // Returns a NEW dictionary — original is never mutated.
    IDictionary<string, JToken> ResolveStepReferences(
        IDictionary<string, JToken>? customParms,
        IDictionary<int, string> stepWorkloadExecutions);

    // Resolves a single value string (returns original if not a token).
    string? ResolveValue(string? value, IDictionary<int, string> stepWorkloadExecutions);

    // Quick check: does any value contain a {{STEP:N}} token?
    bool HasStepReferences(IDictionary<string, JToken>? customParms);
}
```

---

## Usage Pattern

```csharp
// Build the step-to-WE-code map from the pre-created execution details
var stepWeCodes = new Dictionary<int, string>
{
    [1] = "WE-00001",
    [2] = "WE-00002",
};

if (_resolver.HasStepReferences(step.CustomParms))
{
    step.CustomParms = _resolver.ResolveStepReferences(step.CustomParms, stepWeCodes);
}
```

---

## Resolution Behavior

| Scenario | Outcome |
|---|---|
| Value matches `{{STEP:N}}` and step N exists | Replaced with the WorkloadExecution code for step N |
| Value matches `{{STEP:N}}` but step N not in map | Original value returned; warning logged at `Warning` level |
| Value does not match the pattern | Original value returned unchanged |
| `customParms` is null or empty | Returns empty `Dictionary<string, JToken>()` |

The resolver uses `WorkflowConstants.TryParseStepReference` and `WorkflowConstants.IsStepReference` for pattern matching — do not reimplement the regex inline.

---

## Logging

All resolution activity is logged under `LogTagConstants.StepReference`. Successful resolutions log at `Information`; unresolvable tokens at `Warning`; debug detail at `Debug`.

---

## Sources

- `TestAuto.Web\BusinessLogic\Services\StepReferenceResolver.cs`
