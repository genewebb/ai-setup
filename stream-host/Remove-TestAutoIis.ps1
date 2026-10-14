# Remove-TestAutoIis.ps1 -- remove the IIS applications under Default Web Site/TestAuto and the TestAuto-* app pools
# on CORPVM17. IIS refuses to delete a pool that still has applications, and with the TestAuto folder gone IIS Manager
# no longer shows those applications, so they are deleted here by appcmd first, then the pools.
# Run ON CORPVM17 in an elevated console (pwsh 7 or Windows PowerShell):
#   pwsh -NoProfile -File C:\tmp\stream-host\Remove-TestAutoIis.ps1           # dry run: lists what would go
#   pwsh -NoProfile -File C:\tmp\stream-host\Remove-TestAutoIis.ps1 -Apply    # backs up the IIS config, then deletes
# Undo: appcmd restore backup <the backup name printed by -Apply>
# Leaves alone: the Windows service "Profisee 25.2.0 (TestAuto)", C:\Program Files\Profisee\...\25.2.0, its database.
param([switch] $Apply)
$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an elevated console (Run as administrator).' }
$appcmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
if (-not (Test-Path $appcmd)) { throw "appcmd not found at $appcmd" }

$apps = @(([xml](& $appcmd list app /xml)).appcmd.APP |
    Where-Object { $_.'APPPOOL.NAME' -like 'TestAuto-*' -or $_.'APP.NAME' -like 'Default Web Site/TestAuto/*' } |
    Sort-Object { $_.'APP.NAME'.Length } -Descending)
$pools = @(([xml](& $appcmd list apppool /xml)).appcmd.APPPOOL | Where-Object { $_.'APPPOOL.NAME' -like 'TestAuto-*' })

# A TestAuto-* pool used by an application OUTSIDE /TestAuto would break that application: stop rather than guess.
$foreign = @(([xml](& $appcmd list app /xml)).appcmd.APP | Where-Object { $_.'APPPOOL.NAME' -like 'TestAuto-*' -and $_.'APP.NAME' -notlike 'Default Web Site/TestAuto/*' })
if ($foreign) { throw "TestAuto-* pools are also used outside /TestAuto: $(($foreign | ForEach-Object { $_.'APP.NAME' }) -join ', '). Nothing changed." }

Write-Host "Applications to delete ($($apps.Count)):"; $apps | ForEach-Object { Write-Host "  $($_.'APP.NAME')  (pool $($_.'APPPOOL.NAME'))" }
Write-Host "App pools to delete ($($pools.Count)):"; $pools | ForEach-Object { Write-Host "  $($_.'APPPOOL.NAME')  ($($_.state))" }
if (-not $Apply) { Write-Host "`nDry run: nothing changed. Re-run with -Apply to delete." -ForegroundColor Yellow; return }

$backup = 'pre-testauto-cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
& $appcmd add backup $backup | Out-Null
if ($LASTEXITCODE) { throw "appcmd backup failed ($LASTEXITCODE): nothing changed" }
Write-Host "IIS config backed up as '$backup' (undo: appcmd restore backup $backup)" -ForegroundColor Green

foreach ($a in $apps) {
    & $appcmd delete app "$($a.'APP.NAME')" | Out-Null
    if ($LASTEXITCODE) { throw "delete app $($a.'APP.NAME') failed ($LASTEXITCODE); restore with: appcmd restore backup $backup" }
    Write-Host "  deleted app $($a.'APP.NAME')"
}
foreach ($p in $pools) {
    $name = $p.'APPPOOL.NAME'
    if ($p.state -eq 'Started') { & $appcmd stop apppool /apppool.name:"$name" | Out-Null }
    & $appcmd delete apppool "$name" | Out-Null
    if ($LASTEXITCODE) { throw "delete apppool $name failed ($LASTEXITCODE); restore with: appcmd restore backup $backup" }
    Write-Host "  deleted pool $name"
}
$left = @(([xml](& $appcmd list apppool /xml)).appcmd.APPPOOL | Where-Object { $_.'APPPOOL.NAME' -like 'TestAuto-*' }).Count
Write-Host "`nDone. TestAuto-* pools left: $left" -ForegroundColor Green
