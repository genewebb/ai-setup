#requires -Version 7
<#
.SYNOPSIS
    Installs or updates this machine's Claude Code runtime from the AI corpus and the machine profile
    (spec docs\machine-config-design.md, 4.3, 4.3b, 4.3c, R1-R16).

.DESCRIPTION
    One applicator for first setup, /machine-config apply and the ai launcher. Every run is a transaction (R14):
      1. read the inputs once (profile, corpus manifest, templates)   2. stage every output
      3. validate                                                      4. take the per-install lock
      5. check no destination changed since the last install (drift)   6. apply
      7. write the state record LAST; on any failure restore the previous install.

    Outputs: the local runtime copy (skills, agents, commands, scripts, lib, CLAUDE.md, statusline, bin), the
    generated settings.json (owned properties only, R12), the ai launcher shim, MCP servers and secrets
    (only when missing, or with -SecretsFile).

.PARAMETER WhatIf
    Stage, validate and print the plan and the settings diff. Changes nothing.
.PARAMETER Check
    Validate and report drift, links and availability. Writes nothing.
.PARAMETER Launch
    Used by the ai launcher: quiet; applies only when the installation identity changed.
.PARAMETER AcceptDrift
    Proceed although installed files or owned settings were changed outside the applicator. Their content is
    preserved under machine-config\drift-<stamp> and changed permission rules go to the harvest queue first.
.PARAMETER SecretsFile
    A file written by Export-AISecrets.ps1; its values fill MCP secret placeholders and secret user env vars.
#>
[CmdletBinding()]
param(
    [string]$CorpusRoot,
    [string]$ConfigPath,
    [switch]$WhatIf,
    [switch]$Check,
    [switch]$Launch,
    [switch]$AcceptDrift,
    [string]$SecretsFile,
    [string]$ClaudeExeDir,
    [switch]$SkipMcp
)
$ErrorActionPreference = 'Stop'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID"   # PID: two runs in one second must not share staging/rollback folders
$InstallerVersion = '1.0.0'

function Write-Info([string]$m) { if (-not $Launch) { Write-Host $m } }
function Write-Problem([string]$lvl, [string]$m) {
    $c = @{ error = 'Red'; warning = 'Yellow'; info = 'DarkGray' }[$lvl]
    if ($Launch -and $lvl -eq 'info') { return }
    Write-Host ("[{0}] {1}" -f $lvl.ToUpperInvariant(), $m) -ForegroundColor $c
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-StringSha([string]$s) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($s))) }

# ---------------------------------------------------------------------------------------------------------------
# 1. Inputs
# ---------------------------------------------------------------------------------------------------------------
# The lib this script loads: next to it in the corpus (setup\..\lib) or in the installed runtime (bin\..\lib).
$libDir = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'MachineConfig.psm1') } | Select-Object -First 1
if (-not $libDir) { throw "MachineConfig.psm1 not found next to $PSCommandPath." }
Import-Module (Join-Path $libDir 'MachineConfig.psm1') -Force -DisableNameChecking
if (-not (Get-Module -ListAvailable powershell-yaml)) {
    Write-Info 'Installing the powershell-yaml module (CurrentUser)...'
    Install-Module powershell-yaml -Scope CurrentUser -Force -AcceptLicense -Repository PSGallery
}
Import-Module (Join-Path $libDir 'AISettings.psm1') -Force -DisableNameChecking

$pa = @{}; if ($ConfigPath) { $pa.Path = $ConfigPath }
$prof = Get-AIMachineProfile @pa
$claudeVersion = $null
try { $cv = (& claude --version 2>$null | Select-Object -First 1); if ($cv -match '(\d+\.\d+\.\d+)') { $claudeVersion = $Matches[1] } } catch { }

$problems = @(Test-AIMachineProfile -Profile $prof -ClaudeVersion $claudeVersion)
$claudeHome = $prof.Keys['ClaudeHome']
$mcDir = Join-Path $claudeHome 'machine-config'
$statePath = Join-Path $claudeHome 'machine-config.state.json'
$lockPath = Join-Path $claudeHome 'machine-config.lock'
$pendingPath = Join-Path $claudeHome 'machine-config.pending.json'
$state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 30 } else { $null }

# Corpus: the profile's AIWorkRoot unless overridden. When it is unreachable, fall back to the installed mirror
# (settings-only mode): the runtime copy stays as it is and settings are re-rendered from the installed templates.
if (-not $CorpusRoot) { $CorpusRoot = $prof.Keys['AIWorkRoot'] }
$settingsOnly = $false
if (-not $CorpusRoot -or -not (Test-Path -LiteralPath (Join-Path $CorpusRoot 'ai-manifest.json'))) {
    $mirror = Join-Path $mcDir 'claude'
    if (Test-Path -LiteralPath (Join-Path $mirror 'settings.template.json')) {
        $problems += [pscustomobject]@{ Level = 'warning'; Message = "Corpus not reachable at '$CorpusRoot'; using the installed templates (runtime files unchanged)." }
        $settingsOnly = $true
    }
    else { $problems += [pscustomobject]@{ Level = 'error'; Message = "Corpus not reachable at '$CorpusRoot' and nothing is installed yet." } }
}

foreach ($p in $problems) { Write-Problem $p.Level $p.Message }
if (@($problems | Where-Object Level -eq 'error').Count) {
    Write-Host "Validation failed. Nothing was changed. Fix $($prof.Path) and run again." -ForegroundColor Red
    if ($state) { Write-Host "The previous install (revision $($state.identity.Substring(0,12))) is still on disk for recovery, but this launch is refused (R2)." -ForegroundColor Red }
    exit 2
}

