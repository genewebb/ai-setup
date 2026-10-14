---
name: testauto-crewchief-export
description: >
  Exporting a TestAuto MultiStepUtility workflow as a CrewChief-importable workload bundle — the
  hand-written mirror types that exist because TestAuto.Web may never reference a CrewChief assembly, the
  R1-R7 preflight rule catalogue and its two-state severity model, and the parameter-hoisting rule that
  makes deselecting a step a form of conflict resolution. Use when working on CrewChiefWorkloadExporter /
  ExportPreflight / ExportAnalysis / CrewChiefStepTypes / the CrewChiefExportWizard, adding a step type to
  the export, diagnosing a step silently dropped from a bundle, or a parameter that refused to hoist.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto → CrewChief workload export

TestAuto.Web can emit a `<name>.workload-bundle.json` that CrewChief imports. Three doctrines govern it,
and none is inferable from the code's shape alone.

For the receiving side — CrewChief's own `WorkloadBundle` type and import path — see
[[crewchief-workload-transfer]]. **The two are deliberately not the same type.**

## When to Use

- "Export this workflow to CrewChief"
- "A step vanished from the bundle"
- "Why won't this parameter hoist to a global?"
- Adding a step type to the export surface
- Changing the bundle wire shape on either side

## 1. The mirror rule — and why nothing catches you breaking it

**TestAuto.Web must NEVER reference a CrewChief assembly.** The bundle and step-type types in
`Services/CrewChiefExport/` are **hand-written mirrors** of CrewChief's own.

The consequence is the important part: because there is no shared assembly, **the wire shape is pinned only
by literal shape tests** — so compiler drift is *impossible to catch*. If CrewChief changes its bundle
shape, nothing in TestAuto fails to build. The ~2,100 lines of tests under
`Testing.SpeedMerchants.Unit/Tests/Web/Services/CrewChiefExport/` are the entire safety net.

**When you touch either side's bundle shape, change the mirror and its shape tests in the same commit.**

## 2. The R1–R7 preflight catalogue, and a two-state severity model

`ExportPreflight` applies a fixed rule catalogue with exactly two severities:

| Severity | Effect | Operator override |
|---|---|---|
| **Incompatible** | The scenario is **disabled** / the step is **silently dropped** from the bundle | **None.** There is no override |
| **Warning** | Proceed | n/a |

"Silently dropped" is deliberate and is why the wizard surfaces the preflight prominently — a bundle that
quietly lost a step is otherwise indistinguishable from one that never had it.

**`MonitorStep` is a permanent exclusion.** It is not a gap waiting to be filled — it has no CrewChief
equivalent by design, and `CrewChiefStepTypes` records it as such. Do not "add support" for it.

`ExportPreflight` also carries a **secretish-field** check, so a bundle does not carry a value that looks
like a credential out of TestAuto.

## 3. Parameter hoisting — and why deselecting a step resolves a conflict

A parameter key is **global-safe iff it has exactly one distinct value across the CURRENT selection.**

Two details that decide behaviour:

| Aspect | Comparison |
|---|---|
| Keys | `OrdinalIgnoreCase` |
| **Values** | **`Ordinal`** |

So `Dev` and `dev` are two distinct values under one key, and the key will not hoist.

`ParameterClassification` is a **pure recompute** over the current selection. That has a consequence worth
stating out loud: **deselecting the step that defines the odd value IS the conflict resolution.** There is
no separate "resolve conflict" action — the classification simply recomputes and the key becomes hoistable.
An agent looking for a resolve button will not find one.

## Sources

- `TestAuto.Web\Services\CrewChiefExport\CrewChiefWorkloadBundle.cs`
- `TestAuto.Web\Services\CrewChiefExport\CrewChiefStepTypes.cs`
- `TestAuto.Web\Services\CrewChiefExport\ExportPreflight.cs`
- `TestAuto.Web\Services\CrewChiefExport\ExportAnalysis.cs`
- `TestAuto.Web\Services\CrewChiefExport\CrewChiefWorkloadExporter.cs`
- `TestAuto.Web\Components\Controls\CrewChiefExportWizard.razor.cs`
- `TestAuto.Web\Components\Pages\WorkflowScenariosEditor.razor.cs`
- `Testing.SpeedMerchants.Unit\Tests\Web\Services\CrewChiefExport\` (5 files, the only pin on the wire shape)
