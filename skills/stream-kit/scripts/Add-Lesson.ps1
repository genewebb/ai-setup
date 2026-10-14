# Adds one lesson to a role's lessons file, .streams\lessons\<role>.md (EnhanceStream option E).
#
#   Add-Lesson.ps1 -Repo <repo> -Role <role> -Session <id> -Task <id|-> -Text "<one line>"
#   Add-Lesson.ps1 -Repo <repo> -Role <role> -Session <id> -Remove "<text in the lesson>" -Reason "<why>"     (prune)
#
# A runner session starts with an empty context, so what one unit learned about the work (a test that needs the
# PowerShell tool, a grader that holds a lock, a script flag that misleads) is gone in the next. The file carries those
# lessons forward in a form anyone can read and correct: one line per lesson, "<yyyy-MM-dd> <task> <session> <lesson>",
# read by every runner session of the role before it claims work.
#
# Rules: one line, 1 to 240 characters, no ticket detail a later unit cannot use, never a secret (a line that looks like
# one is refused). The file keeps at most 40 lessons: adding the 41st drops the oldest, and each dropped line is logged
# in decisions.md. The coordinator prunes a wrong or stale lesson with -Remove: every lesson that contains the text is
# removed, each logged in decisions.md with the reason; no match = exit 3 (NO-MATCH), nothing written.
# The edit runs under the tasks.json lock, like every other .streams\ writer, so two sessions never lose each other's line.
# Exit 0 = added (prints ADDED, plus DROPPED lines) or pruned (REMOVED lines); 2 = refused (prints REFUSED and why), nothing
# written; 3 = -Remove matched nothing.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [ValidateSet('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator', 'adhoc')] [string] $Role,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Task = '-',
    [AllowEmptyString()] [string] $Text = '',
    [string] $Remove = '',
    [string] $Reason = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$MaxLessons = 40
$MaxChars = 240
$dir = Join-Path $P.Root 'lessons'
$file = Join-Path $dir "$Role.md"

if ($Remove) {
    if (-not $Reason.Trim()) { 'REFUSED a prune names its -Reason'; exit 2 }
    $removed = @()
    [void](Invoke-TasksLocked $P $Session {
        param($doc)
        if (-not (Test-Path $file)) { return $null }
        $lines = @(Get-Content -LiteralPath $file | Where-Object { $_.Trim() })
        $script:removed = @($lines | Where-Object { $_.Contains($Remove) })
        if ($script:removed.Count) { Write-AtomicText $file (((@($lines | Where-Object { -not $_.Contains($Remove) })) -join "`n") + "`n") }
        $null
    })
    if (-not $removed.Count) { "NO-MATCH no lesson in lessons\$Role.md contains '$Remove'"; exit 3 }
    foreach ($d in $removed) { Add-Decision $P $Session "lessons\$Role.md pruned ($($Reason.Trim())): $d"; "REMOVED $d" }
    exit 0
}

$line = $Text.Trim()
$why = $null
if (-not $line) { $why = 'the lesson is empty' }
elseif ($line -match "[\r\n]") { $why = 'a lesson is one line' }
elseif ($line.Length -gt $MaxChars) { $why = "a lesson is at most $MaxChars characters (this one is $($line.Length))" }
elseif ($line -match '(?i)(password|passwd|pwd|secret|api[_-]?key|token|connectionstring)\s*[:=]' -or $line -match '\b[A-Za-z0-9+/]{40,}={0,2}') {
    $why = 'it looks like it holds a secret; lessons never do'
}
if ($Task -match '\s') { $why = 'the task id has a space in it' }
if ($why) { "REFUSED $why"; exit 2 }

$entry = '{0} {1} {2} {3}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'), $Task, $Session, $line
$dropped = @()
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = @(if (Test-Path $file) { Get-Content -LiteralPath $file | Where-Object { $_.Trim() } })
    $lines += $entry
    if ($lines.Count -gt $MaxLessons) {
        $script:dropped = @($lines[0..($lines.Count - $MaxLessons - 1)])
        $lines = @($lines[($lines.Count - $MaxLessons)..($lines.Count - 1)])
    }
    Write-AtomicText $file (($lines -join "`n") + "`n")
    $null
})
foreach ($d in $dropped) { Add-Decision $P $Session "lessons\$Role.md full ($MaxLessons): dropped the oldest lesson: $d" }
"ADDED $entry"
foreach ($d in $dropped) { "DROPPED $d" }
exit 0
