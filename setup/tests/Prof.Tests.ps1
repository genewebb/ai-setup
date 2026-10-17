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
    Test-Case 'text: the reader answers, Enter alone is empty' {
        Assert-Equal 'D:' (Read-GeneText -Prompt p -Reader (New-Queue @('D:')))
        Assert-Equal '' (Read-GeneText -Prompt p -Reader (New-Queue @('')))
    }

    # ---------------------------------------------------------------- groups and the dispatcher
    . (Join-Path $mod 'Verbs.ps1')
    Test-Case 'groups: streams holds the eleven commands, help is not one of them' {
        Assert-True ($script:ProfGroups.Contains('streams'))
        Assert-Equal @('push', 'pull', 'status', 'check', 'bootstrap', 'terminal', 'secrets', 'config', 'edit', 'reload', 'show') @($script:ProfGroups['streams'].Verbs.Keys)
    }
    Test-Case 'resolve: group + command, command alone, help words, unknown' {
        $r = Resolve-GeneProfCommand 'streams' 'Status'
        Assert-Equal 'streams' $r.Group; Assert-Equal 'status' $r.Verb
        $r = Resolve-GeneProfCommand 'push'
        Assert-Equal 'streams' $r.Group; Assert-Equal 'push' $r.Verb
        $r = Resolve-GeneProfCommand 'help' 'streams' 'push'
        Assert-True $r.Help; Assert-Equal @('streams', 'push') $r.Words
        $r = Resolve-GeneProfCommand 'nope'
        Assert-Equal '' $r.Group; Assert-Equal 'nope' $r.Verb
    }
    Test-Case 'command line: the group comes first' {
        Assert-Equal 'prof streams push -Machine M1 -WhatIf' (Format-GeneProfCommand -Group streams -Verb push -Params ([ordered]@{ Machine = 'M1'; WhatIf = $true }))
    }
    Test-Case 'menu flow: group, command, shows the full command, n runs nothing' {
        $o = Invoke-GeneProfMenu -Reader (New-Queue @('1', '11', 'n')) 6>&1 | Out-String
        Assert-Match $o '> prof streams show'
        Assert-True ($o -notmatch 'Profile: ') 'show ran although the answer was n'
    }
    Test-Case 'menu flow: q at the main menu does nothing' {
        $o = Invoke-GeneProfMenu -Reader (New-Queue @('q')) 6>&1 | Out-String
        Assert-True ($o -notmatch '> prof')
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
Complete-Tests
