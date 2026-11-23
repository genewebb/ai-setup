# prof travel: work away from the NAS. Wraps the scripts in C:\Travel (each has its own -Help):
#   Sync-NasToTravel.ps1   NAS -> C:\Travel  (before the trip)
#   Sync-TravelToNas.ps1   C:\Travel -> NAS  (after the trip; baseline 3-way, conflicts are skipped)
#   Use-TravelDrives.ps1   D: O: Q: -> C:\Travel (away) or back to the NAS (home), normal + admin shell
# Not part of prof setup share (Share.ps1 lists the files it copies); a machine without C:\Travel gets a clear error.

$script:ProfTravelRoot = 'C:\Travel'

$script:ProfTravelVerbs = [ordered]@{
    status      = 'Where D: O: Q: point, when the last sync ran, which folders are marked (changes nothing)'
    'to-laptop' = 'BEFORE the trip: copy the marked NAS folders down to C:\Travel (preview; -Apply to do it)'
    away        = 'On the trip: point D: O: Q: at C:\Travel in this shell and the admin shell (redo after a reboot)'
    'to-nas'    = 'AFTER the trip: send what you changed in C:\Travel back to the NAS (preview; -Apply to do it)'
    home        = 'Back home, after to-nas: point D: O: Q: at the NAS again (both shells)'
    folders     = 'Open the checklists that pick which folders travel (DriveD/O/Q-Folders.md)'
}
$script:ProfTravelDetails = @{
    status      = @('Drive letters in this shell, the baseline date per drive (C:\Travel\.sync), and the marked folders.')
    'to-laptop' = @('Makes C:\Travel\DriveD, DriveO, DriveQ match the NAS for the folders marked "- [x]". Never changes the NAS.',
        'Unmarked local folders are deleted (local copy only). Local edits not yet sent back are CONFLICTs and kept.',
        'With -Apply it saves the baseline that to-nas needs: run it with -Apply right before you leave.',
        'Drives: prof travel to-laptop Q   (or D,O,Q; default all).   -Force: the NAS wins every conflict.',
        "Script: $($script:ProfTravelRoot)\Sync-NasToTravel.ps1 -Help")
    away        = @('net use X: /delete, then subst X: C:\Travel\DriveX for D, O, Q. From a normal shell it then opens an',
        'admin shell (approve UAC) that does the same. subst does not survive a reboot: run it again after a restart.',
        "Script: $($script:ProfTravelRoot)\Use-TravelDrives.ps1 -Help")
    'to-nas'    = @('Compares local now, NAS now and the baseline from the last to-laptop -Apply:',
        '  PUSH changed here only -> copied up     DEL-NAS deleted here, NAS untouched -> deleted on the NAS',
        '  CONFLICT changed on both sides -> skipped, both kept     NAS-CHANGED changed only on the NAS -> info',
        'Refuses a drive that would delete more than 50 NAS files (-MaxNasDeletes to raise).',
        "Script: $($script:ProfTravelRoot)\Sync-TravelToNas.ps1 -Help")
    home        = @('Removes the subst letters, then remaps every NAS letter with MapSyn.ps1 (same as prof nas map).',
        'Order coming home: prof travel to-nas, read the conflicts, prof travel to-nas -Apply, then prof travel home.')
    folders     = @("Opens $($script:ProfTravelRoot)\DriveD-Folders.md, DriveO-Folders.md and DriveQ-Folders.md.",
        'Mark a folder with "- [x] Name" to take it; clear the x to drop it (dropped folders leave C:\Travel on the next to-laptop -Apply).')
}
$script:ProfTravelUsage = @{
    status      = 'prof travel status'
    'to-laptop' = 'prof travel to-laptop [D,O,Q] [-Apply] [-Force]'
    away        = 'prof travel away [D,O,Q] [-ThisShellOnly] [-WhatIf]'
    'to-nas'    = 'prof travel to-nas [D,O,Q] [-Apply] [-MaxNasDeletes <n>]'
    home        = 'prof travel home [D,O,Q] [-ThisShellOnly] [-WhatIf]'
    folders     = 'prof travel folders'
}

$script:ProfGroups.Insert([Math]::Min(1, $script:ProfGroups.Count), 'travel', [pscustomobject]@{
        Description = 'Travel: copy NAS folders to C:\Travel and back, switch D: O: Q: between NAS and laptop'
        Verbs       = $script:ProfTravelVerbs
        Details     = $script:ProfTravelDetails
        Usage       = $script:ProfTravelUsage
        Prefix      = 'Invoke-GeneProfTravel'
        NeedMachine = @()
        TopicParam  = 'Drive'
        TopicNames  = { 'D', 'O', 'Q', 'D,O,Q' }
        Ask         = 'Read-GeneTravelParams'
    })

function Get-GeneTravelScript([string]$Name) {
    $p = Join-Path $script:ProfTravelRoot $Name
    if (-not (Test-Path -LiteralPath $p)) { throw "$p not found on this machine." }
    return $p
}

