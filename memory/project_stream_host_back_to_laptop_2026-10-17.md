---
name: project-stream-host-back-to-laptop-2026-10-17
description: "10/17: stream board pulled back CORPVM17 -> laptop (sync only, no streams here); next = fresh deploy on SMVMTR1; VM17 nightly deleted"
metadata:
  node_type: memory
  type: project
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-17T17:07:20.516Z
---

Gene 2026-10-17: VM17 went almost unresponsive; streams stopped there (STOP file + Gene closed the 4 loop sessions). Decision: **sync laptop only, run nothing here; next a NEW deploy on SMVMTR1** (when Gene says ready). Supersedes the live-host part of [[project-stream-host-move-corpvm17-2026-10-13]].

**Done 10/17:**
- speedmerchants: VM17, laptop, origin all at 2573b27 (users/agenewe/stream-sync), VM17 clean, no stash. Laptop fast-forwarded 147.
- ai-setup: VM17 clone held 5 UNCOMMITTED stream-kit script edits (kit items IN-20261017025015-83de + IN-20261017100037-aa62; both suites fails=0 on stage kit8/rec7; published 14:27Z, never installed/committed). Copied to laptop clone (diff identical), committed a644425, PUSHED by Gene 10/17 (on origin/main). Laptop install.ps1 still to run. Both kit inbox items still open on the board: close done citing a644425. VM17 clone still shows them as uncommitted (identical content).
- Board: laptop's old 10/5 .streams moved to C:\scratch\stream-move\20261017\laptop-streams-old-20261005; VM17 .streams mirrored to laptop (robocopy /MIR /XF *.lock, log in same folder). 5 orphan build claims (G8.T005, G9.T010, G6.T307, G9.T029, G11.T003) from units dead ~12:25Z; their VM17 worktrees already reaped. G9.T011 built, patch on board.
- VM17 nightly task DELETED (Gene: "remove it"); XML backup C:\scratch\stream-move\20261017\vm17-nightly-task.xml.
- Laptop prep (unused yet): root .env with the 11 channel names only (SM_SA_PASSWORD from user env), certs %LOCALAPPDATA%\Speedy\dev-stack\worker-channel (fleet..fleet-5). Test-StreamHostReady on laptop: 0 FAIL.

**Gotcha:** Write-SpeedyStackEnv.ps1 now provisions only the SEPARATE E2E stack (speedmerchants-e2e, port 5320) and never writes the root .env; .env.example comment still says it does. Owner-stack .env values = src/Agent/appsettings.sample.json Channel section + `/worker-channel/coordinator/server.pfx`.
