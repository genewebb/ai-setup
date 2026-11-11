$url = '{{ProfiseeBaseUrl}}'.TrimEnd('/') + '/health'
$deadline = (Get-Date).AddMinutes(10)
do {
    $down = @()
    try {
        $r = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 120
        $checks = ($r.Content | ConvertFrom-Json).healthChecks
        $down = @($checks.PSObject.Properties | Where-Object { $_.Value.status -ne 'Healthy' } | ForEach-Object { $_.Name })
        if (-not $checks) { $down = @("no healthChecks in HTTP $([int]$r.StatusCode) response") }
    }
    catch { $down = @($_.Exception.Message) }
    if (-not $down) { "All $(@($checks.PSObject.Properties).Count) health checks Healthy at $url."; return }
    "Not healthy yet: $($down -join ', ')"
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)
throw "Services still not healthy after 10 minutes at ${url}: $($down -join ', ')"