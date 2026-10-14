#requires -Version 7
<#
.SYNOPSIS
    Harvests clicked permission approvals back into shared policy (spec 4.3a "harvest", R9, R10).

.DESCRIPTION
    Sources of clicked approvals:
      - the harvest queue {ClaudeHome}\machine-config.pending.json (rules found in settings.json at a drift stop);
      - live settings.json rules that the last install did not generate (state.lastSettings);
      - repo-local <repo>\.claude\settings.local.json files under ReposRoot and WorktreesRoot (R10).

    Each approval is classified by tool, operation, tier, scope (repo or user) and full rule text. It is marked
    'covered' ONLY when the installed generated policy provably allows the same operation in the same tier for a
    scope at least as wide: an identical rule, a same-tool file rule whose //path/** contains it, a command rule
    Tool(*) or Tool(prefix:*) that matches it, or an mcp__server rule for its tool. Path containment by a DIFFERENT
    tool (a Read access row for a script run, or an edit under a read-only row) never covers anything; an approval
    that a generated deny contradicts is marked 'conflict'.

    Actions:
      propose   (default) classify, give each uncovered approval a proposed {Key} form, write the report.
      accept    -Id <ids> [-Global]. Without -Global the approval stays repo/user scoped where it is ('kept').
                With -Global its {Key} form is added to the corpus permissions.yaml (through Write-AIFile).
      reject    -Id <ids>. Recorded; the rule stays where it is and is not proposed again.
      finalize  For each accepted global item whose rendered replacement is present in the installed settings.json
                AND in the last install's generated set, remove the original exact entry from its source, and mark
                the item 'verified'. Nothing is removed before that check passes. Other settings are preserved.

    Item state lives in {ClaudeHome}\machine-config.harvest.json. A rejected or kept item is never re-proposed.
#>
[CmdletBinding()]
param(
    [ValidateSet('propose', 'accept', 'reject', 'finalize')][string]$Action = 'propose',
    [string[]]$Id,
    [switch]$Global,
    [string]$ConfigPath,
    [string]$CorpusRoot,
    [string]$ClaudeHome,
    [string[]]$RepoSearchRoots
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'MachineConfig.psm1') } | Select-Object -First 1
foreach ($m in 'MachineConfig', 'AISettings', 'AIFile') { Import-Module (Join-Path $lib "$m.psm1") -Force -DisableNameChecking }

if (-not $ConfigPath) { $ConfigPath = Get-AIMachineConfigPath }
$prof = Get-AIMachineProfile -Path $ConfigPath
$keys = $prof.Keys
if (-not $ClaudeHome) { $ClaudeHome = $keys['ClaudeHome'] }
if (-not $CorpusRoot) { $CorpusRoot = $keys['AIWorkRoot'] }
if (-not $RepoSearchRoots) { $RepoSearchRoots = @($keys['ReposRoot'], $keys['WorktreesRoot']) | Where-Object { $_ } }

$statePath = Join-Path $ClaudeHome 'machine-config.state.json'
$pendingPath = Join-Path $ClaudeHome 'machine-config.pending.json'
$harvestPath = Join-Path $ClaudeHome 'machine-config.harvest.json'
$settingsPath = Join-Path $ClaudeHome 'settings.json'
$tiers = 'allow', 'ask', 'deny'
$fileTools = 'Read', 'Edit', 'Write', 'NotebookEdit', 'MultiEdit'
$cmdTools = 'Bash', 'PowerShell'

