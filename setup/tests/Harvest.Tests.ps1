#requires -Version 7
# Spec 5.10 harvest semantics: nothing is dropped or broadened because a path sits under an access root, repo scope
# is kept, unrelated local settings survive, and an exact entry goes only after its replacement is applied and verified.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$harvest = Join-Path $PSScriptRoot '..\Invoke-AIHarvest.ps1'

$root = New-TestRoot 'harvest'
try {
    $home1 = Join-Path $root 'claude'; $repos = Join-Path $root 'repos'; $corpus = Join-Path $root 'corpus'
    New-Item -ItemType Directory -Force -Path $home1, (Join-Path $repos 'r1\.git'), (Join-Path $repos 'r1\.claude'), (Join-Path $corpus 'claude') | Out-Null
    $cfg = Join-Path $root 'profile.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = 'X:\repos'; AIWorkRoot = $corpus; ScratchRoot = 'X:\tmp'; WorktreesRoot = 'X:\wt'; ClaudeHome = $home1 })
    $env:AI_MACHINE_CONFIG = $cfg

    # The last install generated: repos read+edit, a read-only row (Read allow + Edit deny), no Bash(*).
    $gen = [ordered]@{ allow = @('Read(//x/repos/**)', 'Edit(//x/repos/**)', 'Read(//x/ro/**)'); ask = @(); deny = @('Edit(//x/ro/**)') }
    (@{ identity = 'test'; lastSettings = $gen } | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $home1 'machine-config.state.json')
    (@{ permissions = $gen } | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $home1 'settings.json')
    "allow:`n- Skill`nask: []`ndeny:`n- Edit({VaultWorkRoot}\x\**)`n" | Set-Content (Join-Path $corpus 'claude\permissions.yaml') -NoNewline
    $local = Join-Path $repos 'r1\.claude\settings.local.json'
    ([ordered]@{
        permissions = [ordered]@{ allow = @('Bash(pwsh -File X:\repos\r1\run.ps1)', 'Read(//x/ro/a.md)', 'Edit(//x/ro/b.md)', 'Bash(git log:*)') }
        env         = [ordered]@{ FOO = '1' }
    } | ConvertTo-Json -Depth 10) | Set-Content $local

    function Invoke-Harvest { param([string[]]$More) & pwsh -NoProfile -File $harvest -ConfigPath $cfg -ClaudeHome $home1 -CorpusRoot $corpus -RepoSearchRoots $repos @More 2>&1 }
    function Items { (Get-Content (Join-Path $home1 'machine-config.harvest.json') -Raw | ConvertFrom-Json).items }
    function ItemOf([string]$rule) { Items | Where-Object rule -ceq $rule }

    [void](Invoke-Harvest)
    Test-Case 'a script-run approval inside a repo stays an open command rule (a Read row does not cover it)' {
        $i = ItemOf 'Bash(pwsh -File X:\repos\r1\run.ps1)'
        Assert-Equal 'proposed' $i.status; Assert-Equal 'command:Bash' $i.operation
    }
    Test-Case 'the command rule gets a {Key} form' { Assert-Equal 'Bash(pwsh -File {ReposRoot}\r1\run.ps1)' (ItemOf 'Bash(pwsh -File X:\repos\r1\run.ps1)').proposed }
    Test-Case 'an edit approval under a read-only row is a conflict, not redundant' {
        $i = ItemOf 'Edit(//x/ro/b.md)'; Assert-Equal 'conflict' $i.coverage; Assert-Equal 'proposed' $i.status
    }
    Test-Case 'a read approval under a Read allow of the same tool is covered' { Assert-Equal 'covered' (ItemOf 'Read(//x/ro/a.md)').status }
    Test-Case 'a repo-scoped command keeps its repo scope' { $i = ItemOf 'Bash(git log:*)'; Assert-Equal 'repo' $i.scope; Assert-Equal 'r1' $i.repo }

    $runId = (ItemOf 'Bash(pwsh -File X:\repos\r1\run.ps1)').id
    $logId = (ItemOf 'Bash(git log:*)').id
    $editId = (ItemOf 'Edit(//x/ro/b.md)').id
    [void](Invoke-Harvest -More @('-Action', 'accept', '-Id', $runId, '-Global'))
    [void](Invoke-Harvest -More @('-Action', 'accept', '-Id', $logId))
    [void](Invoke-Harvest -More @('-Action', 'reject', '-Id', $editId))
    Test-Case 'a global accept adds the {Key} form to permissions.yaml, which still parses' {
        $y = ConvertFrom-Yaml (Get-Content (Join-Path $corpus 'claude\permissions.yaml') -Raw)
        Assert-True (@($y.allow) -contains 'Bash(pwsh -File {ReposRoot}\r1\run.ps1)') (@($y.allow) -join ' | ')
        Assert-True (@($y.allow) -contains 'Skill') 'existing rule lost'
    }
    Test-Case 'a repo-scope accept leaves the rule in the repo file' { Assert-Equal 'kept' (ItemOf 'Bash(git log:*)').status }

    [void](Invoke-Harvest -More @('-Action', 'finalize'))
    Test-Case 'finalize removes nothing before the replacement is applied' {
        $l = Get-Content $local -Raw | ConvertFrom-Json
        Assert-True (@($l.permissions.allow) -contains 'Bash(pwsh -File X:\repos\r1\run.ps1)') 'removed too early'
        Assert-Equal 'accepted' (ItemOf 'Bash(pwsh -File X:\repos\r1\run.ps1)').status
    }

    # Simulate the apply: the generated set and the live settings now carry both rendered forms.
    $gen.allow += @('Bash(pwsh -File X:\repos\r1\run.ps1)', 'Bash(pwsh -File X:/repos/r1/run.ps1)')
    (@{ identity = 'test2'; lastSettings = $gen } | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $home1 'machine-config.state.json')
    (@{ permissions = $gen } | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $home1 'settings.json')
    [void](Invoke-Harvest -More @('-Action', 'finalize'))
    Test-Case 'after a verified apply, finalize removes exactly the original entry' {
        $l = Get-Content $local -Raw | ConvertFrom-Json
        Assert-True (@($l.permissions.allow) -notcontains 'Bash(pwsh -File X:\repos\r1\run.ps1)') 'not removed'
        Assert-Equal 'Read(//x/ro/a.md)|Edit(//x/ro/b.md)|Bash(git log:*)' (@($l.permissions.allow) -join '|')
        Assert-Equal 'verified' (ItemOf 'Bash(pwsh -File X:\repos\r1\run.ps1)').status
    }
    Test-Case 'the unrelated local setting survives' { Assert-Equal '1' (Get-Content $local -Raw | ConvertFrom-Json).env.FOO }

    [void](Invoke-Harvest)
    Test-Case 'rejected and kept items are not proposed again' {
        Assert-Equal 'rejected' (ItemOf 'Edit(//x/ro/b.md)').status
        Assert-Equal 'kept' (ItemOf 'Bash(git log:*)').status
    }
    Test-Case 'with no installed revision nothing is marked covered' {
        Remove-Item (Join-Path $home1 'machine-config.state.json'), (Join-Path $home1 'machine-config.harvest.json')
        [void](Invoke-Harvest)
        Assert-Equal 0 @(Items | Where-Object status -eq 'covered').Count
    }
}
finally {
    Remove-Item Env:\AI_MACHINE_CONFIG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
