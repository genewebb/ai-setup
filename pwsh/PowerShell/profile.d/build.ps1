# profile.d\build: build, run and package the products (dp*). Definitions only; loaded by the core profile.

function Publish-GeneSharedBits {
    <#
        Second publish target for the dp* -Package tail (Publish-SpeedMerchantsPackage): copies the freshly built
        setup exes to SharedBitsShare and prunes STRICTLY-OLDER versions of the SAME product there, the same rule
        as the team share. Off while SharedBitsHost is blank in this machine's config.

        SharedBitsShare is SMVMTR1's S: (an Azure Files share). Outbound port 445 to Azure is blocked on the
        laptop's network, so the laptop cannot open it; SharedBitsHost can. The exes are staged on that host
        through its admin share (SharedBitsStaging is a path on the host), and a remote session there copies
        and prunes. The storage key is read ON the host from SharedBitsKeyScript (the `$AccountKey = "..."` line
        of MapDrive.ps1), used for a connection that lives only in that session, and never sent back: the
        session returns status lines only. The session uses this logon's Kerberos ticket; when there is none
        (a cached logon from before the domain was reachable) it asks for this account's password once and
        connects with that. Best-effort like the team share: every failure is a warning and the packages stay
        in the bits folder.
    #>
    param([Parameter(Mandatory)][object[]]$Plan, [Parameter(Mandatory)][string]$BitsDir)

    $relayHost = $global:GeneMachine.SharedBitsHost
    if (-not $relayHost) { return }
    $share     = $global:GeneMachine.SharedBitsShare
    $keyScript = $global:GeneMachine.SharedBitsKeyScript
    $staging   = $global:GeneMachine.SharedBitsStaging
    if (-not ($share -and $keyScript -and $staging)) {
        Write-Warning "Shared bits skipped: SharedBitsHost is set but SharedBitsShare, SharedBitsKeyScript or SharedBitsStaging is blank in $global:GeneMachineConfigPath."
        return
    }
    if ($staging -notmatch '^(?<d>[A-Za-z]):\\(?<rest>.+)$') {
        Write-Warning "Shared bits skipped: SharedBitsStaging must be a local path on $relayHost (e.g. C:\ProgramData\GeneSharedBits), not '$staging'."
        return
    }
    $stagingUnc = "\\$relayHost\$($Matches.d)`$\$($Matches.rest)"

    # 1. Stage the exes on the host (laptop -> host admin share; the host -> Azure leg is step 2).
    $names = @($Plan | ForEach-Object { $_.Built.Name })
    try { New-Item -ItemType Directory -Path $stagingUnc -Force -ErrorAction Stop | Out-Null }
    catch {
        Write-Warning "Shared bits skipped: cannot reach $stagingUnc ($($_.Exception.Message)) - package(s) left in $BitsDir."
        return
    }
    Write-Host "Staging $($names.Count) package(s) on $relayHost for $share..." -ForegroundColor Yellow
    $null = & robocopy $BitsDir $stagingUnc @names /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) {
        Write-Warning "Shared bits skipped: staging on $relayHost failed (robocopy exit $LASTEXITCODE) - package(s) left in $BitsDir."
        return
    }

    # 2. Copy + prune on the host. Only Level/Text lines come back.
    $items = @($Plan | ForEach-Object {
        [pscustomobject]@{ Name = $_.Built.Name; Length = $_.Built.Length; Filter = $_.Filter; Version = [string]$_.Version }
    })
    $remote = {
            param($Share, $KeyScript, $Staging, $Items)
            $out = [System.Collections.Generic.List[object]]::new()
            function Say([string]$Level, [string]$Text) { $out.Add([pscustomobject]@{ Level = $Level; Text = $Text }) }
            $root = $null
            try {
                if ($Share -notmatch '^\\\\(?<srv>[^\\]+)\\(?<sh>[^\\]+)') { Say 'Warn' "SharedBitsShare is not a UNC path: $Share"; return }
                $root    = "\\$($Matches.srv)\$($Matches.sh)"
                $account = $Matches.srv.Split('.')[0]
                $hit = Select-String -LiteralPath $KeyScript -Pattern '^\s*\$AccountKey\s*=\s*"([^"]+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $hit) { Say 'Warn' "No `$AccountKey line in $KeyScript on $env:COMPUTERNAME."; $root = $null; return }
                $null = & net.exe use $root "/user:Azure\$account" $hit.Matches[0].Groups[1].Value 2>&1
                $hit = $null
                if ($LASTEXITCODE -ne 0) { Say 'Warn' "Could not connect $root from $env:COMPUTERNAME (net use exit $LASTEXITCODE)."; $root = $null; return }

                New-Item -ItemType Directory -Path $Share -Force -ErrorAction Stop | Out-Null
                $existing = @(Get-ChildItem -LiteralPath $Share -Filter '*-Setup-*.exe' -File -ErrorAction Stop)
                foreach ($i in $Items) {
                    $on = $existing | Where-Object { $_.Name -eq $i.Name } | Select-Object -First 1
                    if ($on -and $on.Length -eq $i.Length) {
                        Say 'Gray' "Already on shared bits, upload skipped: $($i.Name)"
                    }
                    else {
                        $null = & robocopy $Staging $Share $i.Name /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
                        if ($LASTEXITCODE -ge 8) { Say 'Warn' "robocopy to $Share failed for $($i.Name) (exit $LASTEXITCODE); nothing pruned for it."; continue }
                        Say 'Ok' "Copied $($i.Name) -> $Share"
                    }
                    # Prune against the listing taken before any copy, so a sibling product's fresh upload is never seen.
                    $version = [version]$i.Version
                    foreach ($f in $existing) {
                        if ($f.Name -notlike $i.Filter -or $f.Name -eq $i.Name) { continue }
                        if ($f.Name -notmatch '-Setup-(?<v>\d+\.\d+\.\d+)\.exe$') { Say 'Warn' "Unrecognized package name left in shared bits: $($f.Name)"; continue }
                        if ([version]$Matches.v -ge $version) { Say 'Warn' "Newer package kept in shared bits: $($f.Name) (built $version is older)."; continue }
                        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Say 'Gray' "Removed older package from shared bits: $($f.Name)" }
                        catch { Say 'Warn' "Could not remove old package from shared bits $($f.Name): $($_.Exception.Message)" }
                    }
                }
            }
            catch { Say 'Warn' "Shared bits on ${env:COMPUTERNAME}: $($_.Exception.Message)" }
            finally {
                foreach ($i in $Items) { Remove-Item -LiteralPath (Join-Path $Staging $i.Name) -Force -ErrorAction SilentlyContinue }
                if ($root) { $null = & net.exe use $root /delete /y 2>&1 }
                $out
            }
    }
    $remoteArgs = @($share, $keyScript, $staging, $items)
    try { $lines = Invoke-Command -ComputerName $relayHost -ErrorAction Stop -ArgumentList $remoteArgs -ScriptBlock $remote }
    catch {
        # A logon made while the domain was out of reach (cached logon, VPN up later) holds no Kerberos ticket, and
        # WinRM without -Credential does not get one or fall back; the SMB staging above still works. With the
        # password WinRM gets its own ticket, so ask once (this run only, never stored) and try again.
        $why = $_.Exception.Message
        if ($why -notmatch '0x80090311|0x8009030e|0x8009030c|Kerberos|Access is denied' -or [Console]::IsInputRedirected) {
            Write-Warning "Shared bits: the remote session on $relayHost failed ($why) - package(s) left in $BitsDir."
            return
        }
        $caller = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Host "This logon has no Kerberos ticket for $relayHost; sign in as $caller to finish the shared bits copy." -ForegroundColor Yellow
        $cred = $null
        try { $cred = Get-Credential -UserName $caller -Message "Shared bits: password for $caller on $relayHost (this run only, never stored)" } catch { }
        if (-not $cred) {
            Write-Warning "Shared bits skipped: no password given - package(s) left in $BitsDir."
            return
        }
        try { $lines = Invoke-Command -ComputerName $relayHost -Credential $cred -ErrorAction Stop -ArgumentList $remoteArgs -ScriptBlock $remote }
        catch {
            Write-Warning "Shared bits: the remote session on $relayHost failed with the password too ($($_.Exception.Message)) - package(s) left in $BitsDir."
            return
        }
        finally { $cred = $null }
    }
    foreach ($l in @($lines)) {
        switch ($l.Level) {
            'Ok'    { Write-Host $l.Text -ForegroundColor Green }
            'Gray'  { Write-Host $l.Text -ForegroundColor DarkGray }
            default { Write-Warning $l.Text }
        }
    }
}