function Read-Json([string]$p) { if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -AsHashtable -Depth 50 } else { $null } }
function Write-JsonAtomic([string]$p, $obj) {
    $tmp = "$p.tmp.$PID"
    ($obj | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $p -Force
}
function Get-Rules($settings, [string]$tier) {
    if ($settings -and $settings.Contains('permissions') -and $settings.permissions -and $settings.permissions.Contains($tier)) { return @($settings.permissions[$tier] | Where-Object { $_ }) }
    @()
}
function Split-Rule([string]$r) {
    if ($r -match '^([A-Za-z][A-Za-z0-9_]*)\((.*)\)$') { return [pscustomobject]@{ Tool = $Matches[1]; Arg = $Matches[2] } }
    [pscustomobject]@{ Tool = $r; Arg = $null }
}
function Get-Operation([string]$tool) {
    if ($tool -in $fileTools) { return "file:$tool" }
    if ($tool -in $cmdTools) { return "command:$tool" }
    if ($tool -like 'mcp__*') { return 'mcp' }
    return "tool:$tool"
}
function ConvertTo-RuleForm([string]$arg) {
    # A file-rule argument in //c/... form, lower-case; '~' and relative forms are returned unchanged.
    if ($arg -match '^[A-Za-z]:[\\/]') { return (ConvertTo-AIRulePath $arg).ToLowerInvariant() }
    if ($arg -match '^/([A-Za-z])/') { return ('/' + $arg).ToLowerInvariant() }
    if ($arg -match '^//[A-Za-z]/') { return $arg.ToLowerInvariant() }
    $arg
}
function Test-Covered([string]$tier, [string]$rule, $gen) {
    # Returns 'covered', 'conflict' or 'open'. $gen = hashtable tier -> generated rules of the last install.
    $x = Split-Rule $rule
    $same = @($gen[$tier])
    if ($same -contains $rule) { return 'covered' }
    if ($tier -ne 'deny') {
        foreach ($d in @($gen['deny'])) {
            $y = Split-Rule $d
            if ($y.Tool -eq $x.Tool -and $null -ne $x.Arg -and $null -ne $y.Arg -and $y.Arg.EndsWith('/**')) {
                $root = $y.Arg.Substring(0, $y.Arg.Length - 3).ToLowerInvariant()
                $p = ConvertTo-RuleForm $x.Arg
                if ($p -eq $root -or $p.StartsWith("$root/")) { return 'conflict' }
            }
        }
    }
    foreach ($g in $same) {
        $y = Split-Rule $g
        if ($x.Tool -like 'mcp__*' -and $null -eq $y.Arg -and ($x.Tool -eq $y.Tool -or $x.Tool.StartsWith("$($y.Tool)__"))) { return 'covered' }
        if ($y.Tool -ne $x.Tool) { continue }
        if ($null -eq $x.Arg) { continue }
        if ($x.Tool -in $fileTools -and $null -ne $y.Arg -and $y.Arg.EndsWith('/**')) {
            $root = $y.Arg.Substring(0, $y.Arg.Length - 3).ToLowerInvariant()
            $p = ConvertTo-RuleForm $x.Arg
            if ($p -eq $root -or $p.StartsWith("$root/")) { return 'covered' }
        }
        if ($x.Tool -in $cmdTools -and $null -ne $y.Arg) {
            if ($y.Arg -eq '*') { return 'covered' }
            if ($y.Arg.EndsWith(':*') -and $x.Arg.StartsWith($y.Arg.Substring(0, $y.Arg.Length - 2))) { return 'covered' }
        }
    }
    'open'
}
function Get-KeyForm([string]$rule) {
    # Longest machine path first, in Windows, forward-slash, //c and /c spellings.
    $x = Split-Rule $rule
    if ($null -eq $x.Arg) { return $rule }
    $arg = $x.Arg
    $pairs = foreach ($k in $keys.Keys) {
        $v = [string]$keys[$k]
        if ($v -notmatch '^[A-Za-z]:\\') { continue }
        $v = $v.TrimEnd('\')
        $d = $v.Substring(0, 1).ToLowerInvariant(); $rest = $v.Substring(2)
        foreach ($form in @($v, ($v -replace '\\', '/'), ("//$d" + ($rest -replace '\\', '/')), ("/$d" + ($rest -replace '\\', '/')))) {
            [pscustomobject]@{ Key = $k; Form = $form }
        }
    }
    foreach ($p in @($pairs | Sort-Object { $_.Form.Length } -Descending)) {
        $i = $arg.IndexOf($p.Form, [StringComparison]::OrdinalIgnoreCase)
        while ($i -ge 0) {
            $end = $i + $p.Form.Length
            if ($end -eq $arg.Length -or $arg[$end] -in '\', '/', '"', "'", ' ', '*', ')') {
                $arg = $arg.Substring(0, $i) + "{$($p.Key)}" + $arg.Substring($end)
                $i = $arg.IndexOf($p.Form, $i + $p.Key.Length + 2, [StringComparison]::OrdinalIgnoreCase)
            }
            else { $i = $arg.IndexOf($p.Form, $end, [StringComparison]::OrdinalIgnoreCase) }
        }
    }
    "$($x.Tool)($arg)"
}
function Get-ItemId([string]$tier, [string]$rule, [string]$scope, [string]$source) {
    $b = [Text.Encoding]::UTF8.GetBytes("$tier|$rule|$scope|$source")
    ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))).Substring(0, 8).ToLowerInvariant()
}

