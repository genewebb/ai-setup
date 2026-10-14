#requires -Version 7
# Dependency-free hook test harness.
#
# Pester 5 is not available on this machine (only the legacy bundled 3.4.0, which
# uses incompatible `Should Be` syntax), so this rolls its own asserts.
#
# Every case is atomic: it provisions its own session id / environment and cleans
# up after itself, so cases can run in any order and leave no shared state.
#
# Run:  pwsh -NoProfile -File run-hook-tests.ps1

$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $PSScriptRoot
$script:Failures = 0
$script:Ran      = 0

function Test-Hook {
    param(
        [Parameter(Mandatory)] [string]      $Name,
        [Parameter(Mandatory)] [string]      $ScriptPath,
        [Parameter(Mandatory)] [string]      $Json,
        [hashtable]                          $Env = @{},
        [string[]]                           $ArgumentList = @(),
        [Parameter(Mandatory)] [scriptblock] $Expect
    )

    $script:Ran++
    # The child pwsh inherits this process's environment, so a developer session that has silenced a hook for
    # itself (e.g. $env:CLAUDE_DISABLED_HOOKS='gateguard') would silence it under test too and the case would fail
    # for the wrong reason. Clear the switches first; a case that names one in -Env still wins.
    $vars = @{ CLAUDE_DISABLED_HOOKS = '' }
    foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
    $saved = @{}
    foreach ($k in $vars.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $vars[$k])
    }

    try {
        $out = $Json | & pwsh -NoProfile -File $ScriptPath @ArgumentList 2>&1 | Out-String
        $ok  = & $Expect $out
        if ($ok) {
            Write-Host "  PASS  $Name" -ForegroundColor Green
        }
        else {
            Write-Host "  FAIL  $Name" -ForegroundColor Red
            Write-Host "        output: $($out.Trim())" -ForegroundColor DarkGray
            $script:Failures++
        }
    }
    catch {
        Write-Host "  FAIL  $Name (threw: $_)" -ForegroundColor Red
        $script:Failures++
    }
    finally {
        foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

function New-EditJson {
    param(
        [string]$Path,
        [string]$Session = [guid]::NewGuid().ToString(),
        [string]$Tool = 'Edit'
    )
    @{
        session_id      = $Session
        hook_event_name = 'PreToolUse'
        tool_name       = $Tool
        tool_input      = @{ file_path = $Path }
    } | ConvertTo-Json -Compress -Depth 5
}

function Remove-GateGuardState {
    param([string]$Session)
    $dir = Join-Path $env:TEMP "claude-gateguard\$Session"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
}

Write-Host "`nHook tests" -ForegroundColor Cyan
Write-Host "----------"

# --- dispatcher ---------------------------------------------------------
$dispatch = Join-Path $scriptsDir 'hook-dispatch.ps1'

Test-Hook -Name 'dispatch: unknown id is silent' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'does-not-exist') `
    -Json '{"tool_name":"Edit"}' `
    -Expect { param($o) $o.Trim() -eq '' }

Test-Hook -Name 'dispatch: kill switch suppresses the hook' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'gateguard') `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs') `
    -Env @{ CLAUDE_DISABLED_HOOKS = 'gateguard' } `
    -Expect { param($o) $o.Trim() -eq '' }

# This case reaches the real gateguard through the dispatcher, so it creates
# session state. Pin the session id so it can be cleaned up - a passing test
# that leaves residue would let a later run inherit its markers.
$sd = [guid]::NewGuid().ToString()
Test-Hook -Name 'dispatch: kill switch matches whole tokens only' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'gateguard') `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $sd) `
    -Env @{ CLAUDE_DISABLED_HOOKS = 'gateguard-extra,other' } `
    -Expect { param($o) $o -match 'deny' }
Remove-GateGuardState -Session $sd

# The mid-session disable file. Provision and remove it inside the cases so
# the suite never depends on, or leaves behind, a real one.
$offFile = Join-Path (Split-Path $dispatch) '..\hooks-disabled.txt'   # where the dispatcher looks
$offBackup = if (Test-Path $offFile) { Get-Content $offFile -Raw } else { $null }

