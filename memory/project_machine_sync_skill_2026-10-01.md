---
name: project_machine_sync_skill_2026-10-01
description: machine-sync skill (Sync-Machine.ps1 -Source -Target) carries corpus/pwsh profile/stream-host between laptop and TRs; 3-way vs sync-base; first TR1->laptop sync applied 10/1; TR1 relink off share still pending
metadata:
  node_type: memory
  type: project
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
  modified: 2026-10-06T11:23:03.363Z
---

Built 10/1 at Gene's request ("simple skill, source and target, SMVMTR1 to CORPLTR94 or vice versa").
- Script `{DeployRoot}\steps\Sync-Machine.ps1` (DeployRoot = D:\DeployMyAI on laptop, new profile key, spec R40), helper `steps\SyncBase.ps1`, machine paths `D:\DeployMyAI\machines.json`, base per pair/item in `sync-base\`, backups in `sync-backup\<stamp>`. Tests `steps\tests\Sync-Machine.Tests.ps1` 7/7.
- Stage-Machine.ps1 now refuses to mirror over target edits since the last stage/sync (or no base) unless -Force; records base after staging. Build machine = $env:COMPUTERNAME.
- R39: SkillsLinkRoot = the machine's own corpus copy means an edit there is a corpus edit, not drift.
- 10/1 first sync TR1->laptop APPLIED: TR1 WezTerm tab helpers in pwsh profile (addtab/addnew/New-GeneWezTab), Test-StreamKitRecovery D: fix, 5 stream-host scripts -> D:\DeployMyAI\stream-host. Published to Q:, laptop applied rev 1F61EFD23FE4. The base was seeded from file mtimes (`steps\Seed-TR1SyncBase.ps1`, one-off).
- PENDING: TR1 skill edits made through the links live on the Azure share (laptop can't read it). Gene robocopies the share's skills/agents/commands to `D:\tmp\share-snapshot` on TR1, laptop diffs by hand against `D:\AIWork\work-ai` (do NOT feed the snapshot to Sync-Machine: the share holds the OLD Test-StreamKitRecovery and would revert the fix), then set TR1 SkillsLinkRoot = D:\AIWork\work-ai and apply on TR1. The laptop pwsh profile now has DeployRoot in the key list: shows as newer on the laptop, sync to TR1 later.
- 10/6: a kit Publish to Q: does NOT reach SMVMTR1 by itself. Path = `Sync-Machine.ps1 -Source CORPLTR94 -Target SMVMTR1 -What corpus -Apply` (into `\\SMVMTR1\d$\AIWork\work-ai`), then Gene runs `ai` on TR1: Install-AIMachine (R38) WRITES the corpus into the SkillsLinkRoot share before linking, so NO relink/manual copy is needed (I wrongly told Gene to relink 10/6). Verify from the laptop: `\\SMVMTR1\c$\Users\speedmerchants\.claude\machine-config.state.json` installedAt + `files` hashes vs the D: corpus. Laptop can't follow the share symlinks (Test-Path false is expected).
- Kit scripts throw on a UNC -Repo (Resolve-Path adds a `Microsoft.PowerShell.Core\FileSystem::` prefix): map a temporary drive (`net use W: \\SMVMTR1\d$ /persistent:no`) to drive the TR1 board from the laptop, delete after.

**Why:** TR1 edits must flow back without clobbering laptop work; stage /MIR used to wipe them.
**How to apply:** for any "sync X to Y" request use the machine-sync skill; never re-stage a TR without a sync first. Related: [[project_machine_config_tr1_live_2026-10-01]], [[project_machine_config_laptop_live_2026-10-01]].

2026-10-11 TR1->laptop: 32 stream corpus files applied + published; profile CONFLICT resolved by hand-merge written to BOTH (TR1 Adhoc/addStreamTab -Role + laptop 10/5 --session-id launcher; role lookup also checks GeneStreamOnDemandRoles), base set from SMVMTR1. Traps: D: (DeployRoot) is NAS, reconnect `net use D: \\SynologyDS918\devopslocal` first; `pwsh -File ... -What a,b` fails ValidateSet (one string) - omit -What or pass one value. Profile base json is a hash only, no content: 3-way merge must be done by reading both sides.