function Publish-SpeedMerchantsPackage {
    <#
        Shared tail step for dpspeed / dpcrewchief / dpdatagen / dpmutate -Package and for dpall:
        copies the setup exe(s) the packaging script(s) just produced (in C:\Bits, $global:GeneBitsDir) to the
        team share and prunes STRICTLY-OLDER versions of the SAME product from C:\Bits and the share (version
        parsed from the filename - a newer package already on the share is kept and named in a
        warning, so a downgrade rebuild can never destroy it). Reached only when packaging succeeded
        (the repo scripts throw on any failure). Best-effort: an unreachable share warns and never
        fails the build - the package is still in C:\Bits. -BuiltAfter guards against re-publishing a
        stale exe. Then the same packages go to the shared bits (Publish-GeneSharedBits, SMVMTR1's S:)
        when SharedBitsHost is set, whether or not the team share was reachable.

        -Product takes a LIST so dpall hands over all four products in ONE call. That is what makes
        the share optimisations possible. Measured 2026-08-25 against CORPNAS01, which moves only
        ~1.8 MB/s, so an 81 MB upload costs ~45s and dominates every other step in this function
        (a share delete is 0.84s, a share listing 0.48s):
          * ONE share listing per batch instead of Test-Path + Get-ChildItem per product (~1.7s
            each). A successful listing also proves reachability, which is why the separate
            Test-Path probe is gone - it was the expensive 1.22s half of that pair.
          * A copy is SKIPPED when the share already holds the same filename at the same byte
            length. A repackage with no version bump used to re-upload ~81 MB per product for
            nothing (~3 min on a four-product dpall).
          * The remaining copies run in PARALLEL, one runspace each, via robocopy rather than
            Copy-Item so a runspace needs no profile state. Only the copies parallelise; the prunes
            stay serial in this session because they cost under a second and serial ordering keeps
            the warnings readable.

        The share prune deliberately reads the PRE-RUN snapshot: it only ever considers packages
        that existed before this call, so it can neither see nor delete a sibling product's fresh
        upload. It is also skipped for any product whose own upload failed, so a failed copy never
        deletes the version it was meant to replace.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('CrewChief', 'TestAuto', 'TestDataGeneration', 'TestDataGenerationAndMutation')][string[]]$Product,
        [Parameter(Mandatory)][datetime]$BuiltAfter
    )

    # UNC, not Z:, so this works from elevated shells too (mapped drives are
    # per-logon-token - an admin session cannot see the user's Z: mapping).
    $share = $global:GeneMachine.PackageShare
    $bits  = $global:GeneBitsDir

    # Version parsed from the package filename (TestAuto-Setup-2.5.2.exe -> [version]2.5.2), or
    # $null when the name doesn't match. Prunes compare VERSIONS, not names: only strictly-older
    # packages are removed, so rebuilding an old version can never destroy a newer package that is
    # already on the share (the in-app update feed compares versions the same way).
    function Get-PackageVersion([System.IO.FileInfo]$File) {
        if ($File.Name -match '-Setup-(?<v>\d+\.\d+\.\d+)\.exe$') { [version]$Matches.v } else { $null }
    }

    # Removes packages matching $Filter that are STRICTLY OLDER than $Version; keeps (and names)
    # anything newer or unparseable. $Existing is a listing taken once by the caller, so neither
    # the bits folder nor the share is enumerated more than once per batch.
    function Remove-OlderPackages {
        param($Existing, [string]$Filter, [version]$Version, [string]$KeepName, [string]$FolderLabel)

        foreach ($f in @($Existing)) {
            if ($f.Name -notlike $Filter) { continue }
            if ($f.Name -eq $KeepName)    { continue }

            $v = Get-PackageVersion $f
            if (-not $v) {
                Write-Warning "Unrecognized package name left in ${FolderLabel}: $($f.Name)"
                continue
            }
            if ($v -ge $Version) {
                Write-Warning "Newer package kept in ${FolderLabel}: $($f.Name) (built $Version is older)."
                continue
            }
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                Write-Host "Removed older package from ${FolderLabel}: $($f.Name)" -ForegroundColor DarkGray
            }
            catch {
                Write-Warning "Could not remove old package from $FolderLabel $($f.Name): $($_.Exception.Message)"
            }
        }
    }

    # 1. Locate each freshly built package in the bits folder (local, cheap - one listing for all products).
    $bitsItems = @(Get-ChildItem -Path $bits -Filter '*-Setup-*.exe' -File -ErrorAction SilentlyContinue)
    $plan = foreach ($p in $Product) {
        $productFilter = "$p-Setup-*.exe"
        $built = $bitsItems |
            Where-Object { $_.Name -like $productFilter -and $_.LastWriteTime -ge $BuiltAfter } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $built) {
            Write-Warning "No freshly built $productFilter found in $bits - nothing copied to $share."
            continue
        }
        $builtVersion = Get-PackageVersion $built
        if (-not $builtVersion) {
            Write-Warning "Could not parse a version from '$($built.Name)' - copied nothing, pruned nothing."
            continue
        }
        [pscustomobject]@{ Product = $p; Filter = $productFilter; Built = $built; Version = $builtVersion }
    }
    $plan = @($plan)
    if ($plan.Count -eq 0) { return }

    # 2. Prune the bits folder first, so an unreachable share still leaves it clean.
    foreach ($item in $plan) {
        Remove-OlderPackages -Existing $bitsItems -Filter $item.Filter -Version $item.Version `
            -KeepName $item.Built.Name -FolderLabel $bits
    }

    # 3. ONE share listing for the whole batch; it doubles as the reachability probe.
    $shareItems = $null
    $shareOk = $true
    try {
        $shareItems = @(Get-ChildItem -Path $share -Filter '*-Setup-*.exe' -File -ErrorAction Stop)
    }
    catch {
        # The folder can be missing on a share that is perfectly reachable; only a share we cannot
        # reach at all is fatal here (the packages are still in the bits folder either way).
        try {
            New-Item -ItemType Directory -Path $share -Force -ErrorAction Stop | Out-Null
            $shareItems = @()
        }
        catch {
            Write-Warning "Share not reachable: $share - package(s) left in $bits."
            $shareOk = $false
        }
    }

    if ($shareOk) {
        # 4. Same name at the same byte length means the share already has this exact build: skip ~45s.
        $toCopy = foreach ($item in $plan) {
            $onShare = $shareItems | Where-Object { $_.Name -eq $item.Built.Name } | Select-Object -First 1
            if ($onShare -and $onShare.Length -eq $item.Built.Length) {
                Write-Host ("Already on share, upload skipped: {0} ({1:N1} MB)" -f $item.Built.Name, ($item.Built.Length / 1MB)) -ForegroundColor DarkGray
                continue
            }
            $item
        }
        $toCopy = @($toCopy)

        # 5. Upload in parallel. robocopy exit codes below 8 are its success range; 8 and up is a real
        #    failure. robocopy also skips a byte- and timestamp-identical file on its own, which is a
        #    harmless second line of defence behind the check in step 4.
        $copyResults = @()
        if ($toCopy.Count -gt 0) {
            Write-Host "Uploading $($toCopy.Count) package(s) to $share..." -ForegroundColor Yellow
            $copyResults = $toCopy | ForEach-Object -ThrottleLimit $toCopy.Count -Parallel {
                $name = $_.Built.Name
                $out  = & robocopy $using:bits $using:share $name /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
                [pscustomobject]@{ FileName = $name; Code = $LASTEXITCODE; Output = ($out -join ' ').Trim() }
            }
        }
        foreach ($r in @($copyResults)) {
            if ($r.Code -lt 8) {
                Write-Host "Copied $($r.FileName) -> $share" -ForegroundColor Green
            }
            else {
                Write-Warning "robocopy failed for $($r.FileName) (exit $($r.Code)): $($r.Output) - the package is still in $bits."
            }
        }
        $failedNames = @(@($copyResults) | Where-Object { $_.Code -ge 8 } | ForEach-Object { $_.FileName })

        # 6. Prune the share against the pre-run snapshot (see the header note on why it is a snapshot).
        foreach ($item in $plan) {
            if ($failedNames -contains $item.Built.Name) { continue }
            Remove-OlderPackages -Existing $shareItems -Filter $item.Filter -Version $item.Version `
                -KeepName $item.Built.Name -FolderLabel 'share'
        }
    }

    # 7. The shared bits on SMVMTR1's S: (off while SharedBitsHost is blank).
    Publish-GeneSharedBits -Plan $plan -BitsDir $bits
}

function dpspeed {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [switch]$ClearSecrets,

        [switch]$UpdateClientId,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpspeed  - Speed-Merchants build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpspeed [-UpdateClientId] [-ClearSecrets] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -UpdateClientId Reads encrypted ClientId from meta.tUser, decrypts it, updates"
        Write-Host "                  corpltr94.localspeed.json, and clears cached secrets. Use after"
        Write-Host "                  a full platform build that regenerates the API key."
        Write-Host "  -ClearSecrets   Deletes $env:APPDATA\TestAuto\master.json before running."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release)."
        Write-Host "  -Update         Build + publish + create update zip, then exit (do not run app)."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestAuto-Setup-<version>.exe, then exit. Thin wrapper over"
        Write-Host "                  installer\New-TestAutoInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (2.5.0 -> 2.5.1) in"
        Write-Host "                  TestAuto.Web.csproj <Version> before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (2.5.3 -> 2.6.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (2.5.3 -> 3.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpcrewchief -Package."
        Write-Host "                  At most one bump switch; without one the current version is reused."
        Write-Host "  -Run            Run existing published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish. Use when"
        Write-Host "                  builds start feeling slow/wrong or stale plugin DLLs are suspected."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpspeed -Run"
        Write-Host "    Run existing published output only."
        Write-Host "  dpspeed -UpdateClientId -Run"
        Write-Host "    Refresh API key after platform build, then run."
        Write-Host "  dpspeed -ClearSecrets -Run"
        Write-Host "    Clear local secrets file, then run published output."
        Write-Host "  dpspeed -Update"
        Write-Host "    Build + publish + create update zip, then exit."
        Write-Host "  dpspeed -Package [-Bump|-BumpMinor|-BumpMajor]"
        Write-Host "    Build the TestAuto-Setup-<version>.exe install package, then exit."
        Write-Host "    Version is Major.Minor.Patch in TestAuto.Web.csproj <Version> (same scheme as"
        Write-Host "    CrewChief): -Bump = patch, -BumpMinor = minor, -BumpMajor = major."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestAuto packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: — mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpspeed -Configuration Debug"
        Write-Host "    Build + publish + run using Debug."
        Write-Host ""
        Write-Host "Tip: dpspeed -? shows full native PowerShell help." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Guard: bump switches only mean something inside the -Package path below. Without this,
    # `dpspeed -Bump` (forgot -Package) falls through to the default build+publish+run with NO
    # version bump, no installer, and no error. Multi-bump throws HERE (not just in the repo
    # script) so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpspeed: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpspeed: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in
    # installer\BUILDING.md); this switch is just a convenience entry point.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'installer\New-TestAutoInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (2.5.3 -> 3.0.0) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (2.5.3 -> 2.6.0) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (2.5.0 -> 2.5.1) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestAuto-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestAuto-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs
        # Deploy to the team share + prune older versions there — only reached on success
        # (the packaging script throws on any failure).
        Publish-SpeedMerchantsPackage -Product 'TestAuto' -BuiltAfter $packStarted
        return
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # --- UpdateClientId: decrypt from DB, update secrets JSON, auto-clear cache ---
    if ($UpdateClientId) {
        $secretsFile  = Get-GeneMachineSetting -Name LocalSpeedSecretsFile -MustExist

        # Newest installed platform version wins (was a hardcoded 26.1.0 pin, which went stale the
        # moment 26.2.0 landed). Version-named folders only; anything unparseable is ignored.
        $maestroRoot = Join-Path $env:ProgramFiles 'Profisee\Master Data Maestro Server'
        $securityDll = Get-ChildItem -LiteralPath $maestroRoot -Directory -ErrorAction Stop |
            Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'Gateway\Profisee.Platform.Utilities.Security.dll' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if (-not $securityDll) { throw "Profisee.Platform.Utilities.Security.dll not found under any version folder in $maestroRoot" }

        # Read-only: query and decrypt (always runs, even with -WhatIf)
        $rawJson   = Get-Content -Raw -LiteralPath $secretsFile
        $secrets   = $rawJson | ConvertFrom-Json
        $connStr   = $secrets[0].ConnectionStrings.ProfiseeDB
        $oldApiKey = $secrets[0].RestClients.Profisee.ApiKey

        if (-not $connStr) { throw "ProfiseeDB connection string not found in $secretsFile" }

        # Query encrypted ClientId from meta.tUser. All LIKE matches are collected (ExecuteScalar
        # took an arbitrary first row when several names contained the username); an exact
        # DOMAIN\username (or bare-name) match wins, anything else ambiguous throws with the names.
        $conn = [System.Data.SqlClient.SqlConnection]::new($connStr)
        $conn.Open()
        $userRows = @()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT NAME, ClientID FROM [meta].[tUser] WHERE NAME LIKE @u"
            [void]$cmd.Parameters.AddWithValue('@u', "%$env:USERNAME%")
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $userRows += [pscustomobject]@{
                    Name     = $reader.GetString(0)
                    ClientId = if ($reader.IsDBNull(1)) { $null } else { $reader.GetValue(1) }
                }
            }
        }
        finally { $conn.Dispose() }

        $userRows = @($userRows | Where-Object { $_.ClientId })
        if ($userRows.Count -eq 0) { throw "No ClientID found in meta.tUser for '$env:USERNAME'" }
        if ($userRows.Count -gt 1) {
            $exact = @($userRows | Where-Object { $_.Name -eq $env:USERNAME -or $_.Name -match "\\$([regex]::Escape($env:USERNAME))$" })
            if ($exact.Count -eq 1) {
                Write-Host "Multiple tUser rows matched '$env:USERNAME'; using exact match '$($exact[0].Name)'." -ForegroundColor DarkGray
                $userRows = $exact
            }
            else {
                throw "Ambiguous: $($userRows.Count) meta.tUser rows match '%$env:USERNAME%' ($(($userRows.Name) -join ', ')) and none/several match exactly. Refusing to guess."
            }
        }
        $encrypted = $userRows[0].ClientId

        # Decrypt using Profisee platform assembly (internal class, via reflection)
        if (-not (Test-Path $securityDll)) { throw "Security DLL not found: $securityDll" }
        $asm    = [System.Reflection.Assembly]::LoadFrom($securityDll)
        $type   = $asm.GetType('Profisee.Platform.Utilities.Security.Encryption')
        $method = $type.GetMethod('Decrypt',
            [System.Reflection.BindingFlags]'NonPublic,Static',
            $null, @([string]), $null)
        if (-not $method) { throw "Encryption.Decrypt method not found via reflection" }
        $newApiKey = $method.Invoke($null, @([string]$encrypted))

        if (-not $newApiKey) { throw "Decryption returned null" }

        # Masked 3+3 (same convention as CrewChief's SecretCatalog.GetMaskedValue) — full keys stay
        # out of console scrollback/transcripts; the new key lands in the secrets file either way.
        $maskKey = {
            param($k)
            if (-not $k) { '(none)' }
            elseif ($k.Length -le 8) { '********' }
            else { $k.Substring(0, 3) + ('*' * 6) + $k.Substring($k.Length - 3) }
        }
        Write-Host "Old ApiKey: $(& $maskKey $oldApiKey)" -ForegroundColor DarkGray
        Write-Host "New ApiKey: $(& $maskKey $newApiKey)" -ForegroundColor Green

        if ($oldApiKey -eq $newApiKey) {
            Write-Host "ClientId unchanged - nothing to update." -ForegroundColor Yellow
        }
        elseif ($PSCmdlet.ShouldProcess($secretsFile, "Replace ApiKey in secrets file")) {
            # Replace all occurrences in raw JSON (preserves original formatting)
            $updatedJson = $rawJson.Replace($oldApiKey, $newApiKey)
            $count = ([regex]::Matches($rawJson, [regex]::Escape($oldApiKey))).Count
            Set-Content -LiteralPath $secretsFile -Value $updatedJson -NoNewline
            Write-Host "Replaced $count occurrence(s) in $secretsFile" -ForegroundColor Green

            # Auto-clear cached secrets (stale after key change)
            $ClearSecrets = $true
        }
    }

    # Wrapper-only pre-step (supports -WhatIf)
    if ($ClearSecrets) {
        # Installed-as-service boxes read the MACHINE store advertised by TESTAUTO_SECRETS_FOLDER
        # (%ProgramData%\TestAuto) — this switch only clears the per-user dev-box file. Warn when
        # the env var is present so a cleared-but-still-bootstrapped app isn't a mystery.
        if ($env:TESTAUTO_SECRETS_FOLDER) {
            Write-Warning "TESTAUTO_SECRETS_FOLDER is set ($env:TESTAUTO_SECRETS_FOLDER) - an installed TestAuto reads that machine store; this clears only the per-user file below."
        }
        $secretFile = Join-Path $env:APPDATA 'TestAuto\master.json'

        if ($PSCmdlet.ShouldProcess($secretFile, 'Delete local TestAuto secrets file')) {
            if (Test-Path -LiteralPath $secretFile) {
                try {
                    Remove-Item -LiteralPath $secretFile -Force -ErrorAction Stop
                    Write-Host "Deleted secrets file: $secretFile" -ForegroundColor DarkGray
                }
                catch {
                    throw "Failed to delete secrets file '$secretFile': $($_.Exception.Message)"
                }
            }
            else {
                Write-Host "Secrets file not found (nothing to clear): $secretFile" -ForegroundColor DarkGray
            }
        }
    }

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }

    Dev-SpeedMerchantsRestart @invoke
}

