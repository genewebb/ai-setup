# Checks that a grader survives the kit's build-in-a-worktree, apply-to-main handoff. Run by stream-plan on every
# imported grader before release, and by stream-author on any grader it did not write itself.
# Reads the grader and every .ps1 it names by absolute path (an import shim calls the real grader elsewhere).
# Flags, one line each:
#   FLAG MTIME <file>:<line>        compares file times; git apply on main re-stamps files, so it is red for any patch
#   FLAG LOOP-STATE <file>:<line>   reads MyLoop row state (.loop\rows, Dispatch/Close-Row); stale under the kit
#   FLAG SINCE-UNSET <file>         the called grader takes -Since but the shim does not pass $env:STREAM_SINCE_UTC
#   FLAG COMMIT-PIN <file>:<line>   pins a commit id, or reads a baseline out of git history
#   FLAG OUTSIDE-TREE <file>:<line> names a ROOTED data path - a drive letter or a UNC prefix - anywhere: a param
#                                   default, an assignment, or the call itself. The grader must read only paths built
#                                   from $Root. An absolute .ps1 delegate is exempt (DEAD-DELEGATE covers it).
#   FLAG DEAD-DELEGATE <path>       delegates to an absolute .ps1 that does not exist, so its clauses can never pass
#   FLAG SPANNING-ATTRS <file>:<line> a (?s) dot-all attribute prefix in the grader's own Body/clause helper. It
#                                   matches from the class's first attribute down to the method, so a clause's
#                                   pins are met by unrelated code elsewhere in the file and the clause proves
#                                   nothing (kit item IN-20260929175416-351a). The non-spanning form is
#                                   ((?:[ \t]*\[[^\]\n]*\][ \t]*\r?\n)+)[^\n]*$
#   FLAG CONTROL-BYTE <file>:<line> the file holds a control byte other than TAB, CR or LF - '\b' written through a
#                                   heredoc arrives as 0x08, so a pin like '\bAverage\b' can never match and the
#                                   clause is unsatisfiable while the grader still parses and prints FAIL.
#   FLAG UNTRIMMED-TESTNAME <file>:<line> splits a trx testName on '(' without trimming: MSTest writes a DataRow
#                                   result as 'MyTest ("arg")', so the name keeps a trailing space and a test that ran
#                                   reads as "did not run" (kit item IN-20260930183248-206d).
#   FLAG PARSE-ERROR <file>:<line>  the file does not parse, so it can never print a verdict. Checked FIRST and
#                                   never waivable: an unparseable grader used to print PORTABLE (kit item
#                                   IN-20260929170537-8760), and it reads as RED everywhere because it dies
#                                   before its first clause.
# A shim line "# portable: CODE[,CODE] <reason>" waives those codes for this grader (the reason is printed).
# Exit 0 = PORTABLE (no unwaived flag), 1 = flags printed, 4 = grader missing.
param(
    [Parameter(Mandatory)] [string] $Grader
)
if (-not (Test-Path -LiteralPath $Grader)) { "NO-GRADER $Grader"; exit 4 }
$shim = Get-Content -Raw -LiteralPath $Grader
$waived = @{}
foreach ($m in [regex]::Matches($shim, '(?m)^\s*#\s*portable:\s*([A-Z,\-]+)\s*(.*)$')) {
    foreach ($c in $m.Groups[1].Value -split ',') { if ($c) { $waived[$c.Trim()] = $m.Groups[2].Value.Trim() } }
}
$files = @($Grader)
foreach ($m in [regex]::Matches($shim, "['""]([A-Za-z]:\\[^'""]+?\.ps1)['""]")) { if (Test-Path -LiteralPath $m.Groups[1].Value) { $files += $m.Groups[1].Value } }
$files = @($files | Select-Object -Unique)
# Parse before anything else. A grader that does not parse never prints a clause verdict, so every portability
# rule below it is meaningless and its red says nothing about the code.
$parse = [Collections.Generic.List[string]]::new()
foreach ($f in $files) {
    $perr = $null; $ptok = $null
    [void][Management.Automation.Language.Parser]::ParseFile($f, [ref]$ptok, [ref]$perr)
    foreach ($e in @($perr)) { $parse.Add("PARSE-ERROR ${f}:$($e.Extent.StartLineNumber) $($e.Message)") }
}
if ($parse.Count) { foreach ($pe in $parse) { "FLAG $pe" }; exit 1 }
# A grader written through a shell heredoc can carry the CONTROL BYTE an escape was meant to produce: '\b' typed into
# a double-quoted heredoc arrives as 0x08, so a clause reading '\bAverage\b' becomes '<BS>Average<BS>' and can never
# match any C# file. It parses, it prints FAIL, and the red says nothing about the code. G5.T014 cost a full build
# cycle this way on 2026-09-29 (grader line 272, five 0x08 bytes, C1-C17 and C19 PASS with 18/18 targeted tests, C18
# unsatisfiable) and G4.T062 line 278 carries the same byte while still ticketed. Measured on the live board: 2 of
# 156 graders, so the rule flags the defect and nothing else. TAB, CR and LF are legal; everything else below 0x20
# plus DEL is not. Checked right after the parse, because a corrupt byte makes every clause below it meaningless.
$ctrl = [Collections.Generic.List[string]]::new()
foreach ($f in $files) {
    $n = 0
    foreach ($l in [IO.File]::ReadLines($f)) {
        $n++
        $hit = [regex]::Match($l, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]')
        if ($hit.Success) { $ctrl.Add("CONTROL-BYTE ${f}:$n 0x{0:X2}" -f [int][char]$hit.Value) }
    }
}
foreach ($c in $ctrl) {
    $code = 'CONTROL-BYTE'
    if ($waived.ContainsKey($code)) { "WAIVED $c ($($waived[$code]))" } else { "FLAG $c" }
}
if (@($ctrl | Where-Object { -not $waived.ContainsKey('CONTROL-BYTE') }).Count) { exit 1 }
# An absolute .ps1 the shim names must exist. G1.T01 delegated 19 of its 21 clauses to
# D:\devops\repos\speedmerchants\.loop\criteria\rd-25.ps1, .loop was wiped on 2026-09-26, and every one of those   # history
# clauses then reported "rd-25 printed no line for this clause": a grader that can never pass, and whose red says
# nothing about the code (kit item IN-20260929141819-17fd).
$dead = [Collections.Generic.List[string]]::new()
foreach ($m in [regex]::Matches($shim, "['""]([A-Za-z]:\\[^'""]+?\.ps1)['""]")) {
    if (-not (Test-Path -LiteralPath $m.Groups[1].Value)) { $dead.Add($m.Groups[1].Value) }
}

