---
name: project_stream_kit_token_review_2026-10-17
description: "Stream kit token review built 2026-10-17 - status role is a pure script tick (unit only for its inbox), integrate/plan/kit/coordinator launch only when a script gate finds work, builder/author idle report, authors widen their own write set (-AddWriteSet), scoped-autoapprove hook; all published + installed"
metadata:
  node_type: memory
  type: project
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-17T19:15:33.729Z
---

Gene approved "Both 1 + 2" on 2026-10-17: (1) status = PowerShell tick, (2) timed roles gated. "Runner line is
enough" for the 10/10 "report every tick" ruling. Also "Authors widen their own set".

**Built (Start-StreamRunner.ps1 + Test-StreamKitRecovery.ps1, stream-kit/author/status/integrate/plan/coordinator
SKILL.md, Update-Task.ps1):**
- Status runner: `Invoke-StatusTick` every IntervalSeconds (900): Invoke-Watchdog, Get-StreamStatus, Build-StatusPage,
  Get-StreamCost + Build-CostPage, Build-PriorityPage, Archive-TaskHistory (once per UTC day, marker
  `.streams\runners\status-archive.day`), Activate-Group for focus groups lacking `plans\<G>.activation.json`.
  One `STATUS-TICK` heartbeat line; `TICK-FAILED` files a stream-kit bug item once per script. A Claude unit only
  when `.streams\inbox\stream-status.md` has an open item (`/stream-status inbox repo: <repo>`).
- Timed gates (`Get-TimedGate`): integrate = inbox item | claimable built focus row | group `integrating` | own
  integrator lock beating; plan/kit = actionable inbox item (plan also needs no live planner); coordinator = own
  inbox | plan/kit items with no live session | free RAM < 6 GB (`STREAM_RUNNER_FREE_RAM_GB` override for tests) |
  status flags changed | first review after start | periodic `STREAM_COORDINATOR_REVIEW_SECONDS` (7200).
  Idle shows why + next look, watches tasks.json/inbox (no tokens). `-DryRun` prints GATE/IDLE/TICK lines.
- Builder idle report lists rows being built by live builders; author/builder idle = what finished, when next look.
- `Update-Task.ps1 -AddWriteSet` now author AND build (plan still refused, exit 2); auto-accepted, decisions.md.
  stream-author v0.11 step 7: skeptic write-set leak -> widen, only WRITESET-OVERLAP (exit 7) blocks.
- Permission prompts: [[reference_permissionrequest_hook_scoped_autoapprove_2026-10-17]].

**Stage** was `C:\scratch\streams\speedmerchants\kit-idle-display-root\` (scripts) and `...kit-idle-display-stage\`
(SKILL files); published with `Publish-KitFile.ps1 -BaseHash`, applied with `install.ps1 -NoPull -Yes`.

**Still open after this:** close kit inbox items IN-20261017025015-83de / IN-20261017100037-aa62 citing a644425;
repoint `status-url.txt` at SMVMTR1; Gene runs `Clear-Smvmtr1Tmp.ps1` on SMVMTR1. Hard-path gate baseline on the
corpus = 18 pre-existing hits (none from this work). Related: [[project_stream_host_back_to_laptop_2026-10-17]].
