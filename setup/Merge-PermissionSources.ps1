#requires -Version 7
<#
.SYNOPSIS
    One-time merge of today's permission sources into the corpus permissions.yaml (spec 4.3a).

.DESCRIPTION
    Reads:
      #1 the live ~\.claude\settings.json (the effective truth),
      #2 the old multi-client ~\AI\permissions\permissions.yaml,
      #3 the paused staging template (C:\tmp\AIWork style),   # history
      #4 repo .claude\settings*.json files under ReposRoot and any extra roots.
    Writes:
      - a proposed claude\permissions.yaml (path-free rules + shared path rules by {Key}),
      - a review report listing every rule and what happened to it.

    Rules for the proposal:
      - The live settings are the starting point; nothing that is live is silently lost.
      - Path rules (Read/Edit/Write) leave the shared file: they are machine allows and now come from the profile's
        '## Claude access' table. The report proves each one is covered by an access row, or lists it as uncovered.
      - '/c/'-form rules are no-ops today (relative to the settings folder) and are dropped.
      - Bash(...) and PowerShell(...) allows covered by Bash(*) / PowerShell(*) are dropped as redundant.
      - git push denies move to the git-guard hook (D19) and are dropped here.
      - Rules found only in the old yaml, the template or a repo file are NOT added (they would add prompts or
        denies that are not live today); they are listed for Gene.
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = (Join-Path $HOME '.claude\settings.json'),
    [string]$OldYamlPath = (Join-Path $HOME 'AI\permissions\permissions.yaml'),
    [string]$TemplatePath,
    [string[]]$RepoRoots = @(),
    [Parameter(Mandatory)][string]$OutYaml,
    [Parameter(Mandatory)][string]$OutReport,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1') -Force
Import-Module powershell-yaml
$profileArgs = @{}; if ($ConfigPath) { $profileArgs.Path = $ConfigPath }
$prof = Get-AIMachineProfile @profileArgs

$live = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json -AsHashtable
$lp = $live['permissions']
$report = [System.Collections.Generic.List[string]]::new()
$out = [ordered]@{ allow = [System.Collections.Generic.List[string]]::new(); ask = [System.Collections.Generic.List[string]]::new(); deny = [System.Collections.Generic.List[string]]::new() }
$fate = [System.Collections.Generic.List[object]]::new()
function Add-Fate($tier, $rule, $what, $why) { $fate.Add([pscustomobject]@{ Tier = $tier; Rule = $rule; Fate = $what; Why = $why }) }