try {
    Set-Content -LiteralPath $offFile -Value "# test`ngateguard" -Encoding utf8
    $sf = [guid]::NewGuid().ToString()
    Test-Hook -Name 'dispatch: disable-file switch works mid-session' `
        -ScriptPath $dispatch -ArgumentList @('-Id', 'gateguard') `
        -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $sf) `
        -Expect { param($o) $o.Trim() -eq '' }
    Remove-GateGuardState -Session $sf

    Set-Content -LiteralPath $offFile -Value 'gateguard-extra' -Encoding utf8
    $sg = [guid]::NewGuid().ToString()
    Test-Hook -Name 'dispatch: disable-file matches whole tokens only' `
        -ScriptPath $dispatch -ArgumentList @('-Id', 'gateguard') `
        -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $sg) `
        -Expect { param($o) $o -match 'deny' }
    Remove-GateGuardState -Session $sg
}
finally {
    if ($null -ne $offBackup) { Set-Content -LiteralPath $offFile -Value $offBackup -Encoding utf8 }
    elseif (Test-Path $offFile) { Remove-Item -LiteralPath $offFile -Force }
}

# --- gateguard ----------------------------------------------------------
$gate = Join-Path $scriptsDir 'gateguard.ps1'

$s1 = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: first Edit is denied with four facts' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $s1) `
    -Expect { param($o)
        $o -match '"permissionDecision":"deny"' -and
        $o -match 'reference' -and $o -match 'verbatim'
    }

Test-Hook -Name 'gateguard: second Edit of same file falls through' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $s1) `
    -Expect { param($o) $o.Trim() -eq '' }

Test-Hook -Name 'gateguard: path normalisation shares one marker' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'c:/devops/repos/speed-merchants/Foo.cs' -Session $s1) `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-GateGuardState -Session $s1

$s2 = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: Write gate asks the new-file questions' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\New.cs' -Session $s2 -Tool 'Write') `
    -Expect { param($o) $o -match 'no existing file already serves the same purpose' }
Remove-GateGuardState -Session $s2

$s2b = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: label disambiguates repeated file names' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\work-ai\skills\config-gc\SKILL.md' -Session $s2b) `
    -Expect { param($o) $o -match 'config-gc\\\\SKILL\.md' }
Remove-GateGuardState -Session $s2b

$s3 = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: ignored paths are never gated' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\src\obj\Debug\x.g.cs' -Session $s3) `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-GateGuardState -Session $s3

$s3b = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: non-edit tools are ignored' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\Foo.cs' -Session $s3b -Tool 'Read') `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-GateGuardState -Session $s3b

$s4 = [guid]::NewGuid().ToString()
Test-Hook -Name 'gateguard: denial 1 of 4 is the full block' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\A.cs' -Session $s4) `
    -Expect { param($o) $o -match 'deny' -and $o -match 'verbatim' }
foreach ($f in 'B', 'C', 'D') {
    (New-EditJson -Path "C:\devops\repos\speed-merchants\$f.cs" -Session $s4) |
        & pwsh -NoProfile -File $gate | Out-Null
}
Test-Hook -Name 'gateguard: denials condense past the cap' `
    -ScriptPath $gate `
    -Json (New-EditJson -Path 'C:\devops\repos\speed-merchants\E.cs' -Session $s4) `
    -Expect { param($o) $o -match 'deny' -and $o -notmatch 'verbatim' }
Remove-GateGuardState -Session $s4

Test-Hook -Name 'gateguard: malformed json is silent, never blocks' `
    -ScriptPath $gate -Json 'not json at all' `
    -Expect { param($o) $o.Trim() -eq '' }

Test-Hook -Name 'gateguard: missing file_path is silent' `
    -ScriptPath $gate `
    -Json '{"session_id":"x","tool_name":"Edit","tool_input":{}}' `
    -Expect { param($o) $o.Trim() -eq '' }

# --- rationalization-watch ----------------------------------------------
$rw = Join-Path $scriptsDir 'rationalization-watch.ps1'

function New-Transcript {
    # Build a throwaway JSONL transcript containing the given assistant texts.
    param([string[]]$AssistantTexts, [string[]]$RawLines = @())
    $p = Join-Path $env:TEMP ("rw-transcript-{0}.jsonl" -f [guid]::NewGuid())
    $lines = @()
    $lines += ('{"type":"user","message":{"role":"user","content":"do the thing"}}')
    foreach ($t in $AssistantTexts) {
        $lines += (@{
            type    = 'assistant'
            message = @{ role = 'assistant'; content = @(@{ type = 'text'; text = $t }) }
        } | ConvertTo-Json -Compress -Depth 8)
    }
    $lines += $RawLines
    Set-Content -LiteralPath $p -Value $lines -Encoding utf8
    $p
}

