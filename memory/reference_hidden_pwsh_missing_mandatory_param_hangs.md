---
name: reference-hidden-pwsh-missing-mandatory-param-hangs
description: "Start-Process pwsh -WindowStyle Hidden -File script.ps1 with a missing [Parameter(Mandatory)] arg hangs forever at an invisible prompt"
metadata:
  node_type: memory
  type: reference
  originSessionId: fdb8702f-dda6-4ad9-8b9c-9852b5b7c684
  modified: 2026-10-09T23:59:39.465Z
---

`Start-Process pwsh -WindowStyle Hidden -ArgumentList '-File', 'x.ps1', ...` that omits a `[Parameter(Mandatory)]` parameter does not fail: pwsh prompts "Supply values for the following parameters" in the hidden console and waits forever, with nothing in the redirected stdout.

On 2026-10-09 a builder left `-Repo` off a detached Invoke-Grader.ps1 run. The grader never ran and the claim never got a beat, so 45 min later the watchdog broke the live G4.T136 claim (kit item IN-20261009233639-e3a7).

**How to apply:** pass `-NonInteractive` on every detached pwsh. When a kit script is likely to be launched detached, make its required params non-mandatory and check them explicitly instead. Invoke-Grader.ps1 now prints `MISSING-PARAM` and exits 7. Related: [[index_stream_kit]]
