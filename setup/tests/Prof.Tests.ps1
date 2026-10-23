#requires -Version 7
# prof (Gene.Profile module): target resolution, machines registry, the git sync engine and the menu.
# Local folders stand in for a target's admin-share path; no network, no WinRM.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mod = Join-Path $repoRoot 'pwsh\PowerShell\Modules\Gene.Profile'
Import-Module (Join-Path $repoRoot 'lib\MachineConfig.psm1') -Force -DisableNameChecking
foreach ($f in 'Target.ps1', 'Sync.ps1', 'Menu.ps1') { . (Join-Path $mod $f) }

$root = New-TestRoot 'prof'
function New-Queue([string[]]$Answers) { $q = [System.Collections.Generic.Queue[string]]::new(); foreach ($a in $Answers) { $q.Enqueue($a) }; { param($p) $q.Dequeue() }.GetNewClosure() }
function New-Repo([string]$Path) {
    git init -q -b main $Path
    git -C $Path config user.name t; git -C $Path config user.email t@t; git -C $Path config core.autocrlf false
}
function Add-Commit([string]$Path, [string]$File, [string]$Text, [switch]$Append) {
    $f = Join-Path $Path $File
    New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
    if ($Append) { Add-Content -LiteralPath $f -Value $Text } else { Set-Content -LiteralPath $f -Value $Text }
    git -C $Path add -A; git -C $Path commit -q -m "edit $File"
}
function New-SyncPair([string]$Name) {
    $hub = Join-Path $root "$Name-hub"; $target = Join-Path $root "$Name-target"
    New-Repo $hub
    Set-Content -LiteralPath (Join-Path $hub '.gitattributes') -Value @('* -text', 'memory/MEMORY.md merge=union', 'memory/index_*.md merge=union')
    Add-Commit $hub 'memory/MEMORY.md' '- line0'
    Add-Commit $hub 'a.txt' 'base'
    git clone -q --no-hardlinks $hub $target
    $repo = New-GeneRepo -Path $target
    Set-GeneTargetGitConfig -Hub $hub -Repo $repo
    return @{ Hub = $hub; Target = $target; Repo = $repo }
}

