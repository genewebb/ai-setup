---
name: project-stream-profile-commands-proposal-2026-10-17
description: "10/17 BUILT (uncommitted, awaiting Gene's test): getStreams / pushStreams / updateStreams + getStreams -FromHost takeover + pushStreams -Handoff; Owner push column; board host guard"
metadata:
  node_type: memory
  type: project
  originSessionId: 7f9b7dd7-ddfd-4516-b161-78b73de28302
  modified: 2026-10-17T23:14:39.390Z
---

Built 2026-10-17 in ai-setup (NOT committed; Gene is testing). Profile installed on the laptop by copying only the profile file (backup in C:\scratch\ai-config-work\backups\streams-profile-20261017-191131). Did NOT run install.ps1: another session's uncommitted `prof` hub (pwsh\PowerShell\Modules\Gene.Profile, untracked) and its installer edits are in the same tree. `sp`/`ep` (from commit b17bda9) call Invoke-GeneProf, which is missing until that module is installed.

- Profile `#region Stream sessions`: getStreams, pushStreams, updateStreams. Every stream command's `-Repo` defaults to SpeedyRepo. `-AnyHost` on addStreams, addStreamTab and updateStreams.
- Host guard = board markers `.streams\host.json`, `MOVED.json`, `handoff.json` (Gene's choice, no StreamHost profile key).
- `lib\MachineConfig.psm1`: optional git policy column `Owner push`, giving Get-AIGitPolicy `.OwnerPush` (blank = Push), validated yes/no/blank. git-guard still reads Push only.
- Laptop `C:\Deploy\Setup\ProfileMachineConfig.md`: the {SpeedyRepo} row is Push=no, Owner push=yes (Gene: laptop push for pushStreams only).
- Tests: `setup\tests\StreamSync.Tests.ps1`, 16 passing (throwaway origin, A and B clones, B reached as \\localhost\C$, stub install/publish). MachineConfig.Tests 24 passing.
- Two bugs were caught by those tests. Remember them:
  - `$x = if (..) { @('-Yes') }` unwraps to a string, and splatting a string passes its characters. Wrap it as `@(if ...)`.
  - A child `& pwsh -File` inside a bool-returning function leaks its output into the return value, so a failure reads as truthy. Pipe it to `| Out-Host`.

Overlap to raise: the other session's `prof pull/push` (Gene.Profile Verbs.ps1) syncs the AI setup kit between machines over PSSession. getStreams/pushStreams only call install.ps1/publish.ps1.

Related: [[project-stream-host-back-to-laptop-2026-10-17]], [[project_stream_tabs_profile_2026-10-04]], [[project_profile_machine_config]], [[reference_powershell_h_alias_and_byte_if_expression]].
