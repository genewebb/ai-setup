---
name: project_profile_machine_config
description: "Gene's pwsh profile is identical on CORPLTR94/SMVMTR1/SMVMTR2; machine paths come from C:\\Deploy\\Setup\\ProfileMachineConfig.md (markdown table) read at load"
metadata:
  node_type: memory
  type: project
  originSessionId: 3c7befd5-5a8d-40da-a9e6-8266ba3e66e8
  modified: 2026-09-29T03:31:42.013Z
---

2026-09-28: the PowerShell 7 profile (`Documents\PowerShell\Microsoft.PowerShell_profile.ps1`) plus Gene.DevOpsTools / Gene.GitTools were refactored so ONE profile runs on the laptop (agenewe) and on SMVMTR1 + SMVMTR2 (CORP\speedmerchants).

- `#region Machine config` at the top of the profile: `$global:GeneMachineDefaults` (laptop values), `Read-GeneMachineConfig`, `Get-GeneMachineSetting -Name X -MustExist`, `Show-GeneMachineConfig` (alias `machinecfg`). Result in `$global:GeneMachine`. Modules use `Get-GeneMachineRoot Key 'fallback'`.
- Config = `C:\Deploy\Setup\ProfileMachineConfig.md` on each machine (Gene's choice: .md, hand-edited). Table `| Key | Value | Used by | Status |`; missing row = default, blank Value = not available here, %VARS% expanded. Status column is informational only.
- VMs: PowershellScriptsDir = `C:\PowershellScripts` (pre-existing VM folder; laptop scripts merged in as new-files-only, 3 VM files kept that differ), all other paths on C: ([[feedback_vm_d_drive_containers_only]]). LocalSpeedSecretsFile blank. The Speedy server deployment kit (New-SpeedyBundle.ps1 + 16 files) MOVED 9/28 from the vault (`99 Documentation\speedy\deployment`, now a pointer README) to `<SpeedyRepo>\deploy\`; dpv2 derives the script path from SpeedyRepo, there is no SpeedyBundleScript key any more. Copied straight into both VM trees (untracked until Gene's next sync).
- Installed on both VMs via choco 9/28: InnoSetup 6.7.1, python314 (C:\Python314), ffmpeg, tesseract; markitdown 0.1.7 venv at `C:\Users\speedmerchants\.venvs\markitdown` (the `[all]` extra fails on 3.14 via youtube-transcript-api; used explicit extras). ocr_pdf.py at `C:\devopslocal\powershellscripts`.
- To push profile changes: copy profile + Gene.* psm1 to `\\<vm>\c$\Users\speedmerchants\Documents\PowerShell\`, never overwrite the per-machine .md.
- The `dotnet-suggest` entry in `$Error` after load is pre-existing and silent (Get-Command -EA SilentlyContinue still records).
- WinRM (as agenewe) works to both VMs for installs; CORPNAS01 fails only as a WinRM double hop (port 445 open).
