'@
$ErrorActionPreference = 'Stop'
$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'
$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }
$testAuto = '{{TestAutoBaseUrl}}'.TrimEnd('/')
function Get-Rows($Response) {
    if ($Response -is [array]) { return $Response }
    if ($Response.PSObject.Properties.Name -contains 'data') { return @($Response.data) }
    throw "Unexpected records response shape: $($Response.PSObject.Properties.Name -join ', ')"
}
$spec = $specJson | ConvertFrom-Json
# The automation ID: this box, the Profisee version in reference data, the workflow key. CrewChief finds the
# workflow by this tag alone (TestAuto GET api/workflows/by-tag: whole tag entry, trimmed, case-insensitive).
$tag = "AUTO:{{$env:COMPUTERNAME}}:{{$ref:connect/environment:ProfiseeVersionCode}}:$($spec.Key)"
$tags = "$tag,$($spec.PlainTags)"
$description = $spec.Description.Replace('<AUTOMATION_ID>', $tag)
$lookup = Invoke-RestMethod -Uri "$testAuto/api/workflows/by-tag?tag=$([uri]::EscapeDataString($tag))" -SkipCertificateCheck
$found = @($lookup.data)
if ($found.Count -gt 1) {
    $list = ($found | ForEach-Object { "$($_.code) '$($_.name)'" }) -join '; '
    throw "$($found.Count) TestAuto workflows carry tag '$tag': $list. Remove the tag from the copies, then run connect-setup again."
}
# Step codes: a deterministic GUID of the automation ID and the step order, so a re-run updates in place and
# another box (another automation ID) never touches these steps.
function Get-StepCode([string]$Seed) {
    $md5 = [Security.Cryptography.MD5]::Create()
    try { [guid]::new($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Seed))).ToString() } finally { $md5.Dispose() }
}
# Every tag on the workflow must exist in the TestAutoTags entity: TestAuto's tag picker and tag filters list
# only those. Add the missing ones (Code = Name = the tag text); never change or delete an existing tag.
foreach ($t in @($tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)) {
    $tagFilter = [uri]::EscapeDataString("[Code] eq '$($t.Replace("'", "''"))'")
    $hit = @(Get-Rows (Invoke-RestMethod -Uri "${base}v1/Records/TestAutoTags?Filter=$tagFilter" -Headers $headers))
    if ($hit.Count -eq 0) {
        Invoke-RestMethod -Method Post -Uri "${base}v1/Records/TestAutoTags" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 3 -InputObject @([ordered]@{ Code = $t; Name = $t })) | Out-Null
        "Added tag '$t' to TestAutoTags"
    }
}
$header = [ordered]@{ Name = $spec.Name; Description = $description; Category = $spec.Category; Tags = $tags; Active = 'Y' }
if ($found.Count -eq 0) {
    $created = Invoke-RestMethod -Method Post -Uri "${base}v1/Records/TestAutoWorkflow" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject @($header))
    $code = @($created.createdRecordCodes)[0]
    if (-not $code) { throw "Creating workflow '$($spec.Name)' ($tag) returned no code." }
    "Created workflow $code '$($spec.Name)' tagged $tag"
}
else {
    $code = $found[0].code
    $header = [ordered]@{ Code = $code } + $header
    Invoke-RestMethod -Method Patch -Uri "${base}v1/Records/TestAutoWorkflow?IsUpsert=true" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject @($header)) | Out-Null
    "Updated workflow $code '$($spec.Name)' tagged $tag"
}
$details = foreach ($d in $spec.Details) {
    [ordered]@{ Code = (Get-StepCode "${tag}:$($d.ExecutionOrder)"); Name = $d.Name; Workflow = $code; ExecutionOrder = $d.ExecutionOrder
        ScenarioDisplayName = $d.Name; ScenarioDisplayDescription = $d.Description; Category = $spec.Category; Tags = $spec.PlainTags
        ProfiseeVersion = $d.ProfiseeVersion; ScenarioConfiguration = $d.ScenarioConfiguration }
}
Invoke-RestMethod -Method Patch -Uri "${base}v1/Records/TestAutoWorkflowDetail?IsUpsert=true&recordsAreSameShape=true" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject @($details)) | Out-Null
$wanted = @($details | ForEach-Object { $_.Code })
$detailFilter = [uri]::EscapeDataString("[Workflow] eq '$code'")
$existing = @(Get-Rows (Invoke-RestMethod -Uri "${base}v1/Records/TestAutoWorkflowDetail?Filter=$detailFilter" -Headers $headers))
$extra = @($existing | ForEach-Object { $_.Code ?? $_.code } | Where-Object { $_ -and $_ -notin $wanted })
if ($extra) {
    Invoke-RestMethod -Method Delete -Uri "${base}v1/Records/TestAutoWorkflowDetail?RecordCodes=$([uri]::EscapeDataString(($extra -join ',')))" -Headers $headers | Out-Null
    "Removed $($extra.Count) stale step(s)"
}
"Workflow $code has $($details.Count) step(s): $(($spec.Details | ForEach-Object Name) -join ' | ')"