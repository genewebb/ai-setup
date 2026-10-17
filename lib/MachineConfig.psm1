#requires -Version 7
<#
Machine config resolver for the AI runtime.

Every machine path the skills, hooks and scripts need comes from ONE file per machine:
ProfileMachineConfig.md (spec: docs\machine-config-design.md, section 4.1). This module reads it.

    Import-Module <runtime>\lib\MachineConfig.psm1
    Get-AIPath -Name WorktreesRoot            # the path, or a throw naming the key and the file
    Get-AIPath -Name SecretsDir -Optional     # $null when the row is blank
    Get-AIConfig                              # every key: value, source, exists, local/share
    Get-AIMachineProfile                      # every table, parsed
    Test-AIMachineProfile                     # validation errors and warnings (spec 4.3b)
    Get-AIGitPolicy -Path <dir>               # the git policy row that governs a folder (spec D19)

The profile is authoritative (R3). AI_* environment variables are outputs written for consumers that
cannot import this module; they are never read back, except through -TestOverride in tests.
#>

Set-StrictMode -Version Latest

# The one fixed convention in the whole system (spec 4.1). The gate allowlists this line.
$script:DefaultConfigPath = 'C:\Deploy\Setup\ProfileMachineConfig.md'

# Keys the AI runtime adds to the profile's first table. The pwsh profile accepts these silently (R23).
$script:AIKeys = @(
    'AIWorkRoot', 'ClaudeHome', 'WorktreesRoot', 'ScratchRoot', 'StatusPageDir', 'VaultWorkRoot',
    'VaultPersonalRoot', 'SecretsDir', 'ArchiveRoot', 'TestedClaudeVersion', 'TranscriptRetentionDays',
    'AllowTempInRepo', 'SkillsLinkRoot', 'DeployRoot', 'StreamHostDir'
)
$script:RequiredKeys = @('AIWorkRoot', 'ScratchRoot', 'WorktreesRoot', 'ReposRoot')
# Keys whose value is not a path (never tested for existence, never rendered into access rules).
$script:NonPathKeys = @('TestedClaudeVersion', 'TranscriptRetentionDays', 'AllowTempInRepo')

function Get-AIMachineConfigPath {
    <# The profile path: AI_MACHINE_CONFIG (the only environment input) or the fixed convention. #>
    [CmdletBinding()]
    param()
    if ($env:AI_MACHINE_CONFIG) { return $env:AI_MACHINE_CONFIG }
    return $script:DefaultConfigPath
}

function ConvertFrom-AIMarkdownRow {
    param([string]$Line)
    $cells = $Line.Trim().Trim('|') -split '\|'
    return @($cells | ForEach-Object { $_.Trim().Trim('`').Trim() })
}