function dpcrewchief {
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [switch]$SealSecret,
        [switch]$Unlock,

        [string]$SolutionPath,
        [string]$ProjectName,

        [switch]$ClearSecrets,

        [switch]$UpdateClientId,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpcrewchief  - CrewChief build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpcrewchief [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SealSecret] [-Unlock] [-SolutionPath <path>] [-ProjectName <name>] [-ClearSecrets] [-UpdateClientId] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target CrewChief.Cli instead of CrewChief.Web. Remaining args are"
        Write-Host "                  passed to the CLI when it starts."
        Write-Host "  -SealSecret     Seal the Tier-1 RSA key, then exit. Interactive: prompts (hidden) for"
        Write-Host "                  the raw key XML + travel passphrase. Passphrase is NEVER an argument."
        Write-Host "                  (Also accepts the token form: dpcrewchief --sealsecret)"
        Write-Host "  -Unlock         Unlock the Tier-1 key on this box (hidden passphrase prompt), then exit."
        Write-Host "                  (Also accepts the token form: dpcrewchief --unlock)"
        Write-Host "                  Encrypted secret files live per-user in %APPDATA%\CrewChief (TestAuto-style)."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release)."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\CrewChief.zip, then exit."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\CrewChief-Setup-<version>.exe, then exit. Thin wrapper over"
        Write-Host "                  CrewChief\installer\New-CrewChiefInstaller.ps1 (see BUILDING.md there)."
        Write-Host "  -Bump           With -Package: bump the patch version (1.0.0 -> 1.0.1) in"
        Write-Host "                  Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -ClearSecrets   Clears the per-user encrypted secret store (%APPDATA%\CrewChief\*):"
        Write-Host "                  sealed RSA key, Tier-2 store, DPAPI passphrases, lockout state."
        Write-Host "  -UpdateClientId Accepted for dpspeed parity; CrewChief has no Profisee ClientId."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpcrewchief"
        Write-Host "    Build + publish + run CrewChief.Web using Release."
        Write-Host "  dpcrewchief -Cli list steps"
        Write-Host "    Build + publish + run CrewChief.Cli with arguments."
        Write-Host "  dpcrewchief -Cli -Run history --last 5"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpcrewchief -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\CrewChief.zip, then exit."
        Write-Host "  dpcrewchief -Package"
        Write-Host "    Build the CrewChief-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    CrewChief packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: — mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpcrewchief -Package -Bump"
        Write-Host "    Bump 1.0.0 -> 1.0.1, then build CrewChief-Setup-1.0.1.exe."
        Write-Host "  dpcrewchief -Configuration Debug"
        Write-Host "    Build + publish + run CrewChief.Web using Debug."
        Write-Host ""
        return
    }

    # Interactive Tier-1 secret admin: prompts (hidden) for the passphrase — NEVER an argument, by design.
    # Accepts either the switch form (-SealSecret / -Unlock) or the token form (--sealsecret / --unlock).
    # Runs the CLI verb directly via dotnet run, defaulting --data-folder to the Web app's data folder so
    # the blob/passphrase land where the Web UI reads them. seal-secret must run before unlock.
    $wantSeal   = $SealSecret -or ($CliArgs -contains '--sealsecret') -or ($CliArgs -contains '--seal-secret')
    $wantUnlock = $Unlock     -or ($CliArgs -contains '--unlock')
    if ($wantSeal -or $wantUnlock) {
        $verb = if ($wantSeal) { 'seal-secret' } else { 'unlock' }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run CrewChief.Cli verb '$verb' (interactive: hidden passphrase prompt)." -ForegroundColor Yellow
            return
        }
        $rest = @($CliArgs | Where-Object { $_ -notin '--sealsecret', '--seal-secret', '--unlock' })
        $cliProject = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief\CrewChief.Cli')
        # Encrypted secret files are per-user in %APPDATA%\CrewChief (fixed), so --data-folder is irrelevant here.
        dotnet run --project $cliProject -- $verb @rest
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto CrewChief.Cli). Without this check an invented switch (--Publish) or
    # a double-dashed real one (--Bump — PowerShell binds single-dash switch names only) is silently
    # swallowed and the command falls through to the default build+publish+run path: no version
    # bump, no installer, no share copy, and no error. Fail loudly instead.
    # Runs after the seal/unlock block so the documented --sealsecret/--unlock token forms still work.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (a hand-maintained list silently
        # missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are kept — they are
        # real dpcrewchief switches via SupportsShouldProcess. CliArgs is the catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpcrewchief switch" }
        }
        $message = @("dpcrewchief: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpcrewchief -ShowHelp' for the switch list, or pass -Cli to forward these to CrewChief.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed — a forgotten -Package would otherwise build+run with no bump and no error). Multi-bump
    # throws HERE so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpcrewchief: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpcrewchief: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpcrewchief: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in
    # CrewChief\installer\BUILDING.md); this switch is just a convenience entry point.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief\installer\New-CrewChiefInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\CrewChief-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older CrewChief-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs
        # Deploy to the team share + prune older versions there — only reached on success
        # (the packaging script throws on any failure).
        Publish-SpeedMerchantsPackage -Product 'CrewChief' -BuiltAfter $packStarted
        return
    }

    if ($UpdateClientId) {
        Write-Host "CrewChief does not use Profisee ClientId/API key secrets; nothing to update." -ForegroundColor DarkGray
    }

    if ($ClearSecrets) {
        # secrets.local.json was eliminated from CrewChief (no config source loads it any more) —
        # the only per-user secret state is the encrypted %APPDATA%\CrewChief store below.
        # Encrypted per-user secret store (sealed RSA key, Tier-2 store, DPAPI passphrases, lockout) —
        # same %APPDATA% pattern as TestAuto's master.json (Remove-Item "$env:APPDATA\CrewChief\*").
        $appSecrets = Join-Path $env:APPDATA 'CrewChief'
        if ($PSCmdlet.ShouldProcess("$appSecrets\*", 'Delete per-user CrewChief encrypted secrets')) {
            if (Test-Path $appSecrets) {
                Remove-Item "$appSecrets\*" -Force -ErrorAction SilentlyContinue
                Write-Host "Cleared per-user secrets: $appSecrets" -ForegroundColor DarkGray
            }
            else {
                Write-Host "No per-user secrets to clear: $appSecrets" -ForegroundColor DarkGray
            }
        }
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($Cli) { $invoke.Cli = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }
    if ($CliArgs.Count -gt 0) { $invoke.CliArgs = $CliArgs }

    Dev-CrewChiefRestart @invoke
}

