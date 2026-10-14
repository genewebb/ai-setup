#requires -Version 7
<#
Renders ~\.claude\settings.json for one machine (spec 4.3 output 3, R11, R12).

    $r = New-AISettings -Profile $p -TemplatePath ... -PermissionsPath ... -Current $hashtable -PreviousOwned $state.owned
    $r.Settings   # the full new settings (ordered hashtable)
    $r.Report     # what was rendered, skipped or overlapping
    $r.Owned      # the owned env keys and properties, recorded in the state file for the next apply

Ownership (R12). The applicator owns exactly:
    permissions.allow / ask / deny / additionalDirectories, hooks, statusLine,
    the env keys it writes (AI_*, TEMP, TMP, CLAUDE_CODE_TMPDIR), cleanupPeriodDays.
Every other property is kept as it is. 'seed' values are written only when absent (fresh machine, R13).
#>
Set-StrictMode -Version Latest

$script:FileTools = @('Read', 'Edit', 'Write', 'Glob', 'Grep', 'NotebookEdit')

function ConvertTo-AIRulePath {
    <# example-path: C:\a\b -> //c/a/b ; returns $null for a UNC path (no documented rule form). #>
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -match '^\\\\') { return $null }
    if ($Path -notmatch '^([A-Za-z]):(.*)$') { return $null }
    $rest = ($Matches[2] -replace '\\', '/').TrimEnd('/')
    return '//' + $Matches[1].ToLowerInvariant() + $rest
}

function Expand-AITokens {
    <# {Key} and %VAR% expansion. Returns $null if any {Key} is unknown or blank. #>
    param([string]$Text, [System.Collections.IDictionary]$Keys)
    $v = [Environment]::ExpandEnvironmentVariables($Text)
    foreach ($m in [regex]::Matches($v, '\{([A-Za-z][A-Za-z0-9]*)\}')) {
        $k = $m.Groups[1].Value
        if (-not ($Keys.Contains($k) -and $Keys[$k])) { return $null }
        $v = $v.Replace($m.Value, [string]$Keys[$k])
    }
    return $v
}

function ConvertTo-AIRules {
    <# One permissions.yaml rule -> zero, one or two rendered rules. #>
    param([string]$Rule, [System.Collections.IDictionary]$Keys)
    if ($Rule -notmatch '\{[A-Za-z][A-Za-z0-9]*\}' -and $Rule -notmatch '%[A-Za-z_]+%') { return , @($Rule) }
    if ($Rule -match '^([A-Za-z]+)\((.*)\)$') {
        $tool = $Matches[1]; $arg = $Matches[2]
        $exp = Expand-AITokens -Text $arg -Keys $Keys
        if ($null -eq $exp) { return , @() }
        if ($tool -in $script:FileTools) {
            $rp = ConvertTo-AIRulePath $exp
            if (-not $rp) { return , @() }
            return , @("$tool($rp)")
        }
        $a = "$tool($exp)"; $b = "$tool($($exp -replace '\\', '/'))"
        if ($a -ceq $b) { return , @($a) }
        return , @($a, $b)
    }
    $e = Expand-AITokens -Text $Rule -Keys $Keys
    if ($null -eq $e) { return , @() }
    return , @($e)
}

function Copy-AIValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    return ($Value | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json -AsHashtable -Depth 30)
}

function Expand-AITemplateValue {
    <# Recursively replaces {Key} in strings, with forward slashes in the substituted path. #>
    param($Value, [System.Collections.IDictionary]$Keys, [switch]$Backslash)
    if ($Value -is [string]) {
        $v = $Value
        foreach ($m in [regex]::Matches($v, '\{([A-Za-z][A-Za-z0-9]*)\}')) {
            $k = $m.Groups[1].Value
            if (-not ($Keys.Contains($k) -and $Keys[$k])) { throw "Template value '$Value' needs key '$k', which is blank or missing." }
            $sub = [string]$Keys[$k]; if (-not $Backslash) { $sub = $sub -replace '\\', '/' }
            $v = $v.Replace($m.Value, $sub)
        }
        return $v
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Value.Keys) { $o[$k] = Expand-AITemplateValue -Value $Value[$k] -Keys $Keys -Backslash:$Backslash }
        return $o
    }
    if ($Value -is [System.Collections.IList]) {
        return , @(foreach ($x in $Value) { Expand-AITemplateValue -Value $x -Keys $Keys -Backslash:$Backslash })
    }
    return $Value
}

