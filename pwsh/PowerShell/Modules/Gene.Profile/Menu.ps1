# Menus and prompts shared by every prof group.
#
# Two looks, same answers:
#   rich      arrow keys + Enter, like devutils (Spectre.Console). Uses the PwshSpectreConsole module (PowerShell 7.4+,
#             listed in pwsh\modules.txt). Chosen when that module is installed and a real console is attached.
#   numbered  type a number. Used without the module, with redirected input (remote runs), when a test passes
#             -Reader, or when $env:GENE_PLAIN_MENU is set.

$script:GeneRichMenu = $null

function Test-GeneRichMenu {
    <# $true when the arrow-key menus can be used in this session (decided once per session). #>
    if ($env:GENE_PLAIN_MENU) { return $false }
    if ($null -ne $script:GeneRichMenu) { return $script:GeneRichMenu }
    $ok = $false
    if ($PSVersionTable.PSVersion -ge [version]'7.4' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and
        (Get-Module -ListAvailable -Name PwshSpectreConsole)) {
        try {
            # Spectre draws its boxes and arrows in UTF-8; this is the setting its own warning asks for.
            if ([Console]::OutputEncoding.WebName -ne 'utf-8') {
                $global:OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
            }
            Import-Module PwshSpectreConsole -ErrorAction Stop -Verbose:$false
            $ok = $true
        }
        catch { $ok = $false }
    }
    $script:GeneRichMenu = $ok
    return $ok
}

function ConvertTo-GeneMarkupText([string]$Text) { $Text.Replace('[', '[[').Replace(']', ']]') }

