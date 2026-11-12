# The generator puts two lines above this text: $Mode (Wait, Final, Server or Instance) and $Minutes.
#   Wait     ask until every check is Healthy, for $Minutes; still not healthy = say so and end green (a restart follows)
#   Final    the same wait after the restart; still not healthy = fail
#   Server   ask once; print the short name of the application server when a check is not Healthy, nothing when all are
#   Instance print the instance name
# The server and the instance are read from the address itself, so a restart can only hit the instance that was asked.
$ErrorActionPreference = 'Stop'
$base = '{{ProfiseeBaseUrl}}'.TrimEnd('/')
$url = $base + '/health'
$address = [uri]$base

function Get-Down {
    # Names of the checks that are not Healthy (or why the address did not answer); nothing when every check is Healthy.
    try {
        $r = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 60
        $checks = ($r.Content | ConvertFrom-Json).healthChecks
        if (-not $checks) { return @("no healthChecks in HTTP $([int]$r.StatusCode) response") }
        $script:count = @($checks.PSObject.Properties).Count
        return @($checks.PSObject.Properties | Where-Object { $_.Value.status -ne 'Healthy' } | ForEach-Object { $_.Name })
    }
    catch { return @($_.Exception.Message) }
}

if ($Mode -eq 'Instance') {
    $parts = @($address.AbsolutePath.Trim('/') -split '/' | Where-Object { $_ })
    if ($parts.Count -lt 2 -or $parts[-1] -ne 'rest') {
        throw "cannot tell the instance from the address ${base}: it must read https://<application server>/<instance>/rest."
    }
    $parts[0..($parts.Count - 2)] -join '/'
    return
}

if ($Mode -eq 'Server') {
    $down = @(Get-Down)
    if ($down) {
        if ($address.HostNameType -eq 'Dns' -and $address.Host.Contains('.')) { $address.Host.Split('.')[0] } else { $address.Host }
    }
    return
}

$deadline = (Get-Date).AddMinutes($Minutes)
while ($true) {
    $down = @(Get-Down)
    if (-not $down) { "All $count health checks Healthy at $url."; return }
    "Not healthy yet: $($down -join ', ')"
    if ((Get-Date) -ge $deadline) { break }
    Start-Sleep -Seconds 15
}
if ($Mode -eq 'Wait') {
    "Still not healthy after $Minutes minutes at ${url}: $($down -join ', '). The instance is restarted once, then the wait starts again."
    return
}
throw "Services still not healthy $Minutes minutes after one restart of the instance at ${url}: $($down -join ', ')"
