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
    # A stream unit's own STREAM_UNIT_SESSION / STREAM_UNIT_OUT would also leak in: the log line would read
    # unit=<that session> and every test approval would land in the live unit's approvals log. Clear them too.
    $vars = @{ CLAUDE_DISABLED_HOOKS = ''; STREAM_UNIT_SESSION = ''; STREAM_UNIT_OUT = '' }
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
$wtW = (Get-AIPath WorktreesRoot).TrimEnd('\'); $scW = (Get-AIPath ScratchRoot).TrimEnd('\'); $scF = $scW -replace '\\', '/'; $tmpW = [IO.Path]::GetTempPath().TrimEnd('\')
$dpgSilent = @(
    "rm -rf $rpF/speedmerchants/bin",
    "cd $rpM/speedmerchants && rm -rf src/obj",
    'rm -rf src/obj bin/Debug',
    # A shell script run INSIDE a container (docker run ... sh -c '...') names container paths: /w/a is no host path
    # while the script itself deletes nothing (kit item IN-20261024162923-3943).
    'rm -f srv.log; MSYS_NO_PATHCONV=1 docker run --rm $SDK sh -c ''mkdir -p /w/a && cd /w/a''',
    'rm -f srv.log; docker exec -i speedy-sql bash -lc "mkdir -p /var/opt/x && ls /var/opt/x"',
    # A docker command's own arguments name the container's file system: --entrypoint /bin/sh, the container side of
    # -v host:/cmd.sh:ro and of docker cp, a script run through a shell function that wraps docker run, and a docker
    # run continued over lines with '\'. On 2026-10-26 Builder 3 sat on prompts for /bin/sh and /cmd.sh beside an
    # in-scratch rm (kit item IN-20261026165829-709d). The host side of a volume is still checked.
    "rm -f $scF/x/w1; docker run --rm --user 1654:1654 -v $scF/x/settings:/settings --entrypoint /bin/sh img:latest -c 'touch /settings/w1 && echo ok'",
    "S=$scF/x; rm -rf `$S; mkdir -p `$S/settings`nrun() { docker run --rm --user 0 --entrypoint /bin/sh \`n -v `$S/settings:/settings -v $scF/cmd.sh:/cmd.sh:ro img:latest `"`$@`"; }`nrun -c 'sh /cmd.sh' >> `$L 2>&1`nrun -c 'stat -c `"%u:%g %n`" /settings /state' >> `$L 2>&1",
    "rm -f x.log; docker cp sm-probe:/var/log/a.log $scF/a.log",
    # A container script that STARTS with a container path ('/opt/mssql-tools18/bin/sqlcmd ...') read as one POSIX
    # absolute beside an in-scratch rm on another line, and held Builder 2 on a prompt (kit item IN-20261026174134-8d0e).
    "rm -rf /d/tmp/t/run5 && mkdir -p /d/tmp/t/run5`nsleep 1; until [ -f /d/tmp/t/run5/a.txt ]; do sleep 5; done; docker exec w-1 sh -c '/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P `"`$P`" -Q `"select 1`"' 2>&1 | head -24",
    "rm -f x.log; cd /d/tmp; docker run -d --name p --network n -p 127.0.0.1::18443 alpine:3.20 nc -ll -p 18443 -e nc coordinator 8443 >/dev/null; P=`$(docker port p 18443/tcp | head -1 | sed 's/.*://'); curl -sk https://localhost:`$P/worker/claim; docker exec p sh -c 'echo | nc -w3 coordinator 8443 | wc -c'; docker rm -f p >/dev/null",
    # A script piped through a here-doc (pwsh -File /dev/stdin <<'EOF') names a stream, not a file, beside an in-repo rm;
    # it held Builder 2 on a prompt on 2026-10-26 (kit item IN-20261027020941-131c).
    "cd /d/tmp/g; pwsh -NoProfile -File /dev/stdin <<'EOF'
'ok'
EOF
rm -f /d/devops/repos/speedmerchants/.streams/logs/x.i2*; bash /dev/stdin < /dev/null",
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
    "robocopy $scW\a $scW\b /MIR /R:1; Remove-Item $scW\a -Recurse",
    # A quoted nested command is checked token by token: the 2026-10-18 builder hang read the whole
    # "(Start-Process ... 'C:/...' ...).Id" string as one token, stopped its option prefix at the drive colon and
    # took "/Users/..." for a POSIX absolute (kit item IN-20261018050026-e429).
    "cd $rpM/speedmerchants && rm -f .streams/logs/x.txt; pwsh -NoProfile -Command `"(Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File','$($rpF)/x/Invoke-Grader.ps1','-Root','$($wtW -replace '\\', '/')/x' -RedirectStandardOutput '$rpF/speedmerchants/.streams/logs/x.out.txt' -PassThru).Id`"",
    # A URL is not a path: the 2026-10-20 integrator and coordinator stopped on a commit trailer
    # "Claude-Session: https://claude.ai/code/session_..." beside an in-repo rm (kit item IN-20261020133758-c46f).
    "rm -f .streams/x.tmp; git commit -m `"x`" -m `"Claude-Session: https://claude.ai/code/session_019JfT1VU7Z1Lmxrpi7ZQwHh`"",
    'Remove-Item x.tmp; Invoke-RestMethod -Uri https://example.org/a/b',
    # A bash-escaped backslash (D:\\x\\y) is one separator: Builder 4 stopped on its own repo's src\Cli\bin.
    "rm -rf $($rpW -replace '\\', '\\')\\speedmerchants\\src\\Cli\\bin",
    # A sed / awk / perl / grep script is data, not a path: on 2026-10-21 three builders' mutation checks sat 2-3 h on
    # prompts nobody could answer, read as "/s//", "\\u001f" and "/" out of their sed scripts (kit item
    # IN-20261021063004-304d).
    "sed -i '0,/<ItemGroup>/s//<ItemGroup>\n    <FrameworkReference Include=`"Microsoft.AspNetCore.App`" \/>/' src/Agent/Agent.csproj && rm src/Agent/ZzMutation.cs",
    "sed -i 's/Select(copy => copy.Kind + `"\\u001f`" + copy.Hash)/Where(_ => false).Select(copy)/' src/Domain/x.cs; mkdir -p .x; rmdir .x",
    "sed -i '4645s/profiles.Versions/new Dictionary<string, string>()/' src/x.cs; rmdir .streams-tmp",
    "perl -pi -e 's/a/b c()\//' src/x.cs; awk '/^x/ { print `$1 }' f.txt; grep -E `"x | /y/`" f.txt; rm -f f.txt",
    # Quoted prose is not a nested command: on 2026-10-21 an author stalled on "<config>/<tfm>" in an Add-Content
    # value, re-tokenized and split on <> into a bare "/" (kit item IN-20261021183719-aa28).
    "Add-Content -LiteralPath a.md -Value 'find src/Cli/bin/<config>/<tfm> as well'; Remove-Item -Recurse -Force $wtW\x\Cli",
    # A call's quoted argument is data: on 2026-10-21 two authors stalled on "/c" out of x('/c'), and on a comma-list
    # recursion into .Replace(..., 'at <c>b</c>') / '<see cref="X"/>' (kit item IN-20261021201746-bedf).
    "x('/c')`nRemove-Item -Recurse -Force $scW\x",
    "`$g = `$g.Replace('at <c>a</c>','at <c>b</c>')`nRemove-Item -Recurse -Force $scW\x",
    "`$g = [regex]::Replace(`$g,'x','a <c>b</c>'); Remove-Item -Recurse -Force $scW\x",
    "`$b = [regex]::Replace(`$g,'<see cref=`"TheCanvasBlock`"/>','the test'); Remove-Item -Recurse -Force $scW\x",
    # A quoted value that opens with a C# comment ("// x.txt ...") is text, not a UNC root: on 2026-10-23 an author
    # stalled on a Set-Content value beside an in-scratch Remove-Item (kit item IN-20261023124711-6fbc).
    "Remove-Item -Recurse -Force $scW\x; Set-Content `"$scW/x/a.cs`" `"// Baseline.txt NFR-ENGINEERING-001.yaml common-test-fake``nclass A { }`"",
    # A PATH value is a search list, not an operand: on 2026-10-23 a builder stalled on PATH="/c/Windows/System32:..."
    # beside an in-scratch rm -rf (kit item IN-20261023161132-1e65).
    "rm -rf `"$scW/x/a`"; PATH=`"/c/Windows/System32:/c/Windows:/c/Windows/System32/WindowsPowerShell/v1.0`" bash run.sh",
    "rm -rf $scW/x/a; export PATH=/c/Windows/System32:/c/Windows:`$PATH; bash run.sh",
    "rm -rf $scW/x/a; export PATH='/c/Windows/System32:/c/Windows'; bash run.sh",
    "Remove-Item -Recurse -Force $scW\x; `$env:PATH = 'C:\Windows\System32;C:\Windows'; & bash run.sh",
    # A quoted literal appended with + to another value is a suffix, not an absolute path: on 2026-10-23 a builder
    # stalled on python -c "p=sys.argv[1]+'/sim/docs/x.yaml'" beside an in-scratch rm -rf (kit item IN-20261023212118-f23c).
    "rm -rf `"$scW/sim`"; python -I -c `"`nimport sys;p=sys.argv[1]+'/sim/docs/x.yaml';open(p,'wb').write(b'')`" `"$scW`"",
    "Remove-Item -Recurse -Force $scW\x; `$p = `$base + '/sim/x'; `$p += '/y'"
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

# A Bash double-quoted string ends only at an unescaped quote: '\"' inside it split the sed script
# "s/^.*-c\", '//; s/'\]..." so its fragment '//; s/' read as a root target and held a builder on a prompt nobody
# could answer (kit item IN-20261025234510-db78). The PowerShell tool keeps '\' literal, so its '"C:\x\"' still ends there.
$dpgEscQ = @(
    'cd /d/tmp/claude/probe109; grep -m1 ''entrypoint: \["/bin/sh"'' /d/devops/worktrees/speedmerchants/G17.T109/compose.yaml | tr -d ''\r'' | sed -E "s/^.*-c\", ''//; s/''\]\s*\$//; s/\\\$\\\$/\$/g" > cmd.sh; tail -c 120 cmd.sh; echo; rm -f err.txt out.txt; MSYS_NO_PATHCONV=1 bash run.sh > out.txt 2>&1; cat out.txt; wc -l < err.txt; head -3 err.txt',
    'rm -f a.txt; sed -E "s/a\"b//; s/c/d/" f > g'
)
foreach ($c in $dpgEscQ) {
    Test-Hook -Name "dpg: silent | escaped quote: $($c.Substring(0, [Math]::Min(60, $c.Length)))" -ScriptPath $dpg -Json (New-BashJson $c) `
        -Expect { param($o) $o.Trim() -eq '' }
}
Test-Hook -Name 'dpg: ask    | an outside path after an escaped-quote string still prompts (Bash)' -ScriptPath $dpg `
    -Json (New-BashJson 'rm -f a.txt; sed -E "s/a\"b//" f; rm -rf /etc/x') -Expect { param($o) $o -match '"permissionDecision":"ask"' }
Test-Hook -Name 'dpg: ask    | PowerShell tool: a trailing \ does not escape the quote' -ScriptPath $dpg `
    -Json (New-BashJson 'Remove-Item "C:\ok\" ; Remove-Item -Recurse "/c/Windows/x"' -Tool PowerShell) -Expect { param($o) $o -match '"permissionDecision":"ask"' }

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
    'rm -f srv.log; mkdir -p /w/a',                      # host mkdir: cross-statement scan stays
    'rm -rf /w/a',
    'rm -f x.log; docker run --rm img sh -c ''rm -rf /w/a''',   # a container script that deletes keeps its prompt
    'rm -f x.log; docker exec w sh -c ''/opt/x/run.sh; rm -rf /w/a''',   # also when it starts with a path (8d0e)
    # Only the container side of a docker argument is skipped (IN-20261026165829-709d): the host side of a volume, a
    # deleting script run through a docker-wrapping function, and a host rm beside docker still prompt.
    'rm -f x; docker run --rm -v C:/Users/agenewe/Documents:/data img ls /data',
    'rm -f x; docker run --rm -v /etc:/data img ls /data',
    'rm -f x; run() { docker run --rm img "$@"; }; run sh -c ''rm -rf /w/a''',
    'docker run --rm --entrypoint /bin/sh img -c true; rm -rf /bin/sh',
    'rm -rf /c',
    'Remove-Item -LiteralPath C:\devopslocal\repos\x\bin -Recurse',   # retired root: no longer trusted
    'cmd /c echo x; rm -rf /c',
    'cmd /c rd /s /q C:\Users\agenewe\Documents\x',
    'rm -f x.txt; pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList ''-File'',''C:/Users/agenewe/Documents/x.ps1''"',
    'rm -rf C:\\Users\\agenewe\\Documents\\x',          # doubled separators still resolve outside
    'rm -rf file:///C:/Users/agenewe/Documents/x',      # a file URL is a path, not skipped
    # Only a sed / awk / perl / grep SCRIPT is data: a quoted file operand after it is still a path.
    'sed -i ''s/a/b/'' "C:/Users/agenewe/Documents/x.txt"; rm -f y',
    'rm -rf /etc/x; sed -i ''s/a/b/'' f',
    # A launcher's quoted script is still checked token by token (IN-20261021183719-aa28 keeps IN-20261018050026-e429).
    'rm -f x; bash -c "rm -rf /etc/x"',
    'rm -f x; Start-Process pwsh -ArgumentList ''-NoProfile'',''-Command'',''Remove-Item -Recurse C:/Users/agenewe/Documents/x''',
    # A call's drive, UNC or home argument is still a path (IN-20261021201746-bedf skips only a POSIX-form one).
    '$s = [IO.Path]::Combine(''C:\Users\agenewe\Documents'',''x''); Remove-Item -Recurse $s',
    'rm -rf (Join-Path ''/c'' x)',
    # Only '//' followed by whitespace is text (IN-20261023124711-6fbc): a '//server/share' path is still checked.
    'rm -rf //server/share/x',
    'Remove-Item -Recurse "//server/share/x y"',
    # Only the value assigned to PATH is a search list (IN-20261023161132-1e65): a target beside it is still checked.
    'PATH="/c/Windows/System32:/c/Windows" bash x.sh; rm -rf /c/Windows/x',
    'export PATH=/c/Windows; rm -rf "/c/Windows/x"',
    'MYPATH="/c/Windows/x"; rm -rf "/c/Windows/x"',
    # Only a POSIX-form suffix after + is skipped (IN-20261023212118-f23c): a drive value or a literal that LEADS is checked.
    'rm -rf ($x + ''C:\Users\agenewe\Documents\x'')',
    'rm -rf ''/c/Windows/x'' + $y'
) + $dpgAskExtra
foreach ($c in $dpgAsk) {
    Test-Hook -Name "dpg: ask    | $c" -ScriptPath $dpg -Json (New-BashJson $c) `
        -Expect { param($o) $o -match '"permissionDecision":\s*"ask"' }
}

Test-Hook -Name 'dpg: ask    | the reason names the trusted roots (kit item IN-20261020133758-c46f)' -ScriptPath $dpg `
    -Json (New-BashJson 'rm -rf C:\Users\agenewe\Documents\stuff') `
    -Expect { param($o) $o -match 'Trusted roots: [^"]*' + [regex]::Escape(($rpW.ToLowerInvariant() -replace '\\', '\\')) }

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

# --- scoped-autoapprove ---------------------------------------------------
# Policy (Gene 2026-10-17): work inside the repo/scratch roots never waits on a permission prompt; a call that reaches
# outside them, or acts by name (pkill, docker rm, taskkill /IM), keeps its prompt. Every yes is logged. Each case logs
# into a folder of its own and removes it.
$saa = Join-Path $scriptsDir 'scoped-autoapprove.ps1'
$repoCwd = "$rpW\speedmerchants"
function New-PermJson {
    param([string]$Tool, [hashtable]$ToolInput, $Cwd = $repoCwd)
    $o = @{ session_id = 'test-' + [guid]::NewGuid().ToString('N').Substring(0, 8); hook_event_name = 'PermissionRequest'; tool_name = $Tool; tool_input = $ToolInput }
    if ($null -ne $Cwd) { $o.cwd = $Cwd }
    $o | ConvertTo-Json -Compress -Depth 5
}
function New-SaaLogDir { $d = Join-Path $env:TEMP ('saa-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d -Force | Out-Null; $d }
$saaAllow  = { param($o) ($o -match '"hookEventName":\s*"PermissionRequest"') -and ($o -match '"behavior":\s*"allow"') }
$saaSilent = { param($o) $o.Trim() -eq '' }

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a redirect into the repo from the repo is allowed and logged' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = "echo hi > $rpF/speedmerchants/.streams/logs/x.txt && cat $rpF/speedmerchants/.streams/logs/x.txt" }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } `
    -Expect { param($o) (& $saaAllow $o) -and ((Get-ChildItem $saaDir -Filter '*.log' | Get-Content) -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ALLOW unit=- session=test-\w+ tool=Bash cwd=.* :: echo hi >') }
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a Monitor loop polling a grader by PID and tailing a repo log is allowed' `
    -ScriptPath $saa -Json (New-PermJson 'Monitor' @{ command = "while kill -0 45500 || tasklist //FI `"PID eq 45500`" | grep -q 45500; do sleep 15; done; tail -c 1500 $rpF/speedmerchants/.streams/logs/G9.T029.grader.red-check.txt" }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: PowerShell with a variable, reading and removing under scratch, is allowed' `
    -ScriptPath $saa -Json (New-PermJson 'PowerShell' @{ command = "`$v = Get-Content $scW\x\a.json -Raw; Remove-Item $scW\x\b -Recurse -Force; `$v.Length" } -Cwd "$scW\x") `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a kill by PID is allowed (only a kill by name keeps its prompt)' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'kill -9 4242; taskkill /PID 4242 /T /F' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: an outside path inside a heredoc body is data, the call is allowed' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = "cat <<'EOF' > $rpF/speedmerchants/notes.md`nsee $usersW\OTHERU~1\x`nEOF" }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: an Edit under the worktrees root is allowed' `
    -ScriptPath $saa -Json (New-PermJson 'Edit' @{ file_path = "$wtW\G9.T001\src\Web\Program.cs"; old_string = 'a'; new_string = 'b' } -Cwd "$wtW\G9.T001") `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

# Owner 2026-10-17: a folder the agents routinely read or write OUTSIDE the repo and scratch areas (an access row with
# the edit right but not the delete right, such as a vault or the deploy folder) is treated the same for the yes.
$editOnlyRow = (Get-AIMachineProfile).Access | Where-Object { $_.Path -and 'edit' -in $_.Access -and 'delete' -notin $_.Access -and 'deny' -notin $_.Access } | Select-Object -First 1
if ($editOnlyRow) {
    $saaDir = New-SaaLogDir
    Test-Hook -Name "saa: a write into an edit-right access row outside repo/scratch is allowed ($($editOnlyRow.Path))" `
        -ScriptPath $saa -Json (New-PermJson 'PowerShell' @{ command = "Set-Content -LiteralPath '$($editOnlyRow.Path.TrimEnd('\'))\x\status.md' -Value 'ok'" }) `
        -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
    Remove-Item -LiteralPath $saaDir -Recurse -Force
}
$readOnlyRow = (Get-AIMachineProfile).Access | Where-Object { $_.Path -and 'read' -in $_.Access -and 'edit' -notin $_.Access -and 'deny' -notin $_.Access } | Select-Object -First 1
if ($readOnlyRow) {
    $saaDir = New-SaaLogDir
    Test-Hook -Name "saa: a read under a read-right access row is allowed ($($readOnlyRow.Path))" `
        -ScriptPath $saa -Json (New-PermJson 'Read' @{ file_path = "$($readOnlyRow.Path.TrimEnd('\'))\x\notes.md" }) `
        -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
    Remove-Item -LiteralPath $saaDir -Recurse -Force
}

$saaDir = New-SaaLogDir
$saaOut = Join-Path $saaDir 'unit-result.json'
Test-Hook -Name 'saa: inside a stream unit the yes is also logged beside the unit result, tagged with the unit' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'dotnet test tests/Tests.Unit --no-build' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir; STREAM_UNIT_OUT = $saaOut; STREAM_UNIT_SESSION = 'build-202610171500-ab12' } `
    -Expect { param($o) (& $saaAllow $o) -and (Test-Path "$saaOut.approvals.log") -and ((Get-Content "$saaOut.approvals.log") -match 'ALLOW unit=build-202610171500-ab12 .* tool=Bash .* :: dotnet test') }
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a path under another account''s profile keeps its prompt' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = "cat $usersW\OTHERU~1\Documents\notes.txt" }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } `
    -Expect { param($o) (& $saaSilent $o) -and -not (Get-ChildItem $saaDir -Filter '*.log') }
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a working directory outside the roots keeps its prompt, even for a harmless command' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'echo hi' } -Cwd 'C:\Windows\Temp') `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: a payload with no working directory keeps its prompt (fail closed)' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'echo hi' } -Cwd $null) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
foreach ($c in @('pkill -f python', 'sudo killall dotnet', 'taskkill /F /IM dotnet.exe', 'Stop-Process -Name dotnet -Force', 'Get-Process testhost | Stop-Process -Force', 'docker compose down', 'docker rm -f speedy-sql', 'netsh advfirewall set allprofiles state off', 'icacls C:\devops\repos\x /grant Everyone:F', 'schtasks /delete /tn x /f', 'net user guest /active:yes', "cd $rpF/speedmerchants && docker system prune -af")) {
    Test-Hook -Name "saa: acts by name or machine-wide, the prompt stays: $c" `
        -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = $c }) `
        -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
}
Test-Hook -Name 'saa: a UNC target keeps its prompt' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'cp \\server\share\x.txt .' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
Test-Hook -Name 'saa: a Write outside the roots keeps its prompt' `
    -ScriptPath $saa -Json (New-PermJson 'Write' @{ file_path = 'C:\Windows\System32\drivers\etc\hosts'; content = 'x' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
Test-Hook -Name 'saa: a tool that is neither a command nor a file tool is left alone' `
    -ScriptPath $saa -Json (New-PermJson 'WebFetch' @{ url = 'https://example.org' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaSilent
Test-Hook -Name 'saa: nothing was logged for a kept prompt' `
    -ScriptPath $saa -Json (New-PermJson 'Bash' @{ command = 'pkill -f python' }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } `
    -Expect { param($o) -not (Get-ChildItem $saaDir -Filter '*.log') }
Remove-Item -LiteralPath $saaDir -Recurse -Force

$saaDir = New-SaaLogDir
Test-Hook -Name 'saa: reachable through the dispatcher' `
    -ScriptPath $dispatch -ArgumentList @('-Id', 'scoped-autoapprove') `
    -Json (New-PermJson 'Bash' @{ command = "git -C $rpF/speedmerchants status --porcelain" }) `
    -Env @{ CLAUDE_AUTOAPPROVE_LOG_DIR = $saaDir } -Expect $saaAllow
Remove-Item -LiteralPath $saaDir -Recurse -Force

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