function New-AISettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$PermissionsPath,
        [System.Collections.IDictionary]$Current = [ordered]@{},
        [System.Collections.IDictionary]$PreviousOwned
    )
    Import-Module powershell-yaml -ErrorAction Stop
    $keys = $Profile.Keys
    $report = [System.Collections.Generic.List[object]]::new()
    $note = { param($lvl, $msg) $report.Add([pscustomobject]@{ Level = $lvl; Message = $msg }) }

    $tpl = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    $perm = ConvertFrom-Yaml (Get-Content -LiteralPath $PermissionsPath -Raw)
    $s = Copy-AIValue $Current
    if ($null -eq $s) { $s = [ordered]@{} }

    # --- permissions (owned: allow, ask, deny, additionalDirectories) ---
    $allow = [System.Collections.Generic.List[string]]::new()
    $ask = [System.Collections.Generic.List[string]]::new()
    $deny = [System.Collections.Generic.List[string]]::new()
    $dirs = [System.Collections.Generic.List[string]]::new()
    $addU = { param($list, $r) if (-not $list.Contains($r)) { $list.Add($r) } }

    foreach ($tier in 'allow', 'ask', 'deny') {
        $target = @{ allow = $allow; ask = $ask; deny = $deny }[$tier]
        foreach ($rule in @($perm[$tier])) {
            if (-not $rule) { continue }
            $rendered = ConvertTo-AIRules -Rule $rule -Keys $keys
            if (-not $rendered.Count) {
                & $note $(if ($tier -eq 'deny') { 'warning' } else { 'info' }) "permissions.yaml $tier rule '$rule' skipped: its key is blank or missing on this machine, or its path has no rule form."
                continue
            }
            foreach ($r in $rendered) { & $addU $target $r }
        }
    }

    $rows = @(foreach ($a in $Profile.Access) {
            if (-not $a.Path) { & $note 'info' "Access row '$($a.PathSpec)' skipped: blank or unknown key."; continue }
            $full = [IO.Path]::GetFullPath($a.Path).TrimEnd('\')
            [pscustomobject]@{ Spec = $a.PathSpec; Path = $full; Rule = (ConvertTo-AIRulePath $full); Access = $a.Access }
        })
    foreach ($r in $rows) {
        if (-not $r.Rule) { & $note 'warning' "Access row '$($r.Spec)' ($($r.Path)) has no rule form (UNC); listed in additionalDirectories only."; }
        $read = 'read' -in $r.Access; $edit = 'edit' -in $r.Access; $isDeny = 'deny' -in $r.Access
        if ($isDeny) {
            if ($r.Rule) { & $addU $deny "Read($($r.Rule)/**)"; & $addU $deny "Edit($($r.Rule)/**)" }
            continue
        }
        if ($r.Rule) {
            if ($read -or $edit) { & $addU $allow "Read($($r.Rule)/**)" }
            if ($edit) { & $addU $allow "Edit($($r.Rule)/**)" }
            if ($read -and -not $edit) {
                # R11: an explicit Edit deny, or the extra directory lets edits through in auto/acceptEdits modes.
                $inner = @($rows | Where-Object { $_ -ne $r -and 'edit' -in $_.Access -and $_.Path.Length -gt $r.Path.Length -and $_.Path.StartsWith($r.Path + '\', [StringComparison]::OrdinalIgnoreCase) })
                if ($inner) { & $note 'error' "Access overlap: '$($r.Spec)' is read-only but contains edit row(s) $(($inner.Spec) -join ', '); a deny on the parent would block them. Make the parent read, edit or move the rows." }
                else { & $addU $deny "Edit($($r.Rule)/**)" }
            }
        }
        if ($read -or $edit) { & $addU $dirs $r.Path }
    }
    # Overlaps, reported (most specific wins: an Edit deny on a read-only child beats the parent's allow).
    foreach ($r in $rows) {
        foreach ($o in $rows) {
            if ($o -ne $r -and $o.Path.StartsWith($r.Path + '\', [StringComparison]::OrdinalIgnoreCase)) {
                & $note 'info' "Access overlap: '$($o.Spec)' [$($o.Access -join ',')] sits inside '$($r.Spec)' [$($r.Access -join ',')]."
            }
        }
    }

    if (-not $s.Contains('permissions') -or $s['permissions'] -isnot [System.Collections.IDictionary]) { $s['permissions'] = [ordered]@{} }
    $s['permissions']['allow'] = @($allow)
    $s['permissions']['ask'] = @($ask)
    $s['permissions']['deny'] = @($deny)
    $s['permissions']['additionalDirectories'] = @($dirs)

    # --- hooks, statusLine (owned) ---
    $s['hooks'] = Expand-AITemplateValue -Value $tpl['hooks'] -Keys $keys
    $s['statusLine'] = Expand-AITemplateValue -Value $tpl['statusLine'] -Keys $keys

    # --- env (owned keys only) ---
    if (-not $s.Contains('env') -or $s['env'] -isnot [System.Collections.IDictionary]) { $s['env'] = [ordered]@{} }
    $ownedEnv = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $tpl['env'].Keys) {
        $s['env'][$k] = Expand-AITemplateValue -Value $tpl['env'][$k] -Keys $keys -Backslash
        $ownedEnv.Add($k)
    }
    foreach ($k in $keys.Keys) {
        if (-not $keys[$k]) { continue }
        $name = 'AI_' + $k.ToUpperInvariant()
        $s['env'][$name] = [string]$keys[$k]
        $ownedEnv.Add($name)
    }
    if ($PreviousOwned -and $PreviousOwned.Contains('env')) {
        foreach ($old in @($PreviousOwned['env'])) {
            if ($old -notin $ownedEnv -and $s['env'].Contains($old)) { $s['env'].Remove($old); & $note 'info' "env $old removed (no longer set)." }
        }
    }

    # --- cleanupPeriodDays (owned) ---
    $ownedProps = [System.Collections.Generic.List[string]]::new()
    $days = [string]$keys['TranscriptRetentionDays']
    if ($days) {
        $n = 0; if (-not [int]::TryParse($days, [ref]$n) -or $n -lt 1) { & $note 'error' "TranscriptRetentionDays '$days' is not a positive whole number." }
        else { $s['cleanupPeriodDays'] = $n; $ownedProps.Add('cleanupPeriodDays') }
    }
    elseif ($PreviousOwned -and $PreviousOwned.Contains('props') -and 'cleanupPeriodDays' -in @($PreviousOwned['props']) -and $s.Contains('cleanupPeriodDays')) {
        $s.Remove('cleanupPeriodDays')
    }

    # --- seed (only when absent) ---
    if ($tpl.Contains('seed')) {
        $seed = $tpl['seed']
        foreach ($k in $seed.Keys) {
            if ($k -eq '_comment') { continue }
            switch ($k) {
                'defaultMode' { if (-not $s['permissions'].Contains('defaultMode')) { $s['permissions']['defaultMode'] = $seed[$k]; & $note 'info' "seeded permissions.defaultMode" } }
                'env' { foreach ($ek in $seed['env'].Keys) { if (-not $s['env'].Contains($ek)) { $s['env'][$ek] = $seed['env'][$ek]; & $note 'info' "seeded env $ek" } } }
                default { if (-not $s.Contains($k)) { $s[$k] = Copy-AIValue $seed[$k]; & $note 'info' "seeded $k" } }
            }
        }
    }

    [pscustomobject]@{
        Settings = $s
        Report   = $report
        Owned    = [ordered]@{ env = @($ownedEnv); props = @($ownedProps) }
    }
}

function ConvertTo-AISettingsJson {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Settings)
    return ($Settings | ConvertTo-Json -Depth 30)
}

Export-ModuleMember -Function New-AISettings, ConvertTo-AISettingsJson, ConvertTo-AIRulePath, ConvertTo-AIRules, Expand-AITokens
