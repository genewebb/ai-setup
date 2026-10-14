#requires -Version 7
<#
.SYNOPSIS
    Shared skill category taxonomy. Dot-source this; do not run it directly.

.DESCRIPTION
    The single definition of which category each skill belongs to. Two consumers
    dot-source it:

      Overview\Generate-SkillsReadme.ps1  - section order in the rendered index
      Set-SkillProfile.ps1                - which skills a profile turns on/off

    Keeping one definition is the whole point: a second copy would drift, and a
    profile that disagrees with the README about what "CrewChief" means is worse
    than no profile at all.

    Adding a skill whose name carries a known prefix needs no change here. Adding
    one that does not needs a line in $Overrides. Adding a new category needs a
    line in $CategoryOrder as well, or Generate-SkillsReadme.ps1 throws rather
    than silently dropping the skills in it.

.EXAMPLE
    . "$PSScriptRoot\skill-taxonomy.ps1"
    Get-SkillCategory -Name 'crewchief-secrets'
#>

# Section order in the rendered document. Also the canonical category list.
$CategoryOrder = @(
    'TestAuto — Scenarios & Framework'
    'CrewChief — Standalone Tool'
    'TestData — ETL & Data Generation'
    'Profisee Platform'
    '.NET / C# Patterns'
    'Blazor / UI'
    'Harness, Review & Workflow'
    'AI Tools & Skill Authoring'
    'General'
)

# Short aliases so callers do not have to type em-dashes on a command line.
# Set-SkillProfile.ps1 -Set CrewChief,Harness  ->  the full names above.
$CategoryAlias = [ordered]@{
    'testauto'     = 'TestAuto — Scenarios & Framework'
    'crewchief'    = 'CrewChief — Standalone Tool'
    'testdata'     = 'TestData — ETL & Data Generation'
    'profisee'     = 'Profisee Platform'
    'dotnet'       = '.NET / C# Patterns'
    'blazor'       = 'Blazor / UI'
    'harness'      = 'Harness, Review & Workflow'
    'ai-authoring' = 'AI Tools & Skill Authoring'
    'general'      = 'General'
}

# Default assignment by name prefix.
$PrefixMap = [ordered]@{
    'testauto-'    = 'TestAuto — Scenarios & Framework'
    'crewchief-'   = 'CrewChief — Standalone Tool'
    'testdata-'    = 'TestData — ETL & Data Generation'
    'profisee-'    = 'Profisee Platform'
    'dotnet-'      = '.NET / C# Patterns'
    'blazor-'      = 'Blazor / UI'
    'skill-'       = 'AI Tools & Skill Authoring'
    'ai-'          = 'AI Tools & Skill Authoring'
}

