#requires -Version 7
<#
.SYNOPSIS
    Turns skills on and off in bulk so the always-loaded skill listing stays
    inside its context budget.

.DESCRIPTION
    Claude Code renders every enabled skill's name and description into the
    system prompt of every session. That listing is budgeted at roughly 1% of
    the context window. Past the budget the descriptions are truncated, which
    degrades skill routing silently - the skill is still there, but the model
    can no longer tell what it is for.

    This script is the mechanical half of that problem: build a catalogue of
    every skill with its category, cost, and usage, then write the chosen set
    into `skillOverrides` in the user settings file. The judgement half - which
    skills a given task actually needs - lives in the skill-profile skill.

    Two speeds, and it matters which is which:

      enforcement    immediate. settings.json is re-read when a skill is
                     invoked, so a disabled skill is refused straight away.
      listing size   next session. The listing is assembled at session start,
                     so the token saving lands after /clear.

.PARAMETER Status
    Per-category table: how many skills, how many enabled, estimated tokens.
    Totals against the budget. This is the default when no mode is given.

.PARAMETER Catalog
    Emit the catalogue as JSON on stdout. This is what the recommender reads to
    decide which skills a task needs.

.PARAMETER Set
    Enable exactly these categories, disable every other model-invocable skill.
    Accepts short aliases: crewchief, testauto, harness, dotnet, blazor,
    profisee, testdata, ai-authoring, general.

.PARAMETER Apply
    Enable exactly these skills by name, disable every other model-invocable
    skill. How the recommender commits a per-task selection.

.PARAMETER Reset
    Empty skillOverrides. Every skill back on. The key is left in place as `{}`
    rather than deleted - an empty map and an absent one behave identically, and
    leaving it means the next write is a splice rather than an insert.

.PARAMETER Worksheet
    Regenerate the disable worksheet markdown, including Category and Status
    columns, at -WorksheetPath.

.PARAMETER Budget
    Token target for the listing. Default 10000, which is 1% of a 1M window.

.PARAMETER FullDescriptions
    In -Catalog, emit whole descriptions instead of the first 200 characters.

.EXAMPLE
    pwsh Set-SkillProfile.ps1 -Status

.EXAMPLE
    pwsh Set-SkillProfile.ps1 -Set crewchief,harness,general

.EXAMPLE
    pwsh Set-SkillProfile.ps1 -Apply seq-query,testauto-matching-scenarios,diagnose

.EXAMPLE
    pwsh Set-SkillProfile.ps1 -Reset
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Status')]   [switch]   $Status,
    [Parameter(ParameterSetName = 'Catalog')]  [switch]   $Catalog,
    [Parameter(ParameterSetName = 'Set',       Mandatory)][string[]] $Set,
    [Parameter(ParameterSetName = 'Apply',     Mandatory)][string[]] $Apply,
    [Parameter(ParameterSetName = 'Reset')]    [switch]   $Reset,
    [Parameter(ParameterSetName = 'Worksheet')][switch]   $Worksheet,

    [string] $SkillsDir     = (Join-Path $env:USERPROFILE 'AI\skills'),
    [string] $SettingsPath  = (Join-Path $env:USERPROFILE '.claude\settings.json'),
    [string] $ClaudeJson    = (Join-Path $env:USERPROFILE '.claude.json'),
    [string] $WorksheetPath = 'C:\tmp\claude-skill-disable-list.md',
    [int]    $Budget        = 10000,
    [switch] $FullDescriptions
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'skill-taxonomy.ps1')

# The switcher must never switch itself off: it is the only way back.
$Protected = @('skill-profile')

function Expand-ListArg {
    <#
    .SYNOPSIS
        Flatten comma-joined list arguments.

        `pwsh -File script.ps1 -Set a,b,c` hands the script the single string
        "a,b,c" rather than three elements, because -File does no parameter
        binding. Splitting here means both invocation styles behave the same
        and callers never have to know the difference.
    #>
    param([AllowEmptyCollection()][string[]]$Value)

    @($Value |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object   { $_ })
}

