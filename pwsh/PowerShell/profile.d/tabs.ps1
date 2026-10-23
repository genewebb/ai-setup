# profile.d\tabs: Windows Terminal tabs and remote shells (addtab, addnew, addLinux). Definitions only; loaded by the core profile.

function addtab {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name,

        [string]$Path,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "addtab <name...> [<path>] [-Path <path>] [-h|--help]" @(
            "Open a new tab in the current Windows Terminal window, titled <name>.",
            "The name is required; all words join into one title ('addtab Author 1' -> 'Author 1').",
            "Directory: -Path, or a trailing word that is an existing folder, else the current folder.",
            "Examples:",
            "  addtab Author 1",
            "  addtab Author 1 D:\devops\repos\speedmerchants",
            "  addtab build 2 -Path D:\devops\repos\speedmerchants"
        )
        return
    }

    if (-not (Test-GeneWt -Caller 'addtab')) { return }

    $words = @($Name | Where-Object { $_ })
    # A trailing word that is an existing folder is the directory, not part of the title.
    if (-not $Path -and $words.Count -gt 1 -and (Test-Path -LiteralPath $words[-1] -PathType Container)) {
        $Path  = $words[-1]
        $words = @($words[0..($words.Count - 2)])
    }

    $title = ($words -join ' ').Trim()
    if (-not $title) {
        Write-Warning "addtab: a tab name is required. Use 'addnew' for a tab with the default name."
        return
    }

    if (-not $Path) { $Path = (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "addtab: folder not found: $Path"
        return
    }

    New-GeneTab -Directory $Path -Title $title
    Write-Host "Opened tab '$title' -> $Path" -ForegroundColor DarkGray
}

function addnew {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateRange(1,50)]
        [int]$Count = 1,

        [Parameter(Position=1)]
        [string]$Path,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "addnew [[-Count] <1..50>] [[-Path] <path>] [-h|--help]" @(
            "Open 1..N new tabs in the current Windows Terminal window with the default tab name.",
            "Directory: -Path, else the current folder.",
            "Alias: ntab",
            "Examples:",
            "  addnew",
            "  addnew 3",
            "  addnew 2 D:\devops\repos"
        )
        return
    }

    if (-not (Test-GeneWt -Caller 'addnew')) { return }

    if (-not $Path) { $Path = (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "addnew: folder not found: $Path"
        return
    }

    1..$Count | ForEach-Object { New-GeneTab -Directory $Path }
}

# Optional short alias (safer than using 'add')
Set-Alias -Name ntab -Value addnew -ErrorAction SilentlyContinue

# -----------------------------
# Linux droplet (DigitalOcean SFO2, Ubuntu 24.04 LTS)
# -----------------------------
function addLinux {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [string]$User = 'gene',
        [string]$HostAddress = '138.68.42.81',
        [string]$KeyFile = (Join-Path $HOME '.ssh\do_droplet_ed25519'),
        [switch]$Desktop,
        [int]$DesktopLocalPort = 13389,
        [switch]$Cockpit,
        [int]$CockpitLocalPort = 19090,
        [Alias('h','help')]
        [switch]$ShowHelp,
        [Parameter(ValueFromRemainingArguments=$true)]
        $RemoteCommand
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp -RemainingArgs $RemoteCommand) {
        Write-Usage "addLinux [-User <name>] [-HostAddress <ip>] [-KeyFile <path>] [-Desktop [-DesktopLocalPort <port>]] [-Cockpit [-CockpitLocalPort <port>]] [<remote command>] [-h|--help]" @(
            "SSH into the DigitalOcean Ubuntu droplet (default gene@138.68.42.81, SFO2, 2 GB)."
            "Root SSH login is disabled; gene has passwordless sudo, e.g. addLinux 'sudo apt update'."
            "Uses passphrase-less key $HOME\.ssh\do_droplet_ed25519."
            "Anything after the options runs as a one-off remote command, e.g. addLinux uptime"
            ""
            "-Desktop  Opens a hidden SSH tunnel localhost:$DesktopLocalPort -> droplet xrdp (3389), then"
            "          launches Remote Desktop to it. Log in as gene. RDP is never exposed to the internet."
            "-Cockpit  Opens a hidden SSH tunnel localhost:$CockpitLocalPort -> droplet Cockpit (9090), then"
            "          opens https://localhost:$CockpitLocalPort (self-signed cert warning is expected). Log in as gene."
            "Stop a tunnel with the Stop-Process command it prints."
        )
        return
    }

    Assert-PathExists $KeyFile
    $baseArgs = @('-i', $KeyFile, '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new')

    # Hidden 'ssh -N -L local:localhost:remote'; returns the ssh process once the local port accepts connections.
    $openTunnel = {
        param([int]$LocalPort, [int]$RemotePort, [string]$Label)
        $tunnelArgs = $baseArgs + @('-N', '-o', 'ExitOnForwardFailure=yes', '-L', "${LocalPort}:localhost:${RemotePort}", "$User@$HostAddress")
        $tunnel = Start-Process ssh -ArgumentList $tunnelArgs -WindowStyle Hidden -PassThru

        $ready = $false
        for ($i = 0; $i -lt 30 -and -not $ready -and -not $tunnel.HasExited; $i++) {
            $client = [System.Net.Sockets.TcpClient]::new()
            try { $ready = $client.ConnectAsync('127.0.0.1', $LocalPort).Wait(500) -and $client.Connected } catch { $ready = $false }
            finally { $client.Dispose() }
            if (-not $ready) { Start-Sleep -Milliseconds 500 }
        }
        if (-not $ready) {
            if (-not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
            throw "$Label tunnel did not come up on localhost:$LocalPort (port in use, or SSH failed - try plain addLinux first)."
        }
        $tunnel
    }

    if ($Desktop) {
        $tunnel = & $openTunnel $DesktopLocalPort 3389 'Desktop'
        Start-Process mstsc -ArgumentList "/v:localhost:$DesktopLocalPort"
        Write-Host "Desktop tunnel up (ssh PID $($tunnel.Id)). Log in as gene. Stop it with: Stop-Process -Id $($tunnel.Id)" -ForegroundColor Green
    }
    if ($Cockpit) {
        $tunnel = & $openTunnel $CockpitLocalPort 9090 'Cockpit'
        Start-Process "https://localhost:$CockpitLocalPort"
        Write-Host "Cockpit tunnel up (ssh PID $($tunnel.Id)). Log in as gene. Stop it with: Stop-Process -Id $($tunnel.Id)" -ForegroundColor Green
    }
    if ($Desktop -or $Cockpit) { return }

    $sshArgs = $baseArgs + @("$User@$HostAddress")
    if ($RemoteCommand) { $sshArgs += $RemoteCommand }
    ssh @sshArgs
}
