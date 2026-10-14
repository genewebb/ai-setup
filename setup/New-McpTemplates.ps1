#requires -Version 7
<#
.SYNOPSIS
    Builds claude\mcp-servers.json (R15) from a machine's ~\.claude.json: every secret field becomes a
    {secret:<server>/<field>} placeholder and machine paths become {Key} tokens. Secret VALUES are never written
    or printed; the output lists secret names only.
#>
param(
    [string]$ClaudeJson = (Join-Path $HOME '.claude.json'),
    [Parameter(Mandatory)][string]$Out,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1') -Force
$pa = @{}; if ($ConfigPath) { $pa.Path = $ConfigPath }
$prof = Get-AIMachineProfile @pa
$pathKeys = @(foreach ($k in $prof.Keys.Keys) { $v = $prof.Keys[$k]; if ($v -and $v -match '^[A-Za-z]:\\') { [pscustomobject]@{ Key = $k; Path = $v.TrimEnd('\') } } }) | Sort-Object { $_.Path.Length } -Descending
function ConvertTo-Keyed([string]$s) {
    if ($s.StartsWith($HOME + '\', [StringComparison]::OrdinalIgnoreCase)) { return '%USERPROFILE%' + $s.Substring($HOME.Length) }
    foreach ($pk in $pathKeys) {
        foreach ($form in $pk.Path, ($pk.Path -replace '\\', '/')) {
            if ($s.StartsWith($form, [StringComparison]::OrdinalIgnoreCase)) { return '{' + $pk.Key + '}' + $s.Substring($form.Length) }
        }
    }
    return $null
}
$secretFlag = '(?i)(token|pat|key|secret|password|pwd|auth)'

$j = Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json -AsHashtable
$servers = [ordered]@{}
$secrets = [System.Collections.Generic.List[string]]::new()
$notes = [System.Collections.Generic.List[string]]::new()
foreach ($name in $j.mcpServers.Keys) {
    $s = $j.mcpServers[$name]
    $t = [ordered]@{}
    foreach ($prop in $s.Keys) {
        switch ($prop) {
            'headers' {
                $h = [ordered]@{}
                foreach ($hk in $s.headers.Keys) { $id = "$name/headers.$hk"; $h[$hk] = "{secret:$id}"; $secrets.Add($id) }
                $t.headers = $h
            }
            'env' {
                $e = [ordered]@{}
                foreach ($ek in $s.env.Keys) {
                    $v = [string]$s.env[$ek]
                    $keyed = if ($v -match '^[A-Za-z]:[\\/]') { ConvertTo-Keyed $v } else { $null }
                    if ($keyed) { $e[$ek] = $keyed }
                    elseif ($v -match '^[A-Za-z]:[\\/]') { $e[$ek] = $v; $notes.Add("$name env $ek is a machine path with no key: kept literally") }
                    else { $id = "$name/env.$ek"; $e[$ek] = "{secret:$id}"; $secrets.Add($id) }
                }
                $t.env = $e
            }
            'args' {
                $a = [System.Collections.Generic.List[string]]::new()
                $prev = ''
                $i = 0
                foreach ($x in @($s.args)) {
                    $x = [string]$x
                    if ($prev -match '^--?' -and $prev -match $secretFlag) { $id = "$name/args.$i"; $a.Add("{secret:$id}"); $secrets.Add($id) }
                    elseif ($x -match '^[A-Za-z]:[\\/]') {
                        $k = ConvertTo-Keyed $x
                        if ($k) { $a.Add($k) } else { $notes.Add("$name arg dropped: '$x' is a machine path with no key") }
                    }
                    else { $a.Add($x) }
                    $prev = $x; $i++
                }
                $t.args = @($a)
            }
            default { $t[$prop] = $s[$prop] }
        }
    }
    $servers[$name] = $t
}
$doc = [ordered]@{
    _comment = 'MCP server templates (R15). {Key} = profile value; {secret:<id>} = a value moved by Export-AISecrets / Install-AIMachine -SecretsFile. No secret value is ever stored here.'
    servers  = $servers
    secrets  = @($secrets)
}
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
[IO.File]::WriteAllText($Out, ($doc | ConvertTo-Json -Depth 10))
"servers: $($servers.Count); secret fields: $($secrets.Count)"
$notes
