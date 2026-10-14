#Requires -Version 7
<#
.SYNOPSIS
  Top N memory consumers on this machine, rolled up to where the memory is coming from.

.DESCRIPTION
  Groups processes into SOURCES instead of raw process names, so the answer reads as
  "which thing is using my RAM" rather than "38 w3wp, 26 dotnet, 18 node":

    Claude Code session   claude.exe plus every descendant (MCP servers, tool shells,
                          builds, test hosts, conhost)
    IIS: <install>        w3wp.exe plus its out-of-process dotnet children, grouped by the
                          app-pool prefix before the first '-' (speedmerchants-data -> speedmerchants)
    Service: <name>       a non-svchost service process plus its descendants
    Windows services      every shared svchost.exe
    <process name>        everything else, all instances of one name (firefox, msedge, ...)

  A process belongs to the OUTERMOST source in its parent chain, so a claude.exe launched by
  a hook inside a Claude session counts toward that session, not as a second one.

  Read-only. No elevation needed; a process whose details cannot be read still counts by name.

.PARAMETER Top
  Number of sources to show. Default 10.

.PARAMETER ShowMembers
  Also list every member process (PID, name, MB) under each source.

.EXAMPLE
  pwsh -NoProfile -File Get-TopMemory.ps1
.EXAMPLE
  pwsh -NoProfile -File Get-TopMemory.ps1 -Top 15 -ShowMembers
#>
[CmdletBinding()]
param(
  [ValidateRange(1, 200)]
  [int]$Top = 10,

  [switch]$ShowMembers
)

$ErrorActionPreference = 'Stop'

# --- Snapshot ---------------------------------------------------------------------------
$os      = Get-CimInstance Win32_OperatingSystem
$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$freeMB  = [math]::Round($os.FreePhysicalMemory / 1KB)
$usedMB  = $totalMB - $freeMB

$liveById = @{}
foreach ($p in Get-Process) { $liveById[$p.Id] = $p }

$cimById = @{}
foreach ($c in Get-CimInstance Win32_Process) { $cimById[[int]$c.ProcessId] = $c }

$servicesById = @{}
foreach ($s in Get-CimInstance Win32_Service -Filter "State='Running'") {
  $sid = [int]$s.ProcessId
  if ($sid -le 0) { continue }
  if (-not $servicesById.ContainsKey($sid)) { $servicesById[$sid] = [System.Collections.Generic.List[string]]::new() }
  $servicesById[$sid].Add($s.DisplayName)
}

# --- Source rules -----------------------------------------------------------------------
# Returns the source label if this process is itself a roll-up root, else $null.
function Get-RootLabel {
  param([int]$ProcessId)

  $c = $cimById[$ProcessId]
  if (-not $c) { return $null }

  if ($c.Name -eq 'claude.exe') {
    $started = if ($c.CreationDate) { $c.CreationDate.ToString('M/d HH:mm') } else { '?' }
    return "Claude Code session (PID $ProcessId, started $started)"
  }

  if ($c.Name -eq 'w3wp.exe') {
    $prefix = 'unknown pool'
    if ($c.CommandLine -and $c.CommandLine -match '-ap "([^"]+)"') {
      $prefix = ($Matches[1] -split '-', 2)[0]
    }
    return "IIS: $prefix app pools"
  }

  if ($c.Name -ne 'svchost.exe' -and $servicesById.ContainsKey($ProcessId)) {
    $names = $servicesById[$ProcessId] -join ', '
    # vmmemWSL / vmmem (the WSL2 + Docker VM) are children of this service; say what it really is.
    if ($c.Name -eq 'vmcompute.exe') { return "WSL2 / Docker VMs ($names)" }
    return "Service: $names"
  }

  return $null
}