# ---- catalogue -------------------------------------------------------------

function Get-SkillFrontmatter {
    <#
    .SYNOPSIS
        name, description and disable-model-invocation from a SKILL.md.
        Returns $null when there is no frontmatter block at all.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw -notmatch '(?s)^---\r?\n(.*?)\r?\n---') { return $null }
    $fm = $Matches[1]

    $name = ''
    if ($fm -match '(?m)^name:\s*(.+?)\s*$') { $name = $Matches[1].Trim() }

    # description may be a plain scalar or a folded/literal block that runs on
    # until the next top-level key. Collapse whitespace either way.
    $desc = ''
    if ($fm -match '(?s)description:\s*(?:>-?|\|-?)?\s*(.*?)(?:\r?\n[a-zA-Z_-]+:|\Z)') {
        $desc = ($Matches[1] -replace '\s+', ' ').Trim()
    }

    # Slash-command-only skills are absent from the model's listing, so they
    # cost nothing and must never be disabled - that would break the command.
    $slashOnly = $fm -match '(?m)^disable-model-invocation:\s*true\s*$'

    [pscustomobject]@{
        Name        = $name
        Description = $desc
        SlashOnly   = [bool]$slashOnly
    }
}

function Get-SkillUsage {
    <#
    .SYNOPSIS
        skill name -> @{ Uses; LastUsed }. Counters are lifetime totals since
        install; they never reset and are not windowed.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    try   { $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { Write-Warning "Could not parse $Path - usage columns will read 0."; return $map }

    if (-not $json.skillUsage) { return $map }

    foreach ($p in $json.skillUsage.PSObject.Properties) {
        # Nested skills are recorded as '<dir>:<name>' or bare '<name>'.
        $key  = ($p.Name -split ':')[-1]
        $uses = [int]($p.Value.usageCount)
        $last = if ($p.Value.lastUsedAt) {
            [DateTimeOffset]::FromUnixTimeMilliseconds([long]$p.Value.lastUsedAt).LocalDateTime
        } else { $null }

        if ($map.ContainsKey($key)) {
            if ($uses -gt $map[$key].Uses)                       { $map[$key].Uses = $uses }
            if ($last -and (-not $map[$key].LastUsed -or $last -gt $map[$key].LastUsed)) {
                $map[$key].LastUsed = $last
            }
        }
        else { $map[$key] = [pscustomobject]@{ Uses = $uses; LastUsed = $last } }
    }
    $map
}

function Get-Catalog {
    param(
        [Parameter(Mandatory)][string]$SkillsDir,
        [Parameter(Mandatory)][hashtable]$Disabled,
        [Parameter(Mandatory)][hashtable]$Usage
    )

    $rows = @()
    foreach ($d in (Get-ChildItem -LiteralPath $SkillsDir -Directory | Sort-Object Name)) {
        $f = Join-Path $d.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $f)) { continue }

        $fm = Get-SkillFrontmatter -Path $f
        if (-not $fm -or -not $fm.Name) { continue }   # co-located docs, not skills

        $u = $Usage[$d.Name]

        $rows += [pscustomobject]@{
            Name        = $d.Name
            Category    = Get-SkillCategory -Name $d.Name
            # What the listing actually costs: name + description, 4 chars/token.
            Tokens      = if ($fm.SlashOnly) { 0 }
                          else { [int](($fm.Name.Length + $fm.Description.Length + 4) / 4) }
            Uses        = if ($u) { $u.Uses } else { 0 }
            LastUsed    = if ($u) { $u.LastUsed } else { $null }
            Enabled     = -not $Disabled.ContainsKey($d.Name)
            SlashOnly   = $fm.SlashOnly
            Protected   = $Protected -contains $d.Name
            Description = $fm.Description
        }
    }
    $rows
}

# ---- settings read / write -------------------------------------------------