function dpdatagen {
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpdatagen  - TestDataGeneration build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpdatagen [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target TestData.Generation.Cli instead of TestData.Generation.Web."
        Write-Host "                  Remaining args are passed to the CLI when it starts."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release). Default Release."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\TestDataGeneration.zip, then exit."
        Write-Host "                  Excludes a box's own state so an update never clobbers it:"
        Write-Host "                  Samples\* (shape definitions), *.local.json (credentials/overrides),"
        Write-Host "                  *.runtime.json and *.resume.json (generated run state)."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestDataGeneration-Setup-<version>.exe, then exit. Thin"
        Write-Host "                  wrapper over TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (1.0.0 -> 1.0.1) in"
        Write-Host "                  TestData.Generation\Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed/dpcrewchief -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host "  This tool has no secret store and no Profisee ClientId, so there is no"
        Write-Host "  -SealSecret/-Unlock/-ClearSecrets/-UpdateClientId here (unlike dpcrewchief/dpspeed)."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpdatagen"
        Write-Host "    Build + publish + run TestData.Generation.Web using Release."
        Write-Host "  dpdatagen -Cli generate --shape PDATAGEN1M"
        Write-Host "    Build + publish + run TestData.Generation.Cli with arguments."
        Write-Host "  dpdatagen -Cli -Run verify --shape PDATAGEN1M"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpdatagen -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\TestDataGeneration.zip, then exit."
        Write-Host "  dpdatagen -Package"
        Write-Host "    Build the TestDataGeneration-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestDataGeneration packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: - mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpdatagen -Package -Bump"
        Write-Host "    Bump 1.0.0 -> 1.0.1, then build TestDataGeneration-Setup-1.0.1.exe."
        Write-Host "  dpdatagen -Configuration Debug"
        Write-Host "    Build + publish + run TestData.Generation.Web using Debug."
        Write-Host ""
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto TestData.Generation.Cli). Without this check an invented switch
    # (--Publish) or a double-dashed real one (--Bump - PowerShell binds single-dash switch names
    # only) is silently swallowed and the command falls through to the default build+publish+run
    # path: no version bump, no installer, no share copy, and no error. Fail loudly instead.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (in dpcrewchief a hand-maintained
        # list silently missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are
        # kept - they are real dpdatagen switches via SupportsShouldProcess. CliArgs is the
        # catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpdatagen switch" }
        }
        $message = @("dpdatagen: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpdatagen -ShowHelp' for the switch list, or pass -Cli to forward these to TestData.Generation.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed/dpcrewchief - a forgotten -Package would otherwise build+run with no bump and no
    # error). Multi-bump throws HERE so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpdatagen: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpdatagen: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpdatagen: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in the
    # script's own comment header); this switch is just a convenience entry point. Note the folder is
    # 'Installer' (capital I) here, unlike CrewChief's lower-case 'installer'.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestDataGeneration-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestDataGeneration-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs

        # Deploy to the team share + prune older versions there - only reached on success (the
        # packaging script throws on any failure). Same shared tail step dpspeed/dpcrewchief use.
        #
        # Publish-SpeedMerchantsPackage carries [ValidateSet('CrewChief','TestAuto')] on -Product, so
        # 'TestDataGeneration' is rejected until that set is widened by one token. Checked from the
        # attribute rather than assumed, so this call site is already exact-parity and starts working
        # the moment the set includes it - and a successful package is never destroyed by a
        # parameter-binding throw in the tail step (the exe is already in C:\Bits either way).
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        $productSet = @(
            if ($publishCmd -and $publishCmd.Parameters.ContainsKey('Product')) {
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            }
        )
        if ($productSet.Count -gt 0 -and $productSet -notcontains 'TestDataGeneration') {
            Write-Warning ("Share deploy skipped: Publish-SpeedMerchantsPackage -Product accepts only [{0}]. Add 'TestDataGeneration' to that ValidateSet to enable the copy+prune. The package is in $global:GeneBitsDir." -f ($productSet -join ', '))
        }
        else {
            Publish-SpeedMerchantsPackage -Product 'TestDataGeneration' -BuiltAfter $packStarted
        }
        return
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($Cli) { $invoke.Cli = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }
    if ($CliArgs.Count -gt 0) { $invoke.CliArgs = $CliArgs }

    Dev-DataGenRestart @invoke
}

