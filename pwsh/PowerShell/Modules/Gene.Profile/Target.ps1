# Target resolution for prof: the hub clone, the machines registry, a target's machine profile read over the admin
# share, the WinRM session as -User, and the target's paths in both local and admin-share form.

# The machine profile lives at this path on every machine (the one convention string; see docs\machine-config-design.md).
$script:GeneProfileRelPath = 'Deploy\Setup\ProfileMachineConfig.md'

function Get-GeneHubRoot {
    <# This machine's ai-setup clone (AIWorkRoot): the hub every prof verb works from. #>
    [CmdletBinding()]
    param()
    if ($env:GENE_PROF_HUB) { return $env:GENE_PROF_HUB }
    if ($global:GeneMachineAI -and $global:GeneMachineAI['AIWorkRoot']) { return $global:GeneMachineAI['AIWorkRoot'] }
    $cfg = if ($env:AI_MACHINE_CONFIG) { $env:AI_MACHINE_CONFIG } else { Join-Path "$env:SystemDrive\" $script:GeneProfileRelPath }
    if (Test-Path -LiteralPath $cfg) {
        foreach ($line in Get-Content -LiteralPath $cfg) {
            if ($line -match '^\s*\|\s*`?AIWorkRoot`?\s*\|([^|]*)\|') { return [Environment]::ExpandEnvironmentVariables($Matches[1].Trim().Trim('`').Trim()) }
        }
    }
    throw "No AIWorkRoot on $env:COMPUTERNAME: set it in $cfg (the ai-setup clone prof works from)."
}

function Import-GeneMachineLib {
    <# lib\MachineConfig.psm1 from the hub: the one machine-profile parser. #>
    param([string]$Hub = (Get-GeneHubRoot))
    if (-not (Get-Command Read-AIMarkdownTables -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $Hub 'lib\MachineConfig.psm1') -DisableNameChecking -Scope Global -ErrorAction Stop
    }
}

# The process token, not USERNAME/USERDOMAIN: some hosts (agent sandboxes, scheduled tasks) set those to SYSTEM.
function Get-GeneCaller { [Security.Principal.WindowsIdentity]::GetCurrent().Name }

function Resolve-GeneUser {
    <# 'agenewe' -> 'CORP\agenewe'; blank -> the caller. #>
    param([string]$User)
    if (-not $User) { return Get-GeneCaller }
    if ($User -notmatch '\\') { return "$((Get-GeneCaller).Split('\')[0])\$User" }
    return $User
}

function Get-GeneUserName { param([string]$User) ($User -split '\\')[-1] }

function Test-GeneIsCaller { param([string]$User) [string]::Equals((Resolve-GeneUser $User), (Get-GeneCaller), [StringComparison]::OrdinalIgnoreCase) }

function Get-GeneTargetCredential {
    <# $null when -User is the caller (Kerberos, no prompt); otherwise asked every time, never stored. #>
    param([Parameter(Mandatory)][string]$User)
    if (Test-GeneIsCaller $User) { return $null }
    $u = Resolve-GeneUser $User
    if ([Console]::IsInputRedirected) { throw "prof needs the password for $u and there is no console to ask on. Run prof in a terminal." }
    return Get-Credential -UserName $u -Message "prof: password for $u (used for this run only, never stored)"
}

function Test-GeneIsLocalMachine { param([string]$Machine) $Machine -and ($Machine -ieq $env:COMPUTERNAME -or $Machine -ieq 'localhost' -or $Machine -eq '.') }

function ConvertTo-GeneUncPath {
    <# D:\x\y on machine M -> \\M\D$\x\y. A UNC path passes through; on this machine the path is returned as is. #>
    param([Parameter(Mandatory)][string]$Machine, [Parameter(Mandatory)][string]$Path)
    if ($Path -match '^\\\\') { return $Path }
    if (Test-GeneIsLocalMachine $Machine) { return $Path }
    if ($Path -notmatch '^([A-Za-z]):(?:\\(.*))?$') { throw "Not a drive path: '$Path'" }
    $rest = $Matches[2]
    return "\\$Machine\$($Matches[1].ToUpperInvariant())`$" + $(if ($rest) { "\$rest" } else { '' })
}

function ConvertTo-GeneGitUrl {
    <# Git takes a UNC path as a URL most reliably with forward slashes. #>
    param([string]$Path)
    if ($Path -match '^\\\\') { return ($Path -replace '\\', '/') }
    return $Path
}

function Get-GeneMachinesPath { param([string]$Hub = (Get-GeneHubRoot)) Join-Path $Hub 'machines.yaml' }

function Get-GeneMachines {
    <# machines.yaml: name => @{ users = string[]; systemDrive = 'C' }. Missing file = empty. #>
    param([string]$Path = (Get-GeneMachinesPath))
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    Import-Module powershell-yaml -ErrorAction Stop
    $y = ConvertFrom-Yaml (Get-Content -LiteralPath $Path -Raw) -Ordered
    if (-not $y -or -not $y['machines']) { return $result }
    foreach ($name in $y['machines'].Keys) {
        $m = $y['machines'][$name]
        $result[$name] = [ordered]@{
            users       = @(if ($m -and $m['users']) { $m['users'] | ForEach-Object { Resolve-GeneUser ([string]$_) } })
            systemDrive = if ($m -and $m['systemDrive']) { ([string]$m['systemDrive']).TrimEnd(':') } else { 'C' }
        }
    }
    return $result
}

function Save-GeneMachines {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Machines, [string]$Path = (Get-GeneMachinesPath))
    $lines = @('# Machines prof knows (names and accounts only; every path comes from that machine''s own machine profile).',
        '# systemDrive: only when the machine profile is not on C:.', 'machines:')
    foreach ($name in $Machines.Keys) {
        $m = $Machines[$name]
        $lines += "  ${name}:"
        $lines += "    users: [$((@($m.users) | ForEach-Object { $_ }) -join ', ')]"
        if ($m.systemDrive -and $m.systemDrive -ne 'C') { $lines += "    systemDrive: $($m.systemDrive)" }
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8NoBOM
}

function Add-GeneMachine {
    <# Adds a machine, or a user to a known machine. Returns $true when the file changed. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$User, [string]$Path = (Get-GeneMachinesPath))
    $all = Get-GeneMachines -Path $Path
    $u = Resolve-GeneUser $User
    $key = @($all.Keys | Where-Object { $_ -ieq $Name }) | Select-Object -First 1
    if (-not $key) { $all[$Name.ToUpperInvariant()] = [ordered]@{ users = @($u); systemDrive = 'C' } }
    elseif (@($all[$key].users) -notcontains $u) { $all[$key].users = @($all[$key].users) + $u }
    else { return $false }
    Save-GeneMachines -Machines $all -Path $Path
    return $true
}

function Resolve-GeneTargetUser {
    <# The account a remote verb acts as: -User when given; else the one account machines.yaml lists for the machine;
       else, for a machine it does not know, the caller. Several listed and no -User: refuse, naming them. #>
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [string]$Path = (Get-GeneMachinesPath))
    if ($User) { return Resolve-GeneUser $User }
    $all = Get-GeneMachines -Path $Path
    $key = @($all.Keys | Where-Object { $_ -ieq $Machine }) | Select-Object -First 1
    $users = @(if ($key) { @($all[$key].users) | Where-Object { $_ } })
    if ($users.Count -eq 1) { return [string]$users[0] }
    if ($users.Count -gt 1) { throw "$key has several accounts in machines.yaml ($($users -join ', ')). Say which one: -User <DOMAIN\name>." }
    return Resolve-GeneUser ''
}

