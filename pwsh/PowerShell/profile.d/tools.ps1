# profile.d\tools: small tools (chocoenv, cleannul, newguid, markitdown). Definitions only; loaded by the core profile.

# -----------------------------
# Chocolatey profile import (on demand)
# -----------------------------
function chocoenv {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "chocoenv [-h|--help]" @(
            "Loads Chocolatey's profile module on demand."
        )
        return
    }

    if (-not $env:ChocolateyInstall) {
        Write-Host "Chocolatey not installed (CHOCOLATEYINSTALL not set)." -ForegroundColor DarkGray
        return
    }

    $ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    if (Test-Path -LiteralPath $ChocolateyProfile) {
        Import-Module $ChocolateyProfile -Force
        Write-Host "Chocolatey profile loaded." -ForegroundColor DarkGray
    }
    else {
        Write-Host "Chocolatey profile not found." -ForegroundColor DarkGray
    }
}

# -----------------------------
# cleannul: remove stubborn "nul" file created by Windows in the current directory
# -----------------------------
function cleannul {
    cmd /c del /f /q "\\?\$PWD\nul"
}

# -----------------------------
# newguid: generate a new GUID
# -----------------------------
function newguid { (New-Guid).Guid }

# -----------------------------
# markitdown: convert documents to Markdown
#   markitdown C:\tmp\will.pdf -o C:\tmp\will.md   (preferred)
#   markitdown C:\tmp\will.pdf > C:\tmp\will.md
#
# Venv is on local disk (C:) on purpose: the repo lives on the
# SMB-mapped D: drive, and importing onnxruntime/numpy over the
# network cost ~55s per invocation vs ~4.6s locally.
#
# Encoding: a ">" redirect crosses TWO encoders.
#   1. CPython picks the locale codepage (cp1252) when stdout is a
#      pipe instead of a console, so PYTHONIOENCODING forces UTF-8
#      at the producer.
#   2. This shell's [Console]::OutputEncoding is ibm437, so it must
#      be told to decode those bytes as UTF-8.
# Fixing only one of the two silently turns every curly quote and
# dash into U+FFFD. Both are restored in finally{}, so no other
# command in the session is affected.
# -----------------------------
$global:markitdownExe    = "$($global:GeneMachine.MarkitdownVenv)\Scripts\markitdown.exe"

$global:markitdownPython = "$($global:GeneMachine.MarkitdownVenv)\Scripts\python.exe"

$global:markitdownOcr    = $global:GeneMachine.MarkitdownOcrScript

function markitdown {
    if (-not (Test-Path -LiteralPath $global:markitdownExe)) {
        Write-Error "markitdown not found at $global:markitdownExe"
        return
    }

    # Find the source file and any -o/--output destination, so an empty
    # result can be retried through OCR without the caller doing anything.
    $source = $null
    $dest   = $null
    for ($i = 0; $i -lt $args.Count; $i++) {
        $a = $args[$i]
        if ($a -eq '-o' -or $a -eq '--output') {
            if ($i + 1 -lt $args.Count) { $dest = $args[$i + 1]; $i++ }
            continue
        }
        if ($null -eq $source -and $a -notlike '-*' -and (Test-Path -LiteralPath $a -PathType Leaf)) {
            $source = $a
        }
    }

    $prevEnc  = [Console]::OutputEncoding
    $prevPy   = $env:PYTHONIOENCODING
    $prevWarn = $env:PYTHONWARNINGS
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $env:PYTHONIOENCODING = 'utf-8'
        # pydub warns at import that ffmpeg is missing. Only audio
        # transcription needs ffmpeg, so the warning is pure console
        # noise. Scoped to that one module so real warnings from
        # markitdown's own converters still surface.
        $env:PYTHONWARNINGS = 'ignore::RuntimeWarning:pydub.utils'

        if ($dest) {
            & $global:markitdownExe @args
            $produced = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
        }
        else {
            $captured = & $global:markitdownExe @args
            $produced = ($captured | Out-String).Trim().Length
        }

        # markitdown reads an existing text layer and has no OCR. A scanned
        # or photographed PDF therefore yields an empty file and still exits
        # 0. Retry those through Tesseract automatically.
        $needsOcr = ($produced -le 2) -and
                    $source -and ($source -match '\.pdf$') -and
                    (Test-Path -LiteralPath $global:markitdownOcr)

        if ($needsOcr) {
            # Write-Host, not Write-Output: the information stream is not
            # captured by a ">" redirect, so progress never enters the file.
            Write-Host "No text layer found - running OCR, roughly 6s per page..." -ForegroundColor Yellow
            $target = if ($dest) { $dest } else { [System.IO.Path]::GetTempFileName() }
            & $global:markitdownPython $global:markitdownOcr $source $target 300 | Out-Null
            if ($dest) {
                Write-Host "OCR complete: $((Get-Item -LiteralPath $dest).Length) bytes" -ForegroundColor Green
            }
            else {
                Get-Content -LiteralPath $target -Raw -Encoding UTF8
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            }
        }
        elseif (-not $dest) {
            $captured
        }
    }
    finally {
        [Console]::OutputEncoding = $prevEnc
        $env:PYTHONIOENCODING = $prevPy
        $env:PYTHONWARNINGS = $prevWarn
    }
}