function dpmutate {
    <#
        Sibling of dpdatagen for the Data Generation And Mutation tool (TestData.Mutation).
        Unlike dpspeed/dpcrewchief/dpdatagen there is no Dev-*Restart command for this product in
        Gene.DevOpsTools, so the build/publish/run body lives HERE rather than in the module. It is
        an adaptation of Dev-DataGenRestart with this product's own solution, projects, loopback
        port (5047) and update-zip name - values that Dev-DataGenRestart hard-codes for
        TestData.Generation and does not expose as parameters.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpmutate  - Data Generation And Mutation build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpmutate [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target TestData.Mutation.Cli instead of TestData.Mutation.Web."
        Write-Host "                  Remaining args are passed to the CLI when it starts - the CLI takes"
        Write-Host "                  a shape file first: <shape.json> [--test-mode] [--verify-only]"
        Write-Host "                  [--skip-verify] [--reset]."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release). Default Release."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\TestDataGenerationAndMutation.zip,"
        Write-Host "                  then exit. Excludes a box's own state so an update never clobbers it:"
        Write-Host "                  Samples\* (shape definitions) and *.local.json (shape files, which use"
        Write-Host "                  that suffix, plus per-box overrides/credentials). Chunk/resume state is"
        Write-Host "                  kept in SQL checkpoint tables, not on disk, so nothing else is excluded."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestDataGenerationAndMutation-Setup-<version>.exe, then exit."
        Write-Host "                  Thin wrapper over TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (0.1.0 -> 0.1.1) in"
        Write-Host "                  TestData.Mutation\Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed/dpcrewchief/dpdatagen -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host "  This tool has no secret store and no Profisee ClientId, so there is no"
        Write-Host "  -SealSecret/-Unlock/-ClearSecrets/-UpdateClientId here (unlike dpcrewchief/dpspeed)."
        Write-Host "  The Web host listens on http://localhost:5047 (WebUI:HttpPort in appsettings.json"
        Write-Host "  wins) - one past the sibling data-generation tool's 5045 HTTP / 5046 reserved pair."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpmutate"
        Write-Host "    Build + publish + run TestData.Mutation.Web using Release."
        Write-Host "  dpmutate -Cli C:\path\shape.json --test-mode"
        Write-Host "    Build + publish + run TestData.Mutation.Cli as a small probe run."
        Write-Host "  dpmutate -Cli -Run C:\path\shape.json --verify-only"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpmutate -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\TestDataGenerationAndMutation.zip, then exit."
        Write-Host "  dpmutate -Package"
        Write-Host "    Build the TestDataGenerationAndMutation-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestDataGenerationAndMutation packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: - mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpmutate -Package -Bump"
        Write-Host "    Bump 0.1.0 -> 0.1.1, then build TestDataGenerationAndMutation-Setup-0.1.1.exe."
        Write-Host "  dpmutate -Configuration Debug"
        Write-Host "    Build + publish + run TestData.Mutation.Web using Debug."
        Write-Host ""
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto TestData.Mutation.Cli). Without this check an invented switch
    # (--Publish) or a double-dashed real one (--Bump - PowerShell binds single-dash switch names
    # only) is silently swallowed and the command falls through to the default build+publish+run
    # path: no version bump, no installer, no share copy, and no error. Fail loudly instead.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (in dpcrewchief a hand-maintained
        # list silently missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are
        # kept - they are real dpmutate switches via SupportsShouldProcess. CliArgs is the
        # catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpmutate switch" }
        }
        $message = @("dpmutate: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpmutate -ShowHelp' for the switch list, or pass -Cli to forward these to TestData.Mutation.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed/dpcrewchief/dpdatagen - a forgotten -Package would otherwise build+run with no bump
    # and no error). Multi-bump throws HERE so a -WhatIf preview refuses exactly like a real run.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpmutate: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpmutate: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpmutate: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script; this switch is just a convenience
    # entry point. Folder is 'Installer' (capital I), matching TestData.Generation.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestDataGenerationAndMutation-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestDataGenerationAndMutation-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs

        # Deploy to the team share + prune older versions there - only reached on success (the
        # packaging script throws on any failure). Same shared tail step dpspeed/dpcrewchief/dpdatagen use.
        #
        # Publish-SpeedMerchantsPackage carries [ValidateSet('CrewChief','TestAuto','TestDataGeneration')]
        # on -Product, so 'TestDataGenerationAndMutation' is rejected until that set is widened by one
        # token. Checked from the attribute rather than assumed, so this call site is already
        # exact-parity and starts working the moment the set includes it - and a successful package is
        # never destroyed by a parameter-binding throw in the tail step (the exe is already in C:\Bits
        # either way).
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        $productSet = @(
            if ($publishCmd -and $publishCmd.Parameters.ContainsKey('Product')) {
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            }
        )
        if ($productSet.Count -gt 0 -and $productSet -notcontains 'TestDataGenerationAndMutation') {
            Write-Warning ("Share deploy skipped: Publish-SpeedMerchantsPackage -Product accepts only [{0}]. Add 'TestDataGenerationAndMutation' to that ValidateSet to enable the copy+prune. The package is in $global:GeneBitsDir." -f ($productSet -join ', '))
        }
        else {
            Publish-SpeedMerchantsPackage -Product 'TestDataGenerationAndMutation' -BuiltAfter $packStarted
        }
        return
    }

    # ---- build / publish / run (inline; no Dev-MutateRestart exists in Gene.DevOpsTools) ----

    if ([string]::IsNullOrWhiteSpace($Configuration)) { $Configuration = 'Release' }
    if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
        $SolutionPath = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Mutation\TestData.Mutation.sln')
    }
    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        throw "TestData.Mutation solution not found: $SolutionPath"
    }

    $solutionRoot = Split-Path -Parent $SolutionPath
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = if ($Cli) { 'TestData.Mutation.Cli' } else { 'TestData.Mutation.Web' }
    }

    $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"

    # Resolve project path.
    $projectPath = Join-Path (Join-Path $solutionRoot $ProjectName) ($ProjectName + '.csproj')
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $hits = Get-ChildItem -Path $solutionRoot -Recurse -Filter ($ProjectName + '.csproj') -File -ErrorAction SilentlyContinue
        if (-not $hits -or $hits.Count -eq 0) {
            throw "Project not found: $ProjectName. Expected $projectPath or any *\$ProjectName.csproj under $solutionRoot."
        }
        if ($hits.Count -gt 1) {
            $list = ($hits | Select-Object -ExpandProperty FullName) -join "`n"
            throw "Multiple projects named $ProjectName.csproj found. Please disambiguate with -ProjectName. Found:`n$list"
        }
        $projectPath = $hits[0].FullName
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would create output folder: $outDir" -ForegroundColor Yellow
        } else {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
    }

    # Neither csproj overrides <AssemblyName>, so the dll matches the project name for both targets.
    $assemblyName = $ProjectName
    $dllPath = Join-Path $outDir ($assemblyName + '.dll')
    $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

    # TestData.Mutation.Web pins its own default in Program.cs (DefaultHttpPort = 5047) but only when
    # nothing else supplied "urls", so the wrapper sets ASPNETCORE_URLS to the same port the app and
    # installer use. 5047 continues the sibling tool's block (5045 HTTP, 5046 reserved for HTTPS).
    # A WebUI:HttpPort in appsettings.json wins here too - Program.cs reads the same key.
    $webUrls = @()
    $webUrlEnv = $null
    if (-not $Cli) {
        $httpPort = 5047
        $appSettingsPath = Join-Path $solutionRoot 'TestData.Mutation.Web\appsettings.json'
        try {
            if (Test-Path -LiteralPath $appSettingsPath) {
                $cfg = Get-Content -LiteralPath $appSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($cfg.PSObject.Properties.Name -contains 'WebUI' -and $cfg.WebUI.HttpPort) { $httpPort = [int]$cfg.WebUI.HttpPort }
            }
        } catch {
            Write-Host "[warn] Could not read WebUI ports from appsettings.json; using default $httpPort." -ForegroundColor DarkYellow
        }
        $fqdn = try { [System.Net.Dns]::GetHostEntry('').HostName } catch { 'localhost' }
        $webUrls = @(
            "http://localhost:$httpPort",
            "http://${fqdn}:$httpPort"
        )
        # Loopback-only bind: this is a local operator tool with no authentication (same posture the
        # installed shortcut uses), so it is deliberately NOT ListenAnyIP. The FQDN line above is
        # informational for a machine-local browser.
        $webUrlEnv = "http://localhost:$httpPort"
    }

    # Prints the intended web URLs (no-op for the CLI).
    $showUrls = {
        param($urls)
        if ($urls -and $urls.Count -gt 0) {
            Write-Host "  Web UI URLs:" -ForegroundColor Cyan
            foreach ($u in $urls) { Write-Host ("    {0}" -f $u) -ForegroundColor Cyan }
        }
    }

    # Starts the target in the foreground with ASPNETCORE_URLS pinned for the child process only -
    # the previous value is restored so the switch never leaks into the caller's shell.
    $startTarget = {
        param($workDir, $dll, $urlEnv, $extraArgs)
        $priorUrls = $env:ASPNETCORE_URLS
        Push-Location $workDir
        try {
            if ($urlEnv) { $env:ASPNETCORE_URLS = $urlEnv }
            & dotnet $dll @extraArgs
        }
        finally {
            Pop-Location
            $env:ASPNETCORE_URLS = $priorUrls
        }
    }

    # -Run => force Release, run only, no build/publish/zip.
    if ($Run) {
        $Configuration = 'Release'
        $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"
        $dllPath = Join-Path $outDir ($assemblyName + '.dll')
        $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

        if ($WhatIfPreference) {
            Write-Host "[WhatIf] -Run specified: would NOT build/publish/update zip." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
            return
        }

        if (-not (Test-Path -LiteralPath $dllPath)) {
            throw "Published DLL not found (run requires existing publish output): $dllPath`nHint: run dpmutate once (or dpmutate -Configuration Release) to publish first."
        }

        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq 'dotnet.exe' -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName [Release]..." -ForegroundColor Yellow
        & $showUrls $webUrls
        & $startTarget $outDir $dllPath $webUrlEnv $CliArgs
        return
    }

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $outDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        $global:GeneBitsDir\TestDataGenerationAndMutation.zip" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would exclude operator state: Samples\*, *.local.json" -ForegroundColor Yellow
        } else {
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
        }
        return
    }

    if ($CleanBuild) {
        Write-Host "CleanBuild: dotnet clean $projectPath -c $Configuration" -ForegroundColor DarkGray
        dotnet clean $projectPath -c $Configuration --nologo --verbosity minimal
        if ($LASTEXITCODE -ne 0) { throw "dotnet clean failed (exit $LASTEXITCODE)" }

        if (Test-Path -LiteralPath $outDir) {
            Write-Host "CleanBuild: wiping publish folder $outDir" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction Stop
        }
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "Building $ProjectName (and reference closure) [$Configuration]..." -ForegroundColor Yellow
    Import-GeneModuleOnce "Gene.DevOpsTools"   # Invoke-GeneDotnetBuild: interactive NuGet sign-in retry
    Invoke-GeneDotnetBuild $projectPath $Configuration

    Write-Host "Publishing $ProjectName [$Configuration]..." -ForegroundColor Yellow
    dotnet publish $projectPath -c $Configuration -o $outDir --no-build --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

    $escaped = [regex]::Escape($dllPath)
    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq 'dotnet.exe' -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        $publishDir = $outDir
        $zipPath    = Join-Path $global:GeneBitsDir 'TestDataGenerationAndMutation.zip'
        $stageDir   = Join-Path $env:TEMP ('PublishStage_' + [guid]::NewGuid().ToString('N'))
        $robolog    = Join-Path $env:TEMP ('robocopy_' + [guid]::NewGuid().ToString('N') + '.log')

        $oldEAP = $ErrorActionPreference
        try {
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            if (-not (Test-Path -LiteralPath $publishDir)) { throw "Publish directory does not exist: $publishDir" }
            if (-not (Get-ChildItem -LiteralPath $publishDir -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                throw "Publish directory is empty: $publishDir"
            }

            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

            # appsettings.json ships with the code (it holds no per-machine values). Everything a box
            # OWNS is excluded so an update can never clobber it:
            #   /XD Samples        operator-edited shape definitions (shipped under
            #                      TestData.Mutation.Cli\Samples)
            #   *.local.json       the shape files' own suffix, plus per-box overrides/credentials
            # There is no *.runtime.json / *.resume.json here (unlike the data-generation tool):
            # chunk checkpoints and resume state live in SQL tables, not on disk.
            $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
                /XD Samples /XF *.local.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog

            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                Write-Host "Robocopy failed. Tail of log:" -ForegroundColor Red
                Get-Content -Path $robolog -Tail 200 | Write-Host
                throw "Robocopy error (exit code $rc)."
            }

            $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
            if ($stagedCount -eq 0) { throw "Nothing was staged. Check exclude patterns and source folder." }

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            New-Item -ItemType Directory -Path (Split-Path -Parent $zipPath) -Force | Out-Null

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

            $zipInfo = Get-Item -LiteralPath $zipPath
            Write-Host "Created zip: $zipPath  ($($zipInfo.Length) bytes)" -ForegroundColor Green
        }
        finally {
            $ErrorActionPreference = $oldEAP
            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        return
    }

    Write-Host "Starting $ProjectName..." -ForegroundColor Yellow
    & $showUrls $webUrls
    & $startTarget $outDir $dllPath $webUrlEnv $CliArgs

    Write-Host "Done." -ForegroundColor Green
}