$state = Read-Json $statePath
$gen = @{ allow = @(); ask = @(); deny = @() }
$haveInstall = $false
if ($state -and $state.Contains('lastSettings') -and $state.lastSettings) {
    $haveInstall = $true
    foreach ($t in $tiers) { if ($state.lastSettings.Contains($t)) { $gen[$t] = @($state.lastSettings[$t]) } }
}
$store = Read-Json $harvestPath
$items = [System.Collections.Generic.List[object]]::new()
if ($store -and $store.Contains('items')) { foreach ($i in @($store.items)) { $items.Add($i) } }
function Find-Item([string]$id) { $items | Where-Object { $_.id -eq $id } | Select-Object -First 1 }

function Save-Store { Write-JsonAtomic $harvestPath ([ordered]@{ version = 1; items = @($items) }) }

# ---- gather ----
function Get-Candidates {
    $c = [System.Collections.Generic.List[object]]::new()
    $pend = Read-Json $pendingPath
    if ($pend -and $pend.Contains('items')) {
        foreach ($p in @($pend.items)) { $c.Add([pscustomobject]@{ tier = $p.tier; rule = $p.rule; scope = 'user'; repo = ''; source = $pendingPath; sourceKind = 'pending' }) }
    }
    if ($haveInstall) {
        $live = Read-Json $settingsPath
        foreach ($t in $tiers) { foreach ($r in Get-Rules $live $t) { if ($r -notin $gen[$t]) { $c.Add([pscustomobject]@{ tier = $t; rule = $r; scope = 'user'; repo = ''; source = $settingsPath; sourceKind = 'settings' }) } } }
    }
    foreach ($root in $RepoSearchRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $cands = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)
        $cands += @($cands | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue })
        foreach ($d in $cands) {
            $f = Join-Path $d.FullName '.claude\settings.local.json'
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $repo = if (Test-Path -LiteralPath (Join-Path $d.FullName '.git') -PathType Container) { $d.Name } else { "$(Split-Path -Leaf (Split-Path $d.FullName))/$($d.Name)" }
            $js = Read-Json $f
            foreach ($t in $tiers) { foreach ($r in Get-Rules $js $t) { $c.Add([pscustomobject]@{ tier = $t; rule = $r; scope = 'repo'; repo = $repo; source = $f; sourceKind = 'repo-local' }) } }
        }
    }
    $c
}

