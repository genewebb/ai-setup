<#
.SYNOPSIS
    Shared helpers for the orchestrator-worker-loop scripts. Dot-source it; do not run it directly.

.DESCRIPTION
    Provides:
      - Convert-LoopGlobToRegex  : real glob semantics (**, *, ?) instead of PowerShell -like
      - Test-LoopGlobMatch       : match a relative path against a pattern list
      - Get-LoopRelativePath     : root-relative, forward-slash path
      - Get-LoopFileSet          : enumerate in-scope files honouring include/exclude/exclude-dirs
      - Read-LoopJson / Write-LoopJson
      - Get-LoopUtcStamp / Get-LoopLocalStamp
      - Test-LoopGitRepo / Invoke-LoopGit / Get-LoopSha256

    WHY a real glob converter: PowerShell's -like has no path awareness. '*' spans '/', so
    'bin/*' is root-anchored (it never matches 'src/App/bin/x.dll'), while 'src/**/*.cs'
    flattened to 'src/*/*.cs' silently misses direct children like 'src/x.cs'. Both produced
    wrong constraint-gate verdicts. These helpers translate globs to anchored regexes where
    '*' stops at '/' and '**' spans segments.

.NOTES
    Default exclude directories are matched per path SEGMENT, so bin/obj/node_modules are
    excluded at any depth — not just at the root.
#>

Set-StrictMode -Version Latest

# Directories excluded at ANY depth (segment match, case-insensitive).
$script:LoopDefaultExcludeDirs = @(
    '.git'
    '.loop'
    'node_modules'
    'bin'
    'obj'
    '.vs'
    '.vscode'
    'TestResults'
    'packages'
    '.idea'
)

# Loop-owned files excluded wherever they appear, so the loop never flags its own bookkeeping.
$script:LoopOwnedFiles = @(
    'GOAL.md'
    'PLAN.md'
    'PROGRESS.md'
    'BASELINE.json'
    'CRITERIA.json'
    'LOOP_REPORT.md'
    'ARTIFACT.md'
    'state.json'
)

function Get-LoopDefaultExcludeDirs {
    return @($script:LoopDefaultExcludeDirs)
}

function Get-LoopOwnedFilePatterns {
    # Bare filenames match at any depth (see Convert-LoopGlobToRegex).
    return @($script:LoopOwnedFiles)
}