function dpall {
    <#
    .SYNOPSIS
        Packages ALL four SpeedMerchants products in one shot (optionally bumping the version of
        each), serially by default.

    .DESCRIPTION
        One release command over the four products that dpspeed / dpcrewchief / dpdatagen / dpmutate
        package individually. It calls each repo's profile-free New-*Installer.ps1 DIRECTLY rather
        than re-entering the sibling dp* wrappers, because a background job runs in a fresh pwsh
        process with NO profile loaded - the dp* functions do not exist there. The installer scripts
        were designed to be callable that way (see each script's comment header).

        The default is SERIAL - one product at a time with live console output - because four
        concurrent self-contained win-x64 publishes saturate a laptop for a sublinear wall-clock win.
        -Parallel opts into background jobs when the box can spare the cores.

        Parallel is safe (verified 2026-08-25 on a concurrent datagen+mutate run, ISCC 7 included)
        because the four product trees are disjoint: separate installer\stage folders, separate
        <Version> files, and NO shared ProjectReference, so no two publishes ever write the same
        obj\ or bin\. The produced exes have product-distinct names in C:\Bits and the share prune
        filters per product, so they cannot delete each other's packages.

        This command PACKAGES only - it never builds-and-runs an app. Use the individual dp*
        commands for the build/publish/run loop.

    .PARAMETER Products
        Which products to package. Default: all four.

    .PARAMETER Package
        Required. Packages the selected products - the same -Package the dp* commands take. The bump
        switches only apply with it, exactly as in dpspeed.

    .PARAMETER Bump
        With -Package: bump the PATCH version of EVERY selected product before packaging (2.5.0 -> 2.5.1).

    .PARAMETER BumpMinor
        With -Package: bump the MINOR version of EVERY selected product and reset patch (2.5.3 -> 2.6.0).

    .PARAMETER BumpMajor
        With -Package: bump the MAJOR version of EVERY selected product and reset the rest (2.5.3 -> 3.0.0).

    .PARAMETER Parallel
        Package all selected products at once as background jobs instead of one at a time. Faster,
        but four concurrent publishes will peg the machine; each job's output goes to its own log.

    .PARAMETER SkipShare
        Skip the copy-to-share + prune tail; leave the packages in C:\Bits only.

    .EXAMPLE
        dpall -Package -Bump
        Patch-bumps and packages all four products one at a time, then publishes each to the share.

    .EXAMPLE
        dpall -Products speed,crewchief -Package -BumpMinor
        Minor-bumps and packages just TestAuto and CrewChief.

    .EXAMPLE
        dpall -Package -Parallel
        Repackages all four at their current versions concurrently, one log file per product.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
    param(
        [ValidateSet('speed', 'crewchief', 'datagen', 'mutate')]
        [string[]]$Products = @('speed', 'crewchief', 'datagen', 'mutate'),

        [ValidateSet('Debug', 'Release')]
        [string]$Configuration,

        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [switch]$Parallel,
        [switch]$SkipShare,

        [Alias('h', 'help')]
        [switch]$ShowHelp
    )

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpall  - package (and optionally version-bump) ALL SpeedMerchants products" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "USAGE" -ForegroundColor Yellow
        Write-Host "  dpall -Package [-Bump|-BumpMinor|-BumpMajor] [-Products speed,crewchief,datagen,mutate] [-Configuration Debug|Release] [-Parallel] [-SkipShare] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "PRODUCTS" -ForegroundColor Yellow
        Write-Host "  speed      TestAuto                        (dpspeed -Package)"
        Write-Host "  crewchief  CrewChief                       (dpcrewchief -Package)"
        Write-Host "  datagen    TestDataGeneration              (dpdatagen -Package)"
        Write-Host "  mutate     TestDataGenerationAndMutation   (dpmutate -Package)"
        Write-Host ""
        Write-Host "OPTIONS" -ForegroundColor Yellow
        Write-Host "  -Package        Required. Package the selected products (same as dp* -Package)."
        Write-Host "  -Bump           With -Package: patch bump on EVERY selected product (2.5.0 -> 2.5.1)."
        Write-Host "  -BumpMinor      With -Package: minor bump + reset patch (2.5.3 -> 2.6.0)."
        Write-Host "  -BumpMajor      With -Package: major bump + reset the rest (2.5.3 -> 3.0.0)."
        Write-Host "                  At most one; without one the current versions are reused. The SAME"
        Write-Host "                  level applies to all selected products; per-product bumps stay in"
        Write-Host "                  the individual dp* commands."
        Write-Host "  -Parallel       All at once as background jobs (default is one at a time)."
        Write-Host "  -SkipShare      Leave packages in $global:GeneBitsDir; no copy/prune on the team share."
        Write-Host ""
        Write-Host "EXAMPLES" -ForegroundColor Yellow
        Write-Host "  dpall -Package -Bump"
        Write-Host "  dpall -Products speed,crewchief -Package -BumpMinor"
        Write-Host "  dpall -Package -Parallel"
        Write-Host ""
        Write-Host "Serial builds print to the console; -Parallel logs to $global:GeneBitsDir\dpall-<product>.log and the summary names each log." -ForegroundColor DarkGray
        Write-Host "dpall packages only - it never builds-and-runs an app. Use dpspeed/dpcrewchief/dpdatagen/dpmutate for that." -ForegroundColor DarkGray
        return
    }

    # Same guards as dpspeed: bump switches only apply with -Package, and at most one of them. They
    # throw HERE (not just in the repo scripts) so a -WhatIf preview refuses exactly like a real run.
    $bumpCount = @($Bump, $BumpMinor, $BumpMajor | Where-Object { $_ }).Count
    if ($bumpCount -gt 0 -and -not $Package) {
        throw 'dpall: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if (-not $Package) {
        throw 'dpall: pass -Package (dpall packages only). Example: dpall -Package -Bump. See dpall -h.'
    }
    if ($bumpCount -gt 1) {
        throw 'dpall: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    $repoRoot = $global:GeneMachine.SpeedMerchantsRepo

    # Single source of truth for the per-product knobs. Product = the token
    # Publish-SpeedMerchantsPackage validates; VersionFile is read back AFTER packaging so the
    # summary shows what actually shipped rather than what we asked for.
    $catalog = [ordered]@{
        speed = @{
            Label       = 'TestAuto'
            Product     = 'TestAuto'
            Script      = Join-Path $repoRoot 'installer\New-TestAutoInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestAuto.Web\TestAuto.Web.csproj'
        }
        crewchief = @{
            Label       = 'CrewChief'
            Product     = 'CrewChief'
            Script      = Join-Path $repoRoot 'CrewChief\installer\New-CrewChiefInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'CrewChief\Directory.Build.props'
        }
        datagen = @{
            Label       = 'TestDataGeneration'
            Product     = 'TestDataGeneration'
            Script      = Join-Path $repoRoot 'TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestData.Generation\Directory.Build.props'
        }
        mutate = @{
            Label       = 'TestDataGenerationAndMutation'
            Product     = 'TestDataGenerationAndMutation'
            Script      = Join-Path $repoRoot 'TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestData.Mutation\Directory.Build.props'
        }
    }

    # De-duplicated and ordered by the catalog, not by the order the caller typed them, so
    # "-Products mutate,speed,speed" is one predictable run.
    $selected = @($catalog.Keys | Where-Object { $Products -contains $_ })
    if ($selected.Count -eq 0) { throw 'dpall: no products selected.' }

    # Preflight every script BEFORE launching anything - a missing script found halfway through a
    # parallel run would leave a partially bumped set of repos.
    foreach ($key in $selected) {
        $scriptPath = $catalog[$key].Script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "dpall: packaging script not found for '$key': $scriptPath"
        }
    }

    # <Version> reader shared by the -WhatIf preview and the post-run summary. Returns $null rather
    # than throwing - a version we cannot parse is a cosmetic gap in the summary, never a failure.
    $readVersion = {
        param($Path)
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $text = Get-Content -Raw -LiteralPath $Path
        if ($text -match '<Version>\s*(?<v>\d+\.\d+\.\d+)\s*</Version>') { $Matches.v } else { $null }
    }

    $bumpLabel = if ($BumpMajor) { 'MAJOR' } elseif ($BumpMinor) { 'MINOR' } elseif ($Bump) { 'PATCH' } else { $null }
    $cfgLabel  = if ($Configuration) { $Configuration } else { 'Release' }

    if ($WhatIfPreference) {
        $mode = if ($Parallel) { 'in parallel' } else { 'serially' }
        Write-Host "[WhatIf] Would package $($selected.Count) product(s) $mode (-Configuration $cfgLabel):" -ForegroundColor Yellow
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            $cur   = & $readVersion $entry.VersionFile
            $curTxt = if ($cur) { $cur } else { '<unreadable>' }
            if ($bumpLabel) {
                Write-Host ("[WhatIf]   {0,-30} {1} bump from {2} in {3}" -f $entry.Label, $bumpLabel, $curTxt, $entry.VersionFile) -ForegroundColor Yellow
            }
            else {
                Write-Host ("[WhatIf]   {0,-30} repackage at {1} (no bump)" -f $entry.Label, $curTxt) -ForegroundColor Yellow
            }
            Write-Host ("[WhatIf]   {0,-30} -> $global:GeneBitsDir\{1}-Setup-<version>.exe" -f '', $entry.Product) -ForegroundColor Yellow
        }
        if ($SkipShare) {
            Write-Host "[WhatIf] Would NOT touch the team share (-SkipShare)." -ForegroundColor Yellow
        }
        else {
            Write-Host "[WhatIf] Would then copy each package to $($global:GeneMachine.PackageShare) and prune strictly-older versions of the SAME product." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess(($selected -join ', '), "Package$(if ($bumpLabel) { " with $bumpLabel bump" })")) { return }

    # Arg splat handed to every installer script. Identical for all four - that uniformity is the
    # whole point of the command, and it is why -Bump is not per-product.
    $packArgs = @{ OutputDir = $global:GeneBitsDir }
    if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
    if ($Bump)      { $packArgs.Bump      = $true }
    if ($BumpMinor) { $packArgs.BumpMinor = $true }
    if ($BumpMajor) { $packArgs.BumpMajor = $true }

    # Taken ONCE, before anything builds, and passed to every Publish-SpeedMerchantsPackage call so
    # its -BuiltAfter staleness guard covers the whole run.
    $packStarted = Get-Date
    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $Parallel) {
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            Write-Host ""
            Write-Host "=== $($entry.Label) ===" -ForegroundColor Cyan
            $started = Get-Date
            $ok = $true
            $err = $null
            try { & $entry.Script @packArgs }
            catch { $ok = $false; $err = $_.Exception.Message; Write-Warning "$($entry.Label) FAILED: $err" }
            $results.Add([pscustomobject]@{
                Key = $key; Label = $entry.Label; Product = $entry.Product
                VersionFile = $entry.VersionFile; Ok = $ok; Error = $err
                Duration = (Get-Date) - $started; Log = '(live console)'
            })
        }
    }
    else {
        # Each job is its own pwsh process: no profile, no shared runspace state, and one product's
        # $ErrorActionPreference or working directory cannot leak into another's build.
        # A job has no console, so a NuGet feed device-code sign-in would wait unseen: the scripts fail
        # fast instead (-NoInteractiveRestore). Serial dpall signs in interactively on a failed publish.
        $jobArgs = $packArgs.Clone()
        $jobArgs.NoInteractiveRestore = $true
        $jobs = @{}
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            New-Item -ItemType Directory -Path $global:GeneBitsDir -Force | Out-Null
            $log   = Join-Path $global:GeneBitsDir "dpall-$key.log"
            $jobs[$key] = @{
                Entry   = $entry
                Log     = $log
                Started = Get-Date
                Job     = Start-Job -Name "dpall-$key" -ScriptBlock {
                    param($ScriptPath, $ArgTable, $LogPath)

                    # Output is COLLECTED, not piped straight to a file, so a throw partway through
                    # still leaves the lines that led up to it in the log (a pipeline to Out-File
                    # loses its buffer when the upstream command throws).
                    $lines = [System.Collections.Generic.List[string]]::new()
                    $ok = $true
                    $err = $null
                    try {
                        & $ScriptPath @ArgTable *>&1 | ForEach-Object { $lines.Add([string]$_) }
                    }
                    catch {
                        $ok = $false
                        $err = $_.Exception.Message
                        $lines.Add(($_ | Out-String))
                    }
                    finally {
                        try { Set-Content -LiteralPath $LogPath -Value $lines -Encoding utf8 } catch { }
                    }
                    [pscustomobject]@{ Ok = $ok; Error = $err }
                } -ArgumentList $entry.Script, $jobArgs, $log
            }
        }

        Write-Host ""
        Write-Host "Packaging $($selected.Count) product(s) in parallel. Logs:" -ForegroundColor Cyan
        foreach ($key in $selected) { Write-Host ("  {0,-30} {1}" -f $catalog[$key].Label, $jobs[$key].Log) -ForegroundColor DarkGray }
        Write-Host ""

        # Light completion ticker rather than a live tail - four interleaved build logs on one
        # console are unreadable, and each product's full output is already on disk.
        $pending = [System.Collections.Generic.List[string]]::new([string[]]$selected)
        while ($pending.Count -gt 0) {
            Start-Sleep -Seconds 5
            foreach ($key in @($pending)) {
                $j = $jobs[$key].Job
                if ($j.State -in 'Completed', 'Failed', 'Stopped') {
                    $entry   = $jobs[$key].Entry
                    $elapsed = (Get-Date) - $jobs[$key].Started
                    $payload = Receive-Job -Job $j -ErrorAction SilentlyContinue | Select-Object -Last 1
                    $ok  = ($j.State -eq 'Completed') -and $payload -and $payload.Ok
                    $err = if ($payload -and $payload.Error) { $payload.Error }
                           elseif (-not $ok) { "job ended $($j.State)" }
                           else { $null }
                    $results.Add([pscustomobject]@{
                        Key = $key; Label = $entry.Label; Product = $entry.Product
                        VersionFile = $entry.VersionFile; Ok = $ok; Error = $err
                        Duration = $elapsed; Log = $jobs[$key].Log
                    })
                    $color = if ($ok) { 'Green' } else { 'Red' }
                    $verb  = if ($ok) { 'done' } else { 'FAILED' }
                    Write-Host ("  {0,-30} {1} in {2:mm\:ss}" -f $entry.Label, $verb, $elapsed) -ForegroundColor $color
                    Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
                    [void]$pending.Remove($key)
                }
            }
        }
    }

    # Share tail runs in this session (Publish-SpeedMerchantsPackage lives in this profile, so a
    # background job would not have it) but is handed ALL succeeded products in ONE call. That is
    # what lets it take a single share listing, skip any package the share already holds byte-for-
    # byte, and upload the rest in parallel - the upload is ~45s per 81 MB package against
    # CORPNAS01, so four serial calls used to cost ~3 min on their own.
    if (-not $SkipShare) {
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        if (-not $publishCmd) {
            Write-Warning "Publish-SpeedMerchantsPackage not found - packages left in $global:GeneBitsDir."
        }
        else {
            $productSet = @(
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            )
            Write-Host ""
            # Unsupported products are filtered out BEFORE the batch call: -Product has a
            # ValidateSet, so one unknown name would fail the whole batch instead of just its own.
            $shareProducts = foreach ($r in @($results | Where-Object { $_.Ok })) {
                if ($productSet.Count -gt 0 -and $productSet -notcontains $r.Product) {
                    Write-Warning ("Share deploy skipped for {0}: Publish-SpeedMerchantsPackage -Product accepts only [{1}]. The package is in $global:GeneBitsDir." -f $r.Label, ($productSet -join ', '))
                    continue
                }
                $r.Product
            }
            $shareProducts = @($shareProducts)
            if ($shareProducts.Count -gt 0) {
                Publish-SpeedMerchantsPackage -Product $shareProducts -BuiltAfter $packStarted
            }
        }
    }

    # Version read back from the file AFTER the run, so the summary reports what shipped.
    Write-Host ""
    Write-Host "dpall summary ($cfgLabel$(if ($bumpLabel) { ", $bumpLabel bump" }))" -ForegroundColor Cyan
    foreach ($r in $results) {
        $ver    = & $readVersion $r.VersionFile
        $verTxt = if ($ver) { $ver } else { '?' }
        $status = if ($r.Ok) { 'OK    ' } else { 'FAILED' }
        $color  = if ($r.Ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0}  {1,-30} {2,-10} {3:mm\:ss}" -f $status, $r.Label, $verTxt, $r.Duration) -ForegroundColor $color
        if (-not $r.Ok) {
            Write-Host ("          {0}" -f $r.Error) -ForegroundColor Red
            Write-Host ("          log: {0}" -f $r.Log) -ForegroundColor DarkGray
        }
    }

    # Failures throw only AFTER the summary and the share tail, so one broken product never hides
    # the other three's results or strands their packages in C:\Bits.
    $failed = @($results | Where-Object { -not $_.Ok })
    if ($failed.Count -gt 0) {
        throw ("dpall: {0} of {1} product(s) failed to package: {2}. See the log(s) above." -f $failed.Count, $results.Count, (($failed.Label) -join ', '))
    }
}

