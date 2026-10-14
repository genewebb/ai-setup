# Builder step 3b: lays the task's prior patch (artifacts.patch, kept from an earlier build) on top of a fresh worktree,
# unstaged, so the builder starts from the earlier work instead of from nothing.
#   APPLIED <patch>    exit 0  the prior patch is now the builder's change; run the grader, then verify
#   NO-PRIOR           exit 1  the task has no prior patch; build as usual
#   CONFLICT <why>     exit 2  the patch no longer applies to this base; nothing was written; build as usual
# Never touches the main tree.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Task,
    [Parameter(Mandatory)] [string] $Worktree
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$t = Get-Task (Read-Tasks $P) $Task
$patch = Get-Field $t 'artifacts', 'patch'
if (-not $patch -or $t.kind -notin @('code', 'docs')) { 'NO-PRIOR'; exit 1 }
if (-not [IO.Path]::IsPathRooted($patch)) { $patch = Join-Path $Repo $patch }
if (-not (Test-Path -LiteralPath $patch) -or (Get-Item -LiteralPath $patch).Length -eq 0) { 'NO-PRIOR'; exit 1 }

# keep a copy: the builder's next Export-TaskPatch overwrites the same path
$keep = Join-Path $P.Patches ("{0}.prior.{1}.patch" -f $Task, (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))
Copy-Item -LiteralPath $patch -Destination $keep

$check = & git -C $Worktree apply --check --binary --whitespace=nowarn $patch 2>&1
if ($LASTEXITCODE -ne 0) { "CONFLICT $(($check | Select-Object -First 3) -join ' | ')"; exit 2 }
[void](Invoke-Git $Worktree @('apply', '--binary', '--whitespace=nowarn', $patch))
"APPLIED $keep"
exit 0