function Remove-GeneMachineUser {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$User, [string]$Path = (Get-GeneMachinesPath))
    $all = Get-GeneMachines -Path $Path
    $key = @($all.Keys | Where-Object { $_ -ieq $Name }) | Select-Object -First 1
    if (-not $key) { return $false }
    $u = Resolve-GeneUser $User
    $before = @($all[$key].users).Count
    $all[$key].users = @($all[$key].users | Where-Object { $_ -ine $u })
    if (@($all[$key].users).Count -eq $before) { return $false }
    Save-GeneMachines -Machines $all -Path $Path
    return $true
}

function Get-GeneTargetProfilePath {
    param([Parameter(Mandatory)][string]$Machine, [string]$SystemDrive = 'C')
    if (Test-GeneIsLocalMachine $Machine) {
        if ($env:AI_MACHINE_CONFIG) { return $env:AI_MACHINE_CONFIG }
        return Join-Path "$($SystemDrive):\" $script:GeneProfileRelPath
    }
    return Join-Path "\\$Machine\$($SystemDrive)`$" $script:GeneProfileRelPath
}

function Read-GeneTargetProfile {
    <#
    The target's machine profile, unexpanded: Raw = first table Key => Value (as written), Tables = every table, Lines.
    Returns $null when the file is not there.
    #>
    param([Parameter(Mandatory)][string]$Path)
    Import-GeneMachineLib
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $lines = @(Get-Content -LiteralPath $Path)
    $tables = Read-AIMarkdownTables -Lines $lines
    $raw = [ordered]@{}
    if ($tables.Contains('')) {
        foreach ($row in $tables['']) {
            $k = [string]@($row.Values)[0]
            if (-not $k -or $k -notmatch '^[A-Za-z][A-Za-z0-9]*$' -or $k -in 'Key', 'Setting') { continue }
            $raw[$k] = [string]@($row.Values)[1]
        }
    }
    [pscustomobject]@{ Path = $Path; Raw = $raw; Tables = $tables; Lines = $lines }
}

