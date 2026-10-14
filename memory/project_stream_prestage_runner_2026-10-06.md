---
name: project-stream-prestage-runner-2026-10-06
description: "Stream kit pre-staged runner units + .streams\\config.json model configuration implemented 2026-10-06 on the LAPTOP install only; sync to Q: share and SMVMTR1 pending (Gene does it in an Opus 5.5 session); design note in vault speedy\\stream-kit\\2026-10-06-prestage-runner-design.md"
metadata:
  node_type: memory
  type: project
  originSessionId: 6b477d9e-cbab-4a39-9f95-673fbd7d6176
  modified: 2026-10-06T19:14:56.102Z
---

2026-10-06: Start-StreamRunner.ps1 (author, build) now pre-stages every unit in PowerShell before Claude starts: takes the oldest actionable inbox item in the unit's name OR claims the row with Claim-Task.ps1; for build lays the worktree, proves the author grader RED (not red = bounce to planned, no launch), restores a kept patch and grades it; writes a packet `.streams\units\<session>\{task.json,unit.md}`; launches with `packet: <unit.md>` in the command. Idle gated runners WATCH tasks.json + inbox file (stat every 5 s, fallback 300 s) instead of sleeping 1800 s. A build unit that dies holding its claim has its worktree exported to a patch before the claim is released. `-NoPreStage` keeps the old behaviour.

Owner-set FOCUS (Gene's ruling 10/6: "I will manually set the priority group and I might include more than one"; priority order itself stays G4, G5, G6 = board order): `.streams\config.json` `"focus": { "groups": ["G4"] }` or several; lib `Get-FocusGroups`/`Get-FocusLabel`/`Get-FocusSet($doc, $P)` read it via `Get-StreamConfig` (cached by mtime); listed groups kept in board order, closed/unknown dropped, empty list = automatic first-unclosed rule. Focus set = own group in focus OR effective group in focus/closed. Unlisted OPEN group rows are frozen even when a focus row waits on them.

Model configuration (Gene's ruling 10/6: "configurable at all levels, update configuration and restart"): `.streams\config.json` with `defaults` and `roles.<role>` for `model` (--model), `subagentModel` (CLAUDE_CODE_SUBAGENT_MODEL + a rules line), `effort` (--effort), `promptCacheTtl` (CLAUDE_CODE_PROMPT_CACHE_TTL). Read before EVERY unit. Precedence: -Model switch > roles > defaults. Written empty by the first runner that finds it missing.

Files changed (laptop `C:\Users\agenewe\.claude\skills\`): stream-kit\scripts\Start-StreamRunner.ps1, stream-kit\scripts\lib\Inbox.ps1 (`units` skipped in progress reports), stream-kit\scripts\Test-StreamKitRecovery.ps1 (case 100 a-f), stream-author\SKILL.md, stream-build\SKILL.md. 10/6 15:10 SYNCED to SMVMTR1 corpus `\\SMVMTR1\d$\AIWork\work-ai` (Sync-Machine -Apply -Force; 14 files, hash-verified; backup D:\DeployMyAI\sync-backup\20261006-151008); TR1 install applies on next `ai` / runner launch check. Laptop corpus D:\DeployMyAI\corpus updated. Q: share still holds the pre-change copies for 12 files (not published there); the live `.streams\cost\prices.json` + Get-StreamCost reprice fix WERE published earlier the same day.

Also changed for owner focus: lib\Streams.ps1, Claim-Task.ps1, Send-InboxItem.ps1, Test-StreamKit.ps1 (5 cases), stream-integrate + stream-coordinator SKILL.md, stream-kit SKILL.md. Self-tests 10/6 laptop: Test-StreamKit 181/0, Test-StreamKitRecovery fails=0 (567 PASS). Lesson: `& script.ps1 @array` passes '-Repo' as a positional VALUE; splat kit scripts with a HASHTABLE.

Open: packet pruning (watchdog); verify CLAUDE_CODE_SUBAGENT_MODEL vs explicit Agent `model:` on a real transcript; inter-call gap histogram before `promptCacheTtl: 5m`. Related: [[reference-stream-cost-transcript-facts]], [[feedback-stream-mechanical-work-outside-claude]].