# Longest-first key table for turning a literal path into {Key}\rest.
$pathKeys = foreach ($k in $prof.Keys.Keys) {
    $v = $prof.Keys[$k]
    if ($v -and $v -match '^([A-Za-z]:|\\\\)') { [pscustomobject]@{ Key = $k; Path = ([IO.Path]::GetFullPath($v).TrimEnd('\')) } }
}
$pathKeys = @($pathKeys | Sort-Object { $_.Path.Length } -Descending)
function ConvertTo-KeyPath([string]$p) {
    $norm = $p -replace '/', '\'
    foreach ($pk in $pathKeys) {
        if ($norm.StartsWith($pk.Path + '\', [StringComparison]::OrdinalIgnoreCase) -or $norm -ieq $pk.Path) {
            return '{' + $pk.Key + '}' + $norm.Substring($pk.Path.Length)
        }
    }
    return $null
}
function Test-CoveredByAccess([string]$tool, [string]$path) {
    # example-path: $path like 'C:\devops\repos\**'; covered when an access row with the right access contains it.
    $need = if ($tool -eq 'Read') { 'read' } else { 'edit' }
    $base = ($path -replace '/', '\') -replace '\\\*\*$', '' -replace '\\\*$', ''
    foreach ($a in $prof.Access) {
        if (-not $a.Path -or $need -notin $a.Access) { continue }
        if (Test-AIPathUnder -Child $base -Parent $a.Path) { return $a.PathSpec }
    }
    return $null
}

$hasBashStar = 'Bash(*)' -in $lp['allow']
$hasPwshStar = 'PowerShell(*)' -in $lp['allow']

foreach ($tier in 'allow', 'ask', 'deny') {
    foreach ($rule in @($lp[$tier])) {
        if ($rule -match '^(Read|Edit|Write)\((.*)\)$') {
            $tool = $Matches[1]; $path = $Matches[2]
            if ($path -match '^/[a-z]/') { Add-Fate $tier $rule 'dropped' "no-op today: a single leading '/' is relative to the settings folder"; continue }
            if ($path -match '^//') { $path = $path -replace '^//([a-z])/', '$1:/' }
            if ($tier -eq 'allow') {
                $cov = Test-CoveredByAccess $tool $path
                if ($cov) { Add-Fate $tier $rule 'moved to profile' "covered by access row $cov" }
                else { Add-Fate $tier $rule 'UNCOVERED' 'no access row covers it: add a row or accept the prompt' }
                continue
            }
            $kp = ConvertTo-KeyPath $path
            if ($kp) { $out[$tier].Add("$tool($kp)"); Add-Fate $tier $rule 'kept by key' "$tool($kp)" }
            else { Add-Fate $tier $rule 'UNMAPPED' 'a path deny/ask with no key: needs a key or a profile row' }
            continue
        }
        if ($tier -eq 'allow' -and $hasBashStar -and $rule -ne 'Bash(*)' -and $rule -match '^Bash\(') { Add-Fate $tier $rule 'dropped' 'covered by Bash(*)'; continue }
        if ($tier -eq 'allow' -and $hasPwshStar -and $rule -ne 'PowerShell(*)' -and $rule -match '^PowerShell\(') { Add-Fate $tier $rule 'dropped' 'covered by PowerShell(*)'; continue }
        if ($tier -eq 'deny' -and $rule -match '^(Bash|PowerShell)\(git push') { Add-Fate $tier $rule 'moved to git-guard' 'push is allowed per repo by the profile git policy (D19)'; continue }
        if ($rule -match '(?i)[a-z]:[\\/]|/[a-z]/') {
            # A command rule with a literal path: key it so the renderer writes both slash forms.
            $kr = [regex]::Replace($rule, '(?i)\b[a-z]:[\\/][^\s\)\*]*', { param($m) $k = ConvertTo-KeyPath $m.Value; if ($k) { $k } else { $m.Value } })
            $out[$tier].Add($kr); Add-Fate $tier $rule 'kept (keyed)' $kr; continue
        }
        if (-not $out[$tier].Contains($rule)) { $out[$tier].Add($rule) }
        Add-Fate $tier $rule 'kept' ''
    }
}

# Shared deny for the credentials folder: Edit by key. Read is covered by the credentials-guard hook, because any
# Read() deny rule makes Claude Code prompt on every 'cd <dir> && git ...' compound (see credentials-guard.ps1).
$credEdit = 'Edit({VaultWorkRoot}\00 Credentials\**)'
if (-not $out.deny.Contains($credEdit)) { $out.deny.Add($credEdit) }

# Other sources: report what is not live.
$liveAll = @($lp['allow']) + @($lp['ask']) + @($lp['deny'])
$others = [System.Collections.Generic.List[object]]::new()
if ($OldYamlPath -and (Test-Path -LiteralPath $OldYamlPath)) {
    $y = ConvertFrom-Yaml (Get-Content -LiteralPath $OldYamlPath -Raw)
    foreach ($tier in 'allow', 'ask', 'deny') {
        foreach ($c in @($y['commands'][$tier])) {
            $r = "Bash($c)"
            if ($tier -eq 'allow' -and $hasBashStar) { continue }      # all covered by Bash(*)
            $stem = { param($s) ($s -replace '^(Bash|PowerShell)\(', '' -replace '\)$', '' -replace ':?\*$', '').Trim() }
            $liveStems = @($lp[$tier] | ForEach-Object { & $stem $_ })
            if ((& $stem $r) -notin $liveStems) { $others.Add([pscustomobject]@{ Source = 'old yaml'; Tier = $tier; Rule = $r }) }
        }
    }
    foreach ($tier in 'allow', 'ask') {
        foreach ($f in @($y['file_access'][$tier])) { $others.Add([pscustomobject]@{ Source = 'old yaml file_access'; Tier = $tier; Rule = $f }) }
    }
}
if ($TemplatePath -and (Test-Path -LiteralPath $TemplatePath)) {
    $t = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($tier in 'allow', 'ask', 'deny') {
        foreach ($r in @($t['permissions'][$tier])) { if ($r -and $r -notin $liveAll) { $others.Add([pscustomobject]@{ Source = 'staging template'; Tier = $tier; Rule = $r }) } }
    }
}
foreach ($root in $RepoRoots) {
    foreach ($d in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $d.FullName '.claude') -Filter 'settings*.json' -File -ErrorAction SilentlyContinue) {
            $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -AsHashtable
            foreach ($tier in 'allow', 'ask', 'deny') {
                if (-not $j['permissions']) { continue }
                foreach ($r in @($j['permissions'][$tier])) {
                    if (-not $r) { continue }
                    $covered = ($r -match '^Bash\(' -and $hasBashStar) -or ($r -match '^PowerShell\(' -and $hasPwshStar)
                    $others.Add([pscustomobject]@{ Source = "repo $($f.FullName)"; Tier = $tier; Rule = $r + $(if ($covered) { '  [covered by *]' } else { '' }) })
                }
            }
        }
    }
}

# Write the proposed yaml.
$hdr = @'
# Claude Code permission rules shared by every machine (spec 4.3a, D20).
#
# Generated once by setup\Merge-PermissionSources.ps1 from the live settings, then maintained by hand.
# Owner of permissions.allow / ask / deny in the generated ~\.claude\settings.json together with the
# profile's '## Claude access' table (machine path allows). One owner per rule (R12).
#
# {Key} = a machine path from ProfileMachineConfig.md. In Read/Edit/Write rules it renders as //c/... ;
# in Bash/PowerShell command rules it renders literally, once with '\' and once with '/'.
# A rule whose {Key} is blank on a machine is skipped (a skipped deny is reported).
#
# The vault credentials folder: Edit is denied here; Read is blocked by the credentials-guard hook,
# because any Read() deny rule makes Claude Code prompt on every 'cd <dir> && git ...' compound.

'@
$yaml = ConvertTo-Yaml ([ordered]@{ allow = @($out.allow); ask = @($out.ask); deny = @($out.deny) })
New-Item -ItemType Directory -Force -Path (Split-Path $OutYaml) | Out-Null
[IO.File]::WriteAllText($OutYaml, $hdr + $yaml)

# Report.
$report.Add('# Permission merge report')
$report.Add('')
$report.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $SettingsPath. Profile: $($prof.Path).")
$report.Add('')
$report.Add("Proposed shared file: allow $($out.allow.Count), ask $($out.ask.Count), deny $($out.deny.Count).")
$report.Add('')
foreach ($g in $fate | Group-Object Fate | Sort-Object Name) { $report.Add("- $($g.Name): $($g.Count)") }
$report.Add('')
$report.Add('## Needs attention')
$report.Add('')
$att = @($fate | Where-Object Fate -in 'UNCOVERED', 'UNMAPPED')
if (-not $att) { $report.Add('None: every live path allow is covered by an access row, and every path deny/ask has a key.') }
foreach ($f in $att) { $report.Add("- **$($f.Fate)** [$($f.Tier)] ``$($f.Rule)``: $($f.Why)") }
$report.Add('')
$report.Add('## Broad rules to confirm')
$report.Add('')
foreach ($r in 'Bash(*)', 'PowerShell(*)') { if ($out.allow.Contains($r)) { $report.Add("- ``$r`` (kept: it is live today)") } }
$report.Add('- old yaml `{{HOME}}/**` file allow: NOT carried; the access table lists folders explicitly')
$report.Add('')
$report.Add('## Rules only in other sources (not carried)')
$report.Add('')
foreach ($o in $others) { $report.Add("- [$($o.Source)] [$($o.Tier)] ``$($o.Rule)``") }
$report.Add('')
$report.Add('## Every live rule')
$report.Add('')
$report.Add('| Tier | Rule | Fate | Why |')
$report.Add('|---|---|---|---|')
foreach ($f in $fate) { $report.Add("| $($f.Tier) | ``$($f.Rule -replace '\|', '\|')`` | $($f.Fate) | $($f.Why -replace '\|', '\|') |") }
New-Item -ItemType Directory -Force -Path (Split-Path $OutReport) | Out-Null
[IO.File]::WriteAllText($OutReport, ($report -join "`n"))
[pscustomobject]@{ Allow = $out.allow.Count; Ask = $out.ask.Count; Deny = $out.deny.Count; Attention = $att.Count; Others = $others.Count }
