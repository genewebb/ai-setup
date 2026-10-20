# Wakes stream runners on demand (kit item IN-20261020102535-b7f2, owner ask 2026-10-20), instead of waiting out an
# idle watch, an idle backoff or a failed-run backoff. Writes .streams\runners\WAKE (-Role all), WAKE-<role> or
# WAKE-<runner id> (-Runner), the files Start-StreamRunner.ps1 checks in every wait (lib\Streams.ps1 Get-WakeRequest).
# The file is never deleted: each runner remembers the newest wake it acted on, so one write wakes every runner it
# names. -Force writes 'force' as the first line: the woken runner skips its gate once and launches a unit (a model
# call even with nothing to do; a work runner still claims in its pre-stage). Prints WAKE <file> and the live runner
# state files it addresses; logs decisions.md.
# -Tab (kit item IN-20261020104236-1401) names runners by the terminal tab they run in, the 'tab' field of
# .streams\runners\runner-*.json ('Builder 2'), case-insensitive, several per call (a comma list in one string too).
# Each resolves to its live (not stopped) runner, the newest state file when a tab was reused, and gets its own
# WAKE-<runner id>. An unknown tab writes nothing and exits 2 with the live tabs listed.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [ValidateSet('all', 'author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')] [string] $Role = 'all',
    [string] $Runner,
    [string[]] $Tab,
    [switch] $Force,
    [string] $Reason = 'owner wake',
    [string] $Session = 'owner'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths $Repo
$dir = Join-Path $P.Root 'runners'
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$states = foreach ($sf in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
    try { $s = Get-Content -LiteralPath $sf.FullName -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { continue }
    if (-not $s -or -not $s.Contains('role')) { continue }
    [pscustomobject]@{ id = [IO.Path]::GetFileNameWithoutExtension($sf.Name); s = $s; live = [string]$s['status'] -notlike 'stopped*'; tab = [string]$(if ($s.Contains('tab')) { $s['tab'] }) }
}
$targets = @()
if ($Tab) {
    $names = @($Tab | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknown = @()
    foreach ($n in $names) {
        $hit = @($states | Where-Object { $_.live -and $_.tab -and $_.tab -ieq $n }) | Select-Object -First 1
        if ($hit) { if ($targets -notcontains $hit.id) { $targets += $hit.id } } else { $unknown += $n }
    }
    if ($unknown) {
        "UNKNOWN-TAB $($unknown -join ', ')"
        "  live tabs: $((@($states | Where-Object { $_.live -and $_.tab } | ForEach-Object { $_.tab } | Sort-Object -Unique)) -join ', ')"
        exit 2
    }
} elseif ($Runner) { $targets = @($Runner) }
$names = if ($targets) { @($targets | ForEach-Object { "WAKE-$_" }) } elseif ($Role -eq 'all') { @('WAKE') } else { @("WAKE-$Role") }
$reasonLine = ($Reason -replace '[\r\n]+', ' ').Trim()
foreach ($name in $names) {
    Write-AtomicText (Join-Path $dir $name) ("$(if ($Force) { 'force' } else { 'wake' })`n$reasonLine`n$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    Add-Decision $P $Session "WAKE $name$(if ($Force) { ' force' }) : $reasonLine"
    "WAKE $name$(if ($Force) { ' force' }) $reasonLine"
}
foreach ($st in @($states)) {
    $s = $st.s; $id = $st.id
    if ($targets -and $targets -notcontains $id) { continue }
    if (-not $targets -and $Role -ne 'all' -and [string]$s['role'] -ne $Role) { continue }
    if ([string]$s['status'] -like 'stopped*') { continue }
    "  runner $id role $($s['role'])$(if ($st.tab) { " tab '$($st.tab)'" }) status $($s['status'])"
}