# A rooted path: a drive letter, or a UNC \\host\share. The host needs two characters and the share must start   # example-path
# alphanumeric, so PowerShell-escaped regex text such as '\\s\*' is not read as a UNC path.
$rootedRx = '(?:(?<![\w:])[A-Za-z]:[\\/]|\\\\[A-Za-z0-9][A-Za-z0-9._-]+\\[A-Za-z0-9._$-]+)'
# The calls that READ a path. A rooted literal on one of these lines, or in a variable one of them later uses, is
# a read outside the tree; the same literal in a message or an expected-value table is not.
$pathUseRx = '(?i)(Join-Path|Test-Path|Get-Content|Get-ChildItem|Get-Item|Get-FileHash|Resolve-Path|Import-Module|Select-String|Split-Path|New-Item|Set-Content|Out-File|Copy-Item|Remove-Item|ReadAllText|ReadAllLines|ReadAllBytes|ReadLines|EnumerateFiles|::Exists|-LiteralPath|-Path\b|-File\b|-Root\b|-Dir\b)'
$flags = [Collections.Generic.List[string]]::new()
foreach ($f in $files) {
    $n = 0
    $rootedVars = @{}
    $body = @([IO.File]::ReadAllLines($f))
    foreach ($l in [IO.File]::ReadLines($f)) {
        $n++
        if ($l -match '^\s*#') { continue }
        if ($l -match '\b(LastWriteTime|LastWriteTimeUtc|CreationTime|CreationTimeUtc|LastAccessTime)\b') { $flags.Add("MTIME ${f}:$n") }
        if ($l -match '\.loop[\\/]+rows|Dispatch-Row|Close-Row|Collect-Row') { $flags.Add("LOOP-STATE ${f}:$n") }
        # A grader pins CONTENT - a SHA-256, or a base64 blob checked after decoding - and never a commit id. A history
        # re-import replaces commit ids: 909a2f1e11 vanished on 2026-09-29 and every clause of G2.T01 that read its
        # baseline with 'git cat-file blob <sha>:<path>' then reported FAIL, so a correct grader read as a total failure
        # (kit item IN-20260929130448-5d94). A 64-hex content hash never matches; a comment naming a commit is skipped above.
        if ($l -match 'git\s+(cat-file|show)\b' -or $l -match '(?<![0-9A-Fa-f])[0-9A-Fa-f]{40}(?![0-9A-Fa-f])') { $flags.Add("COMMIT-PIN ${f}:$n") }
        # .loop was the MyLoop state folder and was wiped on 2026-09-26. An ABSOLUTE path under it is outside the
        # tree the kit hands the grader; a relative .loop\rows read is already covered by LOOP-STATE above.
        if ($l -match '[A-Za-z]:\\[^''"]*\.loop[\\/]') { $flags.Add("OUTSIDE-TREE ${f}:$n") }
        # A ROOTED path - a drive letter or a UNC host\share - that the grader READS is outside the tree the kit
        # hands it. The grader runs against a worktree AND against main, so a rooted path grades the same copy both
        # times and its verdict says nothing about the tree under test. Measured cases: .loop was wiped on 2026-09-26
        # (G1.T01); G3.T040 graded green off a D:\tmp leftover; G4.T063 line 11 read   # history
        # param([string] $Root, [string] $Dir = 'D:\tmp\speedy-mockups\g4\activity-run-state') and linted PORTABLE -   # history
        # 1 failing clause with -Dir under -Root against 4 with -Dir at the D:\tmp copy (kit item IN-20260929192818-8827).   # history
        # Flagged in the two shapes that READ: the rooted literal sits on a path call itself, or it is assigned to a
        # variable (a param default counts) that a path call later uses. A rooted path pinned as expected TEXT - a
        # reference-data value such as buildDownloadDirectory = 'C:\Deploy\Downloads' in G2.T19, or a message naming   # history
        # a bad path - reads nothing and is NOT flagged. An absolute .ps1 is the supported import-shim delegate and is
        # dropped here (DEAD-DELEGATE checks that one, and the delegate's own body is read as part of $files).
        $dataLine = [regex]::Replace($l, "['""](?:[A-Za-z]:|\\\\[^'""\\]+)[\\/][^'""]*?\.ps1['""]", "''")
        if ($dataLine -match $rootedRx) {
            if ($dataLine -match $pathUseRx) { $flags.Add("OUTSIDE-TREE ${f}:$n") }
            elseif ($dataLine -match "\`$(\w+)\s*=\s*['""]\s*$rootedRx") { $rootedVars[$Matches[1]] = $n }
        }
        # A dot-all attribute prefix swallows the whole preceding file. Measured on tests/Tests.Unit/LocalIdentityTests.cs
        # (26825 chars): prefixes of 514, 1255, 1630, 3312 and 4459 characters where the non-spanning regex returns the one
        # attribute line (18 chars), so pins elsewhere in the file pre-meet the clause (kit item IN-20260929175416-351a).
        if ($l -match '\(\?s\)' -and $l -match '\\\[\.\*\\\]') { $flags.Add("SPANNING-ATTRS ${f}:$n") }
        # MSTest writes a data-driven result's testName as 'MyTest ("arg")', with a SPACE before the parenthesis, so
        # ($r.Node.testName -split '\(')[0] keeps a trailing space and never equals 'MyTest': a DataRow test that ran
        # and passed reads as "did not run". 65 graders carried the untrimmed form on 2026-09-30 (kit item
        # IN-20260930183248-206d). Trim the name, or match by prefix.
        if ($l -match 'testName\s*-split' -and $l -notmatch '\.Trim(End)?\(\)') { $flags.Add("UNTRIMMED-TESTNAME ${f}:$n") }
    }
    # A rooted literal assigned to a variable only matters when a path call uses that variable. G4.T063's -Dir
    # default fed a Join-Path; G2.T19's expected buildDownloadDirectory value feeds nothing.
    foreach ($v in $rootedVars.Keys) {
        foreach ($bl in $body) {
            if ($bl -match '^\s*#') { continue }
            if ($bl -match "\`$$v\b" -and $bl -match $pathUseRx) { $flags.Add("OUTSIDE-TREE ${f}:$($rootedVars[$v])"); break }
        }
    }
    if ($f -ne $Grader) {
        $callee = Get-Content -Raw -LiteralPath $f
        if ($callee -match '\[string\]\s*\$Since\b' -and $shim -notmatch 'STREAM_SINCE_UTC') { $flags.Add("SINCE-UNSET $f") }
    }
}
foreach ($d in $dead) { $flags.Add("DEAD-DELEGATE $d") }
$flags = @($flags | Select-Object -Unique)
$bad = 0
foreach ($fl in $flags) {
    $code = ($fl -split ' ')[0]
    if ($waived.ContainsKey($code)) { "WAIVED $fl ($($waived[$code]))" } else { "FLAG $fl"; $bad++ }
}
if ($bad) { exit 1 }
"PORTABLE $Grader"
exit 0
