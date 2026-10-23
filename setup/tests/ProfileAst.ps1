#requires -Version 7
# AST helpers shared by the profile split tests (dot-sourced by the test file and by the child pwsh it starts):
# what a profile file defines (functions, aliases, globals), what it calls, and which top-level statements are not
# plain definitions. prof setup share (change 2) reuses them to pick what a category file needs.
using namespace System.Management.Automation.Language

function Get-GeneProfileCalls {
    <# Every command name invoked anywhere under the AST, unique and sorted. Dynamic invocations (& $x) have no name and are skipped. #>
    param([Parameter(Mandatory)][Ast]$Ast)
    return @($Ast.FindAll({ param($n) $n -is [CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-GeneAliasName {
    <# The alias a Set-Alias / New-Alias / Remove-Alias command creates or removes: -Name <x> or the first positional. #>
    param([Parameter(Mandatory)][CommandAst]$Command)
    $els = $Command.CommandElements
    for ($i = 1; $i -lt $els.Count; $i++) {
        if ($els[$i] -is [CommandParameterAst] -and $els[$i].ParameterName -eq 'Name' -and $i + 1 -lt $els.Count) { return $els[$i + 1].Extent.Text.Trim("'`"") }
    }
    for ($i = 1; $i -lt $els.Count; $i++) {
        if ($els[$i] -is [CommandParameterAst]) { if ($els[$i].Argument) { continue }; $i++; continue }
        return $els[$i].Extent.Text.Trim("'`"")
    }
    return $null
}

function Get-GeneProfileDefinitions {
    <#
    Functions: every function definition, nested ones included. Nested: the ones defined inside another function. Aliases: Set-Alias / New-Alias names. Globals: every
    $global:X assigned anywhere. Calls: see Get-GeneProfileCalls. OtherTopLevel: the first line of every top-level
    statement that is not a function definition, an assignment, or a Set-Alias / New-Alias / Remove-Alias call.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseFile((Resolve-Path -LiteralPath $Path).ProviderPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$Path does not parse: $($errors[0].Message) at line $($errors[0].Extent.StartLineNumber)" }
    $allFns = @($ast.FindAll({ param($n) $n -is [FunctionDefinitionAst] }, $true))
    $functions = @($allFns | ForEach-Object Name | Sort-Object -Unique)
    # Nested: defined inside another function, so it exists only while that function runs (not after a plain load).
    $nested = @($allFns | Where-Object { $p = $_.Parent; $in = $false; while ($p) { if ($p -is [FunctionDefinitionAst]) { $in = $true; break }; $p = $p.Parent }; $in } | ForEach-Object Name | Sort-Object -Unique)
    $aliases = @($ast.FindAll({ param($n) $n -is [CommandAst] -and $n.GetCommandName() -in 'Set-Alias', 'New-Alias' }, $true) |
            ForEach-Object { Get-GeneAliasName -Command $_ } | Where-Object { $_ } | Sort-Object -Unique)
    $globals = @($ast.FindAll({ param($n) $n -is [AssignmentStatementAst] -and $n.Left -is [VariableExpressionAst] -and $n.Left.VariablePath.IsGlobal }, $true) |
            ForEach-Object { $_.Left.VariablePath.UserPath -replace '^global:', '' } | Sort-Object -Unique)
    $other = foreach ($s in $ast.EndBlock.Statements) {
        if ($s -is [FunctionDefinitionAst] -or $s -is [AssignmentStatementAst]) { continue }
        if ($s -is [PipelineAst] -and $s.PipelineElements.Count -eq 1 -and $s.PipelineElements[0] -is [CommandAst] -and
            $s.PipelineElements[0].GetCommandName() -in 'Set-Alias', 'New-Alias', 'Remove-Alias') { continue }
        $s.Extent.Text.Split("`n")[0].Trim()
    }
    return [pscustomobject]@{
        Path          = $Path
        Functions     = $functions
        Nested        = $nested
        Aliases       = $aliases
        Globals       = $globals
        Calls         = (Get-GeneProfileCalls -Ast $ast)
        OtherTopLevel = @($other)
    }
}
