---
name: reference_runner_prestage_ghost_sessions
description: Status page over-counting authors/builders = runner pre-stage session ids that never became a unit; fixed 2026-10-08 in Claim-Task.ps1 + lib\Streams.ps1
metadata:
  node_type: memory
  type: reference
  originSessionId: f7f972f6-eecc-483b-b761-e6144a85ff21
  modified: 2026-10-09T00:07:23.528Z
---

Start-StreamRunner.ps1 picks a NEW session id for every pre-stage claim. When the claim finds nothing (NONE), or claims a build row and bounces it (author grader not RED), no unit and no `<stamp>-<session>.rules.txt` ever exists, but the idle beat or history it wrote made the board count it live for the role's whole limit (author 8 live with 5 runners; build 6 with 5).

Fix published 2026-10-08 (~20:00 EDT):
- Claim-Task.ps1 detects a pre-stage claim by the `Invoke-PreStage` frame of Start-StreamRunner.ps1 on `Get-PSCallStack` (works for old in-memory runners, since the runner calls Claim-Task in-process from disk every time), or by `-NoIdleBeat`.
- A pre-stage claim writes no idle beat and is marked in `.streams\prestage\<session>.json`.
- `Get-LiveSessionIds` drops marked sessions with no rules file.
- The watchdog never reads the mark, so the claim of a pre-stage that is still proving RED is not freed.
- Regression tests 101e and 101f are in Test-StreamKitRecovery.ps1.

Why it matters: kit fixes inside Start-StreamRunner.ps1 do not reach running runners until the owner restarts them. Put a fix in a script the runner loads per call (Claim-Task.ps1, lib loaded by it) when it must take effect at once. Related: [[project_stream_fresh_context_runner]].