function Invoke-GeneTravelScript {
    <# Runs a C:\Travel script with -Drive and the extra switches (-Apply, -Force ...). Current folder moved to C:\ first. #>
    param([Parameter(Mandatory)][string]$Name, [string]$Drive, [object[]]$Extra, [hashtable]$Fixed = @{}, [switch]$WhatIf)
    $path = Get-GeneTravelScript $Name
    $splat = if ($Extra) { ConvertTo-GeneCommandArgs -Command $path -Extra $Extra } else { [ordered]@{} }
    foreach ($k in $Fixed.Keys) { $splat[$k] = $Fixed[$k] }
    if ($Drive) { $splat['Drive'] = @($Drive -split ',') }
    if ($WhatIf) {
        if ((Get-Command $path).Parameters.ContainsKey('WhatIf')) { $splat['WhatIf'] = $true }
        elseif ($splat.Contains('Apply')) { $splat.Remove('Apply'); Write-ProfNote '-WhatIf: running as a preview (no -Apply).' }
    }
    $shown = @($path) + @($splat.Keys | ForEach-Object { $v = $splat[$_]; if ($v -is [bool] -or $v -is [switch]) { if ($v) { "-$_" } } else { "-$_ $(@($v) -join ',')" } })
    Write-ProfNote "Running: $($shown -join ' ')"
    Push-Location C:\
    try { & $path @splat } finally { Pop-Location }
}

function Invoke-GeneProfTravelToLaptop { param([string]$Drive, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneTravelScript 'Sync-NasToTravel.ps1' -Drive $Drive -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfTravelToNas { param([string]$Drive, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneTravelScript 'Sync-TravelToNas.ps1' -Drive $Drive -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfTravelAway { param([string]$Drive, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneTravelScript 'Use-TravelDrives.ps1' -Drive $Drive -Extra $Extra -Fixed @{ Mode = 'Travel' } -WhatIf:$WhatIf }
function Invoke-GeneProfTravelHome { param([string]$Drive, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneTravelScript 'Use-TravelDrives.ps1' -Drive $Drive -Extra $Extra -Fixed @{ Mode = 'Home' } -WhatIf:$WhatIf }

function Invoke-GeneProfTravelStatus {
    Invoke-GeneTravelScript 'Use-TravelDrives.ps1' -Fixed @{ Mode = 'Status' }
    Write-ProfStep 'Last applied sync (baseline) per drive'
    foreach ($d in 'D', 'O', 'Q') {
        $b = Join-Path $script:ProfTravelRoot ".sync\Drive$d.baseline.csv"
        $list = Join-Path $script:ProfTravelRoot "Drive$d-Folders.md"
        $marked = if (Test-Path -LiteralPath $list) { @(Get-Content -LiteralPath $list | ForEach-Object { if ($_ -match '^\s*-\s*\[[xX]\]\s+(.+?)\s*$') { $Matches[1] } }) } else { @() }
        $when = if (Test-Path -LiteralPath $b) { (Get-Item -LiteralPath $b).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { 'never (run prof travel to-laptop -Apply)' }
        Write-Host ("  {0}:  baseline {1}   marked ({2}): {3}" -f $d, $when, $marked.Count, ($marked -join ', '))
    }
}

function Invoke-GeneProfTravelFolders {
    param([switch]$WhatIf)
    foreach ($d in 'D', 'O', 'Q') {
        $f = Join-Path $script:ProfTravelRoot "Drive$d-Folders.md"
        if (-not (Test-Path -LiteralPath $f)) { Write-ProfWarn "$f not found"; continue }
        if ($WhatIf) { Write-Host "[WhatIf] Would open $f" -ForegroundColor Yellow } else { Write-ProfNote "Opening $f"; Invoke-Item -LiteralPath $f }
    }
}

function Read-GeneTravelParams {
    <# Menu questions: which drives, and preview or apply / both shells. #>
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $p = [ordered]@{}
    if ($Verb -in 'status', 'folders') { return $p }
    $items = @('D', 'O', 'Q') | ForEach-Object { [pscustomobject]@{ Name = $_; Description = @{ D = 'devopslocal'; O = 'OneDriveArchive'; Q = 'obsidian (vaults)' }[$_] } }
    $picked = Select-GeneMenu -Title 'Which drives?' -Items $items -Multi -Reader $Reader
    if ($null -eq $picked) { return $null }
    # Topic = the dispatcher's positional word; the group's TopicParam turns it into -Drive.
    if (@($picked).Count -and @($picked).Count -lt 3) { $p.Topic = (@($picked).Name -join ',') }
    if ($Verb -in 'to-laptop', 'to-nas') {
        $mode = Select-GeneMenu -Title 'Preview or do it?' -Default 1 -Reader $Reader -Items @(
            [pscustomobject]@{ Name = 'preview'; Description = 'show what would change, change nothing' }
            [pscustomobject]@{ Name = 'apply'; Description = 'make the changes' })
        if (-not $mode) { return $null }
        if ($mode.Name -eq 'apply') { $p.Extra = @('-Apply') }
    }
    elseif (-not (Read-GeneYesNo -Question 'Also switch the admin shell (UAC prompt)?' -Default $true -Reader $Reader)) { $p.Extra = @('-ThisShellOnly') }
    return $p
}