function Read-AIMarkdownTables {
    <#
    Splits the profile into tables. The first table is the key/value table; later tables are named by
    the nearest '## Heading' above them. Returns an ordered dictionary: '' => first table, then names.
    Each table is a list of ordered hashtables keyed by the header cells.
    #>
    param([string[]]$Lines)

    $tables  = [ordered]@{}
    $heading = ''
    $header  = $null
    $rows    = $null
    $first   = $true

    foreach ($line in @($Lines) + @('')) {
        $isRow = $line -match '^\s*\|'
        if (-not $isRow -and $null -ne $header) {
            # A table just ended: file it under '' (the first table) or its heading.
            $name = if ($first) { '' } else { $heading }
            if (-not $tables.Contains($name)) { $tables[$name] = $rows }
            $first = $false
            $header = $null
            $rows = $null
        }
        if ($line -match '^\s*#{1,6}\s+(.+?)\s*$') { $heading = $Matches[1].Trim(); continue }
        if (-not $isRow) { continue }

        $cells = ConvertFrom-AIMarkdownRow $line
        if ($null -eq $header) {
            $header = $cells
            $rows = [System.Collections.Generic.List[object]]::new()
            continue
        }
        if (($cells -join '') -match '^[-:\s]*$') { continue }   # the |---|---| separator
        $row = [ordered]@{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows.Add($row)
    }
    return $tables
}
function Expand-AIValue {
    <# Expands %VAR% and {Key} references. Unknown {Key} or blank {Key} returns $null. #>
    param([string]$Value, [System.Collections.IDictionary]$Keys)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = [Environment]::ExpandEnvironmentVariables($Value)
    foreach ($m in [regex]::Matches($v, '\{([A-Za-z][A-Za-z0-9]*)\}')) {
        $k = $m.Groups[1].Value
        if (-not ($Keys.Contains($k) -and $Keys[$k])) { return $null }
        $v = $v.Replace($m.Value, [string]$Keys[$k])
    }
    return $v
}
function Get-AIMachineProfile {
    <#
    .SYNOPSIS
        Parses the machine profile into Keys, Resources, Access, GitPolicy and Mcp.
    .PARAMETER TestOverride
        Tests only: a hashtable of key => value applied on top of the profile (R3).
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-AIMachineConfigPath),
        [hashtable]$TestOverride
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Machine config file not found: $Path. Create it (see docs\machine-config-design.md, 4.1)."
    }
    $lines  = Get-Content -LiteralPath $Path
    $tables = Read-AIMarkdownTables -Lines $lines

    $raw  = [ordered]@{}
    $keys = [ordered]@{}
    if ($tables.Contains('')) {
        foreach ($row in $tables['']) {
            $k = [string]@($row.Values)[0]
            if (-not $k -or $k -notmatch '^[A-Za-z][A-Za-z0-9]*$') { continue }
            $raw[$k] = [string]@($row.Values)[1]
        }
    }
    if ($TestOverride) { foreach ($k in $TestOverride.Keys) { $raw[$k] = [string]$TestOverride[$k] } }

    foreach ($k in $raw.Keys) {
        $keys[$k] = if ([string]::IsNullOrWhiteSpace($raw[$k])) { '' } else { [Environment]::ExpandEnvironmentVariables($raw[$k]) }
    }
    # The one derivation (spec 4.2): ClaudeHome = $HOME\.claude when the row is absent.
    $derived = @()
    if (-not $keys.Contains('ClaudeHome')) {
        $keys['ClaudeHome'] = Join-Path $HOME '.claude'
        $derived += 'ClaudeHome'
    }

    $section = {
        param([string]$Name)
        foreach ($n in $tables.Keys) { if ($n -and $n -ieq $Name) { return , @($tables[$n]) } }
        return , @()
    }

    $resources = foreach ($r in (& $section 'Resources')) {
        [pscustomobject]@{
            Key      = [string]$r['Key']
            Route    = ([string]$r['Route']).ToLowerInvariant()
            Endpoint = [string]$r['Obsidian endpoint']
        }
    }
    $access = foreach ($r in (& $section 'Claude access')) {
        $p = [string]$r['Path']
        [pscustomobject]@{
            PathSpec = $p
            Path     = Expand-AIValue -Value $p -Keys $keys
            Access   = @(([string]$r['Access']) -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
            Note     = [string]$r['Note']
        }
    }
    $git = foreach ($r in (& $section 'Git policy')) {
        $p = [string]$r['Repo']
        [pscustomobject]@{
            RepoSpec  = $p
            Repo      = Expand-AIValue -Value $p -Keys $keys
            Commit    = ([string]$r['Commit']).Trim().ToLowerInvariant()
            Push      = ([string]$r['Push']).Trim().ToLowerInvariant()
            Worktrees = ([string]$r['Worktrees']).Trim().ToLowerInvariant()
            # Optional column: the owner's own push (the pwsh profile's pushStreams). git-guard never reads it, so a
            # row can give the owner push while Claude sessions keep Push = no. Blank or absent = same as Push.
            OwnerPush = ([string]$r['Owner push']).Trim().ToLowerInvariant()
            Note      = [string]$r['Note']
        }
    }
    $mcp = foreach ($r in (& $section 'MCP servers')) {
        [pscustomobject]@{
            Server  = [string]$r['Server']
            Install = ([string]$r['Install']).Trim().ToLowerInvariant()
            Note    = [string]$r['Note']
        }
    }

    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath)
    $hash  = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))

    [pscustomobject]@{
        Path      = $Path
        Hash      = $hash
        Keys      = $keys
        RawKeys   = $raw
        Derived   = $derived
        Resources = @($resources)
        Access    = @($access)
        GitPolicy = @($git)
        Mcp       = @($mcp)
        Sections  = @($tables.Keys | Where-Object { $_ })
    }
}