function Get-DisabledMap {
    <#
    .SYNOPSIS
        Current skillOverrides as a hashtable of the entries set to 'off'.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not $json.skillOverrides) { return $map }

    foreach ($p in $json.skillOverrides.PSObject.Properties) {
        if ("$($p.Value)".ToLowerInvariant() -eq 'off') { $map[$p.Name] = $true }
    }
    $map
}

function Find-JsonValueSpan {
    <#
    .SYNOPSIS
        Character span of a top-level key's value, or $null if the key is absent.
        Brace matching skips over string literals so a '}' inside a value cannot
        end the object early.
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Key
    )

    $m = [regex]::Match($Text, '"' + [regex]::Escape($Key) + '"\s*:\s*')
    if (-not $m.Success) { return $null }

    $i = $m.Index + $m.Length
    if ($i -ge $Text.Length -or $Text[$i] -ne '{') {
        throw "skillOverrides is not an object - refusing to edit it."
    }

    $depth = 0; $inStr = $false; $esc = $false
    for ($j = $i; $j -lt $Text.Length; $j++) {
        $c = $Text[$j]
        if ($inStr) {
            if     ($esc)        { $esc = $false }
            elseif ($c -eq '\')  { $esc = $true }
            elseif ($c -eq '"')  { $inStr = $false }
            continue
        }
        if     ($c -eq '"') { $inStr = $true }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{ Start = $m.Index; End = $j; ValueStart = $i }
            }
        }
    }
    throw "Unbalanced braces after `"$Key`" - refusing to edit the file."
}

function Set-SkillOverrides {
    <#
    .SYNOPSIS
        Splice a new skillOverrides block into settings.json, leaving every other
        byte untouched. Backs up first, validates after, restores on failure.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DisabledNames
    )

    $text = Get-Content -LiteralPath $Path -Raw

    # Refuse to write over a file we could not read - a parse failure here means
    # the settings are already broken and a rewrite would destroy the evidence.
    try { $before = $text | ConvertFrom-Json -AsHashtable }
    catch { throw "settings.json does not parse; not writing. Fix it first: $($_.Exception.Message)" }

    $block = if ($DisabledNames.Count -eq 0) { '{}' } else {
        $lines = $DisabledNames | Sort-Object -Unique | ForEach-Object {
            '    ' + (ConvertTo-Json $_ -Compress) + ': "off"'
        }
        "{`n" + ($lines -join ",`n") + "`n  }"
    }

    $span = Find-JsonValueSpan -Text $text -Key 'skillOverrides'
    if ($span) {
        $new = $text.Substring(0, $span.ValueStart) + $block + $text.Substring($span.End + 1)
    }
    else {
        # Insert as the last key, before the document's closing brace.
        $close = $text.LastIndexOf('}')
        if ($close -lt 0) { throw "No closing brace in $Path - refusing to edit it." }
        $head = $text.Substring(0, $close).TrimEnd()
        $tail = $text.Substring($close)
        $new  = $head + ",`n  `"skillOverrides`": " + $block + "`n" + $tail
    }

    # Validate the result before it replaces anything.
    try { $after = $new | ConvertFrom-Json -AsHashtable }
    catch { throw "Generated settings.json would be invalid; nothing written. $($_.Exception.Message)" }

    # Every other top-level key must survive untouched.
    $keysBefore = @($before.Keys | Where-Object { $_ -ne 'skillOverrides' } | Sort-Object)
    $keysAfter  = @($after.Keys  | Where-Object { $_ -ne 'skillOverrides' } | Sort-Object)
    if (Compare-Object $keysBefore $keysAfter) {
        throw "Top-level keys would change; nothing written."
    }

    $backup = "$Path.bak-skillprofile-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $new, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    catch {
        Copy-Item -LiteralPath $backup -Destination $Path -Force
        throw
    }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }

    $backup
}

# ---- reporting -------------------------------------------------------------

