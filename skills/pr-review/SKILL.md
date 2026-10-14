---
name: pr-review
description: >
  Comprehensive pull request review with 18+ analysis categories. Use when
  reviewing PRs, performing code reviews, or analyzing pull request changes.
  Supports both Azure DevOps PR review mode and local branch review mode.
---

# PR Review

This skill performs comprehensive pull request reviews using Azure DevOps MCP tools, analyzing code changes, organizational patterns, complexity, and potential issues across all modified files. It also supports reviewing local changes before creating a PR.

**This skill documentation has been structured into multiple files for better maintainability. When executing this skill, refer to the detailed documentation files listed below for complete implementation guidance.**

## Quick Reference

### Invocation

```
# Review local changes before creating a PR
pr-review local master

# Review a PR by project and PR number
pr-review --project "ProjectName" --pr-number 123

# Review PR using Azure DevOps link format (recommended)
pr-review --project "ProjectName" "Pull Request 19798: Simplifying MiddlePanel flow"

# Review PR by URL
pr-review --url "https://dev.azure.com/org/project/_git/repo/pullrequest/123"
```

### Quick Start Examples

```
# Local review with focus areas
pr-review local master --focus security,performance,type-assertions

# PR review with specific focus
pr-review --project "ProjectName" --pr-number 123 --focus fontawesome,component-extraction,inline-styles
```

## Documentation Structure

**When implementing or executing this skill, read from these files:**

### Reference Documentation

- **[references/main.md](./references/main.md)** - Complete command documentation including:
  - Command invocation and usage examples
  - Objectives and prerequisites
  - Configuration options
  - Project-specific rules
  - Output format examples

- **[references/process.md](./references/process.md)** - Detailed step-by-step process including:
  - Fetching changes (PR Review Mode and Local Review Mode)
  - Linting and type checking
  - Impact analysis
  - Cross-file analysis
  - Report generation
  - Comment posting (PR Review Mode)

### Analysis Sections

Each analysis section is documented in separate files. **When performing analysis, read from these files in `./references/`:**

- **organizational-patterns.md** - File naming, organization, imports/exports
- **complexity.md** - Cyclomatic complexity, file size, dependencies
- **potential-issues.md** - Logic errors, type safety, React-specific issues
- **optimizations.md** - Performance, memory, network optimizations
- **refactorings.md** - Code duplication, design patterns, code smells
- **improvements.md** - Documentation, testing, code style
- **bugs.md** - Runtime errors, logic bugs, state management bugs
- **security.md** - Authentication, authorization, input validation
- **performance.md** - Rendering, JavaScript, network performance
- **accessibility.md** - ARIA, keyboard navigation, semantic HTML
- **internationalization.md** - String management, cultural considerations
- **react-rules.md** - Adherence to React rules
- **spelling-grammar.md** - Spelling errors in code, comments, user-facing text
- **regex.md** - Regex detection, optimization, code smell indicators
- **fontawesome.md** - Font Awesome CSS class detection and replacement recommendations
- **component-extraction.md** - Opportunities to break large components into smaller ones
- **inline-styles.md** - Detection of overuse of inline styles
- **type-assertions.md** - Detection and analysis of type assertions (`as`, `as unknown as`) with automatic comment generation

## Execution Flow

When executing a PR review, follow this flow:

1. **Read [references/main.md](./references/main.md)** for:
   - Command invocation syntax
   - Prerequisites and setup
   - Configuration options
   - Overall command structure

2. **Read [references/process.md](./references/process.md)** for:
   - Step-by-step execution process
   - How to fetch changes (PR vs Local mode)
   - How to run linting/type checking
   - How to perform impact analysis
   - How to generate and post reports

3. **For each analysis task, read the corresponding analysis file** from `./references/`:
   - Each file contains detailed detection patterns
   - Severity classifications
   - Reporting formats
   - Code examples
   - Recommendations

## Key Features

- **PR Review Mode**: Reviews existing Azure DevOps pull requests
- **Local Review Mode**: Reviews local changes before creating a PR
- **Comprehensive Analysis**: 18+ analysis categories covering code quality, security, performance, accessibility, and more
- **Type Assertion Analysis**: Automatically suggests adding explanatory comments for necessary type assertions
- **Font Awesome Analysis**: Detects CSS class usage and recommends React components
- **Component Extraction**: Identifies opportunities to break large components into smaller ones
- **Inline Style Analysis**: Detects overuse of inline styles and recommends CSS classes
- **Impact Analysis**: Identifies high-impact files with many dependent files
- **Linting Integration**: Automatically runs ESLint and TypeScript checks (Local Review Mode)

## Focus Categories

Use `--focus` to analyze specific categories:

- `security` - Security vulnerabilities
- `performance` - Performance issues
- `spelling` - Spelling and grammar errors
- `regex` - Regex usage analysis
- `fontawesome` - Font Awesome usage
- `component-extraction` - Component extraction opportunities
- `inline-styles` - Inline style usage
- `type-assertions` - Type assertion analysis
- `react-rules` - React rules compliance
- `accessibility` - Accessibility issues
- And more (see [references/main.md](./references/main.md) for complete list)

## Notes

- All analysis respects existing project patterns and conventions
- Findings include educational explanations and impact assessments
- Suggestions include code examples and implementation guidance
- False positives can be dismissed during user review
- **PR Review Mode**: Comments are posted only after user approval
- **Local Review Mode**: Generates console output and optional report file, automatically runs ESLint and TypeScript checks

## Implementation Notes

**When executing this skill:**

1. **Always read from the referenced files** - Don't rely solely on this summary file
2. **Follow the process in [references/process.md](./references/process.md)** - It contains the detailed step-by-step instructions
3. **Use analysis files for detection patterns** - Each analysis file contains specific patterns, severity classifications, and reporting formats
4. **Reference [references/main.md](./references/main.md)** for configuration options, usage examples, and project-specific rules

**File Reading Priority:**
1. Start with [references/main.md](./references/main.md) for command structure
2. Follow [references/process.md](./references/process.md) for execution steps
3. Reference individual analysis files as needed during analysis

---

**For complete documentation, see:**
- **Main Documentation**: [references/main.md](./references/main.md)
- **Process Details**: [references/process.md](./references/process.md)
- **Analysis Sections**: `./references/` directory