function Select-GeneMenu {
    <#
    .SYNOPSIS
        Shows a pick list and returns the picked item(s); $null when cancelled.
    .PARAMETER Items
        Strings, or objects with Name and Description.
    .PARAMETER Default
        1-based item. Numbered menu: taken on Enter (0 = Enter asks again). Arrow-key menu: listed first.
    .PARAMETER Multi
        Several picks: arrow-key menu = Space to tick, Enter when done; numbered = numbers separated by commas or spaces.
        Returns an array.
    .PARAMETER AllowEmpty
        With -Multi: picking nothing returns an empty array instead of asking again ($null still means cancelled).
    .PARAMETER Reader
        Tests only: replaces Read-Host and forces the numbered menu. Receives the prompt, returns the answer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Items,
        [int]$Default = 0,
        [switch]$Multi,
        [switch]$AllowEmpty,
        [scriptblock]$Reader
    )
    $names = @($Items | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.Name } })
    $width = ($names | Measure-Object -Property Length -Maximum).Maximum

    if (-not $Reader -and $Multi -and (Test-GeneRichMenu)) {
        $labels = @(for ($i = 0; $i -lt $Items.Count; $i++) {
                $desc = if ($Items[$i] -isnot [string] -and $Items[$i].Description) { "  [grey]$(ConvertTo-GeneMarkupText $Items[$i].Description)[/]" } else { '' }
                "$(ConvertTo-GeneMarkupText $names[$i].PadRight($width))$desc"
            })
        Write-Host ''
        $picked = Read-SpectreMultiSelection -Message "[cyan]$(ConvertTo-GeneMarkupText $Title)[/]" -Choices $labels -AllowEmpty:$AllowEmpty `
            -PageSize ([Math]::Max(3, [Math]::Min(20, $labels.Count))) -Color Cyan
        if ($null -eq $picked -and -not $AllowEmpty) { return $null }
        return , @(@($picked) | Where-Object { $_ } | ForEach-Object { $Items[[array]::IndexOf($labels, [string]$_)] })
    }
    if (-not $Reader -and -not $Multi -and (Test-GeneRichMenu)) {
        $order = @(0..($Items.Count - 1))
        if ($Default -ge 1 -and $Default -le $Items.Count) { $order = @($Default - 1) + @($order | Where-Object { $_ -ne $Default - 1 }) }
        $labels = @($order | ForEach-Object {
                $desc = if ($Items[$_] -isnot [string] -and $Items[$_].Description) { "  [grey]$(ConvertTo-GeneMarkupText $Items[$_].Description)[/]" } else { '' }
                "$(ConvertTo-GeneMarkupText $names[$_].PadRight($width))$desc"
            })
        $cancel = '[grey](cancel)[/]'
        Write-Host ''
        $pick = Read-SpectreSelection -Message "[cyan]$(ConvertTo-GeneMarkupText $Title)[/]" -Choices (@($labels) + $cancel) `
            -PageSize ([Math]::Max(3, [Math]::Min(20, $labels.Count + 1))) -Color Cyan
        if ($null -eq $pick -or $pick -eq $cancel) { return $null }
        return $Items[$order[[array]::IndexOf($labels, [string]$pick)]]
    }

    if (-not $Reader) { $Reader = { param($p) Read-Host $p } }
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $desc = if ($Items[$i] -isnot [string] -and $Items[$i].Description) { "  $($Items[$i].Description)" } else { '' }
        $mark = if ($Default -eq $i + 1) { '*' } else { ' ' }
        Write-Host ("  {0}{1,2}) {2}{3}" -f $mark, ($i + 1), $names[$i].PadRight($width), $desc)
    }
    $hint = "Pick $(if ($Multi) { 'one or more, e.g. 1,3' } else { "1-$($Items.Count)" })$(if ($Default) { ", Enter = $Default" } elseif ($Multi -and $AllowEmpty) { ', Enter = none' }), q = cancel"
    while ($true) {
        $answer = ([string](& $Reader $hint)).Trim()
        if ($answer -ieq 'q') { return $null }
        if (-not $answer) {
            if ($Multi -and $AllowEmpty -and -not $Default) { return , @() }
            if ($Default -ge 1 -and $Default -le $Items.Count) { return $(if ($Multi) { , @($Items[$Default - 1]) } else { $Items[$Default - 1] }) }
            continue
        }
        $parts = @($answer -split '[,\s]+' | Where-Object { $_ })
        if (-not $Multi -and $parts.Count -ne 1) { Write-Host '  One number, please.' -ForegroundColor Yellow; continue }
        $picked = @()
        $ok = $true
        foreach ($p in $parts) {
            $n = 0
            if (-not [int]::TryParse($p, [ref]$n) -or $n -lt 1 -or $n -gt $Items.Count) { $ok = $false; break }
            $picked += , $Items[$n - 1]
        }
        if (-not $ok) { Write-Host "  Not a number from 1 to $($Items.Count): $answer" -ForegroundColor Yellow; continue }
        if ($Multi) { return , $picked }
        return $picked[0]
    }
}

function Read-GeneYesNo {
    <# y/n question; Enter = the default. -Reader (tests) forces the plain prompt. #>
    param([Parameter(Mandatory)][string]$Question, [bool]$Default = $false, [scriptblock]$Reader)
    if (-not $Reader -and (Test-GeneRichMenu)) {
        return [bool](Read-SpectreConfirm -Message (ConvertTo-GeneMarkupText $Question) -DefaultAnswer $(if ($Default) { 'y' } else { 'n' }) -Color Cyan)
    }
    if (-not $Reader) { $Reader = { param($p) Read-Host $p } }
    while ($true) {
        $a = ([string](& $Reader "$Question [$(if ($Default) { 'Y/n' } else { 'y/N' })]")).Trim()
        if (-not $a) { return $Default }
        if ($a -match '^(y|yes)$') { return $true }
        if ($a -match '^(n|no)$') { return $false }
    }
}

function Read-GeneText {
    <# One line of free text; Enter alone returns ''. -Reader (tests) forces the plain prompt. #>
    param([Parameter(Mandatory)][string]$Prompt, [scriptblock]$Reader)
    if (-not $Reader -and (Test-GeneRichMenu)) { return [string](Read-SpectreText -Message (ConvertTo-GeneMarkupText $Prompt) -AllowEmpty) }
    if (-not $Reader) { $Reader = { param($p) Read-Host $p } }
    return [string](& $Reader $Prompt)
}
