#requires -Version 7
<#
.SYNOPSIS
    Pull the latest AI setup and install all of it on this machine, after showing where every file will go.

.DESCRIPTION
    The only command a machine needs after a change was pushed from anywhere. Every location comes from this
    machine's profile (C:\Deploy\Setup\ProfileMachineConfig.md, or AI_MACHINE_CONFIG), never from this script.

    Before it writes anything it LISTS every location it reads or writes and asks once to confirm:
      - this clone, which must be the profile's AIWorkRoot (the ai launcher and every skill read the corpus there);
      - the Claude home (ClaudeHome), which must be the folder Claude Code really reads: CLAUDE_CONFIG_DIR when set,
        else ~\.claude of the account running this script;
      - every path key in the profile with its state (local, share, missing, blank);
      - the repos in the git policy table;
      - the install targets of steps 2-5 below.
    A wrong drive or a stale row is caught here (the laptop is all C:, SMVMTR1 is all D:). -Yes skips the question
    for a run with nobody at the keyboard; a run whose input is redirected refuses without -Yes, so it never hangs.

    Then, in order:
      1. git pull --ff-only (refuses to pull over unpublished local commits; run publish.ps1 first)
      2. Claude runtime: setup\Install-AIMachine.ps1 -CorpusRoot <this clone> (skills, agents, commands, scripts,
         lib, CLAUDE.md, the generated settings.json from this machine's profile, the ai launcher shim)
      3. memory: ClaudeHome\memory becomes a junction to <this clone>\memory, so every session writes straight into
         the working tree and publish.ps1 carries it. A real folder found there is merged into the repo first and
         kept as memory.pre-git-<stamp>.
      4. PowerShell: pwsh\PowerShell -> the pwsh 7 profile folder ($PROFILE), pwsh\WindowsPowerShell -> the
         Windows PowerShell profile folder (profiles, powershell.config.json, own Gene.* modules). A changed file's
         old copy goes to {ScratchRoot}\ai-config-work\backups\install-<stamp>\. Files under profile.d\ and
         Modules\Gene.*\ that the repo no longer has are removed the same way (the profile loads every file there,
         so a retired one would still run); anything else in the profile folder is left alone. PSGallery modules
         listed in pwsh\modules.txt are installed when missing (a failure there is reported and does not stop the
         install). -PwshProfileDir and -WinPsProfileDir replace the two folders PowerShell reports (tests).
      5. stream-host scripts -> the profile's StreamHostDir (skipped when the key is absent or blank).
      6. the hourly scheduled task "AI scratch cleanup" for this account: {ClaudeHome}\bin\Clear-AIScratch.ps1
         -Root {ScratchRoot} -KeepDays 7. It works ONLY under ScratchRoot (and refuses any other root), removing
         files nothing holds open and nothing has written for 7 days, day-old tool leftovers at the top, then empty
         folders. No Claude session and no tokens are involved. Re-running install re-registers it on the current
         profile.
    It ends with a summary of what each step did and where.

    -PassphraseFromStdin (with -SecretsFile) reads the secrets passphrase as the FIRST line of standard input, before
    anything else runs, and keeps it in memory only: never on the command line, in the environment or on disk. It is
    how prof secrets runs this script on another machine.

    -WhatIf or -Check list the locations, run step 2 in its own report-only mode and make steps 3-6 report without
    writing; nothing is asked. Exit code: 0 ok; 1 you said no; 2 the machine configuration is invalid; 3 the runtime
    apply stopped on drift (see Install-AIMachine.ps1 -AcceptDrift); anything else is the failing step's error.

.EXAMPLE
    pwsh -NoProfile -File .\install.ps1
.EXAMPLE
    pwsh -NoProfile -File .\install.ps1 -NoPull -WhatIf
.EXAMPLE
    pwsh -NoProfile -File .\install.ps1 -Yes
#>
[CmdletBinding()]
param(
    [switch]$NoPull,
    [switch]$WhatIf,
    [switch]$Check,
    [switch]$AcceptDrift,
    [string]$SecretsFile,
    [switch]$PassphraseFromStdin,
    [string]$PwshProfileDir,
    [string]$WinPsProfileDir,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
# First, before any child process can inherit and read standard input: the secrets passphrase, kept in memory.
$stdinPassphrase = $null
if ($PassphraseFromStdin) {
    if (-not $SecretsFile) { Write-Host 'STOP: -PassphraseFromStdin needs -SecretsFile. Nothing was changed.' -ForegroundColor Red; exit 2 }
    $line = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($line)) { Write-Host 'STOP: -PassphraseFromStdin read an empty first line. Nothing was changed.' -ForegroundColor Red; exit 2 }
    $stdinPassphrase = ConvertTo-SecureString -String $line -AsPlainText -Force
    $line = $null
}
$repo = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$dry = $WhatIf -or $Check
$InstallerArgs = @{}
foreach ($n in "WhatIf", "Check", "AcceptDrift", "SecretsFile") { if ($PSBoundParameters.ContainsKey($n)) { $InstallerArgs[$n] = $PSBoundParameters[$n] } }
if ($stdinPassphrase) { $InstallerArgs['Passphrase'] = $stdinPassphrase }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summary = [System.Collections.Generic.List[string]]::new()
function Step([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }
function Same-Path([string]$a, [string]$b) { [string]::Equals([IO.Path]::GetFullPath($a).TrimEnd('\'), [IO.Path]::GetFullPath($b).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }
function Refuse([string]$m) { Write-Host "STOP: $m" -ForegroundColor Red; Write-Host 'Nothing was changed.' -ForegroundColor Red; exit 2 }

# ---------------------------------------------------------------------------------------------------------------
# 0. The machine profile: every location comes from it
# ---------------------------------------------------------------------------------------------------------------
Import-Module (Join-Path $repo 'lib\MachineConfig.psm1') -Force -DisableNameChecking
try { $prof = Get-AIMachineProfile }
catch {
    Write-Host "STOP: $_" -ForegroundColor Red
    Write-Host 'This machine has no readable machine profile. The profile is the ONE file that says where everything goes on this machine (AIWorkRoot = this clone, ClaudeHome, ReposRoot, ScratchRoot, WorktreesRoot, the git policy). Create it before installing: docs\machine-config-design.md section 4.1 describes every row, and another machine''s profile is the quickest start (copy it, then change every drive and path to this machine''s).' -ForegroundColor Yellow
    exit 2
}
$keys = $prof.Keys
$problems = @(Test-AIMachineProfile -Profile $prof)
foreach ($p in $problems) { Write-Host ("[{0}] {1}" -f $p.Level.ToUpperInvariant(), $p.Message) -ForegroundColor $(if ($p.Level -eq 'error') { 'Red' } elseif ($p.Level -eq 'warning') { 'Yellow' } else { 'DarkGray' }) }
if (@($problems | Where-Object Level -eq 'error').Count) { Refuse "the machine profile $($prof.Path) is invalid (see above). Fix it and run again." }

# The two locations that must agree with what is really on this machine, or the install lands where nothing reads it.
$claudeHome = [IO.Path]::GetFullPath($keys['ClaudeHome']).TrimEnd('\')
$realClaudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$aiWorkRoot = $keys['AIWorkRoot']
$fatal = [System.Collections.Generic.List[string]]::new()
if (-not (Same-Path $repo $aiWorkRoot)) { $fatal.Add("this clone is $repo but the profile's AIWorkRoot is $aiWorkRoot. The ai launcher and every skill read the corpus at AIWorkRoot, so an install from here would be read by nothing. Either run install.ps1 from the clone at AIWorkRoot, or set AIWorkRoot in $($prof.Path) to this clone.") }
if (-not (Same-Path $claudeHome $realClaudeHome)) { $fatal.Add("the profile's ClaudeHome is $claudeHome but Claude Code on this machine, run as $env:USERDOMAIN\$env:USERNAME, reads $realClaudeHome$(if ($env:CLAUDE_CONFIG_DIR) { ' (CLAUDE_CONFIG_DIR)' } else { ' (~\.claude)' }). Run install.ps1 as the account that runs Claude, or fix ClaudeHome in $($prof.Path).") }

# ---------------------------------------------------------------------------------------------------------------
# 0b. Show every location and confirm
# ---------------------------------------------------------------------------------------------------------------
Step "locations on $env:COMPUTERNAME, from $($prof.Path)"
$fmt = '  {0,-25} {1,-62} {2}'
Write-Host ($fmt -f 'KEY', 'PATH', 'STATE') -ForegroundColor DarkGray
foreach ($c in @(Get-AIConfig) | Where-Object { $_.Location -ne 'value' }) {
    # Exists is $null when the location could not be checked (a share seen from a remote session): no MISSING then.
    $state = if (-not $c.Value) { 'blank (not on this machine)' } elseif ($c.Exists -or $null -eq $c.Exists) { $c.Location } else { "$($c.Location), MISSING" }
    Write-Host ($fmt -f $c.Key, $c.Value, $state) -ForegroundColor $(if ($c.Value -and -not $c.Exists) { 'Yellow' } else { 'Gray' })
}
Write-Host '  repos (git policy: a repo not listed gets no commit, push or worktree):' -ForegroundColor DarkGray
foreach ($g in @($prof.GitPolicy)) {
    $there = if ($g.Repo -and (Test-Path -LiteralPath (Join-Path $g.Repo '.git'))) { 'present' } elseif ($g.Repo -and (Test-Path -LiteralPath $g.Repo)) { 'present, NOT A GIT CLONE' } else { 'MISSING' }
    Write-Host ($fmt -f '', $g.Repo, "$there, commit=$($g.Commit) push=$($g.Push) worktrees=$($g.Worktrees)") -ForegroundColor $(if ($there -eq 'present') { 'Gray' } else { 'Yellow' })
}
# Profile folders come from PowerShell itself, not from an assumed Documents path (OneDrive can move Documents).
$pwshDir = if ($PwshProfileDir) { $PwshProfileDir } else { Split-Path $PROFILE.CurrentUserCurrentHost }
$winPsDir = if ($WinPsProfileDir) { $WinPsProfileDir } else { $null }
if (-not $winPsDir -and (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { try { $winPsDir = (& powershell.exe -NoProfile -NonInteractive -Command 'Split-Path $PROFILE.CurrentUserCurrentHost' 2>$null | Select-Object -First 1) } catch { } }
if (-not $winPsDir) { $winPsDir = Join-Path (Split-Path $pwshDir) 'WindowsPowerShell' }
$scratch = $keys['ScratchRoot']
$backupDir = Join-Path $scratch "ai-config-work\backups\install-$stamp"
$shDir = if ($keys.Contains('StreamHostDir')) { $keys['StreamHostDir'] } else { '' }
$cleanTask = 'AI scratch cleanup'; $cleanKeepDays = 7
$cleanUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$cleanState = if (Get-ScheduledTask -TaskName $cleanTask -ErrorAction SilentlyContinue) { 'registered, will be replaced' } else { 'NEW' }
Write-Host '  install targets:' -ForegroundColor DarkGray
foreach ($t in @(
        @('this clone (AIWorkRoot)', $repo, $(if (Same-Path $repo $aiWorkRoot) { 'ok' } else { 'NOT THE PROFILE''S AIWorkRoot' })),
        @('Claude runtime', $claudeHome, $(if (Same-Path $claudeHome $realClaudeHome) { 'ok: what Claude reads' } else { "NOT what Claude reads ($realClaudeHome)" })),
        @('memory junction', "$(Join-Path $claudeHome 'memory') -> $(Join-Path $repo 'memory')", ''),
        @('Claude temp', "$scratch (CLAUDE_CODE_TMPDIR); TEMP/TMP $(Join-Path $scratch 'temp')", ''),
        @('PowerShell 7 profile', $pwshDir, '$PROFILE'),
        @('Windows PowerShell', $winPsDir, ''),
        @('backups of changed files', $backupDir, ''),
        @('stream-host scripts', $(if ($shDir) { $shDir } else { '(StreamHostDir blank: skipped)' }), ''),
        @('scratch cleanup task', "'$cleanTask' hourly as $cleanUser, ONLY under $scratch, files unused $cleanKeepDays days", $cleanState))) {
    Write-Host ($fmt -f $t[0], $t[1], $t[2]) -ForegroundColor $(if ($t[2] -like 'NOT*') { 'Red' } else { 'Gray' })
}
if ($fatal.Count) {
    foreach ($f in $fatal) { Write-Host "STOP: $f" -ForegroundColor $(if ($dry) { 'Yellow' } else { 'Red' }) }
    if (-not $dry) { Write-Host 'Nothing was changed.' -ForegroundColor Red; exit 2 }
    Write-Host '  (-WhatIf/-Check: a real run would stop here)' -ForegroundColor Yellow
}
if ($dry) { Write-Host '  (-WhatIf/-Check: nothing is written, so no confirmation is asked)' -ForegroundColor DarkGray }
elseif (-not $Yes) {
    if ([Console]::IsInputRedirected) { Refuse 'install.ps1 asks to confirm the locations above, and its input is redirected. Re-run with -Yes once they are right.' }
    $answer = Read-Host 'Install to these locations? [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Stopped: nothing was changed. Fix the paths in the machine profile above, then re-run.' -ForegroundColor Yellow; exit 1 }
}

# ---------------------------------------------------------------------------------------------------------------
# 1. pull
# ---------------------------------------------------------------------------------------------------------------
if ($NoPull) { $summary.Add('pull: skipped (-NoPull)') }
elseif ($dry) { $summary.Add('pull: skipped (-WhatIf/-Check)') }
else {
    Step 'git pull'
    $before = git -C $repo rev-parse HEAD
    git -C $repo pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "git pull --ff-only failed (git's message is above). Unpublished local commits or a diverged branch: run publish.ps1 first. Ownership or credential errors: fix as git says, then re-run."
    }
    $after = git -C $repo rev-parse HEAD
    $summary.Add($(if ($before -eq $after) { "pull: already up to date ($($after.Substring(0,7)))" } else { "pull: $($before.Substring(0,7)) -> $($after.Substring(0,7)), $(@(git -C $repo rev-list --count "$before..$after")) commit(s)" }))
    # The pull may have changed the lib this script loaded; the installer below imports it again itself.
    Import-Module (Join-Path $repo 'lib\MachineConfig.psm1') -Force -DisableNameChecking
}

# ---------------------------------------------------------------------------------------------------------------
# 2. Claude runtime
# ---------------------------------------------------------------------------------------------------------------
Step 'Claude runtime (Install-AIMachine)'
$global:LASTEXITCODE = 0
& (Join-Path $repo 'setup\Install-AIMachine.ps1') -CorpusRoot $repo @InstallerArgs
$installerExit = $LASTEXITCODE
if ($installerExit -in 0, $null) { $installerExit = 0; $summary.Add("runtime: $(if ($dry) { 'checked' } else { 'installed' }) into $claudeHome") }
elseif ($installerExit -eq 2) { $summary.Add('runtime: NOT installed, the machine configuration is invalid (see above)') }
elseif ($installerExit -eq 3) { $summary.Add('runtime: NOT installed, stopped on drift (edits made outside the installer are kept; re-run with -AcceptDrift after moving wanted edits into the corpus)') }
else { $summary.Add("runtime: FAILED (exit $installerExit), the previous install was restored") }
if ($installerExit -notin 0, 3) { Write-Warning "Install-AIMachine exited $installerExit; continuing with memory, PowerShell, stream-host and the cleanup task so the rest of the machine is still right." }

# ---------------------------------------------------------------------------------------------------------------
# 3. memory junction
# ---------------------------------------------------------------------------------------------------------------
Step 'memory'
$live = Join-Path $claudeHome 'memory'
$src = Join-Path $repo 'memory'
$item = Get-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
if ($item -and $item.LinkType -eq 'Junction' -and (Same-Path ([string]($item.Target | Select-Object -First 1)) $src)) {
    Write-Host "  already linked -> $src"
    $summary.Add("memory: $live -> $src (already linked)")
}
elseif ($dry) {
    Write-Host "  would link $live -> $src$(if ($item) { ' (merging the existing folder into the repo first)' })"
    $summary.Add("memory: would link $live -> $src")
}
else {
    if ($item) {
        if ($item.LinkType) { throw "$live is a $($item.LinkType) to $($item.Target), not to $src. Remove it by hand and re-run." }
        # merge: files missing from the repo, or newer locally, go into the repo before the switch
        $merged = 0
        foreach ($f in Get-ChildItem -LiteralPath $live -Recurse -File) {
            $rel = [IO.Path]::GetRelativePath($live, $f.FullName)
            $dest = Join-Path $src $rel
            $d = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            if (-not $d -or ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $dest).Hash -and $f.LastWriteTimeUtc -gt $d.LastWriteTimeUtc)) {
                New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                Write-Host "  merged $rel"; $merged++
            }
        }
        $kept = "$live.pre-git-$stamp"
        Rename-Item -LiteralPath $live -NewName (Split-Path $kept -Leaf)
        Write-Host "  old folder kept as $kept"
        $summary.Add("memory: merged $merged file(s) into the repo; old folder kept as $kept")
    }
    New-Item -ItemType Junction -Path $live -Target $src | Out-Null
    Write-Host "  linked $live -> $src"
    $summary.Add("memory: linked $live -> $src")
}

# ---------------------------------------------------------------------------------------------------------------
# 4. PowerShell profiles and own modules
# ---------------------------------------------------------------------------------------------------------------
Step 'PowerShell'
$psTargets = @{ PowerShell = $pwshDir; WindowsPowerShell = $winPsDir }
foreach ($edition in 'PowerShell', 'WindowsPowerShell') {
    $from = Join-Path $repo "pwsh\$edition"
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = $psTargets[$edition]
    $updated = 0
    foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File) {
        $rel = [IO.Path]::GetRelativePath($from, $f.FullName)
        $dest = Join-Path $to $rel
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        $updated++
        if ($dry) { Write-Host "  would update $dest"; continue }
        if (Test-Path -LiteralPath $dest) {
            $bak = Join-Path $backupDir "$edition\$rel"
            New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
            Copy-Item -LiteralPath $dest -Destination $bak
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $dest"
    }
    # Files the repo no longer has under profile.d\ and Modules\Gene.*\ (a retired command or hub group). The profile
    # dot-sources every profile.d\*.ps1 and the hub module loads every .ps1 beside it, so a stale file would still run.
    # Only those two places are swept; anything else in the profile folder is not the repo's to touch.
    $stale = @(foreach ($area in 'profile.d', 'Modules') {
            $dir = Join-Path $to $area
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {
                $rel = [IO.Path]::GetRelativePath($to, $_.FullName)
                ($area -eq 'profile.d' -or $rel -like 'Modules\Gene.*') -and -not (Test-Path -LiteralPath (Join-Path $from $rel))
            }
        })
    foreach ($f in $stale) {
        if ($dry) { Write-Host "  would remove $($f.FullName) (the repo no longer has it)"; continue }
        $bak = Join-Path $backupDir "$edition\$([IO.Path]::GetRelativePath($to, $f.FullName))"
        New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $bak
        Remove-Item -LiteralPath $f.FullName -Force
        Write-Host "  removed $($f.FullName) (the repo no longer has it; copy in $backupDir)"
    }
    $staleNote = if ($stale.Count) { "; $($stale.Count) stale file(s) $(if ($dry) { 'would be removed' } else { 'removed' })" } else { '' }
    $summary.Add("$edition profile: $(if ($dry) { "$updated file(s) would change" } else { "$updated file(s) updated" })$staleNote in $to$(if (($updated -or $stale.Count) -and -not $dry) { "; old copies in $backupDir" })")
}

# 4b. PSGallery modules listed in pwsh\modules.txt: install the missing ones only. A failure (no internet, gallery
# down) is reported and the install goes on: the profile still loads without them.
$listed = Get-Content -LiteralPath (Join-Path $repo 'pwsh\modules.txt') | Where-Object { $_ -match '^\s*(PowerShell|WindowsPowerShell)\s+(\S+)' } |
    ForEach-Object { [pscustomobject]@{ Edition = $Matches[1]; Name = $Matches[2] } }
$modInstalled = 0; $modFailed = [System.Collections.Generic.List[string]]::new()
foreach ($m in $listed) {
    $present = if ($m.Edition -eq 'PowerShell') { [bool](Get-Module -ListAvailable -Name $m.Name) }
               elseif (Get-Command powershell.exe -ErrorAction SilentlyContinue) { (powershell.exe -NoProfile -NonInteractive -Command "[bool](Get-Module -ListAvailable -Name '$($m.Name)')") -eq 'True' }
               else { $true }   # no Windows PowerShell on this machine: nothing to install for it
    if ($present) { continue }
    if ($dry) { Write-Host "  would install $($m.Edition) module $($m.Name)"; $modInstalled++; continue }
    try {
        if ($m.Edition -eq 'PowerShell') { Install-Module $m.Name -Scope CurrentUser -Force -AcceptLicense -Repository PSGallery }
        else { powershell.exe -NoProfile -NonInteractive -Command "Install-Module '$($m.Name)' -Scope CurrentUser -Force -Repository PSGallery"; if ($LASTEXITCODE) { throw "powershell.exe exit $LASTEXITCODE" } }
        Write-Host "  installed $($m.Edition) module $($m.Name)"; $modInstalled++
    }
    catch { Write-Warning "  could not install $($m.Edition) module $($m.Name): $($_.Exception.Message)"; $modFailed.Add("$($m.Edition) $($m.Name)") }
}
$summary.Add("PSGallery modules: $(if ($dry) { "$modInstalled would be installed" } else { "$modInstalled installed" })$(if ($modFailed.Count) { "; FAILED: $($modFailed -join ', ') (re-run install.ps1 with internet, or Install-Module by hand)" })")

# ---------------------------------------------------------------------------------------------------------------
# 5. stream-host scripts
# ---------------------------------------------------------------------------------------------------------------
Step 'stream-host'
if (-not $shDir) { Write-Host '  StreamHostDir not set in this machine profile: skipped'; $summary.Add('stream-host: skipped (StreamHostDir blank)') }
else {
    $shUpdated = 0
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'stream-host') -File) {
        $dest = Join-Path $shDir $f.Name
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        $shUpdated++
        if ($dry) { Write-Host "  would update $dest"; continue }
        New-Item -ItemType Directory -Force -Path $shDir | Out-Null
        if (Test-Path -LiteralPath $dest) {
            $bak = Join-Path $backupDir "stream-host\$($f.Name)"
            New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
            Copy-Item -LiteralPath $dest -Destination $bak
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $dest"
    }
    $summary.Add("stream-host: $(if ($dry) { "$shUpdated file(s) would change" } else { "$shUpdated file(s) updated" }) in $shDir")
}

# ---------------------------------------------------------------------------------------------------------------
# 6. hourly scratch cleanup task (runs the INSTALLED bin\Clear-AIScratch.ps1, so step 2 must have landed)
# ---------------------------------------------------------------------------------------------------------------
Step 'scratch cleanup task'
$cleanScript = Join-Path $repo 'setup\Clear-AIScratch.ps1'
if ($installerExit -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $claudeHome 'bin\Clear-AIScratch.ps1'))) {
    Write-Host '  the runtime was not installed and no earlier copy is there: skipped' -ForegroundColor Yellow
    $summary.Add("scratch cleanup: NOT registered (runtime step failed; re-run install.ps1 once it passes)")
}
else {
    $cleanArgs = @('-Register', '-Root', $scratch, '-KeepDays', $cleanKeepDays) + $(if ($dry) { @('-DryRun') } else { @() })
    $cleanOut = @(& pwsh -NoProfile -NonInteractive -File $cleanScript @cleanArgs 2>&1)
    $cleanCode = $LASTEXITCODE
    foreach ($l in $cleanOut) { Write-Host "  $l" }
    if ($cleanCode -ne 0) { Write-Warning "  the cleanup task was not registered (exit $cleanCode); the scratch area will not be kept clean until it is."; $summary.Add("scratch cleanup: NOT registered (see above)") }
    elseif ($dry) { $summary.Add("scratch cleanup: would register '$cleanTask' hourly on $scratch (files unused $cleanKeepDays days)") }
    else { $summary.Add("scratch cleanup: '$cleanTask' registered hourly as $cleanUser on $scratch (files unused $cleanKeepDays days); log $(Join-Path $scratch 'ai-config-work\Clear-AIScratch.log')") }
}

# ---------------------------------------------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------------------------------------------
Step $(if ($dry) { 'summary (nothing was written)' } else { 'summary' })
foreach ($s in $summary) { Write-Host "  $s" -ForegroundColor $(if ($s -match 'NOT installed|NOT registered|FAILED') { 'Yellow' } else { 'Gray' }) }
if (-not $dry -and $installerExit -eq 0) { Write-Host "  start Claude with 'ai' so the new runtime and settings are active." -ForegroundColor Gray }
exit $installerExit