function Expand-GeneOffline {
    <#
    Expands a profile value for another account without a session (status): %USERNAME% and %USERPROFILE% only.
    Any other %VAR% left means 'unresolved' and returns $null.
    #>
    param([string]$Value, [Parameter(Mandatory)][string]$User, [string]$SystemDrive = 'C')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $name = Get-GeneUserName $User
    $v = $Value -ireplace '%USERNAME%', $name -ireplace '%USERPROFILE%', "$($SystemDrive):\Users\$name" -ireplace '%HOMEDRIVE%', "$($SystemDrive):"
    if ($v -match '%[A-Za-z_]+%') { return $null }
    return $v
}

function Test-GenePerUserValue { param([string]$Value) $Value -match '%USERNAME%|%USERPROFILE%' }

function New-GeneTargetSession {
    <# One WinRM session as -User for the whole verb. Proves the account is remotable on that machine. #>
    param([Parameter(Mandatory)][string]$Machine, [Parameter(Mandatory)][string]$User)
    $cred = Get-GeneTargetCredential -User $User
    $p = @{ ComputerName = $Machine; ErrorAction = 'Stop' }
    if ($cred) { $p.Credential = $cred }
    try { $s = New-PSSession @p }
    catch { throw "Cannot open a WinRM session on $Machine as $User. The account must be in Administrators or Remote Management Users there, and WinRM must answer ($($_.Exception.Message))" }
    $who = Invoke-Command -Session $s -ScriptBlock { [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    if ($who -ine (Resolve-GeneUser $User)) { Remove-PSSession $s; throw "The session on $Machine runs as $who, not $User." }
    return $s
}

function Get-GeneTargetPaths {
    <#
    Expands the target's path rows with -User's own environment inside the session. Returns local paths (as the
    target sees them) and admin-share paths (as this machine reaches them).
    #>
    param([Parameter(Mandatory)][string]$Machine, [Parameter(Mandatory)][System.Collections.IDictionary]$Raw, $Session)
    $keys = 'AIWorkRoot', 'ClaudeHome', 'ScratchRoot', 'ArchiveRoot', 'ReposRoot'
    $rawValues = @{}; foreach ($k in $keys) { $rawValues[$k] = [string]$Raw[$k] }
    $sb = {
        param($rv)
        $out = @{}
        foreach ($k in $rv.Keys) { $out[$k] = if ($rv[$k]) { [Environment]::ExpandEnvironmentVariables($rv[$k]) } else { '' } }
        if (-not $out['ClaudeHome']) { $out['ClaudeHome'] = Join-Path $HOME '.claude' }
        $out['Home'] = $HOME
        $out['Documents'] = [Environment]::GetFolderPath('MyDocuments')
        $out
    }
    $local = if ($Session) { Invoke-Command -Session $Session -ScriptBlock $sb -ArgumentList $rawValues } else { & $sb $rawValues }
    $unc = @{}
    foreach ($k in @($local.Keys)) { $unc[$k] = if ($local[$k]) { ConvertTo-GeneUncPath -Machine $Machine -Path $local[$k] } else { '' } }
    [pscustomobject]@{ Local = $local; Unc = $unc }
}

function Resolve-GeneTarget {
    <#
    Everything a remote verb needs about -Machine/-User. -NeedSession opens the WinRM session as -User.
    Refuses this machine (the hub) for remote verbs.
    #>
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [switch]$NeedSession, [switch]$AllowMissingProfile)
    if (Test-GeneIsLocalMachine $Machine) { throw "-Machine $Machine is this machine (the hub). push, pull, check, bootstrap, terminal and secrets work on another machine." }
    $u = Resolve-GeneTargetUser -Machine $Machine -User $User
    $known = Get-GeneMachines
    $key = @($known.Keys | Where-Object { $_ -ieq $Machine }) | Select-Object -First 1
    $sysDrive = if ($key) { $known[$key].systemDrive } else { 'C' }
    if (-not (Test-Path -LiteralPath "\\$Machine\$($sysDrive)`$")) { throw "Cannot reach \\$Machine\$($sysDrive)`$ (admin share). Check the name, the network and that you are an administrator there." }
    $profilePath = Get-GeneTargetProfilePath -Machine $Machine -SystemDrive $sysDrive
    $prof = Read-GeneTargetProfile -Path $profilePath
    if (-not $prof -and -not $AllowMissingProfile) { throw "No machine profile on $Machine ($profilePath). Run: prof setup bootstrap -Machine $Machine -User $u" }
    $t = [pscustomobject]@{
        Machine = $(if ($key) { $key } else { $Machine.ToUpperInvariant() }); User = $u; SystemDrive = $sysDrive; Known = [bool]$key
        Users = @(if ($key) { $known[$key].users }); ProfilePath = $profilePath; Profile = $prof; Session = $null; Paths = $null
    }
    if ($NeedSession) {
        $t.Session = New-GeneTargetSession -Machine $Machine -User $u
        if ($prof) { $t.Paths = Get-GeneTargetPaths -Machine $Machine -Raw $prof.Raw -Session $t.Session }
    }
    return $t
}

function Close-GeneTarget { param($Target) if ($Target -and $Target.Session) { Remove-PSSession $Target.Session -ErrorAction SilentlyContinue } }

function Invoke-GeneRemotePwsh {
    <#
    Runs a pwsh 7 script on the target as -User (the session's account), streaming its output with a prefix.
    -Stdin (SecureString) is written to the script's standard input, never to its command line or a file.
    Returns the script's exit code.
    #>
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [securestring]$Stdin)
    $code = $null
    Invoke-Command -Session $Target.Session -ArgumentList $File, $Arguments, $Stdin -ScriptBlock {
        param($file, $argList, $secure)
        $ErrorActionPreference = 'Continue'
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwsh) { 'pwsh 7 is not installed on this machine.'; '__PROF_EXIT__9'; return }
        if ($secure) {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $plain | & $pwsh -NoProfile -NonInteractive -File $file @argList 2>&1 | ForEach-Object { "$_" }
            $plain = $null
        }
        else { & $pwsh -NoProfile -NonInteractive -File $file @argList 2>&1 | ForEach-Object { "$_" } }
        "__PROF_EXIT__$LASTEXITCODE"
    } | ForEach-Object {
        if ($_ -match '^__PROF_EXIT__(-?\d+)$') { $code = [int]$Matches[1] }
        else { Write-Host "  [$($Target.Machine)] $_" }
    }
    return $code
}