function dpv2 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Test,
        [switch]$Arch,
        [switch]$Chaos,

        [ValidateSet('Coordinator','Agent','Cli','Web')]
        [string]$Run,

        [switch]$ComposeUp,
        [switch]$ComposeDown,

        # Dial a REAL authenticated Profisee REST GET workload up and back down, and print the
        # observed worker count and achieved request rate at each step. This is UoW-8's U0 proof.
        [switch]$Dial,

        [switch]$CleanBuild,

        [switch]$LoopStatus,
        [switch]$Criteria,

        # Build the Speedy server release: images + offline bundle + SpeedyServer-Setup-<version>.exe,
        # written straight to the NAS by New-SpeedyBundle.ps1 (the repo's deploy\ folder).
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,
        [switch]$AllowDirty,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    $repo = $global:GeneMachine.SpeedyRepo
    $bundleScript = Join-Path $repo 'deploy\New-SpeedyBundle.ps1'
    $sln  = Join-Path $repo 'Speedmerchants.sln'

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpv2  - Speedmerchants vNext build/test/run helper (standalone repo, NOT speed-merchants)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpv2 [-Test] [-Arch] [-Chaos] [-Dial] [-Run Coordinator|Agent|Cli|Web] [-ComposeUp] [-ComposeDown] [-CleanBuild] [-LoopStatus] [-Criteria] [-Package [-Bump|-BumpMinor|-BumpMajor] [-AllowDirty]] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  (none)        Rebuild the LOCAL environment: dpContainers (all images from this tree, compose up,"
        Write-Host "                fleet-2/fleet-3, migrate exited 0, web answers on /health, standing services hold). No tests."
        Write-Host "  -Test         dotnet build -warnaserror, then the full test suite."
        Write-Host "  -Arch         Run Tests.Architecture only (dependency direction, token census, config round-trip)."
        Write-Host "  -Chaos        Run Tests.Chaos only (kill/restart durability suites; needs Docker for container chaos)."
        Write-Host "  -Dial         Dial a REAL authenticated Profisee REST GET workload up and back down."
        Write-Host "                Prints the observed worker count and achieved request rate at each step."
        Write-Host "                Needs SM_WORKLOAD_URL + SM_WORKLOAD_APIKEY at User scope. ~2700 GETs."
        Write-Host "  -Run <host>   dotnet run the Coordinator, Agent, Cli, or Web host project."
        Write-Host "  -ComposeUp    docker compose up -d --wait (RabbitMQ mgmt UI: http://localhost:15672, SQL warehouse)."
        Write-Host "  -ComposeDown  docker compose down (volumes preserved)."
        Write-Host "  -CleanBuild   dotnet clean + wipe bin/obj before building."
        Write-Host "  -LoopStatus   Show the overnight loop's last PROGRESS entries + criteria state (.loop\)."
        Write-Host "  -Criteria     Show Done-when criteria pass/fail from .loop\CRITERIA.json (read-only; never re-runs them)."
        Write-Host "  -Package      Rebuild the LOCAL environment on the new version FIRST (as plain dpv2), then build the"
        Write-Host "                Speedy server release: the images, the offline bundle and"
        Write-Host "                SpeedyServer-Setup-<version>.exe, written straight to"
        Write-Host "                $($global:GeneMachine.PackageShare)\Deployment\<version>\ (latest.txt moves last)."
        Write-Host "                Thin wrapper over $bundleScript."
        Write-Host "                Version = <Version> in Directory.Build.props; a version that already has a bundle is refused."
        Write-Host "  -Bump         With -Package: bump the patch version (1.0.0 -> 1.0.1) first. Commit Directory.Build.props after."
        Write-Host "  -BumpMinor    With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor    With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "  -AllowDirty   With -Package: build from uncommitted changes (tag <version>-dirty.<time>; never a release)."
        Write-Host "  -WhatIf       Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  Repo: $repo  (own git; commits allowed here, unlike other repos)."
        Write-Host "  Design docs: $($global:GeneMachine.VaultDocsRoot)\speed-merchants\vNext\vNextImplementation_v2.md"
        Write-Host "               (the planning\ plan is SUPERSEDED - it lives in that folder's Archive\ now)."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpv2                 Rebuild the local containers from this tree."
        Write-Host "  dpv2 -Test           Build + test everything."
        Write-Host "  dpv2 -Arch           Fast architecture-rule check."
        Write-Host "  dpv2 -ComposeUp      Bring up broker + warehouse, wait for health."
        Write-Host "  dpv2 -Dial           Dial a real REST workload up and back down (UoW-8 U0)."
        Write-Host "  dpv2 -Run Cli        Run the CLI host."
        Write-Host "  dpv2 -LoopStatus     What did the overnight loop do?"
        Write-Host "  dpv2 -Package -Bump  Bump 1.0.0 -> 1.0.1, rebuild the local containers on 1.0.1, then build the"
        Write-Host "                       bundle + SpeedyServer-Setup-1.0.1.exe on the NAS."
        Write-Host "                       Then relay it on CORPSQL03 (Copy-SpeedyBundle.ps1) and run the Setup on each VM."
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $repo)) {
        throw "dpv2: repo not found at $repo - has the vNext loop created it yet?"
    }

    # Guard: bump switches only mean something with -Package (a forgotten -Package would otherwise fall
    # through to build+test with no bump and no error). Multi-bump throws HERE so -WhatIf refuses too.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if (($bumpSwitchCount -gt 0 -or $AllowDirty) -and -not $Package) {
        throw 'dpv2: -Bump/-BumpMinor/-BumpMajor/-AllowDirty only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpv2: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    # --- Speedy server release package (profile-free path: run the bundle script directly) ---
    if ($Package) {
        if (-not (Test-Path -LiteralPath $bundleScript)) {
            throw "dpv2: bundle script not found: '$bundleScript'. It ships in the speedmerchants repo (deploy\New-SpeedyBundle.ps1); check SpeedyRepo in $global:GeneMachineConfigPath and that the tree is current."
        }
        # -LocalStack: the bundle script rebuilds and restarts the local stack on the version it just wrote,
        # before any bundle image, so the laptop runs what the bundle ships.
        $bundleArgs = @('-LocalStack')
        if ($Bump) { $bundleArgs += '-Bump' }
        if ($BumpMinor) { $bundleArgs += '-BumpMinor' }
        if ($BumpMajor) { $bundleArgs += '-BumpMajor' }
        if ($AllowDirty) { $bundleArgs += '-AllowDirty' }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: powershell.exe -File `"$bundleScript`" $($bundleArgs -join ' ')" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would rebuild the local containers on that version first (compose build, up, fleet-2/3)." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would produce: $($global:GeneMachine.PackageShare)\Deployment\<version>\SpeedyServer-Setup-<version>.exe" -ForegroundColor Yellow
            return
        }
        # Windows PowerShell 5.1, the runtime every bundle so far was built and proven with.
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bundleScript @bundleArgs
        if ($LASTEXITCODE -ne 0) { throw "dpv2: packaging FAILED (exit $LASTEXITCODE). A bundle folder without BUNDLE-COMPLETE may be left on the NAS: delete it and run again." }
        if ($bumpSwitchCount -gt 0) {
            Write-Host "dpv2: commit Directory.Build.props - the next -Package refuses a dirty tree until you do." -ForegroundColor Yellow
        }
        return
    }

    # --- Read-only loop views (work even while a loop is running; never mutate .loop state) ---
    if ($LoopStatus -or $Criteria) {
        $loopDir = Join-Path $repo '.loop'
        if (-not (Test-Path -LiteralPath $loopDir)) {
            Write-Host "No .loop\ state at $repo - no loop has been initialized." -ForegroundColor Yellow
            return
        }
        $critFile = Join-Path $loopDir 'CRITERIA.json'
        if (Test-Path -LiteralPath $critFile) {
            $doc = Get-Content -Raw -LiteralPath $critFile | ConvertFrom-Json
            Write-Host ""
            Write-Host "Done-when criteria (latest recorded run):" -ForegroundColor Cyan
            foreach ($c in $doc.criteria) {
                # Schema per Test-Criteria.ps1: nested baseline{exit,passed,at,...} and latest (null until re-run)
                $state = if ($null -ne $c.latest) { $c.latest } else { $c.baseline }
                $ok = [bool]$state.passed
                $when = if ($null -ne $c.latest) { 'latest' } else { 'baseline' }
                $mark = if ($ok) { '[PASS]' } else { '[fail]' }
                $color = if ($ok) { 'Green' } else { 'DarkYellow' }
                Write-Host ("  {0} {1}  ({2})" -f $mark, $c.label, $when) -ForegroundColor $color
            }
        }
        if ($LoopStatus) {
            $prog = Join-Path $loopDir 'PROGRESS.md'
            if (Test-Path -LiteralPath $prog) {
                Write-Host ""
                Write-Host "PROGRESS (tail):" -ForegroundColor Cyan
                Get-Content -LiteralPath $prog -Tail 40
            }
            Write-Host ""
            Write-Host "Recent commits:" -ForegroundColor Cyan
            git -C $repo log --oneline -10 2>$null
        }
        return
    }

    # --- The dial proof: a real authenticated REST GET workload, dialled up and back down ---
    #
    # The credential is read from the User-scope environment and passed to the child process through
    # the environment, never as an argument: an argument lands in this process's command line, where
    # `ps`, a crash dump and the shell history can all read it. Nothing here echoes either value.
    if ($Dial) {
        $proof = Join-Path $repo 'scripts\dial\Invoke-RestDialProof.ps1'
        if (-not (Test-Path -LiteralPath $proof)) {
            throw "dpv2: $proof not found - UoW-8 iteration 1 lands it."
        }

        # A profile function runs inside a shell that may have started BEFORE these were set, and a
        # process does not re-read the registry once it is running. Read the User scope explicitly
        # rather than trusting what this process happens to have inherited - the failure mode of
        # getting that wrong is a run that succeeds against the wrong installation.
        foreach ($name in 'SM_WORKLOAD_URL', 'SM_WORKLOAD_APIKEY') {
            $value = [Environment]::GetEnvironmentVariable($name, 'User')
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw "dpv2: $name is not set at User scope. It must carry the workload target; nothing is defaulted, because a guessed target turns 'nobody configured this' into 'the target answered nothing'."
            }
            # [Environment]::SetEnvironmentVariable and NOT Set-Item, for one specific reason:
            # Set-Item supports ShouldProcess, so under -WhatIf it announces the operation INCLUDING
            # the value it would set - which prints the API key to the console in the one code path
            # whose entire job is keeping that key off the command line. A .NET call has no WhatIf
            # narration and says nothing. Found by running `dpv2 -Dial -WhatIf` and reading it.
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }

        Write-Host "Dialling $([Environment]::GetEnvironmentVariable('SM_WORKLOAD_URL','User'))" -ForegroundColor Cyan
        Write-Host "Roughly 2700 GETs against a SHARED cloud instance. Run it deliberately." -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess($proof, 'run the REST dial proof')) {
            pwsh -NoProfile -File $proof
            if ($LASTEXITCODE -ne 0) { throw "dpv2: the dial proof FAILED (exit $LASTEXITCODE)." }
            Write-Host "dpv2: the fleet followed the dial up and back down." -ForegroundColor Green
        }
        return
    }

    # --- Compose lifecycle ---
    if ($ComposeUp -or $ComposeDown) {
        $compose = Join-Path $repo 'compose.yaml'
        if (-not (Test-Path -LiteralPath $compose)) {
            throw "dpv2: $compose not found in $repo."
        }
        if ($ComposeUp -and $PSCmdlet.ShouldProcess($compose, 'docker compose up -d --wait')) {
            docker compose -f $compose up -d --wait
            if ($LASTEXITCODE -ne 0) { throw "dpv2: docker compose up failed (exit $LASTEXITCODE). Is Rancher Desktop running?" }
            Write-Host "Services healthy. RabbitMQ mgmt: http://localhost:15672" -ForegroundColor Green
        }
        if ($ComposeDown -and $PSCmdlet.ShouldProcess($compose, 'docker compose down')) {
            docker compose -f $compose down
        }
        return
    }

    # --- Run a host ---
    if ($Run) {
        $proj = Join-Path $repo "src\$Run\$Run.csproj"
        if (-not (Test-Path -LiteralPath $proj)) { throw "dpv2: $proj not found." }
        if ($PSCmdlet.ShouldProcess($proj, 'dotnet run')) {
            dotnet run --project $proj
        }
        return
    }

    if (-not (Test-Path -LiteralPath $sln)) {
        throw "dpv2: $sln not found - the scaffold loop (UoW-0) has not landed it yet. Try: dpv2 -LoopStatus"
    }

    # --- Clean ---
    if ($CleanBuild -and $PSCmdlet.ShouldProcess($sln, 'dotnet clean + wipe bin/obj')) {
        dotnet clean $sln | Out-Host
        Get-ChildItem -LiteralPath $repo -Recurse -Directory -Force |
            Where-Object { $_.Name -in 'bin','obj' -and $_.FullName -notmatch '\\\.git\\|\\\.loop\\' } |
            Remove-Item -Recurse -Force -Confirm:$false
    }

    # --- Targeted test suites ---
    if ($Arch) {
        if ($PSCmdlet.ShouldProcess($sln, 'run Tests.Architecture')) {
            dotnet test (Join-Path $repo 'tests\Tests.Architecture\Tests.Architecture.csproj')
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: architecture tests FAILED.' }
        }
        return
    }
    if ($Chaos) {
        if ($PSCmdlet.ShouldProcess($sln, 'run Tests.Chaos')) {
            dotnet test (Join-Path $repo 'tests\Tests.Chaos\Tests.Chaos.csproj')
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: chaos tests FAILED.' }
        }
        return
    }
    if ($Test) {
        if ($PSCmdlet.ShouldProcess($sln, 'dotnet build -warnaserror + dotnet test')) {
            dotnet build $sln -warnaserror
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: build FAILED.' }
            dotnet test $sln --no-build
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: test suite FAILED.' }
            Write-Host "dpv2: build + tests green." -ForegroundColor Green
        }
        return
    }

    # --- Default: rebuild the local environment (Gene, 2026-09-25) ---
    dpContainers -WhatIf:$WhatIfPreference
}

