# Code Block Style Guide

## Purpose

This guide establishes consistent formatting for code blocks in documentation, optimized for readability in Obsidian, GitHub, and Cursor IDE.

---

## Code Block Rules

### Rule 1: Always Specify Language

Always include a language identifier after the opening triple backticks.

> [!example]- Good Example
> ``` Powershell
> .\sync-ai-rules.ps1 -Force
> ```

> [!danger]- Bad Example
> ```
> .\sync-ai-rules.ps1 -Force
> ```

---

### Rule 2: Common Language Identifiers

| Language | Identifier |
|----------|------------|
| PowerShell | Powershell or powershell |
| C# | csharp |
| JavaScript | javascript or js |
| TypeScript | typescript or ts |
| JSON | json |
| SQL | sql |
| Bash/Shell | bash or shell |
| YAML | yaml |
| Markdown | markdown |
| XML | xml |
| HTML | html |
| CSS | css |

---

### Rule 3: One Command Per Block for Copyability

When documenting CLI commands, use one command per code block so users can easily copy individual commands.

> [!tip]- Correct: Separate Blocks
> #### Push to current directory
> ``` Powershell
> .\sync-ai-rules.ps1
> ```
> #### Push with force
> ``` Powershell
> .\sync-ai-rules.ps1 -Force
> ```

> [!warning]- Avoid: Multiple Commands in One Block
> ``` Powershell
> # Push to current directory
> .\sync-ai-rules.ps1
> # Push with force  
> .\sync-ai-rules.ps1 -Force
> ```

---

### Rule 4: Use Headers Before Code Blocks

Always precede a code block with a descriptive header (h4 recommended for command references).

> [!example]- Correct Format
> #### Install dependencies
> ``` Powershell
> dotnet restore
> ```

> [!warning]- Avoid: No Context
> ``` Powershell
> dotnet restore
> ```

---

### Rule 5: No Backticks in Tables

In tables, use plain text for code references instead of backticks to improve readability.

> [!tip]- Preferred
> | Parameter | Default |
> |-----------|---------|
> | -Force | $false |
> | -WhatIf | $false |

> [!warning]- Avoid
> | Parameter | Default |
> |-----------|---------|
> | `-Force` | `$false` |
> | `-WhatIf` | `$false` |

---

### Rule 6: Inline Code for References

Use single backticks for inline code references within paragraphs.

> [!example]- Example
> The `repos/` subfolder inside `.cursor/` is automatically excluded.

---

### Rule 7: Multi-line Code Blocks

For multi-line code, ensure proper indentation is preserved.

> [!example]- C# Example
> ```csharp
> public class Example
> {
>     public string Name { get; set; }
>     
>     public void Process()
>     {
>         Console.WriteLine(Name);
>     }
> }
> ```

---

### Rule 8: JSON Configuration Blocks

For JSON configuration examples, include the full structure with proper formatting.

> [!example]- JSON Config Example
> ```json
> {
>   "TemplatePath": "<path>",
>   "Include": ["base", "dotnet"],
>   "Exclude": ["solutions"],
>   "SkipVSCode": false
> }
> ```

---

### Rule 9: Command Output Blocks

When showing command output, use plain code blocks without language identifier or use `text`.

> [!example]- Output Example
> ```text
> [COPIED] .cursor\rules\base\coding\clean-code-guidelines.mdc
> [IDENTICAL] .cursor\rules\base\agents\builder.mdc
> [SKIP] .vscode\settings.json (changed, use -Force to overwrite)
> ```

---

### Rule 10: Callouts for Important Code

Use Obsidian callouts to highlight important code examples or warnings.

> [!note] Standard Note
> Use for general code explanations.

> [!tip] Tip Callout
> Use for best practices and recommendations.

> [!warning] Warning Callout
> Use for code that could cause issues if misused.

> [!danger] Danger Callout
> Use for destructive or irreversible commands.

> [!example]- Collapsible Example
> Use `-` after the callout type to make it collapsible.
> ``` Powershell
> Remove-Item -Recurse -Force ./node_modules
> ```

---

## Quick Reference

### Code Block Template

```markdown
#### Description of what this command does
``` Language
command or code here
```
```

### Collapsible Callout Template

```markdown
> [!example]- Click to expand
> ``` Powershell
> your-command-here
> ```
```

### Table Without Backticks

```markdown
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| -Force | Switch | $false | Overwrite files |
```

---

## Enforcement

- All new documentation must follow these rules
- Existing documentation should be updated when edited
- Code reviews should check for consistent formatting
