# prof setup export: pack the PowerShell profile for someone else (a coworker, a fresh account) as one zip.
# The zip holds the pwsh\ tree of the hub (profile, modules, terminal script, modules.txt), a blank-value copy of this
# machine's ProfileMachineConfig.md, Install-Profile.ps1 and a README. Nothing from the AI corpus, no secrets.

function New-GeneProfileTemplate {
    <#
    The machine profile for someone else: the hub's first table with every Value blanked (a %USERPROFILE%-relative
    value is kept: it is the same for everyone), the Status column set to 'fill in', the machine name in the title
    replaced by <MACHINE>, and the later tables (AI runtime: Resources, Claude access, Git policy, MCP servers) dropped.
    Returns the lines.
    #>
    param([Parameter(Mandatory)]$Profile)
    $out = [System.Collections.Generic.List[string]]::new()
    $inFirst = $false; $done = $false
    foreach ($line in $Profile.Lines) {
        $isRow = $line -match '^\s*\|'
        if ($line -match '^#\s') { $line = $line -replace [regex]::Escape($env:COMPUTERNAME), '<MACHINE>' }
        if (-not $done -and $isRow) { $inFirst = $true }
        if ($inFirst -and -not $done -and -not $isRow) { $done = $true; $inFirst = $false }
        if ($done) { break }   # later tables are the AI runtime's: they hold this machine's literal paths
        if ($inFirst) {
            $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            if ($cells.Count -ge 2 -and $cells[0] -match '^`?[A-Za-z][A-Za-z0-9]*`?$' -and $cells[0] -notin 'Key', 'Setting') {
                if ($cells[1] -notmatch '^%USERPROFILE%') { $cells[1] = '' }
                if ($cells.Count -ge 4) { $cells[3] = 'fill in' }
                $line = '| ' + ($cells -join ' | ') + ' |'
            }
            elseif ($cells[0] -in 'Key', 'Setting' -and $cells.Count -ge 4) { $cells[3] = 'Status'; $line = '| ' + ($cells -join ' | ') + ' |' }
        }
        $out.Add($line)
    }
    $out.Add('')
    $out.Add('Fill in the Value column: a blank value means "not on this machine" (the commands in Used by say so when run);')
    $out.Add('delete a row to use the built-in default, which `machinecfg` shows. Rows whose Used by starts with "AI runtime"')
    $out.Add('belong to the AI setup (not part of this export); leave them blank.')
    return $out.ToArray()
}

function Get-GeneBlockedPatterns {
    <# share.yaml blockedPatterns from the hub: the owner's account names, machine names and personal paths. #>
    param([string]$Hub)
    $f = Join-Path $Hub 'share.yaml'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    Import-Module powershell-yaml -ErrorAction Stop
    $y = ConvertFrom-Yaml (Get-Content -LiteralPath $f -Raw) -Ordered
    return @(if ($y -and $y['blockedPatterns']) { $y['blockedPatterns'] | ForEach-Object { [string]$_ } })
}

function Find-GeneExportMentions {
    <# Lines under -Root that match any blocked pattern: file, line number, the matched text. Informational, not secrets. #>
    param([Parameter(Mandatory)][string]$Root, [string[]]$Patterns)
    $hits = [System.Collections.Generic.List[object]]::new()
    if (-not $Patterns) { return $hits }
    $rx = [regex]::new(($Patterns -join '|'), 'IgnoreCase')
    foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.md', '.txt', '.json') {
        $n = 0
        foreach ($line in [IO.File]::ReadLines($f.FullName)) {
            $n++
            $m = $rx.Match($line)
            # The one convention path (ProfileMachineConfig.md under Deploy\Setup) is not a personal path.
            if ($m.Success -and $line -match 'Deploy\\Setup\\ProfileMachineConfig\.md' -and $m.Value -match '^[A-Za-z]:\\') { $m = $rx.Match($line, $m.Index + $m.Length) }
            if ($m.Success) { $hits.Add([pscustomobject]@{ File = [IO.Path]::GetRelativePath($Root, $f.FullName); Line = $n; Match = $m.Value }) }
        }
    }
    return $hits
}

