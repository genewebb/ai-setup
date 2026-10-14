---
name: skill-inspect-workflow
description: >
  Slash shortcut to inspect a TestAuto workflow's stored, decompressed config by its workflow
  Code. Use when the user types `/skill-inspect-workflow <workflowCode>` or asks to inspect /
  dump / show a workflow's stored config or per-step CustomParms by code. Thin wrapper over the
  scenario-config-inspector skill's script.
---

# /skill-inspect-workflow

A one-argument shortcut: `/skill-inspect-workflow <workflowCode>` → prints each step's
decompressed `CustomParms` for that TestAuto workflow.

## When invoked

The argument provided after the command is the **workflow Code** (e.g. `10000124`).

1. If **no argument** was given, ask the user for the workflow Code and stop.
2. Otherwise run (substituting the argument for `<code>`):

```powershell
pwsh -NoProfile -File "{PowershellScriptsDir}\inspect-config.ps1" -WorkflowCode <code> -CustomParmsOnly
```

3. Present the output: the workflow name/header, then each `===== ORDER n : <DisplayName> =====`
   block with its `CustomParms`. Summarize anything notable (e.g. a step whose `ScenarioName`
   or `OperationType` looks off) if relevant to what the user is doing.

## Variations (only if the user asks)

- **Full config (not just CustomParms):** drop `-CustomParmsOnly`.
- **One step:** add `-Step <n>`.
- **Write to a file** (large workflows): add `-OutFile <path>`.

## Notes

- Read-only (SELECTs against the `speedmerchants` ScenarioMgt DB, integrated auth).
- This is a convenience alias; the full tool + parameters live in the
  **scenario-config-inspector** skill (same `inspect-config.ps1`).
