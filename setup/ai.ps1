#requires -Version 7
<#
ai - start Claude Code on this machine's current configuration (spec 4.3c, R1, R2).

    ai [claude arguments...]

1. Reads the machine profile (C:\Deploy\Setup\ProfileMachineConfig.md, or AI_MACHINE_CONFIG).
2. Runs Install-AIMachine.ps1 -Launch: it applies when the installation identity changed (profile, corpus,
   templates, generator), under the per-install lock. A failed validation stops the launch here (R2).
3. Starts claude with CLAUDE_CODE_TMPDIR = {ScratchRoot} and AI_LAUNCH_REVISION = the installed revision,
   passing every argument through.
Installed by Install-AIMachine.ps1 as {ClaudeHome}\bin\ai.ps1, with an ai.cmd shim next to claude.exe.
#>
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'Install-AIMachine.ps1'
$lib = Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1'

& pwsh -NoProfile -NoLogo -File $installer -Launch
$code = $LASTEXITCODE
if ($code -eq 2) {
    Write-Host 'ai: the machine configuration is invalid (see above). Claude was NOT started. Fix the profile, then run ai again.' -ForegroundColor Red
    exit 2
}
if ($code -eq 3) {
    Write-Host 'ai: installed files or settings were edited outside the applicator, so the new revision was not applied. Starting on the previous install; run /machine-config check.' -ForegroundColor Yellow
}
elseif ($code -ne 0) {
    Write-Host "ai: the apply failed (exit $code); the previous install was restored. Claude was NOT started." -ForegroundColor Red
    exit $code
}

Import-Module $lib -Force -DisableNameChecking
$prof = Get-AIMachineProfile
$statePath = Join-Path $prof.Keys['ClaudeHome'] 'machine-config.state.json'
$rev = ''
if (Test-Path -LiteralPath $statePath) {
    $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    $rev = [string]$st.identity
}

# Stale exports (spec 5.11): a shell that ran an older apply may still carry AI_* values. The installed settings'
# env block is the truth: every AI_* it names is set from it, and an AI_* it no longer names (a key made blank or
# removed) is cleared, so claude and its children never see the old value. AI_MACHINE_CONFIG (which profile to read)
# and AI_TEST_* (test switches) are inputs, not exports, and are left alone.
$settingsPath = Join-Path $prof.Keys['ClaudeHome'] 'settings.json'
$sEnv = @{}
if (Test-Path -LiteralPath $settingsPath) {
    $s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    if ($s.Contains('env') -and $s.env) { $sEnv = $s.env }
}
foreach ($name in @(Get-ChildItem Env: | Where-Object Name -like 'AI_*' | ForEach-Object Name)) {
    if ($name -in 'AI_MACHINE_CONFIG', 'AI_LAUNCH_REVISION' -or $name -like 'AI_TEST_*') { continue }
    if (-not $sEnv.Contains($name)) { Remove-Item -LiteralPath "Env:\$name" }
}
foreach ($k in $sEnv.Keys) { if ($k -like 'AI_*') { Set-Item -LiteralPath "Env:\$k" -Value ([string]$sEnv[$k]) } }

$env:CLAUDE_CODE_TMPDIR = $prof.Keys['ScratchRoot']
$env:AI_LAUNCH_REVISION = $rev
& claude @args
exit $LASTEXITCODE
