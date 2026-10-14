# SessionStart hook: cowsay-style greeting with a random engineering quote.
# Emits {"systemMessage": ...} — displayed to the user, costs ZERO tokens (never enters model
# context). Pure PowerShell; no cowsay dependency.

$quotes = @(
    'Simplicity is prerequisite for reliability. -- Edsger W. Dijkstra',
    'Make it work, make it right, make it fast. -- Kent Beck',
    'Programs must be written for people to read. -- Harold Abelson',
    'The best way to predict the future is to invent it. -- Alan Kay',
    'Deleted code is debugged code. -- Jeff Sickel',
    'First, solve the problem. Then, write the code. -- John Johnson',
    'Weeks of coding can save you hours of planning. -- Unknown',
    'A clever person solves a problem. A wise person avoids it. -- Albert Einstein',
    'Testing shows the presence, not the absence of bugs. -- Edsger W. Dijkstra',
    'There are only two hard things in Computer Science: cache invalidation and naming things. -- Phil Karlton'
)
$quote = $quotes | Get-Random

# Word-wrap the quote to a fixed bubble width, then draw the bubble sized to the longest line.
$width = 44
$words = $quote -split ' '
$lines = [System.Collections.Generic.List[string]]::new()
$current = ''
foreach ($w in $words) {
    if ($current -and ($current.Length + 1 + $w.Length) -gt $width) { $lines.Add($current); $current = $w }
    else { $current = if ($current) { "$current $w" } else { $w } }
}
if ($current) { $lines.Add($current) }

$inner = ($lines | Measure-Object -Property Length -Maximum).Maximum
$top    = ' ' + ('_' * ($inner + 2))
$bottom = ' ' + ('-' * ($inner + 2))
$body = for ($i = 0; $i -lt $lines.Count; $i++) {
    $pad = $lines[$i].PadRight($inner)
    if ($lines.Count -eq 1)          { "< $pad >" }
    elseif ($i -eq 0)                { "/ $pad \" }
    elseif ($i -eq $lines.Count - 1) { "\ $pad /" }
    else                             { "| $pad |" }
}

$cow = @'
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
'@

$art = ($top, ($body -join "`n"), $bottom, $cow -join "`n")
@{ systemMessage = $art } | ConvertTo-Json -Compress