# Explicit assignment for anything the prefix rule gets wrong or cannot see.
# Add a line here when a new skill lands in the wrong section.
$Overrides = @{
    # TestAuto internals that do not carry the prefix
    'api-response-standardization'             = 'TestAuto — Scenarios & Framework'
    'bulk-custom-parms-editor-base'            = 'TestAuto — Scenarios & Framework'
    'configuration-compression-codec'          = 'TestAuto — Scenarios & Framework'
    'connex-import-tokenization'               = 'TestAuto — Scenarios & Framework'
    'custom-parm-editor'                       = 'TestAuto — Scenarios & Framework'
    'matching-api-status-poller'               = 'TestAuto — Scenarios & Framework'
    'record-mapper-extension-methods'          = 'TestAuto — Scenarios & Framework'
    'scenario-config-inspector'                = 'TestAuto — Scenarios & Framework'
    'secrets-bootstrap-middleware'             = 'TestAuto — Scenarios & Framework'
    'speedmerchants-db-migration'              = 'TestAuto — Scenarios & Framework'
    'step-reference-resolution'                = 'TestAuto — Scenarios & Framework'
    'utility-step-polymorphic-deserialization' = 'TestAuto — Scenarios & Framework'
    'seq-query'                                = 'TestAuto — Scenarios & Framework'
    'skill-inspect-workflow'                   = 'TestAuto — Scenarios & Framework'
    'skill-fix-integration-tests'              = 'TestAuto — Scenarios & Framework'
    'atomic-tests'                             = 'TestAuto — Scenarios & Framework'

    'inno-setup-installer'                     = 'CrewChief — Standalone Tool'

    'result-pattern'                           = '.NET / C# Patterns'
    'external-json-case-insensitive-reads'     = '.NET / C# Patterns'

    # Process, review, and harness workflows
    'requirements-writing'                    = 'Harness, Review & Workflow'
    'requirements-implementation-goal'         = 'Harness, Review & Workflow'
    'config-gc'                                = 'Harness, Review & Workflow'
    'context-budget'                           = 'Harness, Review & Workflow'
    'dual-review-convergence'                  = 'Harness, Review & Workflow'
    'inherit-legacy-style'                     = 'Harness, Review & Workflow'
    'blazor-click-path-audit'                  = 'Harness, Review & Workflow'
    'permissions-yaml'                         = 'Harness, Review & Workflow'
    'llm-council'                              = 'Harness, Review & Workflow'
    'pr-review'                                = 'Harness, Review & Workflow'
    'solution-architecture-review'             = 'Harness, Review & Workflow'
    'improve-codebase-architecture'            = 'Harness, Review & Workflow'
    'diagnose'                                 = 'Harness, Review & Workflow'
    'tdd'                                      = 'Harness, Review & Workflow'
    'prototype'                                = 'Harness, Review & Workflow'
    'handoff'                                  = 'Harness, Review & Workflow'
    'grill-me'                                 = 'Harness, Review & Workflow'
    'grill-with-docs'                          = 'Harness, Review & Workflow'
    'teach'                                    = 'Harness, Review & Workflow'
    'zoom-out'                                 = 'Harness, Review & Workflow'
    'to-issues'                                = 'Harness, Review & Workflow'

    'find-skills'                              = 'AI Tools & Skill Authoring'
    'write-a-skill'                            = 'AI Tools & Skill Authoring'

    # The profile switcher itself. Filed with the other skill-authoring tooling.
    'skill-profile'                            = 'AI Tools & Skill Authoring'
    # vNext (speedmerchants) UI campaign skills, 2026-09-09: the speedy- prefix has no rule of its own.
    'speedy-ui-playwright-axe'                 = 'Blazor / UI'
    'speedy-ui-composed-graph'                 = 'Blazor / UI'
    'speedy-ui-bunit'                          = 'Blazor / UI'
    'speedy-ui-screen-port'                    = 'Blazor / UI'
}

function Get-SkillCategory {
    <#
    .SYNOPSIS
        Category for a skill folder name. Override wins, then prefix, then General.
    #>
    param([Parameter(Mandatory)][string]$Name)

    if ($Overrides.ContainsKey($Name)) { return $Overrides[$Name] }
    foreach ($p in $PrefixMap.Keys) {
        if ($Name.StartsWith($p)) { return $PrefixMap[$p] }
    }
    'General'
}

function Resolve-CategoryName {
    <#
    .SYNOPSIS
        Accepts a full category name or a short alias; returns the full name.
        Throws on anything unrecognised so a typo cannot silently select nothing.
    #>
    param([Parameter(Mandatory)][string]$Name)

    # -eq and -contains are case-insensitive in PowerShell, so match against the
    # canonical list and return ITS spelling - never the caller's. Returning the
    # input would leak 'general' where every other consumer expects 'General'.
    $exact = $CategoryOrder | Where-Object { $_ -eq $Name } | Select-Object -First 1
    if ($exact) { return $exact }

    $key = $Name.ToLowerInvariant()
    if ($CategoryAlias.Contains($key)) { return $CategoryAlias[$key] }

    throw "Unknown category '$Name'. Valid: $(($CategoryAlias.Keys) -join ', ')"
}
