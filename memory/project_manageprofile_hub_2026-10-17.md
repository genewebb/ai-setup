---
name: project_manageprofile_hub_2026-10-17
description: "10/17 BUILT (uncommitted, tests green, live read-only checks pass on SMVMTR1): prof hub (alias manageProfile) in Gene.Profile module; worktree git runs ON the target over WinRM (40 s git status over share), push = refs/prof/incoming + ff-only, clone = bundle; OPEN: SMVMTR1 live account is genewe (installed 10/17 19:03 from shared clone), not agenewe"
metadata:
  node_type: memory
  type: project
  originSessionId: d68106f8-6760-4f72-b54d-4b3babaf10b2
  modified: 2026-10-18T14:42:18.002Z
---

Design `{AIWorkRoot}\docs\manageprofile-design.md` (approved 10/17), plan `docs\superpowers\plans\2026-10-17-prof.md`. Code: `pwsh\PowerShell\Modules\Gene.Profile\` (Target, Sync, Menu, Verbs .ps1 + psm1/psd1, aliases `prof`/`manageProfile`), `machines.yaml` at clone root, `.gitattributes` union for memory indexes, `install.ps1 -PassphraseFromStdin`, `pwsh\AddOrUpdateMyTerminal.ps1 -ForUser`, profile `sp`/`ep` call prof. Tests `setup\tests\Prof.Tests.ps1` 33/33.

**State 10/17 evening:** UNCOMMITTED. Not committed by pathspec because another session's stream-command work (OwnerPush column, pushStreams, StreamSync.Tests) sits in the same files (profile, lib\MachineConfig.psm1); one publish.ps1 sweeps both. Live read-only runs passed: `prof status`, `prof config -Machine SMVMTR1`, `prof check -Machine SMVMTR1`, `prof bootstrap -Machine SMVMTR1 -Retire CORP\speedmerchants -FixProfile -WhatIf`.

**Why the transport changed from the design draft:** `git status` over `\\SMVMTR1\D$` took 40 s on the 1,400-file clone (and hung prof status). Now worktree commands run in the WinRM session; only fetch and push to side ref `refs/prof/incoming` cross the share, then `merge --ff-only` on the target. No `updateInstead`. Bootstrap clones from a `git bundle` copied to target ScratchRoot, in the -User session, so no ACL/safe.directory step.

**Gotchas found:** `$env:USERNAME` is SYSTEM inside Claude's sandbox: caller = `WindowsIdentity.GetCurrent().Name`. `Get-Credential` hangs with no console: throw when stdin redirected. `[string[]]` Mandatory params need `[AllowEmptyString()]` for markdown lines.

**OPEN (Gene's call):** SMVMTR1 has THREE accounts with Claude installs: `genewe` (installed 10/17 19:03, corpus D:\devops\repos\ai-setup = the clone prof sees, same HEAD as hub), `speedmerchants` (retire), `agenewe` (clone path only, runtime not installed). machines.yaml lists agenewe only. Per-user AIWorkRoot fix would orphan the shared clone and needs genewe retired or bootstrapped; Git policy row `{ReposRoot}\ai-setup` would no longer cover the new per-user path.

**10/17 later, Gene: prof = GENERAL-PURPOSE hub with GROUPS.** `prof <group> <command>`; main menu lists groups + help; the 11 commands are group `streams` (Gene's name); help stays top level; a command one group owns works alone (`prof push`). Add a group = one entry in `$script:ProfGroups` (Verbs.ps1). Other profile commands become groups next. Design section 6 "one hub per domain" SUPERSEDED. OPEN: section 6.1 stream-board commands planned as `streams get/push/...` now collide with this group's name and its `push`.
**Menus look like devutils:** PwshSpectreConsole 2.6.3 (needs pwsh 7.4+, added to pwsh\modules.txt) gives arrow-key Read-SpectreSelection; numbered fallback when module missing, input redirected, tests pass -Reader, or $env:GENE_PLAIN_MENU. Choice labels are Spectre markup: escape [ ] as [[ ]]. Tests 40/40.

**10/17 night: groups `git` + `build` BUILT (GitGroup.ps1, BuildGroup.ps1; tests 55/55; design 4.7).** git status/push/pull [<repo>] (repo = folder name from machine profile or this folder; push = Git-QuickPush/gpush; pull = --ff-only). build compile/run/publish/more <product> (speed crewchief datagen mutate speedy gov all) wraps dp* in the profile; publish -Bump None|Patch|Minor|Major; unknown words pass to dp* (ValueFromRemainingArguments -> ConvertTo-GeneCommandArgs). Both cd into the repo and stay (Gene). `prof push/pull/status` now ambiguous (streams + git). Another session committed earlier prof work as 371eba2 WIP + machines.yaml SMVMTR1=CORP\genewe (4503234).

**10/17 later still (Gene):** governance RETIRED from all tooling (GovernanceRepo key, cgov, dpgov, Dev-ProfiseeGovRestart + app-pool helpers in Gene.DevOpsTools, WindowsPowerShell gov block, prof build gov); laptop + SMVMTR1 machine profiles edited (backups `*.bak-20261017-2011-gov`), governance memory notes deleted. ai-profisee ADDED: key `AIProfiseeRepo` (C: laptop, D: SMVMTR1), `caiprof`, Git policy row `{ReposRoot}\ai-profisee` commit yes / push no on both machines. Group `other` (OtherGroup.ps1) = catalog of every other profile command by category, census test keeps it complete; tests 58/58. Until `prof setup reload` installs the new profile, shells warn "unknown key 'AIProfiseeRepo'" (machine profile already updated).

**10/17 RENAME (Gene):** profile-sync group `streams` is now `setup` (prof setup push|pull|status|check|bootstrap|terminal|secrets|config|edit|reload|show). `streams` = the stream BOARD (StreamsGroup.ps1, thin layer over addStreams..updateStreams; -WhatIf -> -DryRun) plus `status-rebuild` (touches <SpeedyRepo>\.streams\inbox\stream-status.md). New group `ai` (AiGroup.ps1) = dpAI modes as commands. git: scripts folders (PowershellScriptsDir, SqlScriptsDir, CursorRulesDir) in the repo list, `-AIOnly` = pushrules. build: `containers` (dpContainers, Speedy only). Menu order streams, setup, git, build, ai, other. Tests 63/63.

**10/18: COMMITTED in b1cfe17** (swept with the stream-kit dependency review publish, Gene's choice). Rollout recipe Gene uses: `prof setup reload` → `. $PROFILE` → `prof setup push -Machine SMVMTR1 -AllowSecrets` (machines.yaml gives CORP\genewe, no -User needed) → `. $PROFILE` → `prof streams update -RestartSessions`. See [[feedback_ai_setup_rollout_via_prof]].

**Earlier decisions (still hold):** laptop = only GitHub publisher; one clone per user on multi-user machines; `-User` param, creds prompted every run; speedmerchants on SMVMTR1 = retire; terminal = settings-only `-ForUser`; any machine, current target SMVMTR1; later hubs deploy/streams/tab/go; streams proposal rebased on the hub.

Related: [[project_ai_setup_private_git_repo_2026-10-14]], [[project_profile_machine_config]], [[project_stream_profile_commands_proposal_2026-10-17]], [[reference_addorupdatemyterminal_script]].
