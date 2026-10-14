#requires -Version 7
# Spec R15/R16 (5.16 secrets step): Export-AISecrets -> one encrypted file -> Install-AIMcp on a "new machine"
# renders the MCP servers with the secrets and sets the secret user env var. Uses a fake source and target
# .claude.json, a mini template and one throwaway user env var (removed afterwards). Values are synthetic.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$setup = Join-Path $PSScriptRoot '..'
Import-Module (Join-Path $setup '..\lib\AISecrets.psm1') -Force -DisableNameChecking

$root = New-TestRoot 'secrets'
$envName = 'AI_TEST_SECRET_ENV_' + [guid]::NewGuid().ToString('N').Substring(0, 6)
try {
    $corpus = Join-Path $root 'corpus'; New-Item -ItemType Directory -Force (Join-Path $corpus 'claude') | Out-Null
    @{ secretEnv = @($envName) } | ConvertTo-Json | Set-Content (Join-Path $corpus 'ai-manifest.json')
    @{
        secrets = @('svc/headers.x-api-key', 'ado/args.2')
        servers = [ordered]@{
            svc = @{ type = 'http'; url = 'https://svc.example/mcp'; headers = @{ 'x-api-key' = '{secret:svc/headers.x-api-key}' } }
            ado = @{ type = 'stdio'; command = 'npx'; args = @('tool', '--token', '{secret:ado/args.2}'); env = @{} }
            fs  = @{ type = 'stdio'; command = 'npx'; args = @('server-filesystem', '{ReposRoot}'); env = @{} }
        }
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $corpus 'claude\mcp-servers.json')
    # Synthetic secret values (test fixtures, not real credentials).
    $src = Join-Path $root 'source.claude.json'
    @{ mcpServers = @{
            svc = @{ type = 'http'; url = 'https://svc.example/mcp'; headers = @{ 'x-api-key' = 'SYNTH-KEY-123' } }
            ado = @{ type = 'stdio'; command = 'npx'; args = @('tool', '--token', 'SYNTH-PAT-456'); env = @{} }
        } } | ConvertTo-Json -Depth 10 | Set-Content $src
    [Environment]::SetEnvironmentVariable($envName, 'SYNTH-ENV-789', 'User')
    $pass = ConvertTo-SecureString 'correct horse battery' -AsPlainText -Force
    $out = Join-Path $root 'secrets.aisecrets'

    $x = & pwsh -NoProfile -Command "& '$(Join-Path $setup 'Export-AISecrets.ps1')' -Out '$out' -CorpusRoot '$corpus' -ClaudeJson '$src' -Passphrase (ConvertTo-SecureString 'correct horse battery' -AsPlainText -Force)" *>&1
    Test-Case 'export writes one file that holds no plaintext value' {
        Assert-True (Test-Path $out) ($x -join ' ')
        $raw = Get-Content $out -Raw
        foreach ($v in 'SYNTH-KEY-123', 'SYNTH-PAT-456', 'SYNTH-ENV-789') { Assert-NoMatch $raw $v }
        Assert-NoMatch ($x -join ' ') 'SYNTH-'
    }
    Test-Case 'a wrong passphrase is refused' {
        Assert-Throws { Unprotect-AISecrets -Path $out -Passphrase (ConvertTo-SecureString 'wrong passphrase!' -AsPlainText -Force) } '*Wrong passphrase*'
    }
    Test-Case 'the file decrypts to the MCP secrets and the env var' {
        $d = Unprotect-AISecrets -Path $out -Passphrase $pass
        Assert-Equal 'SYNTH-KEY-123' $d.mcp['svc/headers.x-api-key']; Assert-Equal 'SYNTH-PAT-456' $d.mcp['ado/args.2']; Assert-Equal 'SYNTH-ENV-789' $d.env[$envName]
    }

    # ---- the new machine ----
    [Environment]::SetEnvironmentVariable($envName, $null, 'User')
    $cfg = Join-Path $root 'target.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = 'Y:\code'; AIWorkRoot = $corpus; ScratchRoot = 'Y:\s'; WorktreesRoot = 'Y:\w' }) -Sections ([ordered]@{
            'MCP servers' = "| Server | Install | Note |`n|---|---|---|`n| svc | yes | |`n| ado | yes | |`n| fs | yes | |"
        })
    $tgt = Join-Path $root 'target.claude.json'
    $mcp = Join-Path $setup 'Install-AIMcp.ps1'
    $noSecrets = & pwsh -NoProfile -File $mcp -TemplatePath (Join-Path $corpus 'claude\mcp-servers.json') -ConfigPath $cfg -ClaudeJson $tgt *>&1
    Test-Case 'without the secrets file, servers needing a secret are not written and are named' {
        $j = Get-Content $tgt -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($j.mcpServers.Contains('fs') -and -not $j.mcpServers.Contains('svc') -and -not $j.mcpServers.Contains('ado')) ($j.mcpServers.Keys -join ',')
        Assert-Match ($noSecrets -join ' ') 'svc NOT written; missing: svc/headers.x-api-key'
        Assert-Equal 'Y:\code' $j.mcpServers.fs.args[1]
    }
    $withSecrets = & pwsh -NoProfile -Command "& '$mcp' -TemplatePath '$(Join-Path $corpus 'claude\mcp-servers.json')' -ConfigPath '$cfg' -ClaudeJson '$tgt' -SecretsFile '$out' -SecretEnv '$envName' -Passphrase (ConvertTo-SecureString 'correct horse battery' -AsPlainText -Force)" *>&1
    Test-Case 'with the secrets file every server is rendered with its secret' {
        $j = Get-Content $tgt -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal 'SYNTH-KEY-123' $j.mcpServers.svc.headers['x-api-key'] ($withSecrets -join ' ')
        Assert-Equal 'SYNTH-PAT-456' $j.mcpServers.ado.args[2]
        Assert-NoMatch ($withSecrets -join ' ') 'SYNTH-'
    }
    Test-Case 'the secret user env var is set from the file' { Assert-Equal 'SYNTH-ENV-789' ([Environment]::GetEnvironmentVariable($envName, 'User')) }
}
finally {
    [Environment]::SetEnvironmentVariable($envName, $null, 'User')
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