function Write-Status {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][int]$Budget)

    $live = @($Rows | Where-Object { -not $_.SlashOnly })

    $summary = foreach ($cat in $CategoryOrder) {
        $set = @($live | Where-Object Category -eq $cat)
        if (-not $set.Count) { continue }
        $on = @($set | Where-Object Enabled)
        [pscustomobject]@{
            Category  = $cat
            Skills    = $set.Count
            Enabled   = $on.Count
            'Est tok' = [int]($on  | Measure-Object Tokens -Sum).Sum
            'Of tot'  = [int]($set | Measure-Object Tokens -Sum).Sum
        }
    }
    $summary | Format-Table -AutoSize | Out-String | Write-Host

    $enabled = @($live | Where-Object Enabled)
    $total   = ($enabled | Measure-Object Tokens -Sum).Sum
    $slash   = @($Rows | Where-Object SlashOnly).Count

    Write-Host ("Enabled {0} of {1} model-invocable skills ({2} slash-only, always free)." -f `
        $enabled.Count, $live.Count, $slash)
    Write-Host ("Listing {0} est. tokens against a budget of {1}." -f $total, $Budget) -NoNewline

    if ($total -gt $Budget) {
        Write-Host (" OVER by {0}. Descriptions are being truncated." -f ($total - $Budget)) -ForegroundColor Red
    } else {
        Write-Host (" {0} to spare." -f ($Budget - $total)) -ForegroundColor Green
    }
}

function Write-Worksheet {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Budget
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Skill disable worksheet')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Put an **x** in the brackets of every skill to DISABLE, then apply it.')
    [void]$sb.AppendLine('Generated by `Set-SkillProfile.ps1 -Worksheet` - rerun rather than hand-editing.')
    [void]$sb.AppendLine()

    $live    = @($Rows | Where-Object { -not $_.SlashOnly })
    $enabled = @($live | Where-Object Enabled)
    $total   = ($enabled | Measure-Object Tokens -Sum).Sum
    [void]$sb.AppendLine("_$($live.Count) model-invocable skills, $($enabled.Count) enabled, $total est. tokens, budget $Budget - $(Get-Date -Format 'yyyy-MM-dd')_")
    [void]$sb.AppendLine()

    # Never used first: that is the list the user is most likely to act on.
    $order = @($Rows | Sort-Object @{ E = { $_.Uses -gt 0 } }, @{ E = { $_.LastUsed } }, Name)

    [void]$sb.AppendLine('| x | Skill | Category | Status | Uses | Last used | Est tok |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|')
    foreach ($r in $order) {
        $status = if ($r.Protected)      { 'protected' }
                  elseif ($r.SlashOnly)  { 'slash-only' }
                  elseif ($r.Enabled)    { 'on' }
                  else                   { 'off' }
        $last = if ($r.LastUsed) { $r.LastUsed.ToString('yyyy-MM-dd') } else { 'never' }
        [void]$sb.AppendLine("| [ ] | ``$($r.Name)`` | $($r.Category) | $status | $($r.Uses) | $last | $($r.Tokens) |")
    }

    [System.IO.File]::WriteAllText($Path, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $Path - $($Rows.Count) skills." -ForegroundColor Green
}

# ---- selection -------------------------------------------------------------

function Resolve-Selection {
    <#
    .SYNOPSIS
        Given the skills that should stay ON, return the names to write as 'off'.
        Slash-only skills are never written (they cost nothing and disabling one
        breaks its slash command). Protected skills are never written either.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KeepNames
    )

    $keep = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$KeepNames, [StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $Protected) { [void]$keep.Add($p) }

    @($Rows |
        Where-Object { -not $_.SlashOnly -and -not $keep.Contains($_.Name) } |
        Select-Object -ExpandProperty Name)
}

function Show-Applied {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DisabledNames,
        [Parameter(Mandatory)][int]$Budget,
        [Parameter(Mandatory)][string]$Backup
    )

    $off = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$DisabledNames, [StringComparer]::OrdinalIgnoreCase)

    $live  = @($Rows | Where-Object { -not $_.SlashOnly })
    $on    = @($live | Where-Object { -not $off.Contains($_.Name) })
    $total = ($on | Measure-Object Tokens -Sum).Sum

    Write-Host ""
    Write-Host ("Enabled {0}, disabled {1}." -f $on.Count, $DisabledNames.Count) -ForegroundColor Cyan
    Write-Host ("Listing {0} est. tokens against a budget of {1}." -f $total, $Budget) -NoNewline
    if ($total -gt $Budget) {
        Write-Host (" STILL OVER by {0} - narrow the selection further." -f ($total - $Budget)) -ForegroundColor Red
    } else {
        Write-Host (" {0} to spare." -f ($Budget - $total)) -ForegroundColor Green
    }
    Write-Host "Backup: $Backup"
    Write-Host ""
    Write-Host "Disabled skills are refused immediately. Run /clear to reclaim the tokens." -ForegroundColor Yellow
}

# ---- main ------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $SkillsDir))    { throw "Skills directory not found: $SkillsDir" }
if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "Settings file not found: $SettingsPath" }

$disabled = Get-DisabledMap -Path $SettingsPath
$usage    = Get-SkillUsage  -Path $ClaudeJson
$rows     = Get-Catalog -SkillsDir $SkillsDir -Disabled $disabled -Usage $usage

if (-not $rows.Count) { throw "No skills with valid frontmatter found under $SkillsDir" }

switch ($PSCmdlet.ParameterSetName) {

    'Catalog' {
        $rows | ForEach-Object {
            [pscustomobject]@{
                name        = $_.Name
                category    = $_.Category
                tokens      = $_.Tokens
                uses        = $_.Uses
                lastUsed    = if ($_.LastUsed) { $_.LastUsed.ToString('yyyy-MM-dd') } else { $null }
                enabled     = $_.Enabled
                slashOnly   = $_.SlashOnly
                description = if ($FullDescriptions -or $_.Description.Length -le 200) { $_.Description }
                              else { $_.Description.Substring(0, 200) + '...' }
            }
        } | ConvertTo-Json -Depth 4
    }

    'Set' {
        $cats = @(Expand-ListArg $Set | ForEach-Object { Resolve-CategoryName -Name $_ })
        $keep = @($rows | Where-Object { $cats -contains $_.Category } | Select-Object -ExpandProperty Name)
        if (-not $keep.Count) { throw "That category selection matches no skills." }

        $off    = Resolve-Selection -Rows $rows -KeepNames $keep
        $backup = Set-SkillOverrides -Path $SettingsPath -DisabledNames $off
        Write-Host ("Enabled categories: {0}" -f ($cats -join ', ')) -ForegroundColor Cyan
        Show-Applied -Rows $rows -DisabledNames $off -Budget $Budget -Backup $backup
    }

    'Apply' {
        $names   = Expand-ListArg $Apply
        $known   = @{}; foreach ($r in $rows) { $known[$r.Name] = $true }
        $valid   = @($names | Where-Object { $known.ContainsKey($_) })
        $unknown = @($names | Where-Object { -not $known.ContainsKey($_) })

        # A typo should cost one skill, not the whole profile.
        foreach ($u in $unknown) { Write-Warning "Unknown skill '$u' - skipped." }
        if (-not $valid.Count) { throw "None of the requested skills exist; nothing written." }

        $off    = Resolve-Selection -Rows $rows -KeepNames $valid
        $backup = Set-SkillOverrides -Path $SettingsPath -DisabledNames $off
        Show-Applied -Rows $rows -DisabledNames $off -Budget $Budget -Backup $backup
    }

    'Reset' {
        $backup = Set-SkillOverrides -Path $SettingsPath -DisabledNames @()
        Write-Host "skillOverrides cleared - all skills enabled." -ForegroundColor Green
        Write-Host "Backup: $backup"
        $refreshed = Get-Catalog -SkillsDir $SkillsDir -Disabled @{} -Usage $usage
        Write-Status -Rows $refreshed -Budget $Budget
    }

    'Worksheet' { Write-Worksheet -Rows $rows -Path $WorksheetPath -Budget $Budget }

    default     { Write-Status -Rows $rows -Budget $Budget }
}