function Get-AIPath {
    <#
    .SYNOPSIS
        Returns one machine path from the profile, or throws naming the key and the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$Optional,
        [string]$ConfigPath = (Get-AIMachineConfigPath),
        [hashtable]$TestOverride
    )
    $p = Get-AIMachineProfile -Path $ConfigPath -TestOverride $TestOverride
    if (-not $p.Keys.Contains($Name)) {
        if ($Optional) { return $null }
        throw "Machine config key '$Name' is not set. Add a row to $($p.Path)."
    }
    $v = $p.Keys[$Name]
    if (-not $v) {
        if ($Optional) { return $null }
        throw "Machine config key '$Name' is blank (not on this machine). Set its value in $($p.Path)."
    }
    return $v
}

function Get-AILocationKind {
    <# local | share | share (disconnected) | missing. Worked out from Get-PSDrive, no profile column. #>
    param([string]$Path)
    if (-not $Path) { return 'blank' }
    if ($Path -match '^\\\\') { return $(if (Test-Path -LiteralPath $Path) { 'share' } else { 'share (disconnected)' }) }
    if ($Path -match '^([A-Za-z]):') {
        $letter = $Matches[1]
        $drive = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if (-not $drive) {
            # A mapped drive that is disconnected may not appear as a PSDrive at all; ask net use.
            $net = (& net use 2>$null) -join "`n"
            if ($net -match "(?im)^\S*\s+${letter}:\s+\\\\") { return 'share (disconnected)' }
            return 'missing'
        }
        if ($drive.DisplayRoot -and $drive.DisplayRoot -match '^\\\\') {
            return $(if (Test-Path -LiteralPath "${letter}:\") { 'share' } else { 'share (disconnected)' })
        }
        return 'local'
    }
    return 'local'
}

function Get-AIConfig {
    <# Every key: value, source, whether it exists, and local/share. #>
    [CmdletBinding()]
    param([string]$ConfigPath = (Get-AIMachineConfigPath), [hashtable]$TestOverride)
    $p = Get-AIMachineProfile -Path $ConfigPath -TestOverride $TestOverride
    foreach ($k in $p.Keys.Keys) {
        $v = $p.Keys[$k]
        $isPath = $k -notin $script:NonPathKeys -and $v -match '^([A-Za-z]:|\\\\)'
        $kind = if (-not $v) { 'blank' } elseif ($isPath) { Get-AILocationKind -Path $v } else { 'value' }
        [pscustomobject]@{
            Key      = $k
            Value    = $v
            Source   = $(if ($k -in $p.Derived) { 'derived' } else { 'profile' })
            Exists   = $(if ($isPath -and $kind -ne 'share (disconnected)') { Test-Path -LiteralPath $v } elseif ($isPath) { $false } else { $null })
            Location = $kind
        }
    }
}

function Test-AIPathUnder {
    <# True when Child equals Parent or sits inside it (full-path, case-insensitive). #>
    param([string]$Child, [string]$Parent)
    if (-not $Child -or -not $Parent) { return $false }
    $c = [IO.Path]::GetFullPath($Child).TrimEnd('\') + '\'
    $pp = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    return $c.StartsWith($pp, [StringComparison]::OrdinalIgnoreCase)
}

function Test-AIMachineProfile {
    <#
    .SYNOPSIS
        Spec 4.3b validation. Returns objects { Level = 'error'|'warning'|'info'; Message }.
        Any 'error' stops an apply and a launch (R2).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [string]$ClaudeVersion
    )
    $out = [System.Collections.Generic.List[object]]::new()
    $err  = { param($m) $out.Add([pscustomobject]@{ Level = 'error'; Message = $m }) }
    $warn = { param($m) $out.Add([pscustomobject]@{ Level = 'warning'; Message = $m }) }
    $info = { param($m) $out.Add([pscustomobject]@{ Level = 'info'; Message = $m }) }
    $k = $Profile.Keys

    foreach ($r in $script:RequiredKeys) {
        if (-not $k.Contains($r)) { & $err "Required key '$r' is missing. Add a row to $($Profile.Path)." }
        elseif (-not $k[$r]) { & $err "Required key '$r' is blank. Set its value in $($Profile.Path)." }
    }

    # Temporary roots stay out of repos (spec 4.2).
    $allowTemp = ([string]$k['AllowTempInRepo']).Trim() -ieq 'yes'
    if (-not $allowTemp) {
        $repoRoots = @($k['ReposRoot']) + @($Profile.GitPolicy | ForEach-Object { $_.Repo }) | Where-Object { $_ }
        foreach ($t in 'ScratchRoot', 'WorktreesRoot') {
            if (-not $k[$t]) { continue }
            foreach ($r in $repoRoots) {
                if (Test-AIPathUnder -Child $k[$t] -Parent $r) { & $err "$t ($($k[$t])) is inside a repo or ReposRoot ($r). Move it, or add 'AllowTempInRepo | yes'." }
            }
        }
        if ($k['ScratchRoot'] -and $k['WorktreesRoot'] -and
            ((Test-AIPathUnder $k['ScratchRoot'] $k['WorktreesRoot']) -or (Test-AIPathUnder $k['WorktreesRoot'] $k['ScratchRoot']))) {
            & $err "ScratchRoot and WorktreesRoot must not be inside each other ($($k['ScratchRoot']), $($k['WorktreesRoot']))."
        }
    }

    # SkillsLinkRoot (R38): skills, agents and commands become links into this tree, so it must exist and stay
    # outside ClaudeHome (a link into its own folder would loop).
    if ($k['SkillsLinkRoot']) {
        if (-not (Test-Path -LiteralPath $k['SkillsLinkRoot'])) { & $err "SkillsLinkRoot ($($k['SkillsLinkRoot'])) is not reachable. Map it, or blank the row to install real copies." }
        if ($k['ClaudeHome'] -and ((Test-AIPathUnder $k['SkillsLinkRoot'] $k['ClaudeHome']) -or (Test-AIPathUnder $k['ClaudeHome'] $k['SkillsLinkRoot']))) { & $err "SkillsLinkRoot ($($k['SkillsLinkRoot'])) and ClaudeHome must not be inside each other." }
    }

    # Access table.
    foreach ($a in $Profile.Access) {
        if (-not $a.PathSpec) { & $err "Claude access: a row has no Path."; continue }
        $bad = @($a.Access | Where-Object { $_ -notin 'read', 'edit', 'delete', 'deny' })
        if (-not $a.Access -or $bad) { & $err "Claude access: row '$($a.PathSpec)' has an invalid Access '$($a.Access -join ', ')' (use read, edit, delete, deny)." }
        # delete = the destructive-path-guard lets rm/Remove-Item there run without a prompt; it only makes sense on an edit row.
        if ('delete' -in $a.Access -and ('edit' -notin $a.Access -or 'deny' -in $a.Access)) { & $err "Claude access: row '$($a.PathSpec)' has delete without edit (delete needs read, edit, delete)." }
        if (-not $a.Path) { & $info "Claude access: row '$($a.PathSpec)' skipped (its key is blank or unknown on this machine)." }
    }

    # Git policy (D19, R18).
    foreach ($g in $Profile.GitPolicy) {
        foreach ($col in 'Commit', 'Push', 'Worktrees') {
            if ($g.$col -notin 'yes', 'no') { & $err "Git policy: row '$($g.RepoSpec)' column $col must be yes or no (found '$($g.$col)')." }
        }
        if ($g.OwnerPush -notin '', 'yes', 'no') { & $err "Git policy: row '$($g.RepoSpec)' column Owner push must be yes, no or blank (found '$($g.OwnerPush)')." }
        if ($g.Worktrees -eq 'yes' -and $g.Commit -ne 'yes') { & $err "Git policy: row '$($g.RepoSpec)' has Worktrees = yes with Commit = no (R18)." }
        if ($g.Push -eq 'yes' -and $g.Commit -ne 'yes') { & $warn "Git policy: row '$($g.RepoSpec)' allows Push but not Commit." }
        if (-not $g.Repo) { & $err "Git policy: row '$($g.RepoSpec)' does not resolve on this machine." }
    }

    # Resources and routes (R5).
    $vaults = @($Profile.Resources | Where-Object Route -eq 'obsidian')
    foreach ($r in $Profile.Resources) {
        if ($r.Route -notin 'direct', 'obsidian') { & $err "Resources: '$($r.Key)' has Route '$($r.Route)' (use direct or obsidian)."; continue }
        if ($r.Route -eq 'obsidian' -and -not $r.Endpoint) { & $err "Resources: '$($r.Key)' is obsidian but has no endpoint (R6)." }
        if (-not $k.Contains($r.Key)) { & $err "Resources: '$($r.Key)' is not a key in the first table." }
    }
    foreach ($r in $Profile.Resources | Where-Object Route -eq 'direct') {
        foreach ($v in $vaults) {
            if ($k[$r.Key] -and $k[$v.Key] -and (Test-AIPathUnder $k[$r.Key] $k[$v.Key])) {
                & $err "Resources: '$($r.Key)' is direct but sits inside obsidian vault '$($v.Key)'."
            }
        }
    }

    # MCP servers (R15).
    foreach ($m in $Profile.Mcp) {
        if ($m.Install -notin 'yes', 'no') { & $err "MCP servers: '$($m.Server)' Install must be yes or no." }
    }

    # Availability (R7): reported, never a failure.
    foreach ($key in $k.Keys) {
        $v = $k[$key]
        if (-not $v -or $key -in $script:NonPathKeys -or $v -notmatch '^([A-Za-z]:|\\\\)') { continue }
        $kind = Get-AILocationKind -Path $v
        if ($kind -eq 'share (disconnected)' -or $kind -eq 'missing') { & $warn "$key ($v) is unavailable: $kind." }
    }

    # Tested version (R20): a warning only.
    if ($ClaudeVersion -and $k['TestedClaudeVersion']) {
        try {
            if ([version]$ClaudeVersion -lt [version]$k['TestedClaudeVersion']) {
                & $warn "Claude $ClaudeVersion is older than TestedClaudeVersion $($k['TestedClaudeVersion'])."
            }
            elseif ([version]$ClaudeVersion -gt [version]$k['TestedClaudeVersion']) {
                & $info "Claude $ClaudeVersion is newer than TestedClaudeVersion $($k['TestedClaudeVersion']) (untested)."
            }
        }
        catch { & $warn "TestedClaudeVersion '$($k['TestedClaudeVersion'])' is not a version." }
    }
    return $out
}

function Get-AIRepoRoot {
    <# The MAIN repository root for a folder (a worktree maps to its main repo via --git-common-dir). #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    # $? not $LASTEXITCODE: under StrictMode a module cannot read $LASTEXITCODE before the session has set it.
    $common = @(& git -c safe.directory=* -C $Path rev-parse --path-format=absolute --git-common-dir 2>$null)
    if (-not $? -or -not $common -or -not $common[0]) { return $null }
    $common = [string]$common[0]
    $common = [IO.Path]::GetFullPath(($common -replace '/', '\')).TrimEnd('\')
    if ((Split-Path $common -Leaf) -ieq '.git') { return Split-Path $common -Parent }
    return $common   # a bare repository
}

function Get-AIGitPolicy {
    <#
    .SYNOPSIS
        The git policy that governs a folder. A repo with no row gets no commit, no push, no worktrees.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Profile
    )
    $root = Get-AIRepoRoot -Path $Path
    $row = $null
    if ($root) {
        foreach ($g in $Profile.GitPolicy) {
            if (-not $g.Repo) { continue }
            $gp = [IO.Path]::GetFullPath($g.Repo).TrimEnd('\')
            if ([string]::Equals($gp, $root, [StringComparison]::OrdinalIgnoreCase)) { $row = $g; break }
        }
    }
    [pscustomobject]@{
        RepoRoot  = $root
        Row       = $row
        Commit    = [bool]($row -and $row.Commit -eq 'yes')
        Push      = [bool]($row -and $row.Push -eq 'yes')
        Worktrees = [bool]($row -and $row.Worktrees -eq 'yes' -and $row.Commit -eq 'yes')
        # The owner's push (pushStreams): the Owner push column when it is set, else Push.
        OwnerPush = [bool]($row -and $(
                $own = if ($row.PSObject.Properties['OwnerPush']) { $row.OwnerPush } else { '' }
                if ($own) { $own -eq 'yes' } else { $row.Push -eq 'yes' }))
    }
}

# Tool and test leftovers that land at the TOP LEVEL of {ScratchRoot} and its temp folder. Claude's shells point TEMP
# at the scratch root, so every Path.GetTempPath() user drops its folders there, and nothing removed them: SMVMTR1's
# D:\tmp held 89,249 top-level entries (28,840 dotnet workload logs, .NET random-name folders, speedy-* test folders)   # history
# by 2026-10-17. Only these shapes are ever removed; every other name (claude, streams, temp, a backup someone put
# there) is left alone. One list, used by the hourly scratch cleanup task (setup\Clear-AIScratch.ps1, which also
# removes every file unused for -KeepDays under the root) and by the stream watchdog every tick.
$script:ScratchLeftoverShapes = @(
    '^[a-z0-9]{8}\.[a-z0-9]{3}$'          # .NET Path.GetRandomFileName (test temp folders and files)
    '^tmp[0-9A-Fa-f]+\.tmp$'              # Win32 GetTempFileName
    '^Microsoft\.NET\.Workload_.*\.log$'  # dotnet CLI workload logs
    '^MSBuildTemp'                        # MSBuild temp folders
    '^speedy-'                            # speedmerchants test folders
    '^cc_runas_test_', '^ConnExTest_', '^crewchief-', '^CrewChief[A-Za-z]*Tests$', '^cc-model-import-'   # CrewChief tests
)
# Names are compared case-sensitively (-cmatch). A random name is eight lowercase letters or digits, a dot and three
# more, which a real file can also be (settings.yml), so a name whose extension is a common real one never counts.
$script:ScratchKeepExtensions = @('.txt', '.md', '.ps1', '.psm1', '.yml', '.json', '.xml', '.csv', '.zip', '.log', '.cs', '.py', '.sql', '.htm', '.png', '.jpg', '.pdf', '.bak', '.cmd', '.bat', '.exe', '.dll')

function Clear-AIScratchLeftovers {
    <#
    .SYNOPSIS
        Removes stale tool/test leftovers from the top level of each root. Never recurses into other names.
    .DESCRIPTION
        An entry goes only when its name matches $ScratchLeftoverShapes (case-sensitive) and both its write and creation times are older
        than -OlderThanHours, so a folder a running test or build just made is never touched. At most -Max entries go
        per call, so a launch or a watchdog tick on a host that piled up for weeks stays short; the rest go next time.
        An entry that cannot be removed (held open) stays and is not counted. Returns one object per root:
        Root, Swept, Left (matching stale entries not reached this call).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Root,
        [double]$OlderThanHours = 24,
        [int]$Max = 2000
    )
    $cut = (Get-Date).ToUniversalTime().AddHours(-$OlderThanHours)
    $budget = $Max
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Root) {
        if (-not $r -or -not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        $full = [IO.Path]::GetFullPath($r).TrimEnd('\')
        if (-not $seen.Add($full)) { continue }
        $swept = 0; $left = 0
        foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($full)) {
            $name = [IO.Path]::GetFileName($e)
            $match = $false
            foreach ($s in $script:ScratchLeftoverShapes) { if ($name -cmatch $s) { $match = $true; break } }
            if ($match -and $name -cmatch $script:ScratchLeftoverShapes[0] -and [IO.Path]::GetExtension($name) -in $script:ScratchKeepExtensions) { $match = $false }
            if (-not $match) { continue }
            try {
                $isDir = [IO.Directory]::Exists($e)
                $w = if ($isDir) { [IO.Directory]::GetLastWriteTimeUtc($e) } else { [IO.File]::GetLastWriteTimeUtc($e) }
                $c = if ($isDir) { [IO.Directory]::GetCreationTimeUtc($e) } else { [IO.File]::GetCreationTimeUtc($e) }
                if ($w -ge $cut -or $c -ge $cut) { continue }
                if ($budget -le 0) { $left++; continue }
                if ($isDir) { [IO.Directory]::Delete($e, $true) } else { [IO.File]::Delete($e) }
                $swept++; $budget--
            } catch { }   # held open or vanished: it stays, the next call tries again
        }
        [pscustomobject]@{ Root = $full; Swept = $swept; Left = $left }
    }
}

Export-ModuleMember -Function Get-AIMachineConfigPath, Get-AIMachineProfile, Get-AIPath, Get-AIConfig,
    Get-AILocationKind, Test-AIPathUnder, Test-AIMachineProfile, Get-AIRepoRoot, Get-AIGitPolicy, Expand-AIValue,
    Clear-AIScratchLeftovers, Read-AIMarkdownTables
Export-ModuleMember -Variable AIKeys, RequiredKeys
