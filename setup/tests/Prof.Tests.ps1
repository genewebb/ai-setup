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
    Set-GeneTargetGitConfig -Hub $hub -Repo $repo -Name t -Email t@t
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
    # A target's own paths (D:\... on SMVMTR2) are joined on the hub, which may have no such drive: Join-Path would
    # throw "Cannot find drive". Join-GeneRemotePath is plain text.
    $script:noDrive = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S', 'R') | Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
    Test-Case 'remote path join: works for a drive this machine does not have, trims one backslash, keeps UNC' {
        Assert-Equal "$($script:noDrive):\devops\repos\ai-setup\install.ps1" (Join-GeneRemotePath "$($script:noDrive):\devops\repos\ai-setup" 'install.ps1')
        Assert-Equal "$($script:noDrive):\devops\repos\ai-setup\install.ps1" (Join-GeneRemotePath "$($script:noDrive):\devops\repos\ai-setup\" '\install.ps1')
        Assert-Equal '\\BOX\D$\x\y\z' (Join-GeneRemotePath '\\BOX\D$\x' 'y\z')
        Assert-Equal "$($script:noDrive):\a" (Join-GeneRemotePath "$($script:noDrive):\" 'a')
    }
    Test-Case 'Invoke-GeneRemotePwsh marks the child pwsh as a remote session (PROF_REMOTE_SESSION=1) so install.ps1 does not call an unreachable share missing' {
        $body = (Get-Command Invoke-GeneRemotePwsh).ScriptBlock.Ast.Extent.Text
        Assert-Match $body '\$env:PROF_REMOTE_SESSION\s*=\s*''1''[\s\S]*& \$pwsh'
    }
    Test-Case 'remote path join: the hub never calls Join-Path on a target-local base' {
        $src = (Get-Content -LiteralPath "$mod\SetupGroup.ps1" -Raw) + (Get-Content -LiteralPath "$mod\Sync.ps1" -Raw)
        Assert-NoMatch $src 'Join-Path \$[\w.]*Local\b|Join-Path \$\w+\.Paths\.Local|Join-Path \$Repo\.Path|Join-Path \$archive|Join-Path \$base|Join-Path \(Split-Path \$repos\)'
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

    Test-Case 'target config: byte-for-byte, the identity it is given' {
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
    Test-Case 'menu: -Multi takes a / all for every item, and the hint says so' {
        $script:hint = $null
        $q = New-Queue @('all')
        $r = Select-GeneMenu -Title t -Items @('a', 'b', 'c') -Multi -Reader { param($p) $script:hint = $p; & $q $p }
        Assert-Equal @('a', 'b', 'c') $r
        Assert-Match $script:hint 'a = all'
        Assert-Equal @('a', 'b') (Select-GeneMenu -Title t -Items @('a', 'b') -Multi -Reader (New-Queue @('A')))
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
    Test-Case 'arrow-key multi pick: one group whose header ticks every item; ticked labels map back; nothing ticked with -AllowEmpty is an empty list' {
        $script:groups = $null
        function Read-SpectreMultiSelectionGrouped { param($Message, $Choices, $AllowEmpty, $PageSize, $Color) $script:groups = $Choices; @($Choices[0].Choices) | Select-Object -Index $script:multiIdx }
        $script:GeneRichMenu = $true
        try {
            $script:multiIdx = @(0, 2)
            $r = Select-GeneMenu -Title t -Items @('a', 'b', 'c') -Multi
            Assert-Equal @('a', 'c') $r
            Assert-Equal 1 @($script:groups).Count 'one group'
            Assert-Match $script:groups[0].Name 'all'
            Assert-Equal 3 @($script:groups[0].Choices).Count
            $script:multiIdx = @()
            $r = Select-GeneMenu -Title t -Items @('a', 'b') -Multi -AllowEmpty
            Assert-True ($null -ne $r -and @($r).Count -eq 0)
        }
        finally { $script:GeneRichMenu = $null; Remove-Item Function:\Read-SpectreMultiSelectionGrouped }
    }
    Test-Case 'text: the reader answers, Enter alone is empty' {
        Assert-Equal 'D:' (Read-GeneText -Prompt p -Reader (New-Queue @('D:')))
        Assert-Equal '' (Read-GeneText -Prompt p -Reader (New-Queue @('')))
    }

    # ---------------------------------------------------------------- groups and the dispatcher
    foreach ($f in 'Verbs.ps1', 'SetupGroup.ps1', 'Share.ps1', 'StreamsGroup.ps1', 'GitGroup.ps1', 'BuildGroup.ps1', 'OtherGroup.ps1') { . (Join-Path $mod $f) }
    # The profile is not loaded here, and prof other lists only commands that are defined: stand in for every catalog command.
    foreach ($n in @($script:ProfOtherCatalog.Values | ForEach-Object { $_.Commands.Name })) { if (-not (Test-GeneOtherDefined -Name $n)) { Set-Item -Path "function:\global:$n" -Value { } } }
    Update-GeneOtherGroup
    Test-Case 'profile fix: the per-user AIWorkRoot is built from a ReposRoot on a drive this machine does not have' {
        $d = $script:noDrive
        $fix = Get-GeneProfileFix -HubRaw ([ordered]@{ ReposRoot = 'C:\devops\repos'; AIWorkRoot = 'C:\devops\repos\ai-setup' }) -TargetRaw ([ordered]@{ ReposRoot = "$d`:\devops\repos"; AIWorkRoot = "$d`:\devops\repos\ai-setup" })
        Assert-Equal "$d`:\devops\%USERNAME%\ai-setup" $fix.AIWorkRoot.New
        Assert-Equal "$d`:\devops\repos\ai-setup" $fix.AIWorkRoot.Old
        Assert-Equal @() @($fix.Missing)
    }
    # ---------------------------------------------------------------- the installer's name, not the hub owner's
    $owner = @('Gene', 'Webb')
    Test-Case 'owner note: a (...) group or a ; or , clause naming the owner is dropped; module names, URLs and paths stay' {
        Assert-Equal 'whole working tree (repos, worktrees, myworkspace); deletes need no prompt' (Remove-GeneOwnerNote -Names $owner -Text 'whole working tree (repos, worktrees, myworkspace); deletes need no prompt (Gene 9/28)')
        Assert-Equal '' (Remove-GeneOwnerNote -Names $owner -Text '(Gene 9/28)')
        Assert-Equal 'shared Profisee AI repo (Azure DevOps); Promote-ToWork mirrors skills into it' (Remove-GeneOwnerNote -Names $owner -Text 'shared Profisee AI repo (Azure DevOps); Promote-ToWork mirrors skills into it, Gene pushes (Gene 10/17)')
        Assert-Equal 'private AI setup repo (github.com/genewebb/ai-setup)' (Remove-GeneOwnerNote -Names $owner -Text 'private AI setup repo (github.com/genewebb/ai-setup); Gene 10/14')
        Assert-Equal 'config tree: skills, memory. Runtime files are drift' (Remove-GeneOwnerNote -Names $owner -Text 'config tree: skills, memory (Gene 9/29 grant, both machines 10/1). Runtime files are drift')
        Assert-Equal 'cpower, Gene.GitTools, D:\devops\genewe\ai-setup' (Remove-GeneOwnerNote -Names $owner -Text 'cpower, Gene.GitTools, D:\devops\genewe\ai-setup')
        Assert-Equal 'NAS secrets' (Remove-GeneOwnerNote -Names $owner -Text 'NAS secrets; merged only after Gene confirms each file (R24)')
        Assert-Equal 'anything (Gene 9/28)' (Remove-GeneOwnerNote -Names @() -Text 'anything (Gene 9/28)')
    }
    $hubLines = @("# Config - $env:COMPUTERNAME", '', '| Key | Value | Used by | Status |', '|---|---|---|---|',
        '| ReposRoot | C:\devops\repos | cdevops, Gene.GitTools | present |', '| AIWorkRoot | C:\devops\repos\ai-setup | AI runtime, Gene runs it | present |',
        '', '## Claude access', '', '| Path | Access | Note |', '|---|---|---|', '| C:\temp | read, edit, delete | (Gene 9/28) |', '| C:\x | read | plain |')
    Test-Case 'seed: a new machine profile carries no owner notes in any table; module names stay' {
        $hp = [pscustomobject]@{ Lines = $hubLines; Raw = [ordered]@{ ReposRoot = 'C:\devops\repos'; AIWorkRoot = 'C:\devops\repos\ai-setup' } }
        $s = New-GeneSeedProfile -Machine BOX -HubProfile $hp -OwnerNames $owner
        $all = $s.Lines -join "`n"
        Assert-True ($s.Lines -contains '| ReposRoot | C:\devops\repos | cdevops, Gene.GitTools | unverified |') $all
        Assert-True ($s.Lines -contains '| AIWorkRoot | C:\devops\%USERNAME%\ai-setup | AI runtime | unverified |') $all
        Assert-True ($s.Lines -contains '| C:\temp | read, edit, delete |  |') $all
        Assert-True ($s.Lines -contains '| C:\x | read | plain |') $all
        Assert-NoMatch $all '(?<![\w.\\])Gene(?![\w.\\])'
        Assert-True ($s.Lines -contains '# Config - BOX') $all
    }
    Test-Case 'fix: owner notes in an existing profile are listed, make the fix non-empty, and are dropped; other lines unchanged' {
        $raw = [ordered]@{ ReposRoot = 'C:\devops\repos'; AIWorkRoot = 'C:\devops\%USERNAME%\ai-setup' }
        $lines = @($hubLines[0..4]) + '| AIWorkRoot | C:\devops\%USERNAME%\ai-setup | AI runtime | ok |' + @($hubLines[6..12])
        $fix = Get-GeneProfileFix -HubRaw $raw -TargetRaw $raw -TargetLines $lines -OwnerNames $owner
        Assert-Equal 1 @($fix.Notes).Count ($fix.Notes | Out-String)
        Assert-Equal '| C:\temp | read, edit, delete | (Gene 9/28) |' $fix.Notes[0].Old
        Assert-Equal '| C:\temp | read, edit, delete |  |' $fix.Notes[0].New
        Assert-True (-not $fix.Empty) 'owner notes alone make the fix non-empty'
        $new = Edit-GeneProfileLines -Lines $lines -Fix $fix
        Assert-Equal $lines.Count $new.Count
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -ne $fix.Notes[0].Old) { Assert-Equal $lines[$i] $new[$i] "line $i" } else { Assert-Equal $fix.Notes[0].New $new[$i] } }
        $none = Get-GeneProfileFix -HubRaw $raw -TargetRaw $raw -TargetLines $new -OwnerNames $owner
        Assert-True $none.Empty 'a cleaned profile needs no fix'
    }
    Test-Case 'git config: the target gets the identity it is given, never the hub''s, and keeps its own origin user' {
        $h = Join-Path $root 'id-hub'; New-Repo $h; Add-Commit $h 'a.txt' 'x'
        git -C $h remote add origin 'https://hubuser@github.com/o/r.git'
        $tg = Join-Path $root 'id-target'; git clone -q --no-hardlinks $h $tg
        git -C $tg remote set-url origin 'https://theirs@github.com/o/r.git'
        Set-GeneTargetGitConfig -Hub $h -Repo (New-GeneRepo -Path $tg) -Name 'Pat Doe' -Email 'pat@example.test'
        Assert-Equal 'Pat Doe' ((git -C $tg config --local --get user.name) | Select-Object -First 1)
        Assert-Equal 'pat@example.test' ((git -C $tg config --local --get user.email) | Select-Object -First 1)
        Assert-Equal 'https://theirs@github.com/o/r.git' ((git -C $tg remote get-url origin) | Select-Object -First 1)
        git -C $tg remote set-url origin 'https://theirs@github.com/o/other.git'
        Set-GeneTargetGitConfig -Hub $h -Repo (New-GeneRepo -Path $tg)
        Assert-Equal 'https://hubuser@github.com/o/r.git' ((git -C $tg remote get-url origin) | Select-Object -First 1) 'a different repo is pointed back at the hub''s origin'
        Assert-Equal 'Pat Doe' ((git -C $tg config --local --get user.name) | Select-Object -First 1) 'no -Name leaves the identity alone'
    }
    Test-Case 'identity default: the clone''s own config, else the account''s global .gitconfig' {
        $c = Join-Path $root 'idd-clone'; New-Repo $c; git -C $c config user.name 'Clone Name'; git -C $c config user.email 'clone@example.test'
        $g = Join-Path $root 'idd-global.gitconfig'; git config --file $g user.name 'Global Name'; git config --file $g user.email 'global@example.test'
        $d1 = Get-GeneTargetIdentityDefault -Repo (New-GeneRepo -Path $c) -GlobalConfig $g
        Assert-Equal 'Clone Name' $d1.Name; Assert-Equal 'clone@example.test' $d1.Email
        $d2 = Get-GeneTargetIdentityDefault -Repo (New-GeneRepo -Path (Join-Path $root 'idd-none')) -GlobalConfig $g
        Assert-Equal 'Global Name' $d2.Name; Assert-Equal 'global@example.test' $d2.Email
        $d3 = Get-GeneTargetIdentityDefault -Repo (New-GeneRepo -Path (Join-Path $root 'idd-none')) -GlobalConfig (Join-Path $root 'no.gitconfig')
        Assert-Equal '' "$($d3.Name)$($d3.Email)"
    }
    Test-Case 'identity question: Enter keeps the default, typed text replaces it, nothing at all stops' {
        $d = [pscustomobject]@{ Name = 'Def Name'; Email = 'def@example.test' }
        $r = Read-GeneGitIdentity -Label 'x on BOX' -Default $d -Reader (New-Queue @('', 'new@example.test'))
        Assert-Equal 'Def Name' $r.Name; Assert-Equal 'new@example.test' $r.Email
        Assert-Throws { Read-GeneGitIdentity -Label 'x on BOX' -Default ([pscustomobject]@{ Name = ''; Email = '' }) -Reader (New-Queue @('', '')) } '*git name and email*'
    }
    Test-Case 'local install: the script''s output goes to the screen and only its exit code comes back' {
        $fake = Join-Path $root 'fake-hub'; New-Item -ItemType Directory -Force $fake | Out-Null
        Set-Content -LiteralPath (Join-Path $fake 'install.ps1') -Value @('param([switch]$NoPull, [switch]$Yes, [switch]$Check)', "'line one'", "Write-Warning 'a warning'", 'exit 3')
        $code = Invoke-GeneLocalInstall -Hub $fake
        Assert-Equal 1 @($code).Count "returned: $(@($code) -join ' | ')"
        Assert-Equal 3 $code
        Set-Content -LiteralPath (Join-Path $fake 'install.ps1') -Value @('param([switch]$NoPull, [switch]$Yes, [switch]$Check)', "'fine'", 'exit 0')
        $ok = Invoke-GeneLocalInstall -Hub $fake
        Assert-True ($ok -is [int] -and $ok -eq 0) "returned: $(@($ok) -join ' | ')"
    }
    Test-Case 'PAT hint: the printed commands pin origin to the account''s own GitHub user and let Git Credential Manager ask for the PAT' {
        $h1 = Get-GenePatHint -Origin 'https://genewebb@github.com/genewebb/ai-setup.git' -CloneLocal 'D:\devops\pat\ai-setup' -Label 'CORP\pat on BOX'
        Assert-Match $h1 ([regex]::Escape('git -C D:\devops\pat\ai-setup remote set-url origin https://<github-user>@github.com/genewebb/ai-setup.git'))
        Assert-Match $h1 ([regex]::Escape('git -C D:\devops\pat\ai-setup fetch'))
        Assert-Match $h1 'PAT'
        Assert-NoMatch $h1 'genewebb@'
        Assert-Match (Get-GenePatHint -Origin 'https://github.com/o/r.git' -CloneLocal 'C:\c' -Label 'l') ([regex]::Escape('https://<github-user>@github.com/o/r.git'))
    }
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
    Test-Case 'filter: a built-in alias does not make a catalog command defined; an alias to a function does' {
        $script:ProfOtherCatalog['tools'].Commands += New-GeneOtherEntry 'zzalias' 'probe' @('zzalias')
        try {
            Set-Alias -Name zzalias -Value Set-ItemProperty -Scope Global
            Assert-True ((Get-GeneOtherEntries -Category tools).Name -notcontains 'zzalias') 'alias to a cmdlet must be hidden'
            function global:zzaliasTarget { }
            Set-Alias -Name zzalias -Value zzaliasTarget -Scope Global
            Assert-True ((Get-GeneOtherEntries -Category tools).Name -contains 'zzalias') 'alias to a function must be listed'
            # sp is a built-in alias (Set-ItemProperty); without the profile's function sp it is not a profile command.
            $hadSp = Test-Path function:\sp; if ($hadSp) { $spDef = (Get-Item function:\sp).ScriptBlock; Remove-Item function:\sp }
            try { Assert-True ((Get-GeneOtherEntries -Category profile).Name -notcontains 'sp') 'sp must be hidden when function sp is absent' }
            finally { if ($hadSp) { Set-Item -Path function:\global:sp -Value $spDef } }
        }
        finally {
            $script:ProfOtherCatalog['tools'].Commands = @($script:ProfOtherCatalog['tools'].Commands | Where-Object { $_.Name -ne 'zzalias' })
            Remove-Item alias:\zzalias -ErrorAction SilentlyContinue; Remove-Item function:\zzaliasTarget -ErrorAction SilentlyContinue
        }
    }
    Test-Case 'filter: listing the groups and refreshing the catalog is fast (no module discovery per name)' {
        function global:zzSlowProbe { }
        $script:ProfOtherCatalog['tools'].Commands += New-GeneOtherEntry 'zzNotDefinedAnywhere' 'probe' @('x')
        try {
            [void](Get-GeneProfGroupNames)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 5; $i++) { [void](Get-GeneProfGroupNames); [void](& $script:ProfGroups['other'].TopicNames) }
            $ms = $sw.ElapsedMilliseconds / 5
            Assert-True ($ms -lt 100) "one group listing + topic names took $ms ms (limit 100)"
        }
        finally { $script:ProfOtherCatalog['tools'].Commands = @($script:ProfOtherCatalog['tools'].Commands | Where-Object { $_.Name -ne 'zzNotDefinedAnywhere' }); Remove-Item function:\zzSlowProbe -ErrorAction SilentlyContinue }
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
    Test-Case 'trimmed hub: without SetupGroup/Target/Sync/Share the module imports and prof help has no setup group' {
        $t = New-TestRoot 'hub'; Copy-Item -Path "$mod\*" -Destination $t -Recurse
        Remove-Item -LiteralPath "$t\SetupGroup.ps1", "$t\Target.ps1", "$t\Sync.ps1", "$t\Share.ps1", "$t\ShareSkills.ps1"
        $core = Join-Path $repoRoot 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
        $o = @(pwsh -NoProfile -Command "`$ErrorActionPreference = 'Stop'; . '$core'; Import-Module '$t\Gene.Profile.psd1' -DisableNameChecking -Force; prof help 6>&1 | Out-String; 'EXIT-OK'" 2>&1) -join "`n"
        Assert-Match $o 'EXIT-OK'
        Assert-NoMatch $o '(?m)^setup  '
        Assert-Match $o '(?m)^other  '
    }
    Test-Case 'show: a changed profile.d file counts as a difference' {
        $r = New-TestRoot 'show'; $i = New-TestRoot 'inst'
        foreach ($d in $r, $i) {
            New-Item "$d\profile.d", "$d\Modules\M" -ItemType Directory -Force | Out-Null
            Set-Content "$d\Microsoft.PowerShell_profile.ps1" 'a'; Set-Content "$d\profile.d\git.ps1" 'b'; Set-Content "$d\Modules\M\M.psm1" 'c'
        }
        Assert-Equal 0 (Compare-GeneProfileTrees -Repo $r -Installed $i).Categories
        Set-Content "$i\profile.d\git.ps1" 'changed'
        Assert-Equal 1 (Compare-GeneProfileTrees -Repo $r -Installed $i).Categories
        Assert-Equal 'in sync' (Compare-GeneProfileTrees -Repo $r -Installed $i).Profile
        Assert-Equal 0 (Compare-GeneProfileTrees -Repo $r -Installed $i).Modules
        Remove-Item "$i\Modules\M\M.psm1"; Remove-Item "$i\Microsoft.PowerShell_profile.ps1"
        $c = Compare-GeneProfileTrees -Repo $r -Installed $i
        Assert-Equal 'missing' $c.Profile; Assert-Equal 1 $c.Modules
    }
    Test-Case 'show: an installed profile.d or module file the repo no longer has is counted as extra' {
        $r = New-TestRoot 'showx'; $i = New-TestRoot 'instx'
        foreach ($d in $r, $i) {
            New-Item "$d\profile.d", "$d\Modules\M" -ItemType Directory -Force | Out-Null
            Set-Content "$d\Microsoft.PowerShell_profile.ps1" 'a'; Set-Content "$d\profile.d\git.ps1" 'b'; Set-Content "$d\Modules\M\M.psm1" 'c'
        }
        Assert-Equal 0 (Compare-GeneProfileTrees -Repo $r -Installed $i).Extra
        Set-Content "$i\profile.d\old.ps1" 'stale'; Set-Content "$i\Modules\M\Gone.ps1" 'stale'
        $c = Compare-GeneProfileTrees -Repo $r -Installed $i
        Assert-Equal 2 $c.Extra
        Assert-Equal @('Modules\M\Gone.ps1', 'profile.d\old.ps1') @($c.ExtraFiles | Sort-Object)
        Assert-Equal 0 $c.Categories; Assert-Equal 0 $c.Modules
    }
    Test-Case 'trimmed copy: core + tabs + navigate and a hub without setup/streams/git/build lists only those categories (profile = machinecfg, from the core)' {
        $t = New-TestRoot 'trim'; $m2 = Join-Path $t 'Modules\Gene.Profile'
        New-Item -ItemType Directory -Path "$t\profile.d", $m2 -Force | Out-Null
        $src = Join-Path $repoRoot 'pwsh\PowerShell'
        Copy-Item -LiteralPath "$src\Microsoft.PowerShell_profile.ps1" -Destination $t
        foreach ($c in 'tabs', 'navigate') { Copy-Item -LiteralPath "$src\profile.d\$c.ps1" -Destination "$t\profile.d" -ErrorAction Stop }
        Copy-Item -Path "$mod\*" -Destination $m2 -Recurse
        foreach ($f in 'SetupGroup', 'Target', 'Sync', 'Share', 'ShareSkills', 'StreamsGroup', 'GitGroup', 'BuildGroup') { Remove-Item -LiteralPath "$m2\$f.ps1" -ErrorAction Stop }
        $o = @(pwsh -NoProfile -Command "`$ErrorActionPreference = 'Stop'; . '$t\Microsoft.PowerShell_profile.ps1'; Import-Module '$m2\Gene.Profile.psd1' -DisableNameChecking -Force; prof help 6>&1 | Out-String; '--OTHER--'; prof help other 6>&1 | Out-String; '--PROFILE--'; prof other profile 6>&1 | Out-String; 'EXIT-OK'" 2>&1) -join "`n"
        Assert-Match $o 'EXIT-OK'
        foreach ($g in 'streams', 'setup', 'git', 'build') { Assert-NoMatch $o "(?m)^$g  " }
        Assert-Match $o '(?m)^other  '
        # profile stays: machinecfg is an alias to Show-GeneMachineConfig, which the core defines, so every copy has it.
        $other = (($o -split '--OTHER--')[1] -split '--PROFILE--')[0]
        $cats = @([regex]::Matches($other, '(?m)^  (\w+)\s') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        Assert-Equal @('navigate', 'profile', 'tabs') $cats "other lists: $($cats -join ',')"
        $prof = ($o -split '--PROFILE--')[1]
        Assert-Match $prof '(?m)^  machinecfg '
        foreach ($n in 'sp', 'ep', 'rp') { Assert-NoMatch $prof "(?m)^  $n " }
    }
    Test-Case 'groups: main menu order is streams, setup, git, build, other' { Assert-Equal @('streams', 'setup', 'git', 'build', 'other') @($script:ProfGroups.Keys) }
    Test-Case 'groups: setup holds the twelve commands, help is not one of them' {
        Assert-True ($script:ProfGroups.Contains('setup'))
        Assert-Equal @('push', 'pull', 'status', 'check', 'bootstrap', 'terminal', 'secrets', 'config', 'edit', 'reload', 'show', 'share') @($script:ProfGroups['setup'].Verbs.Keys)
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

    # ---------------------------------------------------------------- share (replaces export)
    Test-Case 'setup verbs: share replaces export' {
        $v = @($script:ProfGroups['setup'].Verbs.Keys)
        Assert-True ($v -contains 'share') 'share missing'
        Assert-True ($v -notcontains 'export') 'export still listed'
        Assert-Match $script:ProfUsage['share'] 'prof setup share \[profile \| ai-setup \| help\] \[-Repo <clone>\] \[-WhatIf\]'
    }
    Test-Case 'setup menu: share asks dry-run and repo' {
        $p = Read-GeneSetupMenuParams -Verb 'share' -Reader (New-Queue @('y', 'C:\x\dba'))
        Assert-Equal $true $p.WhatIf; Assert-Equal 'C:\x\dba' $p.Repo
    }
    Test-Case 'prof setup share help prints the help and returns nothing' {
        $out = Invoke-GeneProf setup share help 6>&1 | Out-String
        Assert-Match $out 'prof setup share profile'
        Assert-Match $out 'Never shared'
    }

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
            $o = Invoke-GeneProfMenu -Group git -Reader (New-Queue @('2', '1', 'my msg', 'y', 'n')) 6>&1 | Out-String
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
        Test-Case 'git: -AIOnly is gone with pushrules (retired 10/24)' {
            Assert-Throws { Invoke-GeneProf git push speedy -AIOnly 6>&1 | Out-Null } '*AIOnly*'
            Assert-NoMatch ((Get-Content -LiteralPath "$mod\GitGroup.ps1" -Raw) + (Get-Content -LiteralPath "$mod\Verbs.ps1" -Raw)) 'AIOnly|pushrules'
        }
        Test-Case 'ai: the group is gone with dpAI (retired 10/24)' {
            Assert-True (-not $script:ProfGroups.Contains('ai')) 'ai group still registered'
            Assert-True (-not (Test-Path -LiteralPath "$mod\AiGroup.ps1")) 'AiGroup.ps1 still exists'
            $o = Invoke-GeneProf ai local 6>&1 | Out-String
            Assert-Match $o "No group or command called 'ai'"
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
