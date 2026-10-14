# Copy-StreamToHost.ps1 -- move the stream board (.streams) and the Claude skills from this machine to the stream host.
# Run it ON THE OLD HOST (the laptop). The code does not travel this way: the new host clones the repo from origin.
# .streams is excluded from git (.git/info/exclude) because it is a live board, so it is copied here, once, when quiet.
#   -Phase Seed   : copy the skills and a preview of .streams while the old host keeps running. The new host must NOT
#                   start any loop from a seed copy.
#   -Phase Final  : the cutover copy. Refuses unless the board is quiet (no claims, no building/built task, no
#                   integrator.lock) and the main tree is clean, so nothing in flight is lost or run twice.
#   pwsh -NoProfile -File .\Copy-StreamToHost.ps1 -Phase Seed
#   pwsh -NoProfile -File .\Copy-StreamToHost.ps1 -Phase Final
param(
    [ValidateSet('Seed', 'Final')] [string] $Phase = 'Seed',
    [string] $Repo = 'C:\devops\repos\speedmerchants',
    [string] $HostName = 'SMVMTR1',
    [string] $RepoTarget = '',             # default \\<host>\C$\devops\repos\speedmerchants
    [string] $HostUser = 'speedmerchants', # the account the loops run as on the host (CORP\speedmerchants)
    [string] $SkillsTarget = '',           # default \\<host>\C$\Users\<HostUser>\.claude\skills
    [switch] $SkipSkills
)
$ErrorActionPreference = 'Stop'
if (-not $RepoTarget) { $RepoTarget = "\\$HostName\C$\devops\repos\speedmerchants" }
if (-not $SkillsTarget) { $SkillsTarget = "\\$HostName\C$\Users\$HostUser\.claude\skills" }

if (-not (Test-Path (Join-Path $RepoTarget '.git'))) {
    throw "no clone at ${RepoTarget}: on $HostName run git clone first (see Install-StreamHost.ps1 LEFT TO DO)"
}

if ($Phase -eq 'Final') {
    $doc = Get-Content -Raw (Join-Path $Repo '.streams\tasks.json') | ConvertFrom-Json
    $claims = @($doc.tasks | Where-Object { $_.claim })
    # An unclaimed integration task left 'building' while it waits for its dependencies is parked, not in flight:
    # the host integrator resumes it from the board.
    $state = @{}; foreach ($t in $doc.tasks) { $state[$t.id] = $t.state }
    $parked = @($doc.tasks | Where-Object {
            $_.state -eq 'building' -and -not $_.claim -and
            @($_.dependsOn | Where-Object { $state[$_] -notin 'integrated', 'done' }).Count })
    $flight = @($doc.tasks | Where-Object { $_.state -in 'building', 'built' -and $_.id -notin $parked.id })
    if ($parked) { Write-Host "parked (waiting on dependencies, carried as is): $(($parked.id) -join ', ')" }
    $lock = Test-Path (Join-Path $Repo '.streams\integrator.lock')
    $dirty = @(git -C $Repo status --porcelain)
    if ($claims -or $flight -or $lock -or $dirty) {
        Write-Host "NOT QUIET: $($claims.Count) claims ($(($claims.id) -join ', ')), $($flight.Count) building/built ($(($flight.id) -join ', ')), integrator.lock=$lock, $($dirty.Count) uncommitted entries" -ForegroundColor Red
        Write-Host 'Stop the plan/author/build loops, let integrate drain, commit and push, then re-run.'
        exit 2
    }
    # The host clone must hold the same tree as this repo, or tasks integrated here would be missing there.
    $here = git -C $Repo rev-parse 'HEAD^{tree}'
    $there = git -c "safe.directory=*" -C $RepoTarget rev-parse 'HEAD^{tree}'
    if ($here -ne $there) {
        Write-Host "TREE MISMATCH: here $here, $HostName $there. Push the sync commit and git pull on $HostName, then re-run." -ForegroundColor Red
        exit 3
    }
}

# .streams only. /MIR makes the host board an exact copy; lock files are never carried across.
$src = Join-Path $Repo '.streams'
$dst = Join-Path $RepoTarget '.streams'
Write-Host ".streams -> $dst ($Phase)"
& robocopy $src $dst /MIR /R:2 /W:2 /MT:16 /NP /NFL /NDL /XF '*.lock'
if ($LASTEXITCODE -ge 8) { throw "robocopy .streams failed ($LASTEXITCODE)" }

if (-not $SkipSkills) {
    # robocopy follows the directory symlinks under ~\.claude\skills, so the host gets real copies of each skill.
    Write-Host "skills -> $SkillsTarget"
    & robocopy (Join-Path $env:USERPROFILE '.claude\skills') $SkillsTarget /MIR /R:2 /W:2 /MT:16 /NP /NFL /NDL /XD scripts-stage-* .git
    if ($LASTEXITCODE -ge 8) { throw "robocopy skills failed ($LASTEXITCODE)" }
    $md = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'
    if (Test-Path $md) { Copy-Item $md (Split-Path $SkillsTarget) -Force; Write-Host 'CLAUDE.md copied' }
}

Write-Host "done: $Phase copy. On $HostName run Test-StreamHostReady.ps1." -ForegroundColor Green
if ($Phase -eq 'Final') { Write-Host 'From now on run NO stream loop here: the host copy of .streams is the only live board.' -ForegroundColor Yellow }