function New-GeneExportReadme {
    param([string[]]$Files, [string]$Owner, [string]$Stamp)
    # Single-quoted here-string: backticks are markdown here, not PowerShell escapes.
    $text = @'
# PowerShell profile export

Exported __STAMP__ by __OWNER__ with `prof setup export`. Everything here is the PowerShell profile and its own modules;
nothing from the AI setup (Claude skills, agents, settings) and no secrets.

## Install (PowerShell 7, as the account that will use it)

#### See what would change

```powershell
.\Install-Profile.ps1 -WhatIf
```

#### Install

```powershell
.\Install-Profile.ps1
```

It copies PowerShell\ into your PowerShell 7 profile folder and WindowsPowerShell\ into the 5.1 one (skip with
-SkipWindowsPowerShell), installs the PSGallery modules in modules.txt that you do not have (-SkipModules to skip),
and places ProfileMachineConfig.md at C:\Deploy\Setup\ only if there is none. Replaced files are backed up; the folder is printed.

## Then

1. Edit C:\Deploy\Setup\ProfileMachineConfig.md: fill in the Value column. Every row says which commands use it.
   Blank = that command says "not available on this machine". Delete a row to take the built-in default.
2. Open a new PowerShell 7 window, or type `. $PROFILE`. Then `machinecfg` shows what resolved.
3. `prof help` lists every command group; `prof` alone opens the menu; `prof other` catalogues the typed commands.
4. Optional Windows Terminal tabs and colours: `.\AddOrUpdateMyTerminal.ps1 -Help`.

## What needs more than this zip

- `prof setup *`, `prof streams *`, `pushStreams`, `getStreams`, `updateStreams`, `dpAI`: need the owner's ai-setup repo
  (AIWorkRoot) and the Claude stream kit. Not in this export; those rows stay blank.
- `dpspeed`, `dpcrewchief`, `dpdatagen`, `dpmutate`, `dpv2`, `dpall`: need the speed-merchants / speedmerchants clones named in
  SpeedMerchantsRepo / SpeedyRepo, BitsDir, and for -Package the PackageShare.
- `pps`, `psql`, `gpush`: push to the OWNER's GitHub repos. Change the remotes in Gene.GitTools before using them, or do not.
- `addLinux`: the owner's droplet and key. Edit or ignore.
- WindowsPowerShell\Microsoft.PowerShell_profile.ps1 is the old 5.1 profile with the owner's paths typed in; use -SkipWindowsPowerShell unless you want it.

## Files

__FILES__
'@
    $text.Replace('__STAMP__', $Stamp).Replace('__OWNER__', $Owner).Replace('__FILES__', (($Files | ForEach-Object { "- $_" }) -join "`n"))
}

function Invoke-GeneProfExport {
    <#
    prof setup export [-Out <folder or .zip>] [-WhatIf]
    Builds <ScratchRoot>\prof\profile-export-<stamp>\ (or -Out) and zips it. Refuses when the secret scan hits;
    lists every mention of the owner's names, machines and personal paths (share.yaml blockedPatterns) and asks
    before packing them. -WhatIf lists and writes nothing.
    #>
    param([string]$Out, [switch]$WhatIf, [scriptblock]$Reader)
    $hub = Get-GeneHubRoot
    $src = Join-Path $hub 'pwsh'
    if (-not (Test-Path -LiteralPath $src)) { throw "No pwsh folder in the hub $hub." }
    $hp = Get-GeneHubProfile
    if (-not $hp) { throw "No machine profile on $env:COMPUTERNAME (needed for the template)." }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name = "profile-export-$stamp"
    if ($Out -and $Out -match '\.zip$') { $zip = $Out; $stage = $Out.Substring(0, $Out.Length - 4) }
    else {
        $base = if ($Out) { $Out } else { Join-Path ([string]$hp.Raw['ScratchRoot'] | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) }) 'prof' }
        if (-not $base) { throw 'ScratchRoot is blank in the machine profile: give -Out.' }
        $stage = Join-Path $base $name; $zip = "$stage.zip"
    }

    # What goes in: the pwsh tree (PowerShell\, WindowsPowerShell\, AddOrUpdateMyTerminal.ps1, modules.txt, Install-Profile.ps1).
    $files = @(Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -notlike '*.bak*' })
    $rel = @($files | ForEach-Object { [IO.Path]::GetRelativePath($src, $_.FullName) })
    $tpl = New-GeneProfileTemplate -Profile $hp
    $owner = Get-GeneCaller

    Write-ProfStep "Export the profile for someone else -> $zip"
    Write-ProfNote "$($files.Count) file(s) from $src, plus ProfileMachineConfig.md (template, values blank) and README.md"
    if ($WhatIf) {
        foreach ($r in $rel) { Write-ProfNote "  $r" }
        Write-ProfNote 'Template rows:'
        foreach ($l in $tpl | Where-Object { $_ -match '^\|' }) { Write-ProfNote "  $l" }
        Write-ProfNote '(-WhatIf: nothing written)'
        return
    }

    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        foreach ($f in $files) {
            $dest = Join-Path $stage ([IO.Path]::GetRelativePath($src, $f.FullName))
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $dest
        }
        Set-Content -LiteralPath (Join-Path $stage 'ProfileMachineConfig.md') -Value $tpl -Encoding utf8NoBOM
        $all = @($rel) + 'ProfileMachineConfig.md' + 'README.md'
        Set-Content -LiteralPath (Join-Path $stage 'README.md') -Value (New-GeneExportReadme -Files $all -Owner $owner -Stamp $stamp) -Encoding utf8NoBOM

        # Secrets: a hit stops the export. The scanner masks the value; the owner fixes the source, not the copy.
        $finder = Join-Path $hub 'tools\Find-Secrets.ps1'
        if (Test-Path -LiteralPath $finder) {
            $secrets = @(& $finder -Root $stage)
            if ($secrets.Count) {
                foreach ($s in $secrets) { Write-ProfWarn "$($s.File):$($s.Line) $($s.Rule) $($s.Match)" }
                throw "Possible secrets in the export ($($secrets.Count)); nothing packed. Fix the source file(s) in $src and run again."
            }
        }
        # Mentions of the owner (accounts, machines, personal paths): shown, then the owner decides.
        $hits = Find-GeneExportMentions -Root $stage -Patterns (Get-GeneBlockedPatterns -Hub $hub)
        if ($hits.Count) {
            Write-ProfNote "$($hits.Count) line(s) mention your accounts, machines or personal paths (they travel with the profile):"
            foreach ($h in $hits | Group-Object File) { Write-ProfNote ("  {0}: {1} ({2})" -f $h.Name, $h.Count, (@($h.Group.Match | Select-Object -Unique) -join ', ')) }
            $go = if ($Reader) { Read-GeneYesNo -Question 'Pack them anyway?' -Reader $Reader } else { Confirm-GeneProf 'Pack them anyway?' }
            if (-not $go) { throw 'Export cancelled; nothing packed.' }
        }

        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
    }
    catch { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }; throw }
    Write-ProfNote "zip    : $zip"
    Write-ProfNote "folder : $stage (same content, unzipped)"
    Write-ProfNote 'Give the zip away. On the other machine: unzip, then .\Install-Profile.ps1 -WhatIf, then .\Install-Profile.ps1 (README.md explains the rest).'
    return [pscustomobject]@{ Zip = $zip; Folder = $stage; Files = $all.Count; Mentions = $hits.Count }
}