# Walks the parent chain and returns the OUTERMOST root label, or $null.
# A parent created after its child is a recycled PID, not the real parent - stop there.
function Get-SourceLabel {
  param([int]$ProcessId)

  $label   = Get-RootLabel -ProcessId $ProcessId
  $current = $cimById[$ProcessId]
  $seen    = [System.Collections.Generic.HashSet[int]]::new()
  [void]$seen.Add($ProcessId)

  while ($current) {
    $parentId = [int]$current.ParentProcessId
    if ($parentId -le 0 -or -not $seen.Add($parentId)) { break }

    $parent = $cimById[$parentId]
    if (-not $parent) { break }
    if ($parent.CreationDate -and $current.CreationDate -and $parent.CreationDate -gt $current.CreationDate) { break }

    $parentLabel = Get-RootLabel -ProcessId $parentId
    if ($parentLabel) { $label = $parentLabel }
    $current = $parent
  }

  return $label
}

# --- Attribute every process ------------------------------------------------------------
$rows = foreach ($p in $liveById.Values) {
  $label = Get-SourceLabel -ProcessId $p.Id
  if (-not $label) {
    $label = if ($p.ProcessName -eq 'svchost') { 'Windows services (svchost)' } else { $p.ProcessName }
  }

  $poolName = $null
  $c = $cimById[$p.Id]
  if ($c -and $c.Name -eq 'w3wp.exe' -and $c.CommandLine -match '-ap "([^"]+)"') { $poolName = $Matches[1] }

  [pscustomobject]@{
    Source    = $label
    ProcId    = $p.Id
    Name      = $p.ProcessName
    Pool      = $poolName
    InRamMB   = $p.WorkingSet64 / 1MB
    PrivateMB = $p.PrivateMemorySize64 / 1MB
  }
}

$sources = $rows | Group-Object Source | ForEach-Object {
  $members = $_.Group
  $pools   = @($members | Where-Object Pool | Select-Object -ExpandProperty Pool -Unique)

  $mix = ($members | Group-Object Name | Sort-Object Count -Descending |
          ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }) -join ', '
  if ($pools.Count -gt 0) { $mix = "$($pools.Count) pools; $mix" }
  if ($mix.Length -gt 70) { $mix = $mix.Substring(0, 67) + '...' }

  [pscustomobject]@{
    Source    = $_.Name
    InRamMB   = [math]::Round(($members | Measure-Object InRamMB -Sum).Sum)
    PrivateMB = [math]::Round(($members | Measure-Object PrivateMB -Sum).Sum)
    Procs     = $members.Count
    Made_of   = $mix
    Members   = $members
  }
} | Sort-Object InRamMB -Descending

$topSources = @($sources | Select-Object -First $Top)
$topRamMB   = ($topSources | Measure-Object InRamMB -Sum).Sum

# --- Report -----------------------------------------------------------------------------
"RAM  total {0:N0} MB | used {1:N0} MB | free {2:N0} MB | snapshot {3:yyyy-MM-dd HH:mm:ss}" -f $totalMB, $usedMB, $freeMB, (Get-Date)
"Top $Top sources hold {0:N0} MB in RAM (working set; shared pages count in every process, so sums run high)" -f $topRamMB
""

$rank = 0
$topSources |
  ForEach-Object { $rank++; $_ | Add-Member -NotePropertyName '#' -NotePropertyValue $rank -PassThru } |
  Format-Table -AutoSize -Property '#', Source,
    @{ n = 'In RAM MB'; e = { '{0:N0}' -f $_.InRamMB }; a = 'Right' },
    @{ n = 'Private MB'; e = { '{0:N0}' -f $_.PrivateMB }; a = 'Right' },
    Procs, Made_of |
  Out-String -Width 250

if ($ShowMembers) {
  foreach ($s in $topSources) {
    "== $($s.Source)"
    $s.Members | Sort-Object InRamMB -Descending |
      Format-Table -AutoSize -Property ProcId, Name, Pool,
        @{ n = 'In RAM MB'; e = { '{0:N0}' -f $_.InRamMB }; a = 'Right' },
        @{ n = 'Private MB'; e = { '{0:N0}' -f $_.PrivateMB }; a = 'Right' } |
      Out-String -Width 250
  }
}
