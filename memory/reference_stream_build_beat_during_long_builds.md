---
name: reference-stream-build-beat-during-long-builds
description: A bare dotnet test/build does not beat a stream-kit claim; the 45-minute watchdog reaps the worktree mid-build
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2550a59e-a257-476a-82c3-03144dbd3357
  modified: 2026-09-29T17:51:07.169Z
---

In stream-build, only `Invoke-Grader.ps1 -BeatSession <id> -BeatTask <t>` and `Update-Task.ps1 -Beat`
refresh `claim.beat`. Running `dotnet build` / `dotnet test` directly during step 5 does not. On
2026-09-29 session `build-202609291226-d794` spent ~45 min on G2.T04's targeted tests without beating;
stream-status declared the claim stale, another builder took it over, and the watchdog reaped the
worktree `D:\devops\worktrees\speedmerchants\G2.T04` while files were still being edited there. The
work survived only because status salvaged it into `.streams\patches\G2.T04.patch` first.

**Why:** the skill says to refresh the beat "at least every 10 minutes during step 5"; long targeted
suites (browser/Playwright rows) blow past that between two tool calls.

**How to apply:** on a task whose targeted tests take minutes, call `Update-Task.ps1 -Beat` before and
after every long run, or wrap the run in `Invoke-Grader.ps1 -BeatSession`. Also never keep the session
id in a shared path like `D:\tmp\stream-build-session.txt` — a parallel builder on the same host
overwrites it, and `Update-Task` then answers `CLAIM-LOST` against someone else's id. Keep it in the
session scratchpad. See [[project-stream-capacity-two-authors-two-builders]].
