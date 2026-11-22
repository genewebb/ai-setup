---
name: reference-kit-stage-needs-mirrored-layout
description: "Stream kit self-tests import ..\\..\\..\\lib\\MachineConfig.psm1 relative to scripts\\, so a stage must mirror <root>\\skills\\stream-kit\\scripts plus <root>\\lib or the suite dies at line 32"
metadata:
  node_type: memory
  type: reference
  originSessionId: d3dd6a32-1727-4737-ae40-978fa8533d80
  modified: 2026-10-04T03:28:12.772Z
---

Test-StreamKit.ps1:32 and Test-StreamKitRecovery.ps1:32 run `Import-Module (Join-Path $S '..\..\..\lib\MachineConfig.psm1')`. A stage that copies only `scripts\` to `D:\tmp\streams\<repo>\kit-<x>-stage\scripts` fails before any case runs ("module was not loaded because no valid module file was found").

**How to apply:** stage as `<root>\skills\stream-kit` (copy the whole skill folder) plus `<root>\lib` copied from `{ClaudeHome}\lib`, set `STREAM_TEMP_ROOT` to scratch, and touch every staged file (see [[reference-kit-stage-wiped-by-watchdog-sweep]]). For a RED-on-base proof, build a second root from the live files with only the new test file swapped in.

Example 2026-10-03: G3 lost its date to the chain scale-split guard (4.48x on ordinary 8-255 min variety); Get-StreamStatus.ps1 now dates a split chain off the chain sum, marks `softDate`, and flags "SOFT predicted finish" instead of NO DATE.
