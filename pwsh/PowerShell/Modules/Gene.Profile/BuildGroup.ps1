# prof build: build, run or publish one product, through the dp* commands in the PowerShell profile.
# prof moves this window into the product's repo (from this machine's profile) and leaves it there.
# Every dp* switch still works: anything prof does not know is passed to the product's dp* command as is.

$script:ProfBuildVerbs = [ordered]@{
    compile = 'Build only: compile the product, nothing is published, installed or started'
    run     = 'Build and run it here, the way its dp* command does with no switches'
    publish = 'Make the install package (dp* -Package), optionally raising the version first'
    more    = "Run the product's dp* command with any of its own switches (-Test, -Cli, -CleanBuild ...)"
    containers = 'Speedy only: rebuild the images and restart the local stack on them (dpContainers; -NoBuild = restart only)'
}
$script:ProfBuildDetails = @{
    compile = @(
        'Use it to check that the code compiles. Runs dotnet build on the product''s solution (Debug unless',
        '-Configuration Release). "all" builds TestAuto, CrewChief, DataGen and Mutate in turn.'
    )
    run     = @(
        'Same as typing the dp* command alone (dpspeed, dpcrewchief, dpdatagen, dpmutate, dpv2): for most products',
        'build + publish + start the app here; for speedy (dpv2) rebuild the local containers.',
        'Extra dp* switches may follow (prof build run testauto -CleanBuild).'
    )
    publish = @(
        'Builds the product''s install package and puts it on the team share, as dp* -Package does.',
        '-Bump Patch|Minor|Major raises the version first (7.0.39 -> 7.0.40 | 7.1.0 | 8.0.0); without it the current',
        'version is packaged again. "all" packages all four products (dpall -Package): add -Products testauto,crewchief',
        'to pick some, -Parallel to run them at once. speedy also takes -AllowDirty.'
    )
    containers = @(
        'dpContainers: builds every Speedy image from this tree and restarts the compose stack on them; -NoBuild restarts',
        'on the images already built. prof build run speedy (dpv2) does this too, plus its checks.'
    )
    more    = @(
        'For the switches that are not build/run/publish: prof build more speedy -Test, prof build more crewchief -Cli,',
        'prof build more testauto -UpdateClientId -Run. With no switches it shows the dp* command''s own help.'
    )
}
$script:ProfBuildUsage = @{
    compile = 'prof build compile <product> [-Configuration Debug|Release] [-WhatIf]'
    run     = 'prof build run <product> [-Configuration Debug|Release] [<dp* switches>] [-WhatIf]'
    publish = 'prof build publish <product> [-Bump None|Patch|Minor|Major] [<dp* switches>] [-WhatIf]'
    more    = 'prof build more <product> [<dp* switches>] [-WhatIf]'
    containers = 'prof build containers speedy [-NoBuild] [-WhatIf]'
}

# The products. Repo = key in this machine's profile; Build = solution or project under it (compile);
# VersionFile = where <Version> lives (publish shows it). 'all' is the four speed-merchants products together.
$script:ProfBuildProducts = [ordered]@{
    testauto  = [pscustomobject]@{ Name = 'TestAuto'; Command = 'dpspeed'; Repo = 'SpeedMerchantsRepo'; Build = @('speed-merchants.sln'); VersionFile = 'TestAuto.Web\TestAuto.Web.csproj'; Run = $true; Publish = $true }
    crewchief = [pscustomobject]@{ Name = 'CrewChief'; Command = 'dpcrewchief'; Repo = 'SpeedMerchantsRepo'; Build = @('CrewChief\CrewChief.sln'); VersionFile = 'CrewChief\Directory.Build.props'; Run = $true; Publish = $true }
    datagen   = [pscustomobject]@{ Name = 'DataGen'; Command = 'dpdatagen'; Repo = 'SpeedMerchantsRepo'; Build = @('TestData.Generation\TestData.Generation.sln'); VersionFile = 'TestData.Generation\Directory.Build.props'; Run = $true; Publish = $true }
    mutate    = [pscustomobject]@{ Name = 'Mutate (DataGen + Mutation)'; Command = 'dpmutate'; Repo = 'SpeedMerchantsRepo'; Build = @('TestData.Mutation\TestData.Mutation.sln'); VersionFile = 'TestData.Mutation\Directory.Build.props'; Run = $true; Publish = $true }
    speedy    = [pscustomobject]@{ Name = 'Speedy'; Command = 'dpv2'; Repo = 'SpeedyRepo'; Build = @('Speedmerchants.sln'); VersionFile = 'Directory.Build.props'; Run = $true; Publish = $true }
    all       = [pscustomobject]@{ Name = 'All four (TestAuto, CrewChief, DataGen, Mutate)'; Command = 'dpall'; Repo = 'SpeedMerchantsRepo'; Build = @('speed-merchants.sln', 'CrewChief\CrewChief.sln', 'TestData.Generation\TestData.Generation.sln', 'TestData.Mutation\TestData.Mutation.sln'); VersionFile = ''; Run = $false; Publish = $true }
}