try {
    # ---------------------------------------------------------------- target resolution
    Test-Case 'UNC: drive path maps to the admin share' { Assert-Equal '\\BOX\D$\devops\x' (ConvertTo-GeneUncPath -Machine BOX -Path 'D:\devops\x') }
    Test-Case 'UNC: bare drive maps to the share root' { Assert-Equal '\\BOX\C$' (ConvertTo-GeneUncPath -Machine BOX -Path 'c:') }
    Test-Case 'UNC: a UNC path passes through' { Assert-Equal '\\S\share\x' (ConvertTo-GeneUncPath -Machine BOX -Path '\\S\share\x') }
    Test-Case 'UNC: this machine keeps the local path' { Assert-Equal 'D:\x' (ConvertTo-GeneUncPath -Machine $env:COMPUTERNAME -Path 'D:\x') }
    Test-Case 'git URL: UNC uses forward slashes' { Assert-Equal '//BOX/D$/x' (ConvertTo-GeneGitUrl '\\BOX\D$\x') }

    Test-Case 'offline expansion: USERPROFILE and USERNAME for another account' {
        Assert-Equal 'C:\Users\bob\.claude' (Expand-GeneOffline -Value '%USERPROFILE%\.claude' -User 'CORP\bob')
        Assert-Equal 'D:\devops\bob\ai-setup' (Expand-GeneOffline -Value 'D:\devops\%USERNAME%\ai-setup' -User 'CORP\bob')
    }
    Test-Case 'offline expansion: any other variable is unresolved' { Assert-True ($null -eq (Expand-GeneOffline -Value '%APPDATA%\x' -User 'CORP\bob')) }
    Test-Case 'per-user value detection' {
        Assert-True (Test-GenePerUserValue 'D:\devops\%USERNAME%\ai-setup')
        Assert-True (-not (Test-GenePerUserValue 'D:\AIWork\work-ai'))
    }
    Test-Case 'user: bare name gets this domain; the caller needs no credential' {
        Assert-Equal "$((Get-GeneCaller).Split('\')[0])\zed" (Resolve-GeneUser 'zed')
        Assert-True ($null -eq (Get-GeneTargetCredential -User (Get-GeneCaller).Split('\')[1]))
    }
    Test-Case 'this machine is refused as a remote target' { Assert-Throws { Resolve-GeneTarget -Machine $env:COMPUTERNAME } '*is this machine*' }

    $yaml = Join-Path $root 'machines.yaml'
    Test-Case 'machines.yaml: add, re-add is a no-op, second user, remove' {
        Assert-True (Add-GeneMachine -Name box1 -User 'CORP\a' -Path $yaml)
        Assert-True (-not (Add-GeneMachine -Name BOX1 -User 'corp\a' -Path $yaml)) 're-add must not change the file'
        Assert-True (Add-GeneMachine -Name BOX1 -User 'CORP\b' -Path $yaml)
        $m = Get-GeneMachines -Path $yaml
        Assert-Equal 'BOX1' @($m.Keys)[0]
        Assert-Equal @('CORP\a', 'CORP\b') $m['BOX1'].users
        Assert-True (Remove-GeneMachineUser -Name box1 -User 'CORP\a' -Path $yaml)
        Assert-Equal @('CORP\b') (Get-GeneMachines -Path $yaml)['BOX1'].users
    }
    Test-Case 'target user: -User wins, else the one machines.yaml account, else the caller; several = refuse' {
        $yaml = Join-Path $root 'users.yaml'
        Assert-True (Add-GeneMachine -Name one -User 'CORP\solo' -Path $yaml)
        Assert-True (Add-GeneMachine -Name two -User 'CORP\a' -Path $yaml)
        Assert-True (Add-GeneMachine -Name two -User 'CORP\b' -Path $yaml)
        Assert-Equal 'CORP\solo' (Resolve-GeneTargetUser -Machine ONE -Path $yaml)
        Assert-Equal 'CORP\x' (Resolve-GeneTargetUser -Machine one -User 'CORP\x' -Path $yaml)
        Assert-Equal (Get-GeneCaller) (Resolve-GeneTargetUser -Machine unknown -Path $yaml)
        Assert-Throws { Resolve-GeneTargetUser -Machine two -Path $yaml } '*several accounts*CORP\a, CORP\b*'
    }
    Test-Case 'machines.yaml: missing file is an empty registry' { Assert-Equal 0 (Get-GeneMachines -Path (Join-Path $root 'none.yaml')).Count }

    Test-Case 'target profile: first table raw and unexpanded; missing file = null' {
        $p = Join-Path $root 'p.md'
        New-TestProfile -Path $p -Keys ([ordered]@{ AIWorkRoot = 'D:\devops\%USERNAME%\ai-setup'; ScratchRoot = 'D:\tmp' }) -Sections ([ordered]@{ 'Git policy' = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| X | yes | no | no | |" })
        $t = Read-GeneTargetProfile -Path $p
        Assert-Equal 'D:\devops\%USERNAME%\ai-setup' $t.Raw['AIWorkRoot']
        Assert-True (-not $t.Raw.Contains('Repo'))
        Assert-True ($null -eq (Read-GeneTargetProfile -Path (Join-Path $root 'nope.md')))
    }

    # ---------------------------------------------------------------- sync engine
    $finder = $repoRoot   # tools\Find-Secrets.ps1 lives here

    Test-Case 'target config: byte-for-byte, hub identity' {
        $p = New-SyncPair 'cfg'
        Assert-Equal 'false' ((git -C $p.Target config core.autocrlf))
        Assert-Equal 't@t' ((git -C $p.Target config user.email))
    }
    Test-Case 'harvest commits a dirty target and leaves it clean' {
        $p = New-SyncPair 'hv'
        Set-Content -LiteralPath (Join-Path $p.Target 'memory\new note.md') -Value 'remember this'
        $r = Invoke-GeneHarvest -Repo $p.Repo -Label 'BOX\u' -Hub $finder
        Assert-True $r.Committed
        Assert-Equal @('memory/new note.md') $r.Files
        Assert-Equal 0 (Get-GeneRepoState $p.Repo).Dirty.Count
        Assert-Match ((git -C $p.Target log -1 --format=%s)) '^prof: BOX\\u local changes$'
    }
    Test-Case 'harvest of a clean target commits nothing' {
        $p = New-SyncPair 'hc'
        Assert-True (-not (Invoke-GeneHarvest -Repo $p.Repo -Label x -Hub $finder).Committed)
    }
    Test-Case 'harvest refuses a file that looks like a secret' {
        $p = New-SyncPair 'hs'
        Set-Content -LiteralPath (Join-Path $p.Target 'leak.md') -Value ('token: ghp_' + ('a1B2c3D4e5' * 4))
        Assert-Throws { Invoke-GeneHarvest -Repo $p.Repo -Label x -Hub $finder } '*Possible secrets*'
        Assert-Equal 1 (Get-GeneRepoState $p.Repo).Dirty.Count
    }
    Test-Case 'union merge keeps both MEMORY.md lines, then push updates the target tree' {
        $p = New-SyncPair 'un'
        Add-Commit $p.Hub 'memory/MEMORY.md' '- hub line' -Append
        Add-Content -LiteralPath (Join-Path $p.Target 'memory\MEMORY.md') -Value '- target line'
        Invoke-GeneHarvest -Repo $p.Repo -Label x -Hub $finder | Out-Null
        $m = Invoke-GeneMergeFromTarget -Hub $p.Hub -Repo $p.Repo
        Assert-Equal 1 $m.Merged
        $text = Get-Content -LiteralPath (Join-Path $p.Hub 'memory\MEMORY.md') -Raw
        Assert-Match $text 'hub line'; Assert-Match $text 'target line'
        $r = Invoke-GenePushToTarget -Hub $p.Hub -Repo $p.Repo
        Assert-Equal ((git -C $p.Hub rev-parse HEAD)) $r.To
        Assert-Match (Get-Content -LiteralPath (Join-Path $p.Target 'memory\MEMORY.md') -Raw) 'hub line'
        Assert-Equal 0 (Get-GeneRepoState $p.Repo).Dirty.Count
    }
    Test-Case 'merge with nothing new reports 0' {
        $p = New-SyncPair 'nm'
        Assert-Equal 0 (Invoke-GeneMergeFromTarget -Hub $p.Hub -Repo $p.Repo).Merged
    }
    Test-Case 'push fast-forwards past an unrelated uncommitted file and keeps it' {
        $p = New-SyncPair 'uf'
        Add-Commit $p.Hub 'b.txt' 'hub file'
        Set-Content -LiteralPath (Join-Path $p.Target 'memory\live.md') -Value 'session note'
        $r = Invoke-GenePushToTarget -Hub $p.Hub -Repo $p.Repo
        Assert-Equal ((git -C $p.Hub rev-parse HEAD)) $r.To
        Assert-True (Test-Path -LiteralPath (Join-Path $p.Target 'b.txt'))
        Assert-Equal 'session note' ((Get-Content -LiteralPath (Join-Path $p.Target 'memory\live.md')) -join '')
    }
    Test-Case 'push is refused when the target got dirty, and the target is unchanged' {
        $p = New-SyncPair 'dr'
        Add-Commit $p.Hub 'a.txt' 'hub change'
        $before = (Get-GeneRepoState $p.Repo).Head
        Set-Content -LiteralPath (Join-Path $p.Target 'a.txt') -Value 'live session edit'
        Assert-Throws { Invoke-GenePushToTarget -Hub $p.Hub -Repo $p.Repo } '*refused*'
        Assert-Equal $before (Get-GeneRepoState $p.Repo).Head
        Assert-Equal 'live session edit' ((Get-Content -LiteralPath (Join-Path $p.Target 'a.txt')) -join '')
    }
    Test-Case 'a real conflict aborts the merge and leaves the hub clean at its old HEAD' {
        $p = New-SyncPair 'cf'
        Add-Commit $p.Hub 'a.txt' 'hub version'
        Add-Commit $p.Target 'a.txt' 'target version'
        $head = (git -C $p.Hub rev-parse HEAD)
        Assert-Throws { Invoke-GeneMergeFromTarget -Hub $p.Hub -Repo $p.Repo } '*conflicts in: a.txt*'
        Assert-Equal $head ((git -C $p.Hub rev-parse HEAD))
        Assert-Equal 0 (Get-GeneRepoState (New-GeneRepo -Path $p.Hub)).Dirty.Count
    }
    Test-Case 'relation: same, behind, ahead of the hub' {
        $p = New-SyncPair 'rl'
        Assert-Equal 'same as hub' (Get-GeneRelation -Hub $p.Hub -TargetHead (Get-GeneRepoState $p.Repo).Head)
        Add-Commit $p.Hub 'b.txt' 'x'
        Assert-Match (Get-GeneRelation -Hub $p.Hub -TargetHead (Get-GeneRepoState $p.Repo).Head) '^behind hub by 1'
        Add-Commit $p.Target 'c.txt' 'y'
        Assert-Match (Get-GeneRelation -Hub $p.Hub -TargetHead (Get-GeneRepoState $p.Repo).Head) 'lacks'
        Assert-Equal 'no clone' (Get-GeneRelation -Hub $p.Hub -TargetHead $null)
    }

    # ---------------------------------------------------------------- Windows Terminal -ForUser
    $term = Join-Path $repoRoot 'pwsh\AddOrUpdateMyTerminal.ps1'
    function Invoke-Term([string]$LocalAppData, [string]$Start) {
        $saved = $env:LOCALAPPDATA
        try { $env:LOCALAPPDATA = $LocalAppData; $o = & pwsh -NoProfile -NonInteractive -File $term -ForUser -StartingDirectory $Start 2>&1 | Out-String; return @{ Code = $LASTEXITCODE; Out = $o } }
        finally { $env:LOCALAPPDATA = $saved }
    }
    Test-Case 'terminal -ForUser: no settings for this account = exit 3, nothing written' {
        $lad = Join-Path $root 'lad-empty'; New-Item -ItemType Directory $lad | Out-Null
        $r = Invoke-Term $lad $root
        Assert-Equal 3 $r.Code $r.Out
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $lad -Recurse).Count
    }
    Test-Case 'terminal -ForUser: writes with a backup, then reports up to date' {
        $lad = Join-Path $root 'lad'
        $st = Join-Path $lad 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
        New-Item -ItemType Directory -Force $st | Out-Null
        Set-Content -LiteralPath (Join-Path $st 'settings.json') -Value '{}'
        $r = Invoke-Term $lad $root
        Assert-Equal 0 $r.Code $r.Out
        Assert-Match $r.Out 'Updated:'
        Assert-Equal 1 @(Get-ChildItem -LiteralPath $st -Filter 'settings.json.bak-*').Count
        Assert-Match (Get-Content -LiteralPath (Join-Path $st 'settings.json') -Raw) ([regex]::Escape(($root -replace '\\', '\\')))
        $r2 = Invoke-Term $lad $root
        Assert-Match $r2.Out 'Up to date:'
    }

    # ---------------------------------------------------------------- install.ps1 -PassphraseFromStdin guards (run before anything else)
    $install = Join-Path $repoRoot 'install.ps1'
    Test-Case 'install: -PassphraseFromStdin without -SecretsFile stops with exit 2' {
        $o = 'x' | pwsh -NoProfile -NonInteractive -File $install -PassphraseFromStdin -WhatIf 2>&1 | Out-String
        Assert-Equal 2 $LASTEXITCODE $o
        Assert-Match $o 'needs -SecretsFile'
    }
    Test-Case 'install: an empty first stdin line stops with exit 2' {
        $o = '' | pwsh -NoProfile -NonInteractive -File $install -SecretsFile (Join-Path $root 'none.bin') -PassphraseFromStdin -WhatIf 2>&1 | Out-String
        Assert-Equal 2 $LASTEXITCODE $o
        Assert-Match $o 'empty first line'
    }

    # ---------------------------------------------------------------- menu
    $items = @([pscustomobject]@{ Name = 'push'; Description = 'p' }, [pscustomobject]@{ Name = 'pull'; Description = 'q' }, 'status')
    Test-Case 'menu: Enter takes the default' { Assert-Equal 'pull' (Select-GeneMenu -Title t -Items $items -Default 2 -Reader (New-Queue @(''))).Name }
    Test-Case 'menu: a number picks; a bad answer asks again' { Assert-Equal 'status' (Select-GeneMenu -Title t -Items $items -Reader (New-Queue @('9', 'x', '3'))) }
    Test-Case 'menu: q cancels' { Assert-True ($null -eq (Select-GeneMenu -Title t -Items $items -Default 1 -Reader (New-Queue @('q')))) }
    Test-Case 'menu: Enter without a default asks again' { Assert-Equal 'push' (Select-GeneMenu -Title t -Items $items -Reader (New-Queue @('', '1'))).Name }
    Test-Case 'menu: -Multi takes several' {
        $r = Select-GeneMenu -Title t -Items @('a', 'b', 'c') -Multi -Reader (New-Queue @('1, 3'))
        Assert-Equal @('a', 'c') $r
    }
    Test-Case 'yes/no: Enter = default, y and n' {
        Assert-True (Read-GeneYesNo -Question q -Default $true -Reader (New-Queue @('')))
        Assert-True (-not (Read-GeneYesNo -Question q -Reader (New-Queue @('maybe', 'n'))))
    }
    Test-Case 'arrow-key menu: default listed first, pick maps back to the item, (cancel) = null, markup escaped' {
        $script:seen = $null
        function Read-SpectreSelection { param($Message, $Choices, $PageSize, $Color) $script:seen = $Choices; $Choices[$script:pickIndex] }
        $script:GeneRichMenu = $true
        try {
            $script:pickIndex = 0
            Assert-Equal 'pull' (Select-GeneMenu -Title t -Items $items -Default 2).Name
            Assert-Match $script:seen[0] '^pull'
            $script:pickIndex = 2
            Assert-Equal 'status' (Select-GeneMenu -Title t -Items $items -Default 2)
            $script:pickIndex = 3
            Assert-True ($null -eq (Select-GeneMenu -Title t -Items $items)) 'the (cancel) entry returns null'
            $script:pickIndex = 0
            [void](Select-GeneMenu -Title t -Items @([pscustomobject]@{ Name = 'x'; Description = 'a [b] c' }))
            Assert-Match $script:seen[0] '\[\[b\]\]'
        }
        finally { $script:GeneRichMenu = $null; Remove-Item Function:\Read-SpectreSelection }
    }
    Test-Case 'arrow-key multi pick: ticked labels map back to items; nothing ticked with -AllowEmpty is an empty list' {
        function Read-SpectreMultiSelection { param($Message, $Choices, $AllowEmpty, $PageSize, $Color) $Choices | Select-Object -Index $script:multiIdx }
        $script:GeneRichMenu = $true
        try {
            $script:multiIdx = @(0, 2)
            $r = Select-GeneMenu -Title t -Items @('a', 'b', 'c') -Multi
            Assert-Equal @('a', 'c') $r
            $script:multiIdx = @()
            $r = Select-GeneMenu -Title t -Items @('a', 'b') -Multi -AllowEmpty
            Assert-True ($null -ne $r -and @($r).Count -eq 0)
        }
        finally { $script:GeneRichMenu = $null; Remove-Item Function:\Read-SpectreMultiSelection }
    }
    Test-Case 'text: the reader answers, Enter alone is empty' {
        Assert-Equal 'D:' (Read-GeneText -Prompt p -Reader (New-Queue @('D:')))
        Assert-Equal '' (Read-GeneText -Prompt p -Reader (New-Queue @('')))
    }

    # ---------------------------------------------------------------- groups and the dispatcher
    foreach ($f in 'Verbs.ps1', 'SetupGroup.ps1', 'Export.ps1', 'StreamsGroup.ps1', 'GitGroup.ps1', 'BuildGroup.ps1', 'AiGroup.ps1', 'OtherGroup.ps1') { . (Join-Path $mod $f) }
    # The profile is not loaded here, and prof other lists only commands that are defined: stand in for every catalog command.
    foreach ($n in @($script:ProfOtherCatalog.Values | ForEach-Object { $_.Commands.Name })) { if (-not (Get-Command $n -ErrorAction SilentlyContinue)) { Set-Item -Path "function:\global:$n" -Value { } } }
    Update-GeneOtherGroup
    Test-Case 'hub: setup group is registered by SetupGroup.ps1, not Verbs.ps1' {
        Assert-NoMatch (Get-Content -LiteralPath "$mod\Verbs.ps1" -Raw) "ProfGroups\['setup'\]|ProfGroups = \[ordered\]@\{\s*setup"
        Assert-Match (Get-Content -LiteralPath "$mod\SetupGroup.ps1" -Raw -ErrorAction Stop) "ProfGroups\['setup'\]"
    }
    Test-Case 'filter: prof other hides a command whose function is not defined' {
        function global:zzprobe { }
        $script:ProfOtherCatalog['tools'].Commands += New-GeneOtherEntry 'zzprobe' 'probe' @('zzprobe')
        try {
            Assert-True ((Get-GeneOtherEntries -Category tools).Name -contains 'zzprobe') 'defined probe must be listed'
            Remove-Item function:\zzprobe
            Assert-True ((Get-GeneOtherEntries -Category tools).Name -notcontains 'zzprobe') 'undefined probe must be hidden'
        }
        finally { $script:ProfOtherCatalog['tools'].Commands = @($script:ProfOtherCatalog['tools'].Commands | Where-Object { $_.Name -ne 'zzprobe' }); Remove-Item function:\zzprobe -ErrorAction SilentlyContinue }
    }
    Test-Case 'filter: a group with no defined verb function is not listed' {
        $script:ProfGroups['zz'] = [pscustomobject]@{ Description = 'x'; Verbs = [ordered]@{ go = 'go' }; Details = @{}; Usage = @{}; Prefix = 'Invoke-GeneProfZz'; NeedMachine = @() }
        try {
            Assert-True ((Get-GeneProfGroupNames) -notcontains 'zz') 'group without a function must be hidden'
            function global:Invoke-GeneProfZzGo { }
            Assert-True ((Get-GeneProfGroupNames) -contains 'zz') 'group with a function must be listed'
        }
        finally { Remove-Item function:\Invoke-GeneProfZzGo -ErrorAction SilentlyContinue; $script:ProfGroups.Remove('zz') }
    }
    Test-Case 'filter: old-name rows need the prof command they point at' {
        Assert-Equal 'Invoke-GeneProfGitPush' ([string]@($script:ProfOldNames | Where-Object { $_.Old -eq 'gpush' }).Needs)
        Assert-Equal 'Invoke-GeneProfConfig' ([string]@($script:ProfOldNames | Where-Object { $_.Old -eq 'machinecfg' }).Needs)
        foreach ($row in $script:ProfOldNames) { Assert-True ([bool](Get-Command $row.Needs -ErrorAction SilentlyContinue)) "$($row.Old) needs $($row.Needs), not defined" }
    }
    Test-Case 'trimmed hub: without SetupGroup/Target/Sync/Export the module imports and prof help has no setup group' {
        $t = New-TestRoot 'hub'; Copy-Item -Path "$mod\*" -Destination $t -Recurse
        Remove-Item -LiteralPath "$t\SetupGroup.ps1", "$t\Target.ps1", "$t\Sync.ps1", "$t\Export.ps1"
        $core = Join-Path $repoRoot 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
        $o = @(pwsh -NoProfile -Command "`$ErrorActionPreference = 'Stop'; . '$core'; Import-Module '$t\Gene.Profile.psd1' -DisableNameChecking -Force; prof help 6>&1 | Out-String; 'EXIT-OK'" 2>&1) -join "`n"
        Assert-Match $o 'EXIT-OK'
        Assert-NoMatch $o '(?m)^setup  '
        Assert-Match $o '(?m)^other  '
    }
    Test-Case 'groups: main menu order is streams, setup, git, build, ai, other' { Assert-Equal @('streams', 'setup', 'git', 'build', 'ai', 'other') @($script:ProfGroups.Keys) }
    Test-Case 'groups: setup holds the twelve commands, help is not one of them' {
        Assert-True ($script:ProfGroups.Contains('setup'))
        Assert-Equal @('push', 'pull', 'status', 'check', 'bootstrap', 'terminal', 'secrets', 'config', 'edit', 'reload', 'show', 'export') @($script:ProfGroups['setup'].Verbs.Keys)
    }
    Test-Case 'setup: every command has a usage line, a long description and a function' {
        foreach ($v in $script:ProfGroups['setup'].Verbs.Keys) {
            Assert-True ([bool]$script:ProfUsage[$v]) "no usage for $v"; Assert-True ([bool]$script:ProfDetails[$v]) "no details for $v"
            Assert-True ([bool](Get-Command "Invoke-GeneProf$((Get-Culture).TextInfo.ToTitleCase($v))" -ErrorAction SilentlyContinue)) "no function for $v"
        }
    }
    Test-Case 'resolve: group + command, command alone, help words, unknown' {
        $r = Resolve-GeneProfCommand 'setup' 'Status'
        Assert-Equal 'setup' $r.Group; Assert-Equal 'status' $r.Verb
        $r = Resolve-GeneProfCommand 'publish' 'speed'
        Assert-Equal 'build' $r.Group; Assert-Equal 'publish' $r.Verb; Assert-Equal 'speed' $r.Topic
        $r = Resolve-GeneProfCommand 'push'
        Assert-Equal '' $r.Group; Assert-Equal @('streams', 'setup', 'git') $r.Ambiguous
        $r = Resolve-GeneProfCommand 'help' 'streams' 'push'
        Assert-True $r.Help; Assert-Equal @('streams', 'push') $r.Words
        $r = Resolve-GeneProfCommand 'nope'
        Assert-Equal '' $r.Group; Assert-Equal 'nope' $r.Verb
    }
    Test-Case 'command line: the group comes first' {
        Assert-Equal 'prof setup push -Machine M1 -WhatIf' (Format-GeneProfCommand -Group setup -Verb push -Params ([ordered]@{ Machine = 'M1'; WhatIf = $true }))
    }
    Test-Case 'menu flow: group, command, shows the full command, n runs nothing' {
        $o = Invoke-GeneProfMenu -Reader (New-Queue @('2', '11', 'n')) 6>&1 | Out-String
        Assert-Match $o '> prof setup show'
        Assert-True ($o -notmatch 'Profile: ') 'show ran although the answer was n'
    }
    Test-Case 'menu flow: q at the main menu does nothing' {
        $o = Invoke-GeneProfMenu -Reader (New-Queue @('q')) 6>&1 | Out-String
        Assert-True ($o -notmatch '> prof')
    }

    # ---------------------------------------------------------------- export (profile for someone else)
    $xh = Join-Path $root 'export-hub'
    foreach ($d in 'pwsh\PowerShell\Modules\Gene.X', 'pwsh\WindowsPowerShell', 'tools') { New-Item -ItemType Directory -Force -Path (Join-Path $xh $d) | Out-Null }
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1') -Value '# profile; pushes to github.com/owner1/scripts'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\PowerShell\Modules\Gene.X\Gene.X.psm1') -Value 'function x {}'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Value '# old'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\modules.txt') -Value 'PowerShell posh-git'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\AddOrUpdateMyTerminal.ps1') -Value '# terminal'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\Install-Profile.ps1') -Value '# installer'
    Set-Content -LiteralPath (Join-Path $xh 'pwsh\old.ps1.bak-1') -Value 'never packed'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Find-Secrets.ps1') -Destination (Join-Path $xh 'tools\Find-Secrets.ps1')
    Set-Content -LiteralPath (Join-Path $xh 'share.yaml') -Value @('blockedPatterns:', "  - 'owner1'", "  - 'BOX7'")
    $xp = Join-Path $root 'export-profile.md'
    New-TestProfile -Path $xp -Keys ([ordered]@{ ReposRoot = 'D:\devops\repos'; MarkitdownVenv = '%USERPROFILE%\.venvs\markitdown'; ScratchRoot = (Join-Path $root 'export-scratch'); AIWorkRoot = $xh }) -Sections ([ordered]@{ 'Git policy' = "| Repo | Commit | Push |`n|---|---|---|`n| D:\devops\x | yes | no |" })
    $savedHub = $env:GENE_PROF_HUB; $savedCfg = $env:AI_MACHINE_CONFIG
    $env:GENE_PROF_HUB = $xh; $env:AI_MACHINE_CONFIG = $xp
    try {
        Test-Case 'export: zip + folder with the pwsh tree, a blank-value template, a README; .bak files and later tables left out' {
            $r = Invoke-GeneProfExport -Out (Join-Path $root 'export-out') -Reader (New-Queue @('y')) 6>$null
            Assert-True (Test-Path -LiteralPath $r.Zip) 'no zip'
            Assert-Match $r.Zip 'export-out\\profile-export-\d{8}-\d{6}\.zip$'
            $names = @(Get-ChildItem -LiteralPath $r.Folder -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($r.Folder, $_.FullName) } | Sort-Object)
            Assert-Equal @('AddOrUpdateMyTerminal.ps1', 'Install-Profile.ps1', 'modules.txt', 'PowerShell\Microsoft.PowerShell_profile.ps1', 'PowerShell\Modules\Gene.X\Gene.X.psm1', 'ProfileMachineConfig.md', 'README.md', 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') $names
            $t = Get-Content -LiteralPath (Join-Path $r.Folder 'ProfileMachineConfig.md') -Raw
            Assert-Match $t '\| ReposRoot \|  \| test \| fill in \|'
            Assert-Match $t '\| MarkitdownVenv \| %USERPROFILE%\\\.venvs\\markitdown \| test \| fill in \|'
            Assert-NoMatch $t 'Git policy'; Assert-NoMatch $t 'D:\\devops'
            Assert-Match (Get-Content -LiteralPath (Join-Path $r.Folder 'README.md') -Raw) 'Install-Profile\.ps1 -WhatIf'
            Assert-Equal 1 $r.Mentions
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $z = [IO.Compression.ZipFile]::OpenRead($r.Zip); try { Assert-True (($z.Entries.FullName -contains 'README.md') -and ($z.Entries.FullName -notcontains 'old.ps1.bak-1')) 'zip content' } finally { $z.Dispose() }
        }
        Test-Case 'export: n to the mentions question packs nothing' {
            Assert-Throws { Invoke-GeneProfExport -Out (Join-Path $root 'export-no.zip') -Reader (New-Queue @('n')) 6>$null } '*cancelled*'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'export-no.zip')))
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'export-no')))
        }
        Test-Case 'export: a secret in the profile refuses the export' {
            Add-Content -LiteralPath (Join-Path $xh 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1') -Value ('$t = "ghp_' + ('a1B2c3D4e5' * 4) + '"')
            Assert-Throws { Invoke-GeneProfExport -Out (Join-Path $root 'export-leak.zip') -Reader (New-Queue @('y')) 6>$null } '*Possible secrets*'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'export-leak.zip')))
        }
        Test-Case 'export: -WhatIf lists and writes nothing' {
            $o = Invoke-GeneProfExport -Out (Join-Path $root 'export-dry') -WhatIf 6>&1 | Out-String
            Assert-Match $o 'nothing written'; Assert-Match $o 'ReposRoot'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'export-dry')))
        }
    }
    finally { $env:GENE_PROF_HUB = $savedHub; $env:AI_MACHINE_CONFIG = $savedCfg }

    # ---------------------------------------------------------------- other (catalog)
    Test-Case 'other: every command the profile defines is in the catalog (census)' {
        $profileFile = Join-Path $repoRoot 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
        $ast = [Management.Automation.Language.Parser]::ParseFile($profileFile, [ref]$null, [ref]$null)
        # Top-level functions whose name starts lower case are the typed commands; prompt is PowerShell's own.
        $defined = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cmatch '^[a-z]' -and $_.Name -ne 'prompt' } | ForEach-Object Name)
        $listed = @($script:ProfOtherCatalog.Values | ForEach-Object { $_.Commands.Name })
        $missing = @($defined | Where-Object { $_ -notin $listed })
        Assert-Equal 0 $missing.Count "not in prof other: $($missing -join ', ')"
        Assert-True ('caiprof' -in $listed); Assert-True ('cgov' -notin $listed)
    }
    Test-Case 'other: a category lists its commands; a named command shows how to use it; runs nothing' {
        $o = Invoke-GeneProf other navigate 6>&1 | Out-String
        Assert-Match $o 'cspeed'; Assert-Match $o 'caiprof'
        $o = Invoke-GeneProf other git pps 6>&1 | Out-String
        Assert-Match $o 'How to use'; Assert-Match $o 'powershellscripts'
        $o = Invoke-GeneProf other build dpall 6>&1 | Out-String
        Assert-Match $o 'Also through prof: prof build publish all'
    }
    Test-Case 'other menu: category, then command, shows it, back to the list until q' {
        $o = Invoke-GeneProfMenu -Group other -Reader (New-Queue @('2', '3', 'q')) 6>&1 | Out-String
        Assert-Match $o 'addLinux'; Assert-Match $o 'How to use'
        Assert-True ($o -notmatch 'Run it\?') 'the catalog asked to run something'
    }

    # ---------------------------------------------------------------- build and git groups
    $savedMachine = $global:GeneMachine; $savedAI = $global:GeneMachineAI; $savedLoc = Get-Location
    $sm = Join-Path $root 'sm'
    New-Item -ItemType Directory -Force -Path (Join-Path $sm 'TestAuto.Web') | Out-Null
    Set-Content -LiteralPath (Join-Path $sm 'TestAuto.Web\TestAuto.Web.csproj') -Value '<Project><PropertyGroup><Version>1.2.3</Version></PropertyGroup></Project>'
    $global:GeneMachine = [ordered]@{ SpeedMerchantsRepo = $sm }
    $global:GeneMachineAI = @{}
    function dpfake {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([switch]$Test, [ValidateSet('A', 'B')][string]$Run, [string[]]$Products, [switch]$Package, [switch]$Bump, [switch]$BumpMinor, [switch]$BumpMajor, [Alias('h')][switch]$ShowHelp)
        $script:dpGot = [ordered]@{} + $PSBoundParameters
    }
    $realSpeed = $script:ProfBuildProducts['testauto'].Command
    try {
        Test-Case 'build: dp* switches after prof become a splat; unknown ones are refused' {
            $h = ConvertTo-GeneCommandArgs -Command dpfake -Extra @('-Test', '-Run', 'B', '-Products', @('x', 'y'))
            Assert-True $h.Test; Assert-Equal 'B' $h.Run; Assert-Equal @('x', 'y') $h.Products
            Assert-True (-not (ConvertTo-GeneCommandArgs -Command dpfake -Extra @('-Test:$false')).Test)
            Assert-Equal 0 (ConvertTo-GeneCommandArgs -Command dpfake -Extra $null).Count
            $err = try { ConvertTo-GeneCommandArgs -Command dpfake -Extra @('-Bogus'); '' } catch { "$_" }
            Assert-Match $err 'dpfake has no -Bogus'
        }
        Test-Case 'build: version bumps' {
            Assert-Equal '1.2.4' (Get-GeneBumpedVersion '1.2.3' 'Patch'); Assert-Equal '1.3.0' (Get-GeneBumpedVersion '1.2.3' 'Minor')
            Assert-Equal '2.0.0' (Get-GeneBumpedVersion '1.2.3' 'Major'); Assert-Equal '1.2.3' (Get-GeneBumpedVersion '1.2.3' 'None')
            Assert-Equal '1.2.3' (Get-GeneProductVersion $script:ProfBuildProducts['testauto'])
        }
        Test-Case 'build: command line shows product, bump and the dp* switches' {
            Assert-Equal 'prof build publish testauto -Bump Minor -Products a,b -WhatIf' (Format-GeneProfCommand -Group build -Verb publish -Params ([ordered]@{ Product = 'testauto'; Bump = 'Minor'; Extra = @('-Products', @('a', 'b')); WhatIf = $true }))
        }
        $script:ProfBuildProducts['testauto'].Command = 'dpfake'
        Test-Case 'build: publish -Bump Major runs dp* -Package -BumpMajor in the repo folder, with the extra switches' {
            $script:dpGot = $null
            Invoke-GeneProf build publish testauto -Bump Major -Products a, b 6>&1 | Out-Null
            Assert-True $script:dpGot.Package; Assert-True $script:dpGot.BumpMajor; Assert-Equal @('a', 'b') $script:dpGot.Products
            Assert-Equal $sm (Get-Location).ProviderPath
        }
        Test-Case 'build: prof publish (no group) works; the dp* bump switches through prof are refused' {
            $script:dpGot = $null
            Invoke-GeneProf publish speed 6>&1 | Out-Null
            Assert-True $script:dpGot.Package; Assert-True (-not $script:dpGot.Contains('Bump'))
            $err = try { Invoke-GeneProf build publish speed -BumpMinor 6>&1 | Out-Null; '' } catch { "$_" }
            Assert-Match $err "Use prof's -Bump"
        }
        Test-Case 'build: the old name speed still means TestAuto' {
            Assert-Equal 'TestAuto' (Get-GeneBuildProduct 'speed').Name
            Assert-Equal 'TestAuto' (Get-GeneBuildProduct 'TestAuto').Name
        }
        Test-Case 'build: publish all -Products testauto reaches dpall as speed' {
            $realAll = $script:ProfBuildProducts['all'].Command
            $script:ProfBuildProducts['all'].Command = 'dpfake'
            try {
                $script:dpGot = $null
                Invoke-GeneProf build publish all -Products testauto, crewchief 6>&1 | Out-Null
                Assert-Equal @('speed', 'crewchief') $script:dpGot.Products
                $script:dpGot = $null
                Invoke-GeneProf build publish all -Products 'speed,mutate' 6>&1 | Out-Null
                Assert-Equal @('speed', 'mutate') $script:dpGot.Products
            }
            finally { $script:ProfBuildProducts['all'].Command = $realAll }
        }
        Test-Case 'build menu: TestAuto is listed by name, first' {
            $o = Invoke-GeneProfMenu -Group build -Reader (New-Queue @('q')) 6>&1 | Out-String
            Assert-Match $o '1\) testauto\s+TestAuto'
        }
        Test-Case 'build menu: product, Publish, bump shows versions, n at Run it? runs nothing' {
            $script:dpGot = $null
            $o = Invoke-GeneProfMenu -Group build -Reader (New-Queue @('1', '3', '3', 'n', 'n')) 6>&1 | Out-String
            Assert-Match $o '1\.2\.3 -> 1\.3\.0'
            Assert-Match $o '> prof build publish testauto -Bump Minor'
            Assert-True ($null -eq $script:dpGot) 'ran although the answer was n'
        }
        Test-Case 'build menu: More options ticks switches and asks a choice switch value' {
            $o = Invoke-GeneProfMenu -Group build -Reader (New-Queue @('1', '4', '1,2', '2', 'n', 'n')) 6>&1 | Out-String
            Assert-Match $o '> prof build more testauto -Test -Run B'
        }
        Test-Case 'build menu: Build only asks the configuration' {
            $o = Invoke-GeneProfMenu -Group build -Reader (New-Queue @('1', '1', '2', 'n', 'n')) 6>&1 | Out-String
            Assert-Match $o '> prof build compile testauto -Configuration Release'
        }

        # git: a local bare repo stands in for GitHub
        $bare = Join-Path $root 'gh.git'; git init -q --bare -b main $bare
        $work = Join-Path $root 'speedy'; New-Repo $work; Add-Commit $work 'a.txt' 'one'
        git -C $work remote add origin $bare; git -C $work push -q -u origin main 2>$null
        $other = Join-Path $root 'other'; git clone -q $bare $other 2>$null
        git -C $other config user.name t; git -C $other config user.email t@t
        $global:GeneMachine['SpeedyRepo'] = $work
        Import-Module (Join-Path $repoRoot 'pwsh\PowerShell\Modules\Gene.GitTools') -Force -DisableNameChecking
        Test-Case 'git: known repos come from the machine profile by folder name' {
            Assert-Equal $work (Resolve-GeneGitRepo -Repo 'speedy')
            $err = try { Resolve-GeneGitRepo -Repo 'nope'; '' } catch { "$_" }
            Assert-Match $err 'Known here: speedy'
        }
        Test-Case 'git: status on a named repo moves the window there and reports GitHub' {
            Set-Location $root
            $o = Invoke-GeneProf git status speedy 6>&1 | Out-String
            Assert-Match $o 'Same as the server'
            Assert-Equal $work (Get-Location).ProviderPath
        }
        Test-Case 'git: pull brings the new commit from GitHub' {
            Add-Commit $other 'b.txt' 'two'; git -C $other push -q 2>$null
            Invoke-GeneProf git pull speedy 6>&1 | Out-Null
            Assert-True (Test-Path (Join-Path $work 'b.txt'))
        }
        Test-Case 'git: push commits everything with the message and sends it (gpush)' {
            Set-Content -LiteralPath (Join-Path $work 'c.txt') -Value 'three'
            Invoke-GeneProf git push speedy -Message 'from prof' 6>&1 | Out-Null
            Assert-Equal 'from prof' ([string](git -C $bare log -1 --format=%s main)).Trim()
        }
        Test-Case 'git menu: this folder is offered first; push asks the message' {
            Set-Location $work
            $o = Invoke-GeneProfMenu -Group git -Reader (New-Queue @('2', '1', 'my msg', 'n', 'y', 'n')) 6>&1 | Out-String
            Assert-Match $o "> prof git push -Message 'my msg' -WhatIf"
        }
        Test-Case 'git: push with nothing to do says so and pushes nothing' {
            $o = Invoke-GeneProf git push speedy 6>&1 | Out-String
            Assert-Match $o 'Nothing to commit or push: same as the server'
        }
        Test-Case 'git: push while the server is ahead stops before committing' {
            $tmp = Join-Path $root 'ahead'; git clone -q $bare $tmp 2>$null
            Set-Content (Join-Path $tmp 'srv.txt') 'srv'; git -C $tmp add -A; git -C $tmp commit -q -m 'server side'; git -C $tmp push -q 2>$null
            $o = Invoke-GeneProf git push speedy 6>&1 | Out-String
            Assert-Match $o 'Nothing to commit or push here. The server has 1 newer commit'
            Set-Content (Join-Path $work 'mine.txt') 'mine'
            $head = (git -C $work rev-parse HEAD)
            $err = try { Invoke-GeneProf git push speedy 6>&1 | Out-Null; '' } catch { "$_" }
            Assert-Match $err 'Nothing was committed or pushed. Pull first \(prof git pull speedy\)'
            Assert-Equal $head (git -C $work rev-parse HEAD) 'a commit was made'
            Remove-Item (Join-Path $work 'mine.txt')
            Invoke-GeneProf git pull speedy 6>&1 | Out-Null
        }
        Test-Case 'git: -AIOnly pushes through pushrules with the message' {
            function pushrules { param([string]$Message, [string]$Remote) $script:rulesGot = "msg=$Message" }
            try {
                $script:rulesGot = $null
                Invoke-GeneProf git push speedy -AIOnly -Message 'rules x' 6>&1 | Out-Null
                Assert-Equal 'msg=rules x' $script:rulesGot
            }
            finally { Remove-Item Function:\pushrules }
        }
        Test-Case 'ai: local runs dpAI -Local in the named repo with -Force and -WhatIf' {
            function dpAI { param([switch]$Local, [switch]$Remote, [switch]$Git, [switch]$Promote, [string]$RepoPath, [string]$Message, [switch]$Force, [switch]$WhatIf, [switch]$Try) $script:aiGot = [ordered]@{} + $PSBoundParameters }
            try {
                Invoke-GeneProf ai local speedy -Force -WhatIf 6>&1 | Out-Null
                Assert-True $script:aiGot.Local; Assert-True $script:aiGot.Force; Assert-True $script:aiGot.WhatIf
                Assert-Equal $work $script:aiGot.RepoPath
                $err = try { Invoke-GeneProf ai local speedy -Remote 6>&1 | Out-Null; '' } catch { "$_" }
                Assert-Match $err 'The mode is the command'
            }
            finally { Remove-Item Function:\dpAI }
        }
        Test-Case 'streams: status-rebuild touches the Status inbox file of SpeedyRepo' {
            $inbox = Join-Path $work '.streams\inbox'
            New-Item -ItemType Directory -Force -Path $inbox | Out-Null
            $f = Join-Path $inbox 'stream-status.md'; Set-Content -LiteralPath $f -Value 'x'
            (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddDays(-1)
            Invoke-GeneProf streams status-rebuild 6>&1 | Out-Null
            Assert-True ((Get-Item -LiteralPath $f).LastWriteTime -gt (Get-Date).AddMinutes(-1)) 'not touched'
            $err = try { Invoke-GeneProf streams status-rebuild -Repo $root 6>&1 | Out-Null; '' } catch { "$_" }
            Assert-Match $err 'No Status inbox file'
        }
        Test-Case 'streams: tab passes -Author -Count and turns -WhatIf into -DryRun' {
            function addStreamTab { param([string]$Role, [switch]$Author, [switch]$Builder, [int]$Count, [string]$Repo, [switch]$ClearStop, [switch]$DryRun, [switch]$Help) $script:tabGot = [ordered]@{} + $PSBoundParameters }
            try {
                Invoke-GeneProf streams tab -Author -Count 2 -WhatIf 6>&1 | Out-Null
                Assert-True $script:tabGot.Author; Assert-Equal 2 $script:tabGot.Count; Assert-True $script:tabGot.DryRun
                $o = Invoke-GeneProfMenu -Reader (New-Queue @('1', '2', '1', '3', 'y', 'n')) 6>&1 | Out-String
                Assert-Match $o '> prof streams tab -Author -Count 3 -WhatIf'
            }
            finally { Remove-Item Function:\addStreamTab }
        }
        Test-Case 'build: containers is Speedy only and runs dpContainers' {
            function dpContainers { [CmdletBinding(SupportsShouldProcess = $true)] param([switch]$NoBuild, [switch]$ShowHelp) $script:ctrGot = [ordered]@{} + $PSBoundParameters }
            try {
                Invoke-GeneProf build containers speedy -NoBuild 6>&1 | Out-Null
                Assert-True $script:ctrGot.NoBuild
                $err = try { Invoke-GeneProf build containers speed 6>&1 | Out-Null; '' } catch { "$_" }
                Assert-Match $err 'Speedy only'
            }
            finally { Remove-Item Function:\dpContainers }
        }
    }
    finally {
        $script:ProfBuildProducts['testauto'].Command = $realSpeed
        $global:GeneMachine = $savedMachine; $global:GeneMachineAI = $savedAI; Set-Location $savedLoc
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
Complete-Tests
