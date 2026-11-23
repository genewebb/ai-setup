# prof nas: the Synology NAS drive letters (D F L M O Q Y on \\SynologyDS918). Wraps C:\Deploy\Scripts\MapSyn.ps1,
# which remaps in the normal shell AND the admin shell (UAC prompt), using the credential stored in Credential Manager.
# Not part of prof setup share (Share.ps1 lists the files it copies); a machine without MapSyn.ps1 gets a clear error.

$script:ProfNasServer = 'SynologyDS918'
$script:ProfNasMapSyn = 'C:\Deploy\Scripts\MapSyn.ps1'
$script:ProfNasLetters = [ordered]@{ D = 'devopslocal'; F = 'Family'; L = 'LargeFiles'; M = 'PlexMedia'; O = 'OneDriveArchive'; Q = 'obsidian'; Y = 'devops' }

$script:ProfNasVerbs = [ordered]@{
    status     = 'Where every NAS letter points, is it reachable, is the NAS up, is a password stored (changes nothing)'
    map        = 'Fix "Unavailable" NAS letters: remap all of them in this shell and the admin shell (MapSyn.ps1)'
    credential = 'The NAS password changed: save the new one, then remap (MapSyn.ps1 -StoreCredential)'
}
$script:ProfNasDetails = @{
    status     = @('For D F L M O Q Y: subst (travel mode) or NAS mapping and its status, and whether the letter opens.',
        "Also: can \\$($script:ProfNasServer) be reached by its UNC path, and is a credential stored for it.",
        'A letter that says Unavailable while the NAS is reachable is the usual after-reboot problem: prof nas map.')
    map        = @('Drops every connection this shell has to the NAS, then maps every letter with the stored credential.',
        'From a normal shell it then opens an admin shell (approve UAC) that does the same and prints what it did.',
        'From an admin shell it does the admin side only and tells you to run it once in a normal shell.',
        'Letters that are subst to C:\Travel (travel mode) are left alone. -ThisShellOnly skips the other shell.',
        "Script: $($script:ProfNasMapSyn)   (its own help: $($script:ProfNasMapSyn) -Help)")
    credential = @('Prompts for the NAS password (user WEBBGROUP\Gene), saves it in Credential Manager for this Windows', 'account, then remaps like prof nas map.')
}
$script:ProfNasUsage = @{
    status     = 'prof nas status'
    map        = 'prof nas map [-ThisShellOnly] [-WhatIf]'
    credential = 'prof nas credential [-WhatIf]'
}

$script:ProfGroups.Insert([Math]::Min(1, $script:ProfGroups.Count), 'nas', [pscustomobject]@{
        Description = 'NAS drive letters (D F L M O Q Y): check them, fix Unavailable letters, save a new password'
        Verbs       = $script:ProfNasVerbs
        Details     = $script:ProfNasDetails
        Usage       = $script:ProfNasUsage
        Prefix      = 'Invoke-GeneProfNas'
        NeedMachine = @()
        Ask         = 'Read-GeneNasParams'
    })

function Invoke-GeneNasMapSyn {
    param([hashtable]$Splat = @{}, [switch]$WhatIf)
    if (-not (Test-Path -LiteralPath $script:ProfNasMapSyn)) { throw "$($script:ProfNasMapSyn) not found on this machine." }
    $shown = @($script:ProfNasMapSyn) + @($Splat.Keys | ForEach-Object { "-$_" })
    if ($WhatIf) { Write-Host "[WhatIf] Would run: $($shown -join ' ')" -ForegroundColor Yellow; return }
    Write-ProfNote "Running: $($shown -join ' ')"
    # The current folder must not be on a letter being remapped.
    Push-Location C:\
    try { & $script:ProfNasMapSyn @Splat } finally { Pop-Location }
}

function Invoke-GeneProfNasStatus {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $subst = @{}; foreach ($line in @(subst)) { if ($line -match '^([A-Z]):\\: => (.+)$') { $subst[$Matches[1]] = $Matches[2] } }
    $maps = @{}; foreach ($m in @(Get-SmbMapping -ErrorAction SilentlyContinue)) { $maps[$m.LocalPath.TrimEnd(':')] = $m }
    Write-ProfStep "NAS letters in this $(if ($isAdmin) { 'ADMIN' } else { 'normal' }) shell (the other shell has its own)"
    foreach ($d in $script:ProfNasLetters.Keys) {
        $where = if ($subst.ContainsKey($d)) { "subst -> $($subst[$d])  (travel mode)" }
        elseif ($maps.ContainsKey($d)) { "$($maps[$d].RemotePath)  $($maps[$d].Status)" }
        else { 'not mapped' }
        $ok = Test-Path -LiteralPath "${d}:\"
        Write-Host ("  {0}:  {1,-55} opens: {2}" -f $d, $where, $ok) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    }
    $up = Test-Path -LiteralPath "\\$($script:ProfNasServer)\$($script:ProfNasLetters['Q'])"
    $cred = (cmdkey.exe /list:$($script:ProfNasServer) | Out-String) -match 'User:'
    Write-Host ("  NAS reachable by UNC: {0}    credential stored: {1}" -f $up, $cred) -ForegroundColor $(if ($up -and $cred) { 'Green' } else { 'Yellow' })
    if ($up -and @($script:ProfNasLetters.Keys | Where-Object { -not $subst.ContainsKey($_) -and -not (Test-Path -LiteralPath "${_}:\") }).Count) {
        Write-ProfNote 'NAS is up but some letters do not open: prof nas map'
    }
}

function Invoke-GeneProfNasMap {
    param([object[]]$Extra, [switch]$WhatIf)
    $splat = if ($Extra) { ConvertTo-GeneCommandArgs -Command $script:ProfNasMapSyn -Extra $Extra } else { @{} }
    Invoke-GeneNasMapSyn -Splat $splat -WhatIf:$WhatIf
}

function Invoke-GeneProfNasCredential {
    param([switch]$WhatIf)
    Invoke-GeneNasMapSyn -Splat @{ StoreCredential = $true } -WhatIf:$WhatIf
}

function Read-GeneNasParams {
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $p = [ordered]@{}
    if ($Verb -eq 'map' -and -not (Read-GeneYesNo -Question 'Also remap the admin shell (UAC prompt)?' -Default $true -Reader $Reader)) { $p.Extra = @('-ThisShellOnly') }
    return $p
}