# The products whose dp* command exists in this session. A trimmed copy (prof setup share) ships only the picked dp*
# commands; the menu, the topic names and the product lookup must not offer the others. Checked through the function:
# provider at call time (the profile defines the dp* functions after this module may have loaded).
function Get-GeneBuildProducts {
    $r = [ordered]@{}
    foreach ($k in $script:ProfBuildProducts.Keys) { if (Test-GeneProfFunction -Name $script:ProfBuildProducts[$k].Command) { $r[$k] = $script:ProfBuildProducts[$k] } }
    return $r
}

$script:ProfGroups['build'] = [pscustomobject]@{
    Description = 'Build, run or publish a product (TestAuto, CrewChief, DataGen, Mutate, Speedy, all)'
    Verbs       = $script:ProfBuildVerbs
    Details     = $script:ProfBuildDetails
    Usage       = $script:ProfBuildUsage
    Prefix      = 'Invoke-GeneProfBuild'
    NeedMachine = @()
    Menu        = 'Read-GeneBuildMenu'
    TopicParam  = 'Product'
    TopicNames  = { @((Get-GeneBuildProducts).Keys) }
}

# Old product names still accepted on the command line. dpall -Products keeps its own names (speed for TestAuto):
# prof build publish all -Products testauto,... is translated to them.
$script:ProfBuildAliases = @{ speed = 'testauto' }
$script:ProfBuildDpAllNames = [ordered]@{ testauto = 'speed'; crewchief = 'crewchief'; datagen = 'datagen'; mutate = 'mutate' }

function Get-GeneBuildProduct([string]$Product) {
    $products = Get-GeneBuildProducts
    if (-not $Product) { throw "Which product? One of: $($products.Keys -join ', ') (e.g. prof build publish testauto)" }
    if ($script:ProfBuildAliases.Contains($Product.ToLowerInvariant())) { $Product = $script:ProfBuildAliases[$Product.ToLowerInvariant()] }
    $k = @($products.Keys | Where-Object { $_ -ieq $Product }) | Select-Object -First 1
    if (-not $k) { throw "No product called '$Product' here. One of: $($products.Keys -join ', ')" }
    return $products[$k]
}

function Get-GeneProductVersion($Info) {
    <# The product's current Major.Minor.Patch, or '' when it has no single version file. #>
    if (-not $Info.VersionFile) { return '' }
    $f = Join-Path (Get-GeneLocalPath $Info.Repo) $Info.VersionFile
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $m = [regex]::Match((Get-Content -LiteralPath $f -Raw), '<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)\s*</Version>')
    if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

function Get-GeneBumpedVersion([string]$Version, [string]$Bump) {
    if (-not $Version -or $Bump -in '', 'None') { return $Version }
    $a = @($Version.Split('.') | ForEach-Object { [int]$_ })
    switch ($Bump) {
        'Patch' { "$($a[0]).$($a[1]).$($a[2] + 1)" }
        'Minor' { "$($a[0]).$($a[1] + 1).0" }
        'Major' { "$($a[0] + 1).0.0" }
    }
}

function ConvertTo-GeneCommandArgs {
    <#
    The words after prof that prof itself does not know (-Test, -Run Web, -Products speed,crewchief) -> a splat
    for the dp* command. A word naming one of its switches turns it on; any other parameter takes the next word.
    #>
    param([Parameter(Mandatory)][string]$Command, [object[]]$Extra)
    $cmd = Get-Command $Command -ErrorAction Stop
    $Extra = @($Extra | Where-Object { $null -ne $_ })
    $h = [ordered]@{}
    for ($i = 0; $i -lt $Extra.Count; $i++) {
        $t = $Extra[$i]
        if ($t -isnot [string] -or $t -notmatch '^-([A-Za-z][A-Za-z0-9]*)(:(.*))?$') { throw "$Command`: did not expect '$t' here. Its switches: $((Get-GeneCommandSwitches $Command).Name -join ', ')" }
        $name = $Matches[1]; $inline = $Matches[3]
        $param = @($cmd.Parameters.Values | Where-Object { $_.Name -ieq $name -or $_.Aliases -icontains $name }) | Select-Object -First 1
        if (-not $param) { throw "$Command has no -$name. Its switches: $((Get-GeneCommandSwitches $Command).Name -join ', ')" }
        if ($param.SwitchParameter) { $h[$param.Name] = $(if ($null -ne $inline -and $inline -ne '') { $inline -notmatch '^(\$?false|0)$' } else { $true }); continue }
        if ($null -ne $inline -and $inline -ne '') { $h[$param.Name] = $inline; continue }
        if ($i + 1 -ge $Extra.Count) { throw "$Command -$($param.Name) needs a value." }
        $i++; $h[$param.Name] = $Extra[$i]
    }
    return $h
}

$script:ProfBuildCommon = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable',
    'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm', 'ShowHelp', 'CliArgs')

