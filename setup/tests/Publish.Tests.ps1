#requires -Version 7
# publish.ps1 against a scratch clone of a scratch bare origin: it never touches this clone or github. The clone holds a
# copy of publish.ps1 and tools\Find-Secrets.ps1 from this corpus, so the script under test is the one in the tree.
# Run: pwsh -NoProfile -File Publish.Tests.ps1
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$corpus = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')

$root = New-TestRoot 'publish'
try {
    $bare = Join-Path $root 'origin.git'; $clone = Join-Path $root 'clone'
    & git init -q --bare -b main $bare
    & git clone -q $bare $clone 2>$null
    function G([string[]]$a) { $o = & git -C $clone @a 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($a -join ' '): $o" }; $o }
    G @('config', 'user.email', 'test@example.invalid'); G @('config', 'user.name', 'Publish Test'); G @('config', 'commit.gpgsign', 'false')
    G @('checkout', '-q', '-b', 'main')
    New-Item -ItemType Directory -Force (Join-Path $clone 'tools') | Out-Null
    Copy-Item (Join-Path $corpus 'publish.ps1') $clone
    Copy-Item (Join-Path $corpus 'tools\Find-Secrets.ps1') (Join-Path $clone 'tools')
    Set-Content (Join-Path $clone 'README.md') 'seed'
    G @('add', '-A'); G @('commit', '-q', '-m', 'seed'); G @('push', '-q', '-u', 'origin', 'main')
    $pub = Join-Path $clone 'publish.ps1'
    function Run([string[]]$More) { $o = & pwsh -NoProfile -File $pub @More *>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
    function RunPiped([string[]]$More) { $o = '' | & pwsh -NoProfile -File $pub @More *>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
    function OriginHead { (& git -C $bare rev-parse main).Trim() }
    function CloneHead { (& git -C $clone rev-parse HEAD).Trim() }

    $r0 = Run @('-Yes')
    Test-Case 'nothing to publish: says so and exits 0' { Assert-Equal 0 $r0.Code $r0.Out; Assert-Match $r0.Out 'Nothing to publish' }

    Set-Content (Join-Path $clone 'note.md') 'a change'
    $r1 = RunPiped @()
    Test-Case 'a change with redirected input and no -Yes refuses before committing, and the change stays uncommitted' {
        Assert-True ($r1.Code -ne 0) "exit $($r1.Code)"
        Assert-Match $r1.Out 'note\.md'
        Assert-Match $r1.Out 'input is redirected. Nothing was committed'
        Assert-Equal (OriginHead) (CloneHead) 'a commit was made'
        Assert-Match ((& git -C $clone status --short) -join "`n") 'note\.md'
    }
    $r2 = Run @('-Yes', '-Message', 'add note')
    Test-Case '-Yes commits the shown files and pushes main to origin, reporting the commit and remote' {
        Assert-Equal 0 $r2.Code $r2.Out
        Assert-Match $r2.Out 'Changes to commit on main \(1 file\(s\)\)'
        Assert-Match $r2.Out 'Published [0-9a-f]{7,} to .*origin\.git \(main\): 1 file\(s\) committed'
        Assert-Equal (CloneHead) (OriginHead) 'origin did not receive the commit'
        Assert-Equal 'add note' ((& git -C $clone log -1 --format=%s).Trim())
    }

    Set-Content (Join-Path $clone 'leak.txt') 'password=SuperSecret123!'
    $r3 = RunPiped @('-Yes')
    Test-Case 'a secret-looking line with no console to answer on is refused and nothing is committed' {
        Assert-True ($r3.Code -ne 0) "exit $($r3.Code)"
        Assert-Match $r3.Out 'conn-password'
        Assert-Match $r3.Out 'Possible secrets in the change. Nothing was committed'
        Assert-NoMatch $r3.Out 'SuperSecret123'
        Assert-Equal (OriginHead) (CloneHead) 'a commit was made'
    }
    Remove-Item (Join-Path $clone 'leak.txt')

    # Someone else pushed meanwhile: the push is rejected once, rebased and pushed again.
    $other = Join-Path $root 'other'
    & git clone -q $bare $other 2>$null
    & git -C $other config user.email 'o@example.invalid'; & git -C $other config user.name 'Other'; & git -C $other config commit.gpgsign false
    Set-Content (Join-Path $other 'other.md') 'from elsewhere'
    & git -C $other add -A; & git -C $other commit -q -m 'other'; & git -C $other push -q
    Set-Content (Join-Path $clone 'mine.md') 'from here'
    $r4 = Run @('-Yes', '-Message', 'mine')
    Test-Case 'a commit pushed by someone else meanwhile is rebased onto and the publish still lands' {
        Assert-Equal 0 $r4.Code $r4.Out
        Assert-Equal (CloneHead) (OriginHead) 'origin did not receive the commit'
        Assert-True ((Test-Path (Join-Path $clone 'other.md')) -and (Test-Path (Join-Path $clone 'mine.md'))) 'both changes should be in the tree'
    }

    # A conflict: the same line changed on both sides. The other clone is behind origin after the race above, so it
    # pulls first, or ITS push is the rejected one and no conflict reaches origin.
    & git -C $other pull -q --rebase 2>$null
    Set-Content (Join-Path $other 'README.md') 'theirs'; & git -C $other add -A; & git -C $other commit -q -m 'theirs'; & git -C $other push -q
    Set-Content (Join-Path $clone 'README.md') 'ours'
    $r5 = Run @('-Yes', '-Message', 'ours')
    Test-Case 'a rebase conflict stops with the conflicting file named and the commands to finish or abort' {
        Assert-True ($r5.Code -ne 0) "exit $($r5.Code)"
        Assert-Match $r5.Out 'Rebase stopped on a conflict in: README\.md'
        Assert-Match $r5.Out 'git rebase --continue'
    }
    $r6 = Run @('-Yes')
    Test-Case 'while that rebase is unfinished, publish refuses to do anything' {
        Assert-True ($r6.Code -ne 0) "exit $($r6.Code)"
        Assert-Match $r6.Out 'A rebase, merge or cherry-pick is unfinished'
    }
    & git -C $clone rebase --abort 2>$null
    & git -C $clone checkout -q -b feature
    $r7 = Run @('-Yes')
    Test-Case 'on a branch other than main, publish refuses and says how to get back' {
        Assert-True ($r7.Code -ne 0) "exit $($r7.Code)"
        Assert-Match $r7.Out "publishes main only; this clone is on 'feature'"
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
