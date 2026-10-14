#requires -Version 7
<#
.SYNOPSIS
    Publishes a kit-maintenance change into the AI corpus (spec D18): {AIWorkRoot}\<RelativePath>, written
    through Write-AIFile (the resource route: Obsidian API inside a vault, a verified direct write otherwise).
    Run /machine-config apply (or start a new 'ai' session) afterwards to install the change locally.

    Publish-KitFile.ps1 -RelativePath 'skills\stream-kit\scripts\Claim-Task.ps1' -Source <file> -BaseHash <hash>

    -BaseHash is the SHA-256 (or any prefix of it, 12+ hex characters) of the file you staged FROM, or NEW for a file
    that did not exist. The publish is REFUSED (exit 3, DRIFT-REFUSED, nothing written) when the corpus copy, or the
    installed copy under {ClaudeHome}, no longer matches it: another session changed the file after you staged, and
    copying over it drops their work. On 2026-09-30 a drift check that only reported, followed by a copy in the same
    command, dropped another session's suite cases; on 2026-10-01 a publish staged from the installed copy overwrote
    a newer, not-yet-installed corpus copy (stream-kit items IN-20260930210538-9dc0). On drift: stop, diff, merge
    (git merge-file against your base), re-test, and publish the merge with the new base hash.
    Without -BaseHash the publish still runs, with a WARNING, for callers that predate it.
#>
param([Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)][string]$Source, [string]$BaseHash = '')
$ErrorActionPreference = 'Stop'
if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw "RelativePath must be relative to the corpus root and must not climb out of it: $RelativePath" }
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'AIFile.psm1') } | Select-Object -First 1
Import-Module (Join-Path $lib 'MachineConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $lib 'AIFile.psm1') -Force -DisableNameChecking
$root = Get-AIPath AIWorkRoot
$target = Join-Path $root $RelativePath
if ($BaseHash) {
    $want = $BaseHash.Trim().ToUpperInvariant()
    if ($want -ne 'NEW' -and $want -notmatch '^[0-9A-F]{12,64}$') { throw "BaseHash must be NEW or 12 to 64 hex characters of a SHA-256: $BaseHash" }
    # The CORPUS copy is what this write replaces, so it is the one that must still be the base. An installed copy that
    # differs is only warned about: it is either a corpus change not applied yet (staging from the corpus is right) or a
    # hand edit in the installed tree, which /machine-config apply reports as drift and keeps a copy of.
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    $drift = ''
    if ($want -eq 'NEW') { if ($exists) { $drift = "the corpus copy $target already exists" } }
    elseif (-not $exists) { $drift = "the corpus copy $target is gone" }
    else {
        $have = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if (-not $have.StartsWith($want)) { $drift = "the corpus copy $target is $($have.Substring(0, 12)), not the base $($want.Substring(0, [Math]::Min(12, $want.Length)))" }
    }
    if ($drift) {
        "DRIFT-REFUSED $RelativePath : $drift. Nothing written. Diff it, merge your change onto the current file, re-test, and publish with the new base hash."
        exit 3
    }
    $installed = Join-Path (Get-AIPath ClaudeHome) $RelativePath
    if ($want -ne 'NEW' -and (Test-Path -LiteralPath $installed -PathType Leaf) -and -not (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash.StartsWith($want)) {
        Write-Warning "Publish-KitFile: the installed copy $installed differs from your base: a corpus change not applied yet, or a hand edit there. Merge it into the corpus before /machine-config apply -AcceptDrift."
    }
} else {
    Write-Warning "Publish-KitFile: no -BaseHash, so a change another session made to $RelativePath since you staged would be overwritten unseen."
}
$r = Write-AIFile -Path $target -Source $Source
"published ($($r.Route)): $($r.Path) ($($r.Hash.Substring(0,12)))"