function Convert-LoopGlobToRegex {
    <#
    .SYNOPSIS
        Convert a glob pattern to an anchored, case-insensitive regex string.
    .DESCRIPTION
        Semantics (POSIX/gitignore-flavoured):
          **/     leading  -> optional any-number-of-leading-segments
          /**/    middle   -> '/' plus optional segments
          /**     trailing -> whole subtree
          **      bare     -> anything, including '/'
          *                -> anything except '/'
          ?                -> single char except '/'
        A pattern with no '/' at all matches the FILE NAME at any depth ('*.cs' == '**/*.cs').
    #>
    param([Parameter(Mandatory = $true)][string]$Glob)

    $g = $Glob.Replace('\', '/').Trim()
    while ($g.StartsWith('./')) { $g = $g.Substring(2) }
    $g = $g.TrimStart('/')

    # A bare filename pattern applies at any depth.
    if ($g -notmatch '/') { $g = "**/$g" }

    # Trailing '/' means "this directory's whole subtree".
    if ($g.EndsWith('/')) { $g = $g + '**' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $i = 0
    $len = $g.Length
    while ($i -lt $len) {
        $c = $g[$i]

        if ($c -eq '*') {
            $isDouble = ($i + 1 -lt $len) -and ($g[$i + 1] -eq '*')
            if ($isDouble) {
                $atStart = ($i -eq 0)
                $followedBySlash = ($i + 2 -lt $len) -and ($g[$i + 2] -eq '/')
                $precededBySlash = ($i -gt 0) -and ($g[$i - 1] -eq '/')
                $atEnd = ($i + 2 -ge $len)

                if (($atStart -or $precededBySlash) -and $followedBySlash) {
                    # '**/foo' or 'a/**/b' -> optional intervening segments
                    [void]$sb.Append('(?:.*/)?')
                    $i += 3
                    continue
                }
                if ($atEnd) {
                    # 'a/**' -> whole subtree under a/ (the '/' was already emitted)
                    [void]$sb.Append('.*')
                    $i += 2
                    continue
                }
                [void]$sb.Append('.*')
                $i += 2
                continue
            }

            [void]$sb.Append('[^/]*')
            $i++
            continue
        }

        if ($c -eq '?') {
            [void]$sb.Append('[^/]')
            $i++
            continue
        }

        if ($c -eq '/') {
            [void]$sb.Append('/')
            $i++
            continue
        }

        [void]$sb.Append([regex]::Escape([string]$c))
        $i++
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function New-LoopMatcher {
    <#
    .SYNOPSIS
        Compile a pattern list into a regex array for repeated matching.
    .NOTES
        Returns a PLAIN array and every caller wraps the call in @(...). Do NOT use the
        leading-comma idiom here: `return , $arr` combined with a caller's @() double-wraps into
        an array-of-array, so each "matcher" is an array rather than a regex and NOTHING matches.
        With a plain return, the empty case unrolls to nothing and the caller's @() makes it an
        empty array (so .Count is safe under Set-StrictMode).
    #>
    param([string[]]$Patterns)

    $out = New-Object System.Collections.ArrayList
    foreach ($p in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $rx = [regex]::new(
            (Convert-LoopGlobToRegex -Glob $p),
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        [void]$out.Add($rx)
    }
    return $out.ToArray()
}

function Test-LoopGlobMatch {
    <#
    .SYNOPSIS
        True if RelativePath matches any pattern (raw globs or pre-compiled regexes).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [object[]]$Matchers
    )

    foreach ($m in @($Matchers)) {
        if ($null -eq $m) { continue }
        if ($m -is [regex]) {
            if ($m.IsMatch($RelativePath)) { return $true }
            continue
        }
        # Raw glob string. Skip blanks rather than throwing — a gate must never die mid-run
        # because a pattern list contained an empty element.
        $pattern = "$m"
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $rx = [regex]::new(
            (Convert-LoopGlobToRegex -Glob $pattern),
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($rx.IsMatch($RelativePath)) { return $true }
    }
    return $false
}

function Get-LoopRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $root = $RootPath.TrimEnd('\', '/')
    $rel = $FullPath.Substring($root.Length)
    return $rel.TrimStart('\', '/').Replace('\', '/')
}

function Test-LoopExcludedDir {
    <#
    .SYNOPSIS
        True if any path segment (except the final filename) is an excluded directory name.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$ExcludeDirs
    )
    if (-not $ExcludeDirs -or $ExcludeDirs.Count -eq 0) { return $false }
    $segments = $RelativePath.Split('/')
    if ($segments.Count -lt 2) { return $false }
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        foreach ($d in $ExcludeDirs) {
            if ($segments[$i] -ieq $d) { return $true }
        }
    }
    return $false
}

function Get-LoopFileSet {
    <#
    .SYNOPSIS
        Enumerate in-scope files under RootPath as a hashtable of relative path -> FileInfo.
    .DESCRIPTION
        Applied in order: exclude-dir segment test, exclude patterns, include patterns.
        Directory pruning happens during enumeration so huge bin/obj/node_modules trees are
        never walked (this is what keeps the gate fast on large repos).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [string[]]$Include = @('**/*'),
        [string[]]$Exclude = @(),
        [string[]]$ExcludeDirs = $null
    )

    if ($null -eq $ExcludeDirs) { $ExcludeDirs = Get-LoopDefaultExcludeDirs }

    $includeMatchers = @(New-LoopMatcher -Patterns $Include)
    $excludeMatchers = @(New-LoopMatcher -Patterns $Exclude)

    $root = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')
    $result = @{}

    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue($root)

    while ($pending.Count -gt 0) {
        $dir = $pending.Dequeue()

        $children = @()
        try {
            $children = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($child in $children) {
            if ($child.PSIsContainer) {
                $skip = $false
                foreach ($d in $ExcludeDirs) {
                    if ($child.Name -ieq $d) { $skip = $true; break }
                }
                if (-not $skip) { $pending.Enqueue($child.FullName) }
                continue
            }

            $rel = Get-LoopRelativePath -FullPath $child.FullName -RootPath $root
            if (Test-LoopExcludedDir -RelativePath $rel -ExcludeDirs $ExcludeDirs) { continue }
            if (Test-LoopGlobMatch -RelativePath $rel -Matchers $excludeMatchers) { continue }
            if (-not (Test-LoopGlobMatch -RelativePath $rel -Matchers $includeMatchers)) { continue }

            $result[$rel] = $child
        }
    }

    # ANYTHING GIT IGNORES IS BUILD OUTPUT, NOT SOURCE, AND THE CONSTRAINT GATE MUST NOT SEE IT.
    #
    # Added 2026-09-08 18:05 after the vNext loop diagnosed a gate that poisoned itself. `exclude_dirs`
    # is a hand-maintained list -- it covers `node_modules`, `bin`, `obj` -- and it did NOT cover
    # `tests/Tests.E2E/playwright-report/` or `test-results/`. So a baseline captured five Playwright
    # output files, one of which (`index.html`) embeds a timestamp. A criterion in that loop's own sweep
    # runs the browser suite, which rewrites those files, and from then on the constraint gate reported
    # three out-of-scope changes FOREVER -- failing two plan criteria that had been green for days.
    # **The sweep poisoned its own gate**, and no amount of adding names to a hand-maintained list fixes
    # the general case, because the next tool to write build output will not be on the list either.
    #
    # git already knows the answer. A gate asking "did the Executor change repo files" should measure
    # what the repository tracks. Silent no-op when this is not a git repo or git is unavailable, so
    # nothing here depends on git being present.
    if ($result.Count -gt 0 -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $inside = (& git -C $root rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and "$inside".Trim() -eq 'true') {
            # --stdin in one call: a check-ignore per file would cost a process each on a 1,400-file map.
            # -z on BOTH sides, and that is not a detail. Without it git QUOTES and octal-escapes any
            # path containing a non-ASCII byte -- Playwright names its output directories after the test
            # title, so one of them held an em dash and came back as
            # "tests/.../monitor-throttle-Monitor-\342\200\224-ba0c7-.../error-context.md". That never
            # matches the real key, so the two files it should have removed survived the first version
            # of this filter and the gate stayed poisoned. NUL-separated output is unquoted and exact.
            # ENCODING, on BOTH sides, and this cost an hour to find. `$OutputEncoding` decides how
            # PowerShell encodes what it pipes INTO a native command, and `[Console]::OutputEncoding`
            # how it decodes what comes back. Both differ between an interactive host and a
            # `Start-Job` background runspace -- so this filter worked when run by hand and silently
            # failed inside the criteria sweep, leaving two Playwright paths (a test title containing
            # an EM DASH) unfiltered and the constraint gate still poisoned. The sweep then reported
            # two criteria as REGRESSED that exited 0 every time they were run directly.
            # `core.quotepath=false` stops git octal-escaping non-ASCII on top of that.
            # ASK git, do not TELL git. The first two versions of this piped every path into
            # `check-ignore --stdin`, and piping is where it kept breaking: `$OutputEncoding` and
            # `[Console]::OutputEncoding` differ between an interactive host and a `Start-Job`
            # runspace, so an em-dash in a Playwright directory name survived the filter inside the
            # criteria sweep and not outside it; and with that fixed, a single `installer/stage` DLL
            # still slipped through, consistent with the ~1,400-line stdin being truncated. Both
            # failures were invisible — the filter reported nothing, it just quietly kept a file.
            # `git status --ignored` is one call, output only, and it COLLAPSES a wholly-ignored
            # directory to a single entry (`installer/stage/`), so the list is short and prefix
            # matching removes everything beneath it without asking about each file.
            $savedConsole = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
                $ignoredEntries = @(
                    & git -C $root -c core.quotepath=false status --porcelain --ignored --untracked-files=normal 2>$null |
                        Where-Object { $_ -like '!!*' } |
                        ForEach-Object { ($_.Substring(3).Trim('"') -replace '\\', '/') }
                )
            } finally {
                [Console]::OutputEncoding = $savedConsole
            }
            if ($ignoredEntries.Count -gt 0) {
                foreach ($key in @($result.Keys)) {
                    foreach ($ig in $ignoredEntries) {
                        if ($ig.EndsWith('/')) {
                            if ($key.StartsWith($ig, [StringComparison]::OrdinalIgnoreCase)) { $result.Remove($key); break }
                        } elseif ($key -ieq $ig) { $result.Remove($key); break }
                    }
                }
            }
        }
    }

    return $result
}

function Read-LoopJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-LoopJson {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}

function Get-LoopUtcStamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-LoopLocalStamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm')
}

function Test-LoopGitRepo {
    param([Parameter(Mandatory = $true)][string]$RootPath)
    $probe = & git -C $RootPath rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and "$probe".Trim() -eq 'true')
}

function Test-LoopGitHasHead {
    <#
    .SYNOPSIS
        True if the repo has at least one commit (a resolvable HEAD).
    .DESCRIPTION
        A freshly `git init`ed repo is a valid git repo with NO HEAD. Most gate operations still work
        there (`git status`, `git restore` from the index, `git clean`), but `git stash create` needs
        an initial commit, and `git diff` has no committed state to compare against — so without a
        HEAD every staged file looks like a brand-new addition. Callers use this to degrade
        gracefully instead of erroring mid-loop.
    #>
    param([Parameter(Mandatory = $true)][string]$RootPath)
    $null = & git -C $RootPath rev-parse --verify --quiet HEAD 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-LoopGit {
    <#
    .SYNOPSIS
        Run a git command in RootPath, returning output lines plus exit code.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $out = & git -C $RootPath @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Lines    = @($out | ForEach-Object { "$_" })
    }
}

function Write-LoopError {
    <#
    .SYNOPSIS
        Write an error to stderr WITHOUT throwing, so the caller's `exit <code>` actually runs.
    .DESCRIPTION
        These scripts set $ErrorActionPreference = 'Stop', which turns Write-Error into a
        terminating error: the script aborts and pwsh exits 1, so a following `exit 2` never
        executes. That silently collapsed "script error" (2) into "constraint violation" (1) —
        the two outcomes the Verifier branches on. Use this instead of Write-Error before exit.
    #>
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine("ERROR: $Message")
}

function Get-LoopSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    } catch {
        return $null
    }
}