switch ($Action) {
    'propose' {
        $seen = @{}
        foreach ($c in Get-Candidates) {
            $id = Get-ItemId $c.tier $c.rule $c.scope $c.source
            if ($seen[$id]) { continue }; $seen[$id] = $true
            $cov = if ($haveInstall) { Test-Covered $c.tier $c.rule $gen } else { 'open' }
            $old = Find-Item $id
            if ($old -and $old.status -in 'rejected', 'kept', 'accepted', 'verified') { $old.coverage = $cov; continue }
            $x = Split-Rule $c.rule
            $entry = [ordered]@{
                id = $id; tier = $c.tier; rule = $c.rule; tool = $x.Tool; operation = (Get-Operation $x.Tool)
                scope = $c.scope; repo = $c.repo; source = $c.source; sourceKind = $c.sourceKind
                coverage = $cov; proposed = (Get-KeyForm $c.rule)
                status = $(if ($cov -eq 'covered') { 'covered' } else { 'proposed' })
                seen = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            if ($old) { [void]$items.Remove($old) }
            $items.Add($entry)
        }
        Save-Store
        $sb = [Text.StringBuilder]::new()
        [void]$sb.AppendLine("# Harvest report ($((Get-Date).ToString('yyyy-MM-dd HH:mm')))")
        [void]$sb.AppendLine('')
        if (-not $haveInstall) { [void]$sb.AppendLine('No installed revision: nothing can be proven covered, so every approval is listed as open.'); [void]$sb.AppendLine('') }
        [void]$sb.AppendLine('| id | status | tier | scope | rule | proposed | source |')
        [void]$sb.AppendLine('|---|---|---|---|---|---|---|')
        foreach ($i in $items | Sort-Object status, tier, rule) {
            $scope = if ($i.scope -eq 'repo') { "repo $($i.repo)" } else { 'user' }
            [void]$sb.AppendLine("| $($i.id) | $($i.status) | $($i.tier) | $scope | ``$($i.rule)`` | ``$($i.proposed)`` | $($i.sourceKind) |")
        }
        $report = Join-Path $ClaudeHome 'machine-config\harvest-report.md'
        New-Item -ItemType Directory -Force -Path (Split-Path $report) | Out-Null
        [IO.File]::WriteAllText($report, $sb.ToString())
        $sb.ToString()
        "Report: $report. Next: -Action accept -Id <ids> [-Global], or -Action reject -Id <ids>."
    }
    'reject' {
        foreach ($i in $Id) { $it = Find-Item $i; if (-not $it) { throw "No harvest item '$i'. Run -Action propose first." }; $it.status = 'rejected' }
        Save-Store; "rejected: $($Id -join ', ') (the rules stay where they are)"
    }
    'accept' {
        $add = [System.Collections.Generic.List[object]]::new()
        foreach ($i in $Id) {
            $it = Find-Item $i; if (-not $it) { throw "No harvest item '$i'. Run -Action propose first." }
            if ($it.status -eq 'covered') { "skip $i`: already covered by the generated policy"; continue }
            if ($Global) { $it.status = 'accepted'; $add.Add($it) } else { $it.status = 'kept'; "kept $i in its $($it.scope) scope ($($it.source))" }
        }
        if ($add.Count) {
            $yamlPath = Join-Path $CorpusRoot 'claude\permissions.yaml'
            $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($yamlPath))
            foreach ($it in $add) {
                $head = $lines.FindIndex([Predicate[string]] { param($l) $l -match "^$($it.tier):\s*$" })
                if ($head -lt 0) { throw "permissions.yaml has no '$($it.tier):' section." }
                $end = $head + 1
                while ($end -lt $lines.Count -and $lines[$end] -match '^\s*-\s') { $end++ }
                $exists = $false
                for ($k = $head + 1; $k -lt $end; $k++) { if (($lines[$k] -replace '^\s*-\s*', '').Trim("'") -ceq $it.proposed) { $exists = $true } }
                if (-not $exists) {
                    $v = if ($it.proposed -match '^[^A-Za-z]|: |\s#|[''"]') { "'" + $it.proposed.Replace("'", "''") + "'" } else { $it.proposed }
                    $lines.Insert($end, "- $v")
                }
            }
            $text = ($lines -join "`n") + "`n"
            $check = ConvertFrom-Yaml $text
            foreach ($it in $add) { if (@($check[$it.tier]) -notcontains $it.proposed) { throw "permissions.yaml would not parse back to '$($it.proposed)' under $($it.tier); nothing written." } }
            $r = Write-AIFile -Path $yamlPath -Text $text
            "permissions.yaml updated ($($r.Route)): $($add.Count) rule(s). Run /machine-config apply, then -Action finalize."
        }
        Save-Store
    }
    'finalize' {
        $live = Read-Json $settingsPath
        foreach ($it in @($items | Where-Object status -eq 'accepted')) {
            $rendered = @(ConvertTo-AIRules -Rule $it.proposed -Keys $keys | ForEach-Object { $_ })   # the function returns a wrapped array
            $ok = $rendered.Count -gt 0
            foreach ($r in $rendered) { if ($r -notin @(Get-Rules $live $it.tier) -or $r -notin $gen[$it.tier]) { $ok = $false } }
            if (-not $ok) { "not yet: $($it.id) $($it.proposed) is not in the installed settings; run /machine-config apply first"; continue }
            switch ($it.sourceKind) {
                'repo-local' {
                    $js = Read-Json $it.source
                    if ($js) {
                        $js.permissions[$it.tier] = @(Get-Rules $js $it.tier | Where-Object { $_ -cne $it.rule })
                        Write-JsonAtomic $it.source $js
                    }
                }
                'pending' {
                    $pend = Read-Json $pendingPath
                    if ($pend) { $pend.items = @($pend.items | Where-Object { -not ($_.rule -ceq $it.rule -and $_.tier -eq $it.tier) }); Write-JsonAtomic $pendingPath $pend }
                }
                default { }   # a live settings.json rule: the applicator owns permissions, so the installed set replaced it
            }
            $it.status = 'verified'
            "verified $($it.id): $($it.rule) -> $($rendered -join ', ')"
        }
        Save-Store
    }
}
