# Creates <repo>\.streams\ with an empty tasks.json and keeps it out of git through .git\info\exclude (never
# .gitignore, which is a tracked file), and creates the six role inboxes. Safe to re-run: existing state is never overwritten.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string[]] $Requirements = @()
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
foreach ($d in @($P.Root, $P.Plans, $P.Tickets, $P.Graders, $P.Patches, $P.Logs, $P.Verdicts, $P.Owner)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}
if (-not (Test-Path $P.Tasks)) {
    $doc = [ordered]@{ version = 1; repo = $Repo; requirements = @($Requirements); groups = @(); tasks = @() }
    Write-AtomicText $P.Tasks ($doc | ConvertTo-Json -Depth 50)
    Add-Decision $P 'init' "created .streams for $Repo"
}
foreach ($f in @($P.Questions, $P.Gates, $P.Worktrees, $P.Decisions)) { if (-not (Test-Path $f)) { Add-LineTo $f "# $(Split-Path -Leaf $f)" } }
# one inbox per role skill, from inbox-template.md (never overwritten)
Initialize-Inboxes $P

$gitDir = (Invoke-Git $Repo @('rev-parse', '--git-common-dir')) | Select-Object -First 1
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Repo $gitDir }
$exclude = Join-Path $gitDir 'info\exclude'
$has = (Test-Path $exclude) -and ((Get-Content $exclude) -contains '.streams/')
if (-not $has) { Add-LineTo $exclude '.streams/' }
"streams ready: $($P.Root)"