# ---------------------------------------------------------------------------------------------------------------
# 2. Plan: every runtime file (dest relative to ClaudeHome -> source)
# ---------------------------------------------------------------------------------------------------------------
$plan = [ordered]@{}
$templateDir = if ($settingsOnly) { Join-Path $mcDir 'claude' } else { Join-Path $CorpusRoot 'claude' }
$manifest = $null
$junk = '(?i)(\.bak[^\\]*$|\\\.git\\|\\__pycache__\\|\\node_modules\\|\.pyc$)'
if (-not $settingsOnly) {
    $manifest = Get-Content -LiteralPath (Join-Path $CorpusRoot 'ai-manifest.json') -Raw | ConvertFrom-Json -AsHashtable
    $addFile = {
        param([string]$src, [string]$rel)
        if ($src -match $junk) { return }
        $plan[($rel -replace '/', '\')] = $src
    }
    foreach ($e in $manifest.runtime) {
        $from = Join-Path $CorpusRoot ($e.from -replace '/', '\')
        $to = $e.to -replace '/', '\'
        $filters = if ($e.Contains('filter') -and $e.filter) { @($e.filter -split ';') } else { @('*') }
        switch ($e.kind) {
            'dir-each' {
                $ex = if ($e.Contains('exclude')) { @($e.exclude) } else { @() }
                foreach ($d in Get-ChildItem -LiteralPath $from -Directory) {
                    if ($d.Name -in $ex) { continue }
                    foreach ($f in Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force) {
                        & $addFile $f.FullName (Join-Path (Join-Path $to $d.Name) $f.FullName.Substring($d.FullName.Length + 1))
                    }
                }
            }
            'file-each' { foreach ($flt in $filters) { foreach ($f in Get-ChildItem -LiteralPath $from -File -Filter $flt) { & $addFile $f.FullName (Join-Path $to $f.Name) } } }
            'tree' {
                foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File -Force) {
                    if (-not ($filters | Where-Object { $f.Name -like $_ })) { continue }
                    & $addFile $f.FullName (Join-Path $to $f.FullName.Substring($from.TrimEnd('\').Length + 1))
                }
            }
            'file' { & $addFile $from $to }
            default { throw "Unknown manifest entry kind '$($e.kind)'." }
        }
    }
}
$hashes = [ordered]@{}
foreach ($rel in $plan.Keys) { $hashes[$rel] = Get-Sha $plan[$rel] }

# R38: with SkillsLinkRoot set, every skill, agent and command is a symbolic link to {SkillsLinkRoot}\<kind>\<name>,
# a tree other machines may share. The corpus wins: its content is written into that tree before the links are set,
# and files there that the corpus does not have are removed (both kept in the rollback snapshot).
$linkRoot = if ($settingsOnly) { $null } else { $prof.Keys['SkillsLinkRoot'] }
$linkItems = [ordered]@{}   # item rel (skills\x, agents\a.md) -> link target
if ($linkRoot) {
    foreach ($rel in $plan.Keys) {
        $seg = $rel -split '\\'
        if ($seg.Count -ge 2 -and $seg[0] -in 'skills', 'agents', 'commands') {
            $item = "$($seg[0])\$($seg[1])"
            if (-not $linkItems.Contains($item)) { $linkItems[$item] = Join-Path $linkRoot $item }
        }
    }
}
$itemOf = { param($rel) $seg = $rel -split '\\'; if ($seg.Count -ge 2) { "$($seg[0])\$($seg[1])" } }
$inLinkItem = { param($rel) $it = & $itemOf $rel; [bool]($it -and $linkItems.Contains($it)) }
$targetWrites = [System.Collections.Generic.List[string]]::new()   # plan rels whose copy in the link tree differs
$targetExtras = [System.Collections.Generic.List[string]]::new()   # link-tree rels the corpus does not have
$linkFixes = [System.Collections.Generic.List[object]]::new()      # items whose ClaudeHome entry is not the right link
foreach ($item in $linkItems.Keys) {
    $tgt = $linkItems[$item]
    foreach ($rel in @($plan.Keys | Where-Object { $_ -eq $item -or $_.StartsWith($item + '\') })) {
        $dst = Join-Path $linkRoot $rel
        if (-not (Test-Path -LiteralPath $dst) -or (Get-Sha $dst) -ne $hashes[$rel]) { $targetWrites.Add($rel) }
    }
    if (Test-Path -LiteralPath $tgt -PathType Container) {
        foreach ($f in Get-ChildItem -LiteralPath $tgt -Recurse -File -Force) {
            $r = $f.FullName.Substring($linkRoot.TrimEnd('\').Length + 1)
            if (-not $plan.Contains($r) -and "\$r" -notmatch $junk) { $targetExtras.Add($r) }
        }
    }
    $p = Join-Path $claudeHome $item
    $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $i -or $i.LinkType -ne 'SymbolicLink' -or ([string]$i.Target).TrimEnd('\') -ne $tgt.TrimEnd('\')) {
        $was = if (-not $i) { 'missing' } elseif ($i.LinkType) { "$($i.LinkType) to $($i.Target)" } else { 'real copy' }
        $linkFixes.Add([pscustomobject]@{ Rel = $item; Path = $p; Target = $tgt; Was = $was })
    }
}
# Items linked by the last install that the corpus no longer has: their link goes (never the target).
$retiredLinks = @(if (-not $settingsOnly -and $state -and $state.Contains('linkItems')) { @($state.linkItems) | Where-Object { $_ -and -not $linkItems.Contains($_) } })

# ---------------------------------------------------------------------------------------------------------------
# 3. Settings
# ---------------------------------------------------------------------------------------------------------------
$settingsPath = Join-Path $claudeHome 'settings.json'
$currentSettings = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30 } else { [ordered]@{} }
$prevOwned = if ($state -and $state.Contains('owned')) { $state.owned } else { $null }
$render = New-AISettings -Profile $prof -TemplatePath (Join-Path $templateDir 'settings.template.json') -PermissionsPath (Join-Path $templateDir 'permissions.yaml') -Current $currentSettings -PreviousOwned $prevOwned
foreach ($r in $render.Report) { Write-Problem $r.Level $r.Message }
if (@($render.Report | Where-Object Level -eq 'error').Count) { Write-Host 'Settings rendering failed. Nothing was changed.' -ForegroundColor Red; exit 2 }
$newSettingsJson = ConvertTo-AISettingsJson -Settings $render.Settings

function Get-OwnedSnapshot([System.Collections.IDictionary]$s, $ownedEnv, $ownedProps) {
    $p = if ($s.Contains('permissions')) { $s.permissions } else { @{} }
    $env = [ordered]@{}
    if ($s.Contains('env')) { foreach ($k in @($ownedEnv) | Sort-Object) { if ($s.env.Contains($k)) { $env[$k] = $s.env[$k] } } }
    $o = [ordered]@{
        allow = @($p['allow']); ask = @($p['ask']); deny = @($p['deny']); additionalDirectories = @($p['additionalDirectories'])
        hooks = $s['hooks']; statusLine = $s['statusLine']; env = $env
    }
    foreach ($k in @($ownedProps)) { $o[$k] = $s[$k] }
    return ($o | ConvertTo-Json -Depth 30 -Compress)
}
$newOwnedSnap = Get-OwnedSnapshot $render.Settings $render.Owned.env $render.Owned.props

# Identity (R1): profile + effective keys + every runtime source + templates + generator version.
$idParts = [System.Text.StringBuilder]::new()
[void]$idParts.AppendLine("installer=$InstallerVersion")
[void]$idParts.AppendLine("profile=$($prof.Hash)")
[void]$idParts.AppendLine(($prof.Keys | ConvertTo-Json -Compress))
foreach ($rel in $hashes.Keys | Sort-Object) { [void]$idParts.AppendLine("$rel=$($hashes[$rel])") }
foreach ($t in 'settings.template.json', 'permissions.yaml', 'mcp-servers.json') { $tp = Join-Path $templateDir $t; if (Test-Path -LiteralPath $tp) { [void]$idParts.AppendLine("$t=$(Get-Sha $tp)") } }
foreach ($l in 'MachineConfig.psm1', 'AISettings.psm1') { [void]$idParts.AppendLine("$l=$(Get-Sha (Join-Path $libDir $l))") }
[void]$idParts.AppendLine("installerScript=$(Get-Sha $PSCommandPath)")
$identity = Get-StringSha $idParts.ToString()

# ---------------------------------------------------------------------------------------------------------------
# Drift (4.3a): installed files and owned settings changed since the last install
# ---------------------------------------------------------------------------------------------------------------
$drift = [System.Collections.Generic.List[object]]::new()
# R39: when SkillsLinkRoot is the corpus copy itself, a linked item's files ARE corpus files. Editing one on this
# machine is a corpus edit (it changes the identity and is applied as such), not drift; the machine-sync skill carries
# it back to the laptop. Any other link tree (a share other machines write) keeps the drift check.
$linkIsCorpus = $linkRoot -and $CorpusRoot -and ([IO.Path]::GetFullPath($linkRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($CorpusRoot).TrimEnd('\'))
$prevLinked = @(if ($state -and $state.Contains('linkItems')) { @($state.linkItems) | Where-Object { $_ } })
if ($state -and $state.Contains('files')) {
    foreach ($rel in $state.files.Keys) {
        if ($linkIsCorpus -and ((& $itemOf $rel) -in $prevLinked)) { continue }
        $dest = Join-Path $claudeHome $rel
        if (-not (Test-Path -LiteralPath $dest)) { $drift.Add([pscustomobject]@{ Kind = 'file'; Rel = $rel; What = 'deleted' }); continue }
        if ((Get-Sha $dest) -ne $state.files[$rel]) { $drift.Add([pscustomobject]@{ Kind = 'file'; Rel = $rel; What = 'edited' }) }
    }
    $curOwnedSnap = Get-OwnedSnapshot $currentSettings $state.owned.env $state.owned.props
    if ((Get-StringSha $curOwnedSnap) -ne $state.settingsOwnedHash) { $drift.Add([pscustomobject]@{ Kind = 'settings'; Rel = 'settings.json'; What = 'owned properties edited' }) }
}

# Links that a first install turns into real copies (the old ~\AI linker layout).
# Two old layouts: the whole folder is a link (~\AI linker), or each item inside it is (the S:\AIWork linker). # history
# A per-item link the plan writes into is replaced too; otherwise the copy would go THROUGH it into the link
# target (a share other machines use). Per-item links the plan does not cover are kept and reported.
$keptLinks = [System.Collections.Generic.List[object]]::new()
$links = @(foreach ($top in 'skills', 'agents', 'commands', 'CLAUDE.md') {
        $p = Join-Path $claudeHome $top
        $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue   # Get-Item also sees a dangling link
        if (-not $i) { continue }
        if ($i.LinkType) { [pscustomobject]@{ Rel = $top; Path = $p; Type = $i.LinkType; Target = [string]$i.Target }; continue }
        if (-not $i.PSIsContainer) { continue }
        foreach ($c in Get-ChildItem -LiteralPath $p -Force | Where-Object LinkType) {
            $rel = "$top\$($c.Name)"
            if ($linkItems.Contains($rel)) { continue }   # R38: the link phase owns it
            $o = [pscustomobject]@{ Rel = $rel; Path = $c.FullName; Type = $c.LinkType; Target = [string]$c.Target }
            if ($plan.Keys | Where-Object { $_ -eq $rel -or $_.StartsWith($rel + '\') } | Select-Object -First 1) { $o } else { $keptLinks.Add($o) }
        }
    })
$fileLinks = @(foreach ($rel in $plan.Keys) {
        if (& $inLinkItem $rel) { continue }
        $d = Join-Path $claudeHome $rel
        if (Test-Path -LiteralPath $d) { $i = Get-Item -LiteralPath $d -Force; if ($i.LinkType -and -not ($links | Where-Object { $rel -eq $_.Rel -or $rel.StartsWith($_.Rel + '\') })) { [pscustomobject]@{ Rel = $rel; Path = $d; Type = $i.LinkType; Target = [string]$i.Target } } }
    })

# ---------------------------------------------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------------------------------------------
$diffLines = {
    # @(...) around the if: an if that yields @() hands $null on, and Compare-Object refuses $null and empty sets.
    $old = @(if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath })
    $new = @($newSettingsJson -split "\r?\n")
    if (-not $old.Count) { $new | ForEach-Object { "+ $($_.Trim())" }; return }
    Compare-Object -ReferenceObject $old -DifferenceObject $new | ForEach-Object { '{0} {1}' -f $(if ($_.SideIndicator -eq '=>') { '+' } else { '-' }), $_.InputObject.Trim() }
}
if ($Check) {
    Write-Host "Profile: $($prof.Path)   Corpus: $CorpusRoot$(if ($settingsOnly) { ' (unreachable)' })"
    Write-Host "Installed revision: $(if ($state) { $state.identity.Substring(0,12) + ' at ' + $state.installedAt } else { 'none' })"
    Write-Host "Source revision:    $($identity.Substring(0,12)) $(if ($state -and $state.identity -eq $identity) { '(up to date)' } else { '(apply pending)' })"
    foreach ($l in $links + $fileLinks) { Write-Problem 'warning' "Link still in place: $($l.Rel) -> $($l.Target) (a first apply replaces it with a copy)." }
    foreach ($l in $keptLinks) { Write-Problem 'warning' "Link not in the corpus, kept as is: $($l.Rel) -> $($l.Target)." }
    if ($linkRoot) {
        Write-Host "SkillsLinkRoot $linkRoot (R38): $($linkItems.Count) items linked; pending: $($linkFixes.Count) links to set, $($targetWrites.Count) files to write and $($targetExtras.Count) to remove there, $($retiredLinks.Count) retired links."
        foreach ($f in $linkFixes) { Write-Problem 'info' "Link to set: $($f.Rel) -> $($f.Target) (now $($f.Was))." }
        foreach ($r in $targetWrites) { Write-Problem 'warning' "Link tree differs from the corpus: $r (an apply writes the corpus copy)." }
        foreach ($r in $targetExtras) { Write-Problem 'warning' "Link tree has a file the corpus does not: $r (an apply removes it)." }
    }
    foreach ($d in $drift) { Write-Problem 'warning' "Drift: $($d.Rel) $($d.What)." }
    $pending = if (Test-Path -LiteralPath $pendingPath) { @((Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json).items).Count } else { 0 }
    Write-Host "Pending approvals in the harvest queue: $pending"
    $repoClaude = foreach ($root in @($prof.Keys['ReposRoot']) + @($prof.GitPolicy | ForEach-Object Repo) | Where-Object { $_ } | Select-Object -Unique) {
        foreach ($d in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
            $c = Join-Path $d.FullName '.claude'
            if (Test-Path -LiteralPath $c) {
                foreach ($x in Get-ChildItem -LiteralPath $c -Force) {
                    $kind = if ($x.Name -eq 'settings.local.json') { 'pending harvest (R10)' } else { 'breaks D13' }
                    "$($x.FullName): $kind"
                }
            }
        }
    }
    foreach ($x in $repoClaude) { Write-Problem $(if ($x -like '*breaks D13') { 'warning' } else { 'info' }) "Repo .claude: $x" }
    $sd = @(& $diffLines)
    Write-Host "settings.json lines that an apply would change: $($sd.Count)"
    $gate = Join-Path $PSScriptRoot 'Test-NoHardPaths.ps1'
    if (-not $settingsOnly -and (Test-Path -LiteralPath $gate)) { & $gate -Root $CorpusRoot -Summary }
    exit 0
}

# Launch fast path: nothing changed since the last install.
if ($Launch -and $state -and $state.identity -eq $identity -and -not $drift.Count) { exit 0 }

# ---------------------------------------------------------------------------------------------------------------
# 2b. Stage
# ---------------------------------------------------------------------------------------------------------------
$stageRoot = if ($WhatIf) { Join-Path ([IO.Path]::GetTempPath()) "ai-machine-stage-$stamp" } else { Join-Path $mcDir "staging-$stamp" }
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
try {
    foreach ($rel in $plan.Keys) {
        $dst = Join-Path $stageRoot "runtime\$rel"
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $plan[$rel] -Destination $dst -Force
        if ((Get-Sha $dst) -ne $hashes[$rel]) { throw "Staged copy of $rel does not match its source (the corpus changed during the read?)." }
    }
    [IO.File]::WriteAllText((Join-Path $stageRoot 'settings.json'), $newSettingsJson)

    # 3. Validate staged outputs.
    $null = Get-Content -LiteralPath (Join-Path $stageRoot 'settings.json') -Raw | ConvertFrom-Json -Depth 30
    $parseErrors = foreach ($ps in Get-ChildItem -LiteralPath (Join-Path $stageRoot 'runtime') -Recurse -File -Include '*.ps1', '*.psm1' -ErrorAction SilentlyContinue) {
        $tok = $null; $err = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$tok, [ref]$err)
        if ($err) { "$($ps.FullName.Substring($stageRoot.Length + 9)): $($err[0].Message)" }
    }
    $runtimeScripts = @($parseErrors | Where-Object { $_ -match '^(scripts|lib|bin)\\' })
    foreach ($e in $parseErrors) { Write-Problem $(if ($e -in $runtimeScripts) { 'error' } else { 'warning' }) "Parse: $e" }
    if ($runtimeScripts.Count) { throw 'A hook, lib or bin script does not parse; nothing applied.' }
    foreach ($h in @('git-guard.ps1', 'hook-dispatch.ps1', 'machine-paths.ps1', 'credentials-guard.ps1')) {
        if (-not $settingsOnly -and -not $plan.Contains("scripts\$h")) { throw "Runtime is missing scripts\$h; nothing applied." }
    }

    # A file of a linked item lives in the link tree: deleting it through the link would delete it there.
    $isItemLink = { param($rel) $it = & $itemOf $rel; if (-not $it) { return $false }; $x = Get-Item -LiteralPath (Join-Path $claudeHome $it) -Force -ErrorAction SilentlyContinue; [bool]($x -and $x.LinkType) }
    $toDelete = @(if ($state -and $state.Contains('files') -and -not $settingsOnly) { $state.files.Keys | Where-Object { -not $plan.Contains($_) -and -not (& $inLinkItem $_) -and -not (& $isItemLink $_) } })
    # Everything under a link that is about to be replaced must be written, even when it reads identical through the link.
    $underLink = { param($rel) [bool]($links | Where-Object { $rel -eq $_.Rel -or $rel.StartsWith($_.Rel + '\') }) }
    $changed = @($plan.Keys | Where-Object { -not (& $inLinkItem $_) } | Where-Object { $d = Join-Path $claudeHome $_; (& $underLink $_) -or (& $isItemLink $_) -or -not (Test-Path -LiteralPath $d) -or (Get-Item -LiteralPath $d -Force).LinkType -or (Get-Sha $d) -ne $hashes[$_] })
    $sd = @(& $diffLines)

    Write-Info "Revision $($identity.Substring(0,12)): $($changed.Count) runtime files to write, $($toDelete.Count) to remove, $($links.Count + $fileLinks.Count) links to replace, $($sd.Count) settings.json lines change."
    if ($linkRoot) { Write-Info "SkillsLinkRoot $linkRoot (R38): $($linkFixes.Count) links to set, $($targetWrites.Count) files to write and $($targetExtras.Count) to remove in the link tree, $($retiredLinks.Count) retired links." }
    if ($WhatIf) {
        foreach ($l in $links + $fileLinks) { Write-Host "  link -> copy: $($l.Rel) (was $($l.Type) to $($l.Target))" }
        foreach ($r in $targetWrites) { Write-Host "  link tree write: $r" }
        foreach ($r in $targetExtras) { Write-Host "  link tree remove: $r" }
        if ($keptLinks.Count) { Write-Host "  $($keptLinks.Count) link(s) not in the corpus are kept as is (listed in the report)." }
        foreach ($d in $drift) { Write-Problem 'warning' "Drift: $($d.Rel) $($d.What)." }
        $reportDir = Join-Path $prof.Keys['ScratchRoot'] 'ai-config-work\reports'
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
        $rp = Join-Path $reportDir "whatif-$stamp.md"
        @("# Install-AIMachine -WhatIf $stamp", '', "Revision $identity", '', '## settings.json diff', '', '```diff') + $sd + @('```', '', '## Runtime files to write', '') + ($changed | ForEach-Object { "- $_" }) + @('', '## Runtime files to remove', '') + ($toDelete | ForEach-Object { "- $_" }) + @('', '## Links to replace', '') + (($links + $fileLinks) | ForEach-Object { "- $($_.Rel) ($($_.Type) -> $($_.Target))" }) + @('', '## Links kept (not in the corpus)', '') + ($keptLinks | ForEach-Object { "- $($_.Rel) ($($_.Type) -> $($_.Target))" }) + @('', "## Link tree $linkRoot (R38)", '', '### Links to set', '') + ($linkFixes | ForEach-Object { "- $($_.Rel) -> $($_.Target) (now $($_.Was))" }) + @('', '### Files to write there', '') + ($targetWrites | ForEach-Object { "- $_" }) + @('', '### Files to remove there', '') + ($targetExtras | ForEach-Object { "- $_" }) + @('', '### Retired links', '') + ($retiredLinks | ForEach-Object { "- $_" }) | Set-Content -LiteralPath $rp -Encoding utf8NoBOM
        [IO.File]::WriteAllText((Join-Path $reportDir "whatif-$stamp.settings.json"), $newSettingsJson)
        Write-Host "WhatIf: nothing changed. Report: $rp"
        exit 0
    }

    # 4. Lock.
    $lock = $null
    for ($i = 0; $i -lt 120 -and -not $lock; $i++) {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $lock) { throw "Another apply holds $lockPath." }
    try {
        # Another apply may have finished the same revision while we waited; its state is newer than the one this
        # run read before the lock, so drift computed against the old record would be false.
        if (Test-Path -LiteralPath $statePath) {
            $s2 = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
            $movedOn = -not $state -or $s2.identity -ne $state.identity -or $s2.installedAt -ne $state.installedAt
            if ($movedOn) {
                if ($s2.identity -eq $identity) { Write-Info "Revision $($identity.Substring(0,12)) was applied by another run while this one waited."; exit 0 }
                throw "Another apply installed revision $($s2.identity.Substring(0,12)) while this one waited; run again."
            }
        }

        # 5. Drift: preserve, queue changed rules, and stop unless accepted.
        if ($drift.Count) {
            $dd = Join-Path $mcDir "drift-$stamp"
            New-Item -ItemType Directory -Force -Path $dd | Out-Null
            foreach ($d in $drift | Where-Object Kind -eq 'file' | Where-Object What -eq 'edited') {
                $dst = Join-Path $dd $d.Rel; New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
                Copy-Item -LiteralPath (Join-Path $claudeHome $d.Rel) $dst
            }
            if ($drift | Where-Object Kind -eq 'settings') {
                Copy-Item -LiteralPath $settingsPath (Join-Path $dd 'settings.json')
                $last = $state.lastSettings
                $items = [System.Collections.Generic.List[object]]::new()
                if (Test-Path -LiteralPath $pendingPath) { foreach ($x in (Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json -AsHashtable).items) { $items.Add($x) } }
                foreach ($tier in 'allow', 'ask', 'deny') {
                    foreach ($rule in @($currentSettings.permissions[$tier])) {
                        if ($rule -and $rule -notin @($last.$tier) -and -not ($items | Where-Object { $_.rule -eq $rule -and $_.tier -eq $tier })) {
                            $items.Add([ordered]@{ tier = $tier; rule = $rule; scope = 'user'; source = 'settings.json'; seen = $stamp })
                        }
                    }
                }
                ([ordered]@{ items = @($items) } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $pendingPath -Encoding utf8NoBOM
            }
            foreach ($d in $drift) { Write-Problem 'warning' "Drift: $($d.Rel) $($d.What) (copy kept in $dd)." }
            if (-not $AcceptDrift) {
                Write-Host 'Apply stopped: files or owned settings were changed outside the applicator. Their content is preserved above and new permission rules are in the harvest queue. Move wanted edits into the corpus (or run /machine-config harvest), then run again with -AcceptDrift.' -ForegroundColor Yellow
                exit 3
            }
        }

        # Rollback snapshot of everything this apply touches.
        $rb = Join-Path $mcDir "rollback-$stamp"
        New-Item -ItemType Directory -Force -Path $rb | Out-Null
        $rbIndex = [System.Collections.Generic.List[object]]::new()
        foreach ($l in $links + $fileLinks) { $rbIndex.Add([ordered]@{ kind = 'link'; rel = $l.Rel; type = [string]$l.Type; target = $l.Target }) }
        foreach ($rel in @($changed) + @($toDelete) + @('settings.json')) {
            $d = Join-Path $claudeHome $rel
            if ((Test-Path -LiteralPath $d) -and -not ($links | Where-Object { $rel -eq $_.Rel -or $rel.StartsWith($_.Rel + '\') }) -and -not ($fileLinks | Where-Object Rel -eq $rel) -and -not (& $isItemLink $rel)) {
                $b = Join-Path $rb "files\$rel"; New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
                Copy-Item -LiteralPath $d $b
                $rbIndex.Add([ordered]@{ kind = 'file'; rel = $rel })
            }
            else { $rbIndex.Add([ordered]@{ kind = 'new'; rel = $rel }) }
        }
        # R38: link-tree files this apply overwrites or removes, and what each item entry in ClaudeHome was.
        foreach ($r in @($targetWrites) + @($targetExtras)) {
            $t = Join-Path $linkRoot $r
            if (Test-Path -LiteralPath $t) {
                $b = Join-Path $rb "linktree\$r"; New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
                Copy-Item -LiteralPath $t $b
                $rbIndex.Add([ordered]@{ kind = 'linktree-file'; rel = $r })
            }
            else { $rbIndex.Add([ordered]@{ kind = 'linktree-new'; rel = $r }) }
        }
        foreach ($rel in @($linkFixes | ForEach-Object Rel) + @($retiredLinks)) {
            $p = Join-Path $claudeHome $rel
            # Under a whole-folder link being replaced, the item's old state comes back with that link.
            $i = if ($links | Where-Object Rel -eq (($rel -split '\\')[0])) { $null } else { Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
            if (-not $i) { $rbIndex.Add([ordered]@{ kind = 'item'; rel = $rel; was = 'missing' }) }
            elseif ($i.LinkType) { $rbIndex.Add([ordered]@{ kind = 'item'; rel = $rel; was = 'link'; type = [string]$i.LinkType; target = [string]$i.Target }) }
            else {
                $b = Join-Path $rb "items\$rel"; New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
                Copy-Item -LiteralPath $p $b -Recurse
                $rbIndex.Add([ordered]@{ kind = 'item'; rel = $rel; was = 'real' })
            }
        }
        ($rbIndex | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $rb 'index.json') -Encoding utf8NoBOM

        try {
            # 6. Apply. Links first: remove the LINK only (never its target), then lay down real folders.
            foreach ($l in $links) {
                if ($l.Type -in 'Junction', 'SymbolicLink') {
                    $item = Get-Item -LiteralPath $l.Path -Force
                    if ($item.PSIsContainer) { [IO.Directory]::Delete($l.Path, $false) } else { [IO.File]::Delete($l.Path) }
                    if (Test-Path -LiteralPath $l.Path) { throw "Could not remove the link $($l.Path)." }
                    if ($item.PSIsContainer) {
                        New-Item -ItemType Directory -Path $l.Path | Out-Null
                        # Carry over Claude-managed content that lived inside the old link target (skills\synced, skills\.trash).
                        foreach ($u in @($manifest.unmanaged) | Where-Object { $_ -like "$($l.Rel)/*" }) {
                            $name = Split-Path $u -Leaf
                            $srcU = Join-Path $l.Target $name
                            if (Test-Path -LiteralPath $srcU) { Copy-Item -LiteralPath $srcU (Join-Path $l.Path $name) -Recurse -Force }
                        }
                    }
                }
            }
            foreach ($l in $fileLinks) { [IO.File]::Delete($l.Path) }
            # R38: corpus content into the link tree first (the corpus wins), then the links themselves.
            foreach ($r in $targetWrites) {
                $t = Join-Path $linkRoot $r
                New-Item -ItemType Directory -Force -Path (Split-Path $t) | Out-Null
                Copy-Item -LiteralPath (Join-Path $stageRoot "runtime\$r") $t -Force
            }
            foreach ($r in $targetExtras) { Remove-Item -LiteralPath (Join-Path $linkRoot $r) -Force }
            foreach ($tgt in @($targetExtras | ForEach-Object { Join-Path $linkRoot (& $itemOf $_) } | Select-Object -Unique)) {
                Get-ChildItem -LiteralPath $tgt -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending |
                    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | ForEach-Object { [IO.Directory]::Delete($_.FullName) }
            }
            $dropEntry = {
                param($p)
                $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                if (-not $i) { return }
                if ($i.LinkType) { if ($i.PSIsContainer) { [IO.Directory]::Delete($p, $false) } else { [IO.File]::Delete($p) } }   # the link only
                elseif ($i.PSIsContainer) { Remove-Item -LiteralPath $p -Recurse -Force } else { Remove-Item -LiteralPath $p -Force }
                if (Test-Path -LiteralPath $p) { throw "Could not remove $p." }
            }
            foreach ($f in $linkFixes) {
                & $dropEntry $f.Path
                New-Item -ItemType Directory -Force -Path (Split-Path $f.Path) | Out-Null
                New-Item -ItemType SymbolicLink -Path $f.Path -Target $f.Target | Out-Null
            }
            foreach ($r in $retiredLinks) { $p = Join-Path $claudeHome $r; $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; if ($i -and $i.LinkType) { & $dropEntry $p } }
            foreach ($rel in $changed) {
                $dst = Join-Path $claudeHome $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item -LiteralPath (Join-Path $stageRoot "runtime\$rel") $dst -Force
            }
            foreach ($rel in $toDelete) { $d = Join-Path $claudeHome $rel; if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Force } }
            if (Test-Path -LiteralPath $settingsPath) { Copy-Item -LiteralPath $settingsPath "$settingsPath.bak-$stamp" }
            [IO.File]::WriteAllText($settingsPath, $newSettingsJson)

            # The ai launcher shim, next to claude.exe (always on PATH).
            if (-not $ClaudeExeDir) { $ce = Get-Command claude -ErrorAction SilentlyContinue; if ($ce) { $ClaudeExeDir = Split-Path $ce.Source } }
            $shims = @()
            if ($ClaudeExeDir -and (Test-Path -LiteralPath (Join-Path $claudeHome 'bin\ai.ps1'))) {
                $cmd = Join-Path $ClaudeExeDir 'ai.cmd'
                $body = "@echo off`r`npwsh -NoProfile -NoLogo -File `"$(Join-Path $claudeHome 'bin\ai.ps1')`" %*`r`n"
                if (-not (Test-Path -LiteralPath $cmd) -or [IO.File]::ReadAllText($cmd) -ne $body) { [IO.File]::WriteAllText($cmd, $body) }
                $shims += $cmd
            }

            # Scratch folders the settings point at.
            foreach ($d in @($prof.Keys['ScratchRoot'], (Join-Path $prof.Keys['ScratchRoot'] 'temp'), $prof.Keys['WorktreesRoot'])) { if ($d) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

            # 7. State, last.
            $files = [ordered]@{}
            if ($settingsOnly -and $state) { $files = $state.files } else { foreach ($rel in $plan.Keys) { $files[$rel] = $hashes[$rel] } }
            $sessions = if ($state -and $state.Contains('sessions')) { $state.sessions } else { [ordered]@{} }
            $newState = [ordered]@{
                identity          = $identity
                installedAt       = (Get-Date).ToString('o')
                installerVersion  = $InstallerVersion
                profilePath       = $prof.Path
                profileHash       = $prof.Hash
                corpusRoot        = $CorpusRoot
                settingsOnly      = $settingsOnly
                claudeVersion     = $claudeVersion
                files             = $files
                linkRoot          = $(if ($settingsOnly -and $state -and $state.Contains('linkRoot')) { $state.linkRoot } else { $linkRoot })
                linkItems         = $(if ($settingsOnly -and $state -and $state.Contains('linkItems')) { @($state.linkItems) } else { @($linkItems.Keys) })
                owned             = $render.Owned
                settingsOwnedHash = (Get-StringSha $newOwnedSnap)
                lastSettings      = [ordered]@{ allow = @($render.Settings.permissions.allow); ask = @($render.Settings.permissions.ask); deny = @($render.Settings.permissions.deny) }
                shims             = $shims
                sessions          = $sessions
            }
            $tmp = "$statePath.tmp"
            ($newState | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
            if ($env:AI_TEST_FAIL_BEFORE_STATE) { throw 'Injected failure before the state record (test).' }
            Move-Item -LiteralPath $tmp $statePath -Force
        }
        catch {
            Write-Host "Apply failed: $_ . Restoring the previous install from $rb." -ForegroundColor Red
            $idx = Get-Content -LiteralPath (Join-Path $rb 'index.json') -Raw | ConvertFrom-Json
            # A path whose item is (still) a link reaches into the link tree: never remove or write through it here.
            foreach ($x in $idx | Where-Object kind -eq 'new') { $d = Join-Path $claudeHome $x.rel; if ((Test-Path -LiteralPath $d) -and -not (& $isItemLink $x.rel)) { Remove-Item -LiteralPath $d -Force } }
            foreach ($x in $idx | Where-Object kind -eq 'file') { $d = Join-Path $claudeHome $x.rel; New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null; Copy-Item -LiteralPath (Join-Path $rb "files\$($x.rel)") $d -Force }
            # R38 items: drop what this apply laid there (a link, or the copy left after a retired link), then restore.
            foreach ($x in $idx | Where-Object kind -eq 'item') {
                $d = Join-Path $claudeHome $x.rel
                $i = Get-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
                if ($i -and $i.LinkType) { if ($i.PSIsContainer) { [IO.Directory]::Delete($d, $false) } else { [IO.File]::Delete($d) } }
                elseif ($i -and $x.was -ne 'real') { if ($i.PSIsContainer) { Remove-Item -LiteralPath $d -Recurse -Force } else { Remove-Item -LiteralPath $d -Force } }
                if ($x.was -eq 'link' -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType $(if ($x.type -eq 'Junction') { 'Junction' } else { 'SymbolicLink' }) -Path $d -Target $x.target | Out-Null }
                elseif ($x.was -eq 'real' -and -not (Test-Path -LiteralPath $d)) { Copy-Item -LiteralPath (Join-Path $rb "items\$($x.rel)") $d -Recurse -Force }
            }
            foreach ($x in $idx | Where-Object kind -eq 'linktree-new') { $t = Join-Path $linkRoot $x.rel; if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force } }
            foreach ($x in $idx | Where-Object kind -eq 'linktree-file') { $t = Join-Path $linkRoot $x.rel; New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null; Copy-Item -LiteralPath (Join-Path $rb "linktree\$($x.rel)") $t -Force }
            foreach ($x in $idx | Where-Object kind -eq 'link') {
                $d = Join-Path $claudeHome $x.rel
                if (Test-Path -LiteralPath $d) {
                    $it = Get-Item -LiteralPath $d -Force
                    if (-not $it.LinkType) {
                        # Only the runtime copy we laid down lives here (plus carried-over unmanaged folders, which exist in the target).
                        if ($it.PSIsContainer) { Remove-Item -LiteralPath $d -Recurse -Force } else { Remove-Item -LiteralPath $d -Force }
                    }
                }
                if (-not (Test-Path -LiteralPath $d)) {
                    $t = if ($x.type -eq 'Junction') { 'Junction' } else { 'SymbolicLink' }
                    New-Item -ItemType $t -Path $d -Target $x.target | Out-Null
                }
            }
            if (Test-Path -LiteralPath "$statePath.tmp") { Remove-Item -LiteralPath "$statePath.tmp" -Force }
            throw
        }
    }
    finally { $lock.Dispose() }

    # MCP servers and secrets (R15, R16): only servers that are missing, or all of them with -SecretsFile.
    if (-not $SkipMcp) {
        $mcpScript = Join-Path $PSScriptRoot 'Install-AIMcp.ps1'
        if (Test-Path -LiteralPath $mcpScript) {
            $ma = @{ TemplatePath = (Join-Path $templateDir 'mcp-servers.json') }
            if ($ConfigPath) { $ma.ConfigPath = $ConfigPath }
            if ($SecretsFile) { $ma.SecretsFile = $SecretsFile }
            if ($manifest) { $ma.SecretEnv = @($manifest.secretEnv) }
            & $mcpScript @ma
        }
    }

    # Report: what is live now and what needs a fresh launch.
    if (-not $Launch) {
        $oldS = $currentSettings; $newS = $render.Settings
        $fresh = @()
        if (($oldS['env'] | ConvertTo-Json -Compress -Depth 5) -ne ($newS['env'] | ConvertTo-Json -Compress -Depth 5)) { $fresh += 'env (AI_*, TEMP/TMP, CLAUDE_CODE_TMPDIR)' }
        if (($oldS['hooks'] | ConvertTo-Json -Compress -Depth 20) -ne ($newS['hooks'] | ConvertTo-Json -Compress -Depth 20)) { $fresh += 'hooks' }
        if ((@($oldS.permissions.additionalDirectories) -join '|') -ne (@($newS.permissions.additionalDirectories) -join '|')) { $fresh += 'additionalDirectories' }
        Write-Host "Applied revision $($identity.Substring(0,12)): $($changed.Count) files written, $($toDelete.Count) removed, settings.json written (backup settings.json.bak-$stamp)."
        if ($fresh) { Write-Host "Active only after a fresh launch (start Claude with 'ai'): $($fresh -join ', ')." -ForegroundColor Yellow }
        $live = @(Get-Process claude -ErrorAction SilentlyContinue)
        if ($live.Count) { Write-Host "$($live.Count) running Claude process(es) keep their startup settings until restarted." -ForegroundColor Yellow }
    }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
