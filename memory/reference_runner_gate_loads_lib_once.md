---
name: reference-runner-gate-loads-lib-once
description: "Start-StreamRunner.ps1 dot-sources lib\\Streams.ps1 once at startup, so a published change to Get-Claimable reaches the runner GATE only after the runner restarts; Claim-Task.ps1 loads per call"
metadata:
  node_type: memory
  type: reference
  originSessionId: 28c88d04-48e0-401b-b479-5ac38afd10e0
  modified: 2026-10-12T13:49:05.936Z
---

`Start-StreamRunner.ps1` dot-sources `lib\Streams.ps1` and `lib\Inbox.ps1` once (lines 98-99). Its work gate
(`Get-WorkGate` -> `Get-Claimable`) therefore keeps the OLD selector in memory after a kit publish. `Claim-Task.ps1`
and `Get-StreamStatus.ps1` run as fresh processes and pick the change up at once.

Seen 2026-10-12 with the AUTHOR SPILL change: the published Get-Claimable offered authors 70 spill rows, but the five
author runners (started 10/10 in the owner's WezTerm tabs with `-Live -Tab`) stayed `idle` because their gate still
read NONE.

**How to apply:** after publishing any change to `Get-Claimable`, the focus set, or the gate, tell the owner to restart
the affected role's runner tabs (`addStreamTab -Role <role>`), or the change never launches a unit. Related:
[[reference-live-session-does-not-reread-skill-md]], [[project-stream-fresh-context-runner]].