function dpContainers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # Restart on the existing images; skip the image build.
        [switch]$NoBuild,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    $repo    = $global:GeneMachine.SpeedyRepo
    $compose = Join-Path $repo 'compose.yaml'
    $fleets  = Join-Path $repo 'compose.fleets.yaml'

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpContainers  - Rebuild the Speedy (speedmerchants) images and restart the stack on them" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpContainers [-NoBuild] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Steps:" -ForegroundColor Yellow
        Write-Host "  1. docker compose --profile tools build        (all images, migrate included)"
        Write-Host "  2. docker compose up -d                        (recreates containers on the new images)"
        Write-Host "  3. docker compose -f compose.yaml -f compose.fleets.yaml up -d fleet-2 fleet-3"
        Write-Host "  4. Checks migrate exited 0, web answers on /health (https://localhost:5310 when .env.local sets https,"
        Write-Host "     else http://127.0.0.1:5310), and coordinator + fleets stay running for 20s without restarting"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -NoBuild      Skip step 1; restart on the images already built."
        Write-Host "  -WhatIf       Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  Needs Rancher Desktop running and SM_SA_PASSWORD at User scope."
        Write-Host "  Never 'docker start' after a rebuild - it restarts the OLD containers on the OLD images."
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $compose)) { throw "dpContainers: $compose not found." }

    # A shell started before the variable was set does not have it; read the User scope explicitly.
    # Never echoed.
    $sa = [Environment]::GetEnvironmentVariable('SM_SA_PASSWORD', 'User')
    if ([string]::IsNullOrWhiteSpace($sa)) {
        throw "dpContainers: SM_SA_PASSWORD is not set at User scope; compose cannot start the warehouse without it."
    }
    [Environment]::SetEnvironmentVariable('SM_SA_PASSWORD', $sa, 'Process')

    docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "dpContainers: Docker is not answering. Is Rancher Desktop running?" }

    if (-not $NoBuild -and $PSCmdlet.ShouldProcess($compose, 'docker compose --profile tools build')) {
        docker compose -f $compose --profile tools build
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: image build FAILED (exit $LASTEXITCODE)." }
    }

    if ($PSCmdlet.ShouldProcess($compose, 'docker compose up -d')) {
        docker compose -f $compose up -d
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: compose up FAILED (exit $LASTEXITCODE). Check: docker compose logs migrate" }
    }

    if ($PSCmdlet.ShouldProcess($fleets, 'docker compose up -d fleet-2 fleet-3')) {
        docker compose -f $compose -f $fleets up -d fleet-2 fleet-3
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: fleet-2/fleet-3 up FAILED (exit $LASTEXITCODE)." }
    }

    if ($WhatIfPreference) { return }

    docker compose -f $compose ps -a | Out-Host

    $migrate = docker inspect speedmerchants-migrate-1 --format '{{.State.Status}} {{.State.ExitCode}}' 2>$null
    if ($migrate -ne 'exited 0') {
        throw "dpContainers: migrate is '$migrate', expected 'exited 0'. Check: docker compose -f $compose logs migrate"
    }

    # A crash-looping container reads 'running' for the second after each restart, so one inspect right
    # after 'up' can pass a dead service. Snapshot each restart count, let the stack settle, then require
    # the service to be running AND its count unchanged.
    $standing = 'coordinator', 'fleet', 'fleet-2', 'fleet-3'
    $restartsBefore = @{}
    foreach ($svc in $standing) {
        $restartsBefore[$svc] = docker inspect "speedmerchants-$svc-1" --format '{{.RestartCount}}'
    }
    Start-Sleep -Seconds 20

    # Probe the anonymous /health route; every other web route sits behind sign-in and answers 401.
    # Once scripts\e2e\Write-SpeedyStackEnv.ps1 has written .env.local the same port serves https only,
    # with the CN=localhost dev certificate, so the probe follows the scheme that file sets.
    $envLocal = Join-Path $repo '.env.local'
    $servesHttps = (Test-Path -LiteralPath $envLocal) -and
        (Select-String -LiteralPath $envLocal -Pattern '^ASPNETCORE_URLS=https:' -Quiet)
    $webProbe = if ($servesHttps) { 'https://localhost:5310/health' } else { 'http://127.0.0.1:5310/health' }
    try {
        $code = (Invoke-WebRequest -Uri $webProbe -UseBasicParsing -TimeoutSec 30).StatusCode
    }
    catch {
        throw "dpContainers: web did not answer on $webProbe ($($_.Exception.Message))."
    }

    # Standing services must be running, not crash-looping.
    $restarting = @(foreach ($svc in $standing) {
        $state = docker inspect "speedmerchants-$svc-1" --format '{{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}'
        $status, $exit, $restarts = -split $state
        if ($status -ne 'running' -or $restarts -ne $restartsBefore[$svc]) {
            "$svc ($status, exit $exit, restarts $($restartsBefore[$svc]) -> $restarts)"
        }
    })
    if ($restarting.Count -gt 0) {
        throw "dpContainers: not running: $($restarting -join ', '). Check: docker compose -f $compose logs --tail 50 <service>"
    }
    Write-Host "dpContainers: migrate exited 0, web answered $code on $webProbe." -ForegroundColor Green
}