function Get-GeneCommandSwitches {
    <#
    A dp* command's own options for the "more" menu: Name, Switch (true for on/off), Values (its fixed choices) and
    Description (the first help line for it: .PARAMETER help, else its "  -Name   text" usage line).
    #>
    param([Parameter(Mandatory)][string]$Command)
    $cmd = Get-Command $Command -ErrorAction Stop
    $text = @{}
    foreach ($m in [regex]::Matches([string]$cmd.Definition, '(?m)^\s*Write-Host\s+"\s+-([A-Za-z]+)\s{2,}([^"]+)"')) {
        if (-not $text.Contains($m.Groups[1].Value)) { $text[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
    }
    try {
        foreach ($ph in @((Get-Help $Command -Full -ErrorAction Stop).parameters.parameter)) {
            $d = (@($ph.description) | ForEach-Object Text) -join ' '
            if ($d -and -not $text.Contains($ph.name)) { $text[$ph.name] = ($d -split '(?<=\.)\s')[0].Trim() }
        }
    }
    catch { }
    foreach ($p in $cmd.Parameters.Values) {
        if ($p.Name -in $script:ProfBuildCommon) { continue }
        $set = @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object ValidValues)
        [pscustomobject]@{ Name = $p.Name; Switch = [bool]$p.SwitchParameter; Values = $set; Description = [string]$text[$p.Name] }
    }
}

function Enter-GeneBuildRepo($Info) {
    <# Moves the window into the product's repo and leaves it there. #>
    $repo = Get-GeneLocalPath $Info.Repo
    if (-not $repo -or -not (Test-Path -LiteralPath $repo)) { throw "$($Info.Name): repo folder '$repo' ($($Info.Repo) in this machine's profile) is not here." }
    Set-Location -LiteralPath $repo
    Write-ProfNote "Repo: $repo"
    return $repo
}

function Invoke-GeneBuildCommand {
    <# Runs the product's dp* command with the given splat (and -WhatIf). #>
    param($Info, [System.Collections.IDictionary]$Splat, [switch]$WhatIf)
    if (-not (Get-Command $Info.Command -ErrorAction SilentlyContinue)) { throw "$($Info.Command) is not loaded. It lives in the PowerShell profile: open a new tab, or . `$PROFILE." }
    $call = @{} + $Splat
    if ($WhatIf) { $call.WhatIf = $true }
    $shown = @($Info.Command) + @($call.Keys | ForEach-Object { $v = $call[$_]; if ($v -is [bool] -or $v -is [switch]) { if ($v) { "-$_" } } else { "-$_ $(@($v) -join ',')" } })
    Write-ProfNote "Running: $($shown -join ' ')"
    & $Info.Command @call
}

function Invoke-GeneProfBuildCompile {
    param([string]$Product, [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug', [object[]]$Extra, [switch]$WhatIf)
    $info = Get-GeneBuildProduct $Product
    if ($Extra) { Write-ProfWarn "compile only takes -Configuration; ignored: $($Extra -join ' ')" }
    $repo = Enter-GeneBuildRepo $info
    foreach ($b in $info.Build) {
        $path = Join-Path $repo $b
        if ($WhatIf) { Write-Host "[WhatIf] Would run: dotnet build `"$path`" -c $Configuration" -ForegroundColor Yellow; continue }
        Write-ProfStep "dotnet build $b -c $Configuration"
        dotnet build $path -c $Configuration
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $b (exit $LASTEXITCODE)." }
    }
}

function Invoke-GeneProfBuildRun {
    param([string]$Product, [string]$Configuration, [object[]]$Extra, [switch]$WhatIf)
    $info = Get-GeneBuildProduct $Product
    if (-not $info.Run) { throw "$($info.Name) has nothing to run; use compile or publish." }
    $splat = ConvertTo-GeneCommandArgs -Command $info.Command -Extra $Extra
    if ($Configuration) { $splat.Configuration = $Configuration }
    [void](Enter-GeneBuildRepo $info)
    Invoke-GeneBuildCommand -Info $info -Splat $splat -WhatIf:$WhatIf
}

function Invoke-GeneProfBuildPublish {
    param([string]$Product, [ValidateSet('None', 'Patch', 'Minor', 'Major')][string]$Bump = 'None', [string]$Configuration, [object[]]$Extra, [switch]$WhatIf)
    $info = Get-GeneBuildProduct $Product
    if (-not $info.Publish) { throw "$($info.Name) has no install package to publish." }
    $splat = ConvertTo-GeneCommandArgs -Command $info.Command -Extra $Extra
    foreach ($k in 'Bump', 'BumpMinor', 'BumpMajor', 'Package') { if ($splat.Contains($k)) { throw "Use prof's -Bump Patch|Minor|Major instead of -$k." } }
    $splat.Package = $true
    if ([object]::ReferenceEquals($info, $script:ProfBuildProducts['all']) -and $splat.Contains('Products')) {
        $splat.Products = @(@($splat.Products) | ForEach-Object { "$_" -split ',' } | Where-Object { $_ } | ForEach-Object { $n = $_.Trim().ToLowerInvariant(); if ($script:ProfBuildDpAllNames.Contains($n)) { $script:ProfBuildDpAllNames[$n] } else { $n } })
    }
    switch ($Bump) { 'Patch' { $splat.Bump = $true } 'Minor' { $splat.BumpMinor = $true } 'Major' { $splat.BumpMajor = $true } }
    if ($Configuration) { $splat.Configuration = $Configuration }
    [void](Enter-GeneBuildRepo $info)
    $v = Get-GeneProductVersion $info
    if ($v) { Write-ProfNote "Version: $v$(if ($Bump -ne 'None') { " -> $(Get-GeneBumpedVersion $v $Bump)" } else { ' (unchanged)' })" }
    Invoke-GeneBuildCommand -Info $info -Splat $splat -WhatIf:$WhatIf
}

function Invoke-GeneProfBuildMore {
    param([string]$Product, [string]$Configuration, [object[]]$Extra, [switch]$WhatIf)
    $info = Get-GeneBuildProduct $Product
    $splat = ConvertTo-GeneCommandArgs -Command $info.Command -Extra $Extra
    if ($Configuration) { $splat.Configuration = $Configuration }
    [void](Enter-GeneBuildRepo $info)
    if (-not $splat.Count) { & $info.Command -ShowHelp; return }
    Invoke-GeneBuildCommand -Info $info -Splat $splat -WhatIf:$WhatIf
}

function Invoke-GeneProfBuildContainers {
    param([string]$Product = 'speedy', [object[]]$Extra, [switch]$WhatIf)
    if ($Product -ine 'speedy') { throw 'containers is Speedy only: prof build containers speedy' }
    $info = [pscustomobject]@{ Name = 'Speedy containers'; Command = 'dpContainers'; Repo = 'SpeedyRepo' }
    $splat = ConvertTo-GeneCommandArgs -Command dpContainers -Extra $Extra
    [void](Enter-GeneBuildRepo $info)
    Invoke-GeneBuildCommand -Info $info -Splat $splat -WhatIf:$WhatIf
}

function Read-GeneBuildMenu {
    <#
    The build group's menu: product first, then what to do with it, then that action's questions.
    Returns @{ Verb; Params } for the dispatcher, 'help' for the group's help, or $null when the user cancels.
    #>
    param([scriptblock]$Reader)
    $products = Get-GeneBuildProducts
    $items = @($products.Keys | ForEach-Object {
            $i = $products[$_]
            $v = try { Get-GeneProductVersion $i } catch { '' }
            [pscustomobject]@{ Name = $_; Description = "$($i.Name)  ($($i.Command)$(if ($v) { ", version $v" }))"; Key = $_ }
        }) + [pscustomobject]@{ Name = 'help'; Description = 'Explain the build commands'; Key = 'help' }
    $pick = Select-GeneMenu -Title 'prof build: which product?' -Items $items -Reader $Reader
    if (-not $pick) { return $null }
    if ($pick.Key -eq 'help') { return 'help' }
    $info = $products[$pick.Key]
    $acts = @([pscustomobject]@{ Name = 'Build only'; Description = 'compile, nothing published or started'; Verb = 'compile' })
    if ($info.Run) { $acts += [pscustomobject]@{ Name = 'Build + run'; Description = "$($info.Command) with no switches"; Verb = 'run' } }
    if ($info.Publish) { $acts += [pscustomobject]@{ Name = 'Publish'; Description = "install package ($($info.Command) -Package), optional version bump"; Verb = 'publish' } }
    if ($pick.Key -eq 'speedy') { $acts += [pscustomobject]@{ Name = 'Containers'; Description = 'rebuild the images + restart the stack (dpContainers)'; Verb = 'containers' } }
    $acts += [pscustomobject]@{ Name = 'More options...'; Description = "pick any of $($info.Command)'s switches"; Verb = 'more' }
    $act = Select-GeneMenu -Title "What to do with $($info.Name)?" -Items $acts -Default 1 -Reader $Reader
    if (-not $act) { return $null }
    $p = [ordered]@{ Product = $pick.Key }
    $yn = { param($q, $d = $false) Read-GeneYesNo -Question $q -Default $d -Reader $Reader }
    $extra = @()
    switch ($act.Verb) {
        'compile' {
            $c = Select-GeneMenu -Title 'Configuration?' -Items @('Debug', 'Release') -Default 1 -Reader $Reader
            if (-not $c) { return $null }
            if ($c -ne 'Debug') { $p.Configuration = $c }
        }
        'run' {
            if (@(Get-GeneCommandSwitches $info.Command | Where-Object Name -eq 'CleanBuild').Count -and (& $yn 'Clean build first (-CleanBuild)?')) { $extra += '-CleanBuild' }
        }
        'publish' {
            $v = Get-GeneProductVersion $info
            $bumps = @('None', 'Patch', 'Minor', 'Major') | ForEach-Object {
                $d = if (-not $v) { @{ None = 'keep each version'; Patch = '1.2.3 -> 1.2.4'; Minor = '1.2.3 -> 1.3.0'; Major = '1.2.3 -> 2.0.0' }[$_] }
                elseif ($_ -eq 'None') { "keep $v" } else { "$v -> $(Get-GeneBumpedVersion $v $_)" }
                [pscustomobject]@{ Name = $_; Description = $d }
            }
            $b = Select-GeneMenu -Title 'Raise the version first?' -Items $bumps -Default 1 -Reader $Reader
            if (-not $b) { return $null }
            if ($b.Name -ne 'None') { $p.Bump = $b.Name }
            if ($pick.Key -eq 'all') {
                $prods = Select-GeneMenu -Title 'Which products? (Enter = all four)' -Items @($script:ProfBuildDpAllNames.Keys) -Multi -Default 0 -Reader $Reader -AllowEmpty
                if ($null -eq $prods) { return $null }
                if (@($prods).Count -and @($prods).Count -lt 4) { $extra += '-Products'; $extra += , @($prods) }
                if (& $yn 'Package them at the same time (-Parallel)? Faster, but pegs the machine') { $extra += '-Parallel' }
            }
            if ($pick.Key -eq 'speedy' -and (& $yn 'Allow uncommitted changes (-AllowDirty, never a release)?')) { $extra += '-AllowDirty' }
        }
        'containers' { if (& $yn 'Restart only, on the images already built (-NoBuild)?') { $extra += '-NoBuild' } }
        'more' {
            $sw = @(Get-GeneCommandSwitches $info.Command | Where-Object { $_.Name -notin 'Package', 'Bump', 'BumpMinor', 'BumpMajor' })
            $chosen = Select-GeneMenu -Title "$($info.Command): which options? (Space to tick, Enter when done)" -Items $sw -Multi -Reader $Reader -AllowEmpty
            if ($null -eq $chosen) { return $null }
            foreach ($s in @($chosen)) {
                if ($s.Switch) { $extra += "-$($s.Name)"; continue }
                $val = if ($s.Values.Count) { Select-GeneMenu -Title "-$($s.Name)?" -Items $s.Values -Default 1 -Reader $Reader } else { ([string](Read-GeneText -Reader $Reader -Prompt "-$($s.Name) value")).Trim() }
                if (-not $val) { return $null }
                if ($s.Name -eq 'Configuration') { $p.Configuration = $val } else { $extra += "-$($s.Name)"; $extra += $val }
            }
        }
    }
    if ($extra.Count) { $p.Extra = $extra }
    if ($act.Verb -ne 'more' -or $p.Contains('Extra')) { if (& $yn 'Dry run only (-WhatIf)?') { $p.WhatIf = $true } }
    return @{ Verb = $act.Verb; Params = $p }
}