function New-StopJson {
    param([string]$Transcript, [string]$Session = [guid]::NewGuid().ToString())
    @{
        session_id      = $Session
        hook_event_name = 'Stop'
        transcript_path = $Transcript
        stop_hook_active = $false
    } | ConvertTo-Json -Compress
}

function Remove-RwState {
    param([string]$Session)
    $d = Join-Path $env:TEMP "claude-rationalization\$Session"
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
}

$t1 = New-Transcript @('I will skip the tests for now and move on.')
$r1 = [guid]::NewGuid().ToString()
Test-Hook -Name 'rationalize: flags a rationalization phrase' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t1 -Session $r1) `
    -Expect { param($o) $o -match 'systemMessage' -and $o -match 'skip the tests for now' }

$rb = [guid]::NewGuid().ToString()
Test-Hook -Name 'rationalize: never emits a block decision' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t1 -Session $rb) `
    -Expect { param($o) $o -match 'systemMessage' -and $o -notmatch '"decision"\s*:\s*"block"' }
Remove-RwState -Session $rb

Test-Hook -Name 'rationalize: same phrase warns only once per session' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t1 -Session $r1) `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-RwState -Session $r1
Remove-Item $t1 -Force

$t2 = New-Transcript @('I ran the full suite and all 16 tests passed. The build is clean.')
$r2 = [guid]::NewGuid().ToString()
Test-Hook -Name 'rationalize: clean transcript stays silent' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t2 -Session $r2) `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-RwState -Session $r2
Remove-Item $t2 -Force

$t3 = New-Transcript @('The scope of this change is the parser. Testing for now-obsolete flags was removed deliberately.')
$r3 = [guid]::NewGuid().ToString()
Test-Hook -Name 'rationalize: innocuous near-miss wording does not fire' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t3 -Session $r3) `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-RwState -Session $r3
Remove-Item $t3 -Force

$t4 = New-Transcript -AssistantTexts @('That is a pre-existing bug, not mine.') -RawLines @('{ this is not valid json', '')
$r4 = [guid]::NewGuid().ToString()
Test-Hook -Name 'rationalize: malformed transcript lines are skipped' `
    -ScriptPath $rw -Json (New-StopJson -Transcript $t4 -Session $r4) `
    -Expect { param($o) $o -match 'pre-existing bug' }
Remove-RwState -Session $r4
Remove-Item $t4 -Force

Test-Hook -Name 'rationalize: missing transcript is silent, never throws' `
    -ScriptPath $rw `
    -Json (New-StopJson -Transcript (Join-Path $env:TEMP 'does-not-exist-xyz.jsonl')) `
    -Expect { param($o) $o.Trim() -eq '' }

Test-Hook -Name 'rationalize: malformed stdin is silent' `
    -ScriptPath $rw -Json 'not json' `
    -Expect { param($o) $o.Trim() -eq '' }

# --- destructive-path-guard --------------------------------------------
# Policy: destructive verbs are silent inside repo/scratch roots, prompt ("ask") outside them.
$dpg = Join-Path $scriptsDir 'destructive-path-guard.ps1'

function New-BashJson {
    param([string]$Command, [string]$Tool = 'Bash')
    @{
        hook_event_name = 'PreToolUse'
        tool_name       = $Tool
        tool_input      = @{ command = $Command }
    } | ConvertTo-Json -Compress -Depth 5
}

# Trusted roots come from this machine's profile (the guard reads the same keys), so the silent cases are built from them.
$mcLib = @((Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Import-Module $mcLib -Force -DisableNameChecking
$rpW = (Get-AIPath ReposRoot).TrimEnd('\'); $rpF = $rpW -replace '\\', '/'; $rpM = '/' + $rpF.Substring(0, 1).ToLowerInvariant() + $rpF.Substring(2)
$wtW = (Get-AIPath WorktreesRoot).TrimEnd('\'); $scW = (Get-AIPath ScratchRoot).TrimEnd('\'); $tmpW = [IO.Path]::GetTempPath().TrimEnd('\')
$dpgSilent = @(
    "rm -rf $rpF/speedmerchants/bin",
    "cd $rpM/speedmerchants && rm -rf src/obj",
    'rm -rf src/obj bin/Debug',
    "Remove-Item -Recurse -Force $tmpW\claude\x\scratchpad\trx",
    'rm -rf /tmp/cx/out',
    'grep -n rm C:\Users\agenewe\.claude\memory\foo.md',
    'echo rd; cat C:\Users\agenewe\.claude\x',
    "D=$rpM/speed-merchants; git -C `$D show HEAD:CrewChief/x.cs",
    "find $rpF/x -name `"*.tmp`" -delete",
    "dotnet test $rpW\speedmerchants\tests\Tests.Unit --filter FullyQualifiedName~Reference",
    "Remove-Item -LiteralPath $wtW\x\bin -Recurse",
    'cmd /c mklink /J "$t\tree\sub\link" "$t\target" | Out-Null; Remove-Item -LiteralPath "$t\tree" -Recurse -Force',
    "cmd /c rd /s /q $scW\x",
    "robocopy $scW\a $scW\b /MIR /R:1; Remove-Item $scW\a -Recurse"
)
# Rows with the delete right (whole working trees, ~\.claude) are trusted too; their cases are built from this
# machine's rows. The 8.3 form of THIS profile expands to the same root as its long spelling; another account's
# short name does not.
$delRows = @((Get-AIMachineProfile).Access | Where-Object { $_.Path -and 'delete' -in $_.Access -and 'edit' -in $_.Access })
foreach ($r in $delRows) { $dpgSilent += "rm -rf $(($r.Path.TrimEnd('\')) -replace '\\', '/')/x/build-output" }
$usersW = Split-Path $env:USERPROFILE; $meLeaf = Split-Path $env:USERPROFILE -Leaf
$homeDel = $delRows | Where-Object { $_.Path.StartsWith($env:USERPROFILE + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
$dpgAskExtra = @("rm -rf $usersW\OTHERU~1\.claude\x")
if ($homeDel) {
    $short = $meLeaf.Substring(0, [Math]::Min(6, $meLeaf.Length)).ToUpperInvariant() + '~1'
    $dpgSilent += "rm -rf $(Join-Path (Join-Path $usersW $short) $homeDel.Path.Substring($env:USERPROFILE.Length + 1))\x"
}
else { Write-Host '  (no delete row under this profile: the 8.3 case is skipped)' -ForegroundColor DarkGray }
foreach ($c in $dpgSilent) {
    Test-Hook -Name "dpg: silent | $c" -ScriptPath $dpg -Json (New-BashJson $c) `
        -Expect { param($o) $o.Trim() -eq '' }
}

$dpgAsk = @(
    'rm -rf C:\Users\agenewe\Documents\stuff',
    'cd /q/Work/Work && rm old.md',
    'Remove-Item -LiteralPath "C:\Program Files\x" -Recurse',
    'Remove-Item -LiteralPath:C:\Windows\Temp\x -Recurse',
    'rm -rf ~/junk',
    'rm -rf $env:USERPROFILE\junk',
    'find /c/Users/agenewe/Downloads -name "*.tmp" -delete',
    'del \\server\share\f.txt',
    'rm -rf /',
    'rm -rf C:\',
    'ls C:\devops\repos | xargs rm -f /etc/hosts',
    'cat C:\Users\agenewe\x.txt; rm -rf ./build',
    'rm -rf /c',
    'Remove-Item -LiteralPath C:\devopslocal\repos\x\bin -Recurse',   # retired root: no longer trusted
    'cmd /c echo x; rm -rf /c',
    'cmd /c rd /s /q C:\Users\agenewe\Documents\x'
) + $dpgAskExtra
foreach ($c in $dpgAsk) {
    Test-Hook -Name "dpg: ask    | $c" -ScriptPath $dpg -Json (New-BashJson $c) `
        -Expect { param($o) $o -match '"permissionDecision":\s*"ask"' }
}

Test-Hook -Name 'dpg: malformed stdin is silent' -ScriptPath $dpg -Json 'not json' `
    -Expect { param($o) $o.Trim() -eq '' }

# Heredoc and here-string bodies are data: the 2026-10-04 builder hang ("/obj/" in a C# string inside <<'XEOF').
$hereData = @(
    "cd `"$($tmpW -replace '\\', '/')/claude/x/scratchpad/probe2`" && rm -rf old && mkdir old && cat > Program.cs <<'XEOF'`nusing Probe;`nvar all = files.Where(p => !p.Contains(`"/obj/`") && !p.Contains(`"\\bin\\`"));`nXEOF`necho ok",
    "rm -rf build && cat > notes.txt <<EOF`nsee /etc/hosts and C:\Windows\x`nEOF",
    "rm -rf build; python - <<-'PY'`n`timport os; os.remove('/etc/x')`n`tPY",
    "Remove-Item build -Recurse; Set-Content x.txt @'`nC:\Users\agenewe\Documents\x`n'@"
)
foreach ($c in $hereData) {
    Test-Hook -Name "dpg: silent | heredoc data: $(($c -split "`n")[0].Substring(0, [Math]::Min(60, ($c -split "`n")[0].Length)))" -ScriptPath $dpg -Json (New-BashJson $c) `
        -Expect { param($o) $o.Trim() -eq '' }
}
Test-Hook -Name 'dpg: ask    | a real outside rm after a heredoc still prompts' -ScriptPath $dpg `
    -Json (New-BashJson "cat > a.txt <<EOF`nx`nEOF`nrm -rf C:\Users\agenewe\Documents\stuff") `
    -Expect { param($o) $o -match '"permissionDecision":\s*"ask"' }

# --- credentials-guard ---------------------------------------------------
$cg = Join-Path $scriptsDir 'credentials-guard.ps1'

$cgDeny = @(
    @{ Tool = 'Read';  Json = (New-EditJson -Tool 'Read' -Path 'C:\devopslocal\ObsidianVaults\Work\MyWorkVault\00 Credentials\vpn.md') },
    @{ Tool = 'Edit';  Json = (New-EditJson -Tool 'Edit' -Path 'Q:\Work\Work\00 Credentials\notes.md') },
    @{ Tool = 'Grep';  Json = (@{ tool_name = 'Grep'; tool_input = @{ pattern = 'pw'; path = '/q/Work/Work/00 Credentials' } } | ConvertTo-Json -Compress) },
    @{ Tool = 'Bash';  Json = (New-BashJson 'cat "/c/devopslocal/ObsidianVaults/Work/MyWorkVault/00 Credentials/vpn.md"') },
    @{ Tool = 'Bash';  Json = (New-BashJson 'ls Q:/Work/Work/00%20Credentials') },
    @{ Tool = 'PowerShell'; Json = (New-BashJson -Tool 'PowerShell' 'Get-Content "\\SynologyDS918\obsidian\Work\Work\00_Credentials\x.md"') }
)
foreach ($c in $cgDeny) {
    Test-Hook -Name "cg: deny   | $($c.Tool) $($c.Json.Substring(0, [Math]::Min(70, $c.Json.Length)))" -ScriptPath $cg -Json $c.Json `
        -Expect { param($o) $o -match '"permissionDecision":\s*"deny"' }
}

$cgSilent = @(
    (New-EditJson -Tool 'Read' -Path 'C:\devopslocal\ObsidianVaults\Work\MyWorkVault\03 Shared\Memory\x.md'),
    (New-EditJson -Tool 'Edit' -Path 'Q:\Work\Work\99 Documentation\speed-merchants\vNext\plan.md'),
    (New-BashJson 'grep -rn credentials C:/devops/repos/speedmerchants/src'),
    (New-BashJson 'cd C:/devops/repos/speedmerchants && git status --porcelain'),
    'not json'
)
foreach ($j in $cgSilent) {
    Test-Hook -Name "cg: silent | $($j.Substring(0, [Math]::Min(70, $j.Length)))" -ScriptPath $cg -Json $j `
        -Expect { param($o) $o.Trim() -eq '' }
}

Test-Hook -Name 'cg: reachable through the dispatcher' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'credentials-guard') `
    -Json (New-EditJson -Tool 'Read' -Path 'C:\devopslocal\ObsidianVaults\Work\MyWorkVault\00 Credentials\vpn.md') `
    -Expect { param($o) $o -match '"permissionDecision":\s*"deny"' }

Test-Hook -Name 'dpg: reachable through the dispatcher' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'destructive-path-guard') `
    -Json (New-BashJson 'rm -rf C:\Users\agenewe\Documents\stuff') `
    -Expect { param($o) $o -match '"permissionDecision":\s*"ask"' }

# --- remember-hook-timeout ----------------------------------------------
# Self-heal of the remember plugin's SessionEnd hook timeout. Each case builds
# its own throwaway plugins dir (installed_plugins.json + hooks/hooks.json) and
# points the script at it via CLAUDE_PLUGINS_DIR, so the real cache is never
# touched and no case depends on another.
$rht = Join-Path $scriptsDir 'remember-hook-timeout.ps1'

function New-RememberFixture {
    param([string]$HooksJson)
    $dir = Join-Path $env:TEMP ("rht-{0}" -f [guid]::NewGuid())
    $install = Join-Path $dir 'cache\remember\9.9.9'
    New-Item -ItemType Directory -Path (Join-Path $install 'hooks') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $install 'hooks\hooks.json') -Value $HooksJson -Encoding utf8
    @{ version = 2; plugins = @{ 'remember@claude-plugins-official' = @(@{ scope = 'user'; installPath = $install; version = '9.9.9' }) } } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dir 'installed_plugins.json') -Encoding utf8
    [pscustomobject]@{ Dir = $dir; HooksFile = (Join-Path $install 'hooks\hooks.json') }
}

$rhtNoTimeout = @'
{ "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-start-hook.sh\"" } ] } ],
    "SessionEnd":   [ { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-end-hook.sh\"" } ] } ]
} }
'@

$fx1 = New-RememberFixture -HooksJson $rhtNoTimeout
Test-Hook -Name 'rht: adds timeout when missing, stdout stays empty' `
    -ScriptPath $rht -Json '{"hook_event_name":"SessionStart","source":"startup"}' `
    -Env @{ CLAUDE_PLUGINS_DIR = $fx1.Dir } `
    -Expect { param($o)
        $after = Get-Content -LiteralPath $fx1.HooksFile -Raw | ConvertFrom-Json
        $end   = $after.hooks.SessionEnd[0].hooks[0]
        $start = $after.hooks.SessionStart[0].hooks[0]
        $o -match 'patched' -and $end.timeout -eq 15 -and
        -not $start.PSObject.Properties['timeout'] -and
        $end.command -eq 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-end-hook.sh"'
    }
Test-Hook -Name 'rht: second run is a silent no-op' `
    -ScriptPath $rht -Json '{"hook_event_name":"SessionStart","source":"startup"}' `
    -Env @{ CLAUDE_PLUGINS_DIR = $fx1.Dir } `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-Item -LiteralPath $fx1.Dir -Recurse -Force

$fx2 = New-RememberFixture -HooksJson ($rhtNoTimeout -replace 'session-end-hook.sh\\""', 'session-end-hook.sh\"", "timeout": 30')
Test-Hook -Name 'rht: larger existing timeout is left alone' `
    -ScriptPath $rht -Json '{}' `
    -Env @{ CLAUDE_PLUGINS_DIR = $fx2.Dir } `
    -Expect { param($o)
        $after = Get-Content -LiteralPath $fx2.HooksFile -Raw | ConvertFrom-Json
        $o.Trim() -eq '' -and $after.hooks.SessionEnd[0].hooks[0].timeout -eq 30
    }
Remove-Item -LiteralPath $fx2.Dir -Recurse -Force

$fx3 = New-RememberFixture -HooksJson $rhtNoTimeout
Test-Hook -Name 'rht: reachable through the dispatcher' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'remember-hook-timeout') `
    -Json '{"hook_event_name":"SessionStart"}' `
    -Env @{ CLAUDE_PLUGINS_DIR = $fx3.Dir } `
    -Expect { param($o) (Get-Content -LiteralPath $fx3.HooksFile -Raw | ConvertFrom-Json).hooks.SessionEnd[0].hooks[0].timeout -eq 15 }
Remove-Item -LiteralPath $fx3.Dir -Recurse -Force

$rhtEmpty = Join-Path $env:TEMP ("rht-empty-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $rhtEmpty -Force | Out-Null
Test-Hook -Name 'rht: missing installed_plugins.json is silent' `
    -ScriptPath $rht -Json 'not json' `
    -Env @{ CLAUDE_PLUGINS_DIR = $rhtEmpty } `
    -Expect { param($o) $o.Trim() -eq '' }
Remove-Item -LiteralPath $rhtEmpty -Recurse -Force

Write-Host ""
if ($script:Failures -gt 0) {
    Write-Host "$script:Failures of $script:Ran failed" -ForegroundColor Red
    exit 1
}
Write-Host "all $script:Ran passed" -ForegroundColor Green
exit 0
