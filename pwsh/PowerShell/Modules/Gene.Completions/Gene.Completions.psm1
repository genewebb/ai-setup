# Gene.Completions.psm1
# Lazy-loadable completions helpers

function Enable-DotnetSuggestCompletions {
    [CmdletBinding()]
    param()

    if (-not (Get-Command "dotnet-suggest" -ErrorAction SilentlyContinue)) { return }

    $availableToComplete = (dotnet-suggest list) | Out-String
    $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

    Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        try {
            $fullpath = (Get-Command $commandAst.CommandElements[0]).Source

            $arguments = $commandAst.Extent.ToString().Replace('"', '\"')
            dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        catch { }
    }
}

Export-ModuleMember -Function Enable-DotnetSuggestCompletions
