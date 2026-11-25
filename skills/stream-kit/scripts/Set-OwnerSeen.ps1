# Records the moment the owner last looked at the board, so the status page can show what changed since
# (.streams\owner\last-seen.json, { at, by }; at is UTC ISO-8601). Run it after reading the page; the next page build
# lists the rows and inbox items that moved after that moment. -At sets a given time instead of now (UTC or with an
# offset). Prints SEEN <local time>, exit 0; REFUSED <why>, exit 2, nothing written.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $At,
    [string] $By = 'owner'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$ownerDir = Join-Path $Repo '.streams\owner'
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.streams'))) { "REFUSED no .streams folder under $Repo"; exit 2 }
$when = (Get-Date).ToUniversalTime()
if ($At) {
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($At, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        "REFUSED -At '$At' is not a date and time"; exit 2
    }
    $when = $parsed
}
if (-not (Test-Path -LiteralPath $ownerDir)) { New-Item -ItemType Directory -Force -Path $ownerDir | Out-Null }
$json = [ordered]@{ at = $when.ToString('yyyy-MM-ddTHH:mm:ssZ'); by = $By } | ConvertTo-Json -Compress
Write-AtomicText (Join-Path $ownerDir 'last-seen.json') $json
"SEEN " + (Format-LocalStamp $when)
