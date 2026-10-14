#requires -Version 7
# Spec 5.15 write routing: one ordinary mapped folder (direct) and two vaults (obsidian, separate endpoints and
# tokens). The same file goes to each through Write-AIFile; then one API is stopped and the write must STOP with no
# direct fallback. The two "Obsidian" APIs are minimal fake servers on loopback that write PUT bodies into their vault
# folder and check the bearer. Nothing touches the live vaults or ~\.claude.json.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$lib = Join-Path $PSScriptRoot '..\..\lib'
Import-Module (Join-Path $lib 'MachineConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $lib 'AIFile.psm1') -Force -DisableNameChecking

$fakeServer = {
    param([int]$Port, [string]$VaultDir, [string]$Token, $Ctl)
    $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port); $l.Start()
    while ($true) {
        # Poll, so a stop request closes the socket (a blocked Accept cannot be interrupted).
        while (-not $l.Pending()) { if ($Ctl.Stop) { $l.Stop(); return }; Start-Sleep -Milliseconds 20 }
        $c = $l.AcceptTcpClient()
        try {
            $s = $c.GetStream(); $buf = [IO.MemoryStream]::new(); $one = [byte[]]::new(1)
            while ($true) {   # headers, byte by byte up to CRLFCRLF
                if ($s.Read($one, 0, 1) -le 0) { break }; $buf.WriteByte($one[0])
                $a = $buf.ToArray(); $n = $a.Length
                if ($n -ge 4 -and $a[$n - 4] -eq 13 -and $a[$n - 3] -eq 10 -and $a[$n - 2] -eq 13 -and $a[$n - 1] -eq 10) { break }
            }
            $head = [Text.Encoding]::ASCII.GetString($buf.ToArray()) -split "`r`n"
            $method, $target = ($head[0] -split ' ')[0, 1]
            $hdr = @{}; foreach ($h in $head[1..($head.Count - 1)]) { if ($h -match '^([^:]+):\s*(.*)$') { $hdr[$Matches[1].ToLowerInvariant()] = $Matches[2] } }
            $len = [int]($hdr['content-length'] ?? 0); $body = [byte[]]::new($len); $got = 0
            while ($got -lt $len) { $r = $s.Read($body, $got, $len - $got); if ($r -le 0) { break }; $got += $r }
            $code = '204 No Content'
            if ($hdr['authorization'] -ne "Bearer $Token") { $code = '401 Unauthorized' }
            elseif ($method -ne 'PUT' -or $target -notlike '/vault/*') { $code = '400 Bad Request' }
            else {
                $rel = ([uri]::UnescapeDataString($target.Substring(7))) -replace '/', '\'
                $dst = Join-Path $VaultDir $rel; New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
                [IO.File]::WriteAllBytes($dst, $body)
            }
            $resp = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $code`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            $s.Write($resp, 0, $resp.Length); $s.Flush()
        }
        catch { }
        finally { $c.Close() }
    }
}
function Get-FreePort { $t = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $t.Start(); $p = $t.LocalEndpoint.Port; $t.Stop(); $p }

$root = New-TestRoot 'route'
$jobs = @()
try {
    $direct = Join-Path $root 'mapped'; $vA = Join-Path $root 'vaultA'; $vB = Join-Path $root 'vaultB'
    New-Item -ItemType Directory -Force $direct, $vA, $vB | Out-Null
    $pA = Get-FreePort; do { $pB = Get-FreePort } while ($pB -eq $pA)
    $ctlA = [hashtable]::Synchronized(@{ Stop = $false }); $ctlB = [hashtable]::Synchronized(@{ Stop = $false })
    $jobs += Start-ThreadJob -ScriptBlock $fakeServer -ArgumentList $pA, $vA, 'tokA', $ctlA
    $jobs += Start-ThreadJob -ScriptBlock $fakeServer -ArgumentList $pB, $vB, 'tokB', $ctlB
    $cj = Join-Path $root 'claude.json'
    @{ mcpServers = @{
            vaultA = @{ type = 'http'; url = "http://127.0.0.1:$pA/mcp"; headers = @{ Authorization = 'Bearer tokA' } }
            vaultB = @{ type = 'http'; url = "http://127.0.0.1:$pB/mcp"; headers = @{ Authorization = 'Bearer tokB' } }
        } } | ConvertTo-Json -Depth 5 | Set-Content $cj
    $cfg = Join-Path $root 'profile.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = 'X:\r'; AIWorkRoot = 'X:\a'; ScratchRoot = 'X:\s'; WorktreesRoot = 'X:\w'; MappedRoot = $direct; VaultA = $vA; VaultB = $vB }) -Sections ([ordered]@{
            Resources = "| Key | Route | Obsidian endpoint |`n|---|---|---|`n| MappedRoot | direct | |`n| VaultA | obsidian | http://127.0.0.1:$pA |`n| VaultB | obsidian | http://127.0.0.1:$pB |"
        })
    $prof = Get-AIMachineProfile -Path $cfg
    $text = "routing test é`n" + ('x' * 5000)
    $want = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($text)))
    Start-Sleep -Milliseconds 300

    Test-Case 'the mapped folder is written directly and verified' {
        $r = Write-AIFile -Path (Join-Path $direct 'sub\f.md') -Text $text -Profile $prof -ClaudeJson $cj
        Assert-Equal 'direct' $r.Route; Assert-Equal $want $r.Hash
    }
    Test-Case 'vault A is written through its own API with its own token' {
        $r = Write-AIFile -Path (Join-Path $vA 'notes\f.md') -Text $text -Profile $prof -ClaudeJson $cj -TimeoutSec 10
        Assert-Equal 'obsidian' $r.Route; Assert-Equal $want (Get-FileHash (Join-Path $vA 'notes\f.md')).Hash
    }
    Test-Case 'vault B is written through its own API (a folder name with a space is escaped)' {
        $r = Write-AIFile -Path (Join-Path $vB '99 Docs\f.md') -Text $text -Profile $prof -ClaudeJson $cj -TimeoutSec 10
        Assert-Equal 'obsidian' $r.Route; Assert-Equal $want (Get-FileHash (Join-Path $vB '99 Docs\f.md')).Hash
    }
    Test-Case 'a wrong token is refused and nothing is written' {
        $bad = Join-Path $root 'bad.json'
        (Get-Content $cj -Raw).Replace('Bearer tokB', 'Bearer nope') | Set-Content $bad
        Assert-Throws { Write-AIFile -Path (Join-Path $vB 'x.md') -Text 'x' -Profile $prof -ClaudeJson $bad -TimeoutSec 5 } '*no direct-write fallback*'
        Assert-True (-not (Test-Path (Join-Path $vB 'x.md'))) 'file written despite 401'
    }
    $ctlB.Stop = $true; [void]($jobs[1] | Wait-Job -Timeout 10)
    Test-Case 'with vault B''s API down the write stops and nothing is written directly' {
        Assert-Throws { Write-AIFile -Path (Join-Path $vB 'down.md') -Text 'x' -Profile $prof -ClaudeJson $cj -TimeoutSec 5 } '*no direct-write fallback*'
        Assert-True (-not (Test-Path (Join-Path $vB 'down.md'))) 'fell back to a direct write'
    }
    Test-Case 'vault A still works while B is down' {
        $r = Write-AIFile -Path (Join-Path $vA 'again.md') -Text 'a' -Profile $prof -ClaudeJson $cj -TimeoutSec 10
        Assert-Equal 'obsidian' $r.Route
    }
}
finally {
    foreach ($c in @(Get-Variable ctlA, ctlB -ValueOnly -ErrorAction SilentlyContinue)) { $c.Stop = $true }
    $jobs | Wait-Job -Timeout 10 | Out-Null; $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
