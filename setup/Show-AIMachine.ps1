#requires -Version 7
# /machine-config show: prints this machine's resolved paths, resource write routes, Claude access list, git policy
# and MCP servers, all from the machine profile (ProfileMachineConfig.md). Read-only.
param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'MachineConfig.psm1') } | Select-Object -First 1
Import-Module (Join-Path $lib 'MachineConfig.psm1') -Force -DisableNameChecking
if (-not $ConfigPath) { $ConfigPath = Get-AIMachineConfigPath }
$prof = Get-AIMachineProfile -Path $ConfigPath

"Machine profile: $($prof.Path)"
''
'Paths'
Get-AIConfig -ConfigPath $ConfigPath | Select-Object Key, Value, Location | Format-Table -AutoSize | Out-String -Width 220
'Resources (write routes)'
$prof.Resources | Select-Object Key, @{ n = 'Path'; e = { $prof.Keys[$_.Key] } }, Route, Endpoint | Format-Table -AutoSize | Out-String -Width 220
'Claude access'
$prof.Access | Select-Object PathSpec, Path, @{ n = 'Access'; e = { $_.Access -join ', ' } }, Note | Format-Table -AutoSize | Out-String -Width 220
'Git policy (a repo not listed gets no commit, push or worktree)'
$prof.GitPolicy | Select-Object RepoSpec, Repo, Commit, Push, Worktrees | Format-Table -AutoSize | Out-String -Width 220
'MCP servers'
$prof.Mcp | Select-Object Server, Install, Note | Format-Table -AutoSize | Out-String -Width 220
$problems = @(Test-AIMachineProfile -Profile $prof)
if ($problems.Count) { 'Profile problems'; $problems | Format-Table -AutoSize | Out-String -Width 220 } else { 'Profile validation: no problems.' }
