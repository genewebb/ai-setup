# Releases a builder's worktree: the counterpart of New-TaskWorktree. A worktree is disposable once its patch is
# exported, because the patch IS its content (Export-TaskPatch runs `git diff` in it) and Integrate-Patch proves main
# holds that content from the patch alone. Nothing in the kit reads a worktree for evidence any more.
#   -Task <id>      the task whose worktree goes; its base.worktree is the path
#   -Path <dir>     an explicit worktree directory, for an orphan no task references any more
#   -BuildOutputOnly  delete only bin/ and obj/ BESIDE A PROJECT FILE and KEEP the worktree (92% of a worktree
#                   measured, and nothing reads it), for a task that may still be resumed. A directory merely NAMED
#                   bin or obj is not build output: node_modules carries 9 of them in this repo. A directory a
#                   compiler holds open is reported as kept, never as a failure.
#   -Label <text>   what to call it on the worktrees.md line when -Task cannot be used, as for a SUPERSEDED copy of a
#                   task that is live in another tree: naming the owner beats logging it as an orphan
#   -Reason <text>  goes on the worktrees.md line
# REFUSES (exit 3, nothing touched) while the task holds a live BUILD claim: a builder is working in there. A live
# AUTHOR claim does not refuse, because an author writes a ticket and never enters a worktree.
# Prints REMOVED / PRUNED <task> <path>, or NOTHING when the directory is already gone.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Task = '',
    [string] $Path = '',
    [string] $Label = '',
    [switch] $BuildOutputOnly,
    [string] $Reason = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"   # Get-Field lives here, not in Streams.ps1
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo

if (-not $Task -and -not $Path) { 'REFUSED give -Task or -Path'; exit 2 }

$wt = $Path
if ($Task) {
    # Get-Task THROWS on an unknown id rather than returning null, and the reaper meets ids that no longer exist.
    $t = $null
    try { $t = Get-Task (Read-Tasks $P) $Task } catch { }
    if (-not $t) { if ($Path) { $Task = '' } else { "REFUSED unknown task $Task"; exit 2 } }
    # A live BUILD claim means a builder is in there right now. Its own session releases it; never this one. An author
    # claim is not about the tree at all: it holds the ticket, so it must not keep a dead worktree alive.
    elseif ($t.claim -and $t.claim.role -eq 'build' -and (Test-ClaimLive $t)) { "REFUSED $Task holds a live $($t.claim.role) claim of $($t.claim.session)"; exit 3 }
    elseif (-not $wt) { $wt = Get-Field $t 'base', 'worktree' }
}
$label = if ($Task) { $Task } elseif ($Label) { $Label } else { '(orphan)' }
if (-not $wt) { "NOTHING $label has no recorded worktree"; exit 0 }
if (-not (Test-Path $wt)) { "NOTHING $label $wt is already gone"; exit 0 }

# Never let a bad -Path turn into a delete of the repo or of a worktree root.
$full = (Resolve-Path $wt).Path
if ($full -eq $Repo -or (Split-Path -Leaf $full) -eq (Split-Path -Leaf $Repo)) { "REFUSED $full is the repository, not a task worktree"; exit 2 }

if ($BuildOutputOnly) {
    # "bin" and "obj" name .NET build output ONLY beside a project file. Matching the NAME alone at any depth also
    # matches a package's own executables: the live repo carries 9 such directories under
    # tests\Tests.E2E\node_modules (eslint\bin, playwright-core\bin, js-yaml\bin, acorn\bin ...), and pruning those
    # leaves a tree whose Playwright run dies on a missing binary - which a builder reads as a product defect, the
    # same phantom failure a grader building a rewritten main tree used to produce (kit item IN-20260930172725-6af7).
    # No tracked file on main sits under a bin/ or obj/ path segment (measured: 0 of 3397), so requiring a sibling
    # project file cannot reach source, and skipping node_modules keeps the node toolchain intact.
    # A reparse point is never entered: the target lives outside this tree and is not ours to prune.
    $freed = 0
    $locked = 0
    $all = @(Get-ChildItem $full -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('bin', 'obj') -and -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) } |
        Where-Object { $_.FullName -notmatch '(^|\\)node_modules(\\|$)' } |
        Where-Object { @(Get-ChildItem $_.Parent.FullName -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.csproj', '.fsproj', '.vbproj', '.sln', '.esproj') }).Count -gt 0 })
    foreach ($d in $all) {
        if (-not (Test-Path $d.FullName)) { continue }   # already gone with its parent
        $was = [long](Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
        Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        # A compiler holding one file keeps the whole directory: that is a SKIP, not a failure. The sweep must stay
        # QUIET-able and must never report a partial prune as a broken tree.
        if (Test-Path $d.FullName) {
            $still = [long](Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
            $freed += ($was - $still)
            $locked++
        } else { $freed += $was }
    }
    $tail = if ($locked) { ", $locked kept (files in use)" } else { '' }
    Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | build output pruned ({3} MB{4}){5}" -f $label, $full, (Get-Now), [int]($freed / 1MB), $tail, $(if ($Reason) { ": $Reason" }))
    "PRUNED $label $full ($([int]($freed / 1MB)) MB$tail)"
    exit 0
}

$size = [long](Get-ChildItem $full -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum

# --force because the worktree still holds its own already-exported change as uncommitted files; that is the normal
# state of a finished build, not a reason to keep it.
& git -C $Repo worktree remove --force $full 2>&1 | Out-Null
& git -C $Repo worktree prune 2>&1 | Out-Null

# git drops the registration first and can then fail to delete the directory, leaving an EMPTY husk with no .git
# (3 of 30 on 2026-09-29, each 0 files). Those are no longer worktrees, so only a plain delete clears them.
if (Test-Path $full) {
    Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $full) {
        Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | removal FAILED (directory still present)" -f $label, $full, (Get-Now))
        "FAILED $label $full is still present"
        exit 1
    }
}

Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | removed ({3} MB){4}" -f $label, $full, (Get-Now), [int]($size / 1MB), $(if ($Reason) { ": $Reason" }))
"REMOVED $label $full ($([int]($size / 1MB)) MB)"
