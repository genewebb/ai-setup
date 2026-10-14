# PR Review Command - Main Documentation

**📖 This is the primary documentation file for the `/pr-review` command. When executing this command, read from this file and the referenced process and analysis files.**

This command performs comprehensive pull request reviews using Azure DevOps MCP tools, analyzing code changes, organizational patterns, complexity, and potential issues across all modified files. It also supports reviewing local changes before creating a PR.

**Related Documentation:**
- **Process Details**: See [process.md](./process.md) for detailed step-by-step execution instructions
- **Analysis Sections**: See [analysis/](./analysis/) directory for individual analysis category documentation
- **Quick Reference**: See [../pr-review.md](../pr-review.md) for quick start examples

## Command Invocation

Execute this command using the `/` prefix in Cursor's chat:

```powershell
/pr-review [options]
```

**Quick Start:**
```powershell
# Review local changes before creating a PR (compare current branch to master)
/pr-review local master

# Review a PR by providing project and PR number
/pr-review --project "ProjectName" --pr-number 123

# Or provide PR link (Azure DevOps format)
/pr-review --project "ProjectName" "Pull Request 19798: Simplifying MiddlePanel flow"

# Or provide PR URL
/pr-review --url "https://dev.azure.com/org/project/_git/repo/pullrequest/123"
```

**Note:** The command can also be invoked with the `@` prefix (`@pr-review`), but `/pr-review` is the recommended format.

## Objectives

- **Review PR Changes**: Fetch and analyze all changes in the specified Azure DevOps pull request
- **Review Local Changes**: Analyze local branch changes before creating a PR (compare current branch to specified base branch)
- **Code Quality Analysis**: Evaluate code quality, patterns, and adherence to project standards
- **Issue Detection**: Identify bugs, security vulnerabilities, performance issues, and accessibility concerns
- **Optimization Opportunities**: Find areas for refactoring, optimization, and improvement
- **Regex Analysis**: Detect regex usage and identify optimization opportunities, as regex often indicates inconsistent code practices
- **Font Awesome Usage**: Detect Font Awesome CSS class usage and recommend using `<FontAwesome />` React components instead
- **Component Extraction**: Identify opportunities to break large components into smaller, more maintainable components
- **Inline Style Usage**: Detect overuse of inline `style` attributes and recommend using CSS classes and specific selectors instead
- **Type Assertion Analysis**: Detect type assertions (`as`, `as unknown as`) and recommend proper type guards or type definitions
- **Organizational Patterns**: Verify adherence to project structure and coding conventions
- **Complexity Analysis**: Assess code complexity across multiple files and identify optimization opportunities
- **Spelling and Grammar**: Check for spelling errors in code, comments, documentation, and user-facing text
- **Actionable Feedback**: Provide detailed, prioritized feedback with solutions

## Prerequisites

### For PR Reviews (Azure DevOps)
- Azure DevOps MCP server must be configured and accessible
- User must provide either:
  - PR ID (pullRequestId) and repository ID (repositoryId), OR
  - Project name and PR number, OR
  - PR link in Azure DevOps format: "Pull Request 19798: [Title]", OR
  - PR URL from Azure DevOps

### For Local Reviews
- Git repository must be initialized and accessible
- Current branch must have uncommitted changes or commits ahead of the base branch
- Base branch (e.g., `master`, `main`) must exist in the repository

## Step-by-Step Process

### Step 1: Determine Review Mode

The command supports two modes:

1. **PR Review Mode**: Reviews an existing Azure DevOps pull request
2. **Local Review Mode**: Reviews local changes before creating a PR (invoked with `local <base-branch>`)

### Step 1A: PR Identification and Validation (PR Review Mode Only)

1. **Extract PR Information**:
   - If PR ID and repository ID are provided, use them directly
   - If project name and PR number are provided, use `mcp_ado_repo_list_pull_requests_by_repo_or_project` to find the PR
   - If PR link in Azure DevOps format "Pull Request 19798: [Title]" is provided:
     - Parse the link using regex pattern: `Pull Request (\d+): (.+)` to extract:
       - PR number (e.g., "19798" from "Pull Request 19798: Simplifying MiddlePanel flow")
       - PR title (optional, can be used for validation)
     - Use the extracted PR number with the project name to find the PR via `mcp_ado_repo_list_pull_requests_by_repo_or_project`
     - Validate that the found PR title matches (if title was provided) to ensure correct PR
   - If PR URL is provided, parse it to extract project, repository, and PR ID

2. **Fetch PR Details**:
   - Use `mcp_ado_repo_get_pull_request_by_id` to retrieve full PR information
   - **IMPORTANT**: Always fetch PR details fresh to ensure we have the latest state
   - Extract and note the latest commit SHA from the PR's source branch
   - Display PR summary to user:
     - PR title and description
     - Source and target branches
     - Latest commit SHA (to verify we're reviewing the most recent code)
     - Author and creation date
     - Last updated date/time
     - Status (Active, Completed, Abandoned)
     - Number of commits and files changed

3. **User Confirmation**:
   - Present PR details to user
   - Confirm this is the correct PR to review
   - If incorrect, prompt for correct PR information

### Step 1B: Local Branch Identification (Local Review Mode Only)

1. **Detect Local Review Mode**:
   - If command starts with `local`, parse the base branch name (e.g., `master`, `main`)
   - **CRITICAL**: Disable git pager for all git commands to prevent vim from opening
   - Determine current branch name using PowerShell: `git --no-pager branch --show-current` or `git --no-pager rev-parse --abbrev-ref HEAD`
   - Validate that both branches exist in the repository using PowerShell: `git --no-pager branch --list <branch-name>`

2. **Display Review Context**:
   - Show current branch name
   - Show base branch name
   - Display summary of changes:
     - Number of commits ahead of base branch
     - Number of files changed
     - Total lines added/removed (if available)

3. **User Confirmation**:
   - Present branch comparison details to user
   - Confirm this is the correct comparison
   - If incorrect, prompt for correct branch information

### Step 2: Fetch Changes

See [process.md](./process.md) for detailed steps on fetching changes for both PR Review Mode and Local Review Mode.

### Step 3: Comprehensive File Analysis

For each changed file, perform the following analysis. Each analysis section is detailed in separate files:

- [Organizational Patterns](./analysis/organizational-patterns.md) - File naming, organization, using/namespaces
- [Complexity Analysis](./analysis/complexity.md) - Cyclomatic complexity, file size, dependencies
- [Potential Issues](./analysis/potential-issues.md) - Logic errors, type safety, .NET/Blazor-specific issues
- [Potential Optimizations](./analysis/optimizations.md) - Performance, memory, I/O optimizations
- [Potential Refactorings](./analysis/refactorings.md) - Code duplication, design patterns, code smells
- [Potential Improvements](./analysis/improvements.md) - Documentation, testing, code style
- [Potential Bugs](./analysis/bugs.md) - Runtime errors, logic bugs, async/state management bugs
- [Security Issues](./analysis/security.md) - Authentication, authorization, input validation
- [Performance Issues](./analysis/performance.md) - Allocation, I/O, async performance
- [Accessibility Issues](./analysis/accessibility.md) - ARIA, keyboard navigation, semantic HTML (Blazor)
- [Internationalization Issues](./analysis/internationalization.md) - String management, cultural considerations
- [Blazor Rules Compliance](./analysis/blazor-rules.md) - Code-behind separation, constants, approved icons per `.cursor/rules/`
- [Spelling and Grammar](./analysis/spelling-grammar.md) - Spelling errors in code, comments, user-facing text
- [Regex Usage Analysis](./analysis/regex.md) - Regex detection, optimization, code smell indicators
- [Approved Icons](./analysis/approved-icons.md) - Material Symbols compliance; no Bootstrap/Font Awesome
- [Blazor Component Extraction](./analysis/blazor-component-extraction.md) - Razor component extraction opportunities
- [Inline Style Usage](./analysis/inline-styles.md) - Detection of overuse of inline styles (Razor/CSS)
- [C# Type Safety](./analysis/csharp-type-safety.md) - Unsafe casts, null-forgiving, nullable handling

### Step 4: Cross-File Analysis

See [process.md](./process.md) for detailed steps on cross-file analysis including impact analysis and dependency analysis.

### Step 5: Severity Classification and Prioritization

Categorize all findings by severity:

#### Critical (Must Fix)
- Security vulnerabilities
- Data loss risks
- Breaking changes
- Critical bugs that cause crashes
- Missing authentication/authorization

#### High (Should Fix)
- Performance issues affecting user experience
- Accessibility violations (WCAG AA)
- Logic errors causing incorrect behavior
- Missing error handling
- Type safety issues (unsafe casts, null-forgiving `!`, excessive `as` without validation)
- Spelling errors in code elements (variable names, method names, class names) that could cause bugs
- C# casts (`as`, `!`) without proper justification or pattern matching

#### Medium (Consider Fixing)
- Code quality issues
- Optimization opportunities
- Refactoring suggestions
- Missing documentation
- Code style inconsistencies
- Regex usage indicating inconsistent code practices (when not causing performance issues)
- Regex patterns that could be optimized or replaced with simpler alternatives
- Bootstrap or Font Awesome icons in Blazor (should use Material Symbols per approved-icons.mdc)
- Large Razor markup blocks (>150 lines) or code-behind (>300 lines) that should be extracted
- IRestClient or direct data access in page code-behind (should use services)
- Overuse of inline `style` attributes (Razor components with >10 inline styles)
- Hard-coded entity/field names (should use EntityNames, FieldNames constants)
- Spelling errors in user-facing text and error messages
- Spelling errors in comments and documentation
- Type assertions that could be replaced with pattern matching or proper typing

#### Low (Nice to Have)
- Minor style improvements
- Documentation enhancements
- Test coverage improvements
- Code organization suggestions
- Non-approved icons in existing code being modified (consider refactoring to Material Symbols)
- Smaller Razor blocks (80-150 lines) that could benefit from component extraction
- Moderate inline style usage (5-10 inline styles, static style objects with 5-8 properties)
- Minor spelling/grammar issues in comments
- Inconsistent terminology (if not causing confusion)
- Type assertions with proper justification comments

### Step 6: Generate Review Report

See [process.md](./process.md) for detailed steps on generating the review report.

### Step 7: User Review of Report

See [process.md](./process.md) for detailed steps on user review of the report.

### Step 8: Prepare Comments and Post to PR (PR Review Mode Only)

See [process.md](./process.md) for detailed steps on preparing and posting comments to the PR.

### Step 8B: Local Review Output (Local Review Mode Only)

See [process.md](./process.md) for detailed steps on local review output.

## Usage Examples

### Basic Usage
```powershell
# Review local changes before creating a PR (compare current branch to master)
/pr-review local master

# Review local changes comparing to main branch
/pr-review local main

# Review PR by ID
/pr-review --pr-id 123 --repo-id "repo-guid-here" --project "ProjectName"

# Review PR by number (will search for it)
/pr-review --project "ProjectName" --pr-number 456

# Review PR using Azure DevOps link format (recommended)
/pr-review --project "ProjectName" "Pull Request 19798: Simplifying MiddlePanel flow"

# Review PR by URL
/pr-review --url "https://dev.azure.com/org/project/_git/repo/pullrequest/789"

# Alternative: Using @ prefix (also supported)
@pr-review local master
@pr-review --pr-id 123 --repo-id "repo-guid-here" --project "ProjectName"
```

### Advanced Usage
```powershell
# Local review with specific focus areas
/pr-review local master --focus security,performance,spelling

# Local review excluding certain file types
/pr-review local main --exclude "*.test.ts,*.spec.ts"

# Local review with custom severity threshold
/pr-review local master --min-severity high

# Local review only spelling errors
/pr-review local master --focus spelling

# Local review focusing on regex patterns
/pr-review local master --focus regex

# Local review focusing on Font Awesome usage
/pr-review local master --focus fontawesome

# Local review focusing on component extraction opportunities
/pr-review local master --focus component-extraction

# Local review focusing on inline style usage
/pr-review local master --focus inline-styles

# Local review focusing on type assertions
/pr-review local master --focus type-assertions

# Local review and save report to file
/pr-review local master --save-report

# PR review with specific focus areas
/pr-review --pr-id 123 --repo-id "repo-guid" --focus security,performance,spelling

# PR review excluding certain file types
/pr-review --pr-id 123 --repo-id "repo-guid" --exclude "*.test.ts,*.spec.ts"

# PR review with custom severity threshold
/pr-review --pr-id 123 --repo-id "repo-guid" --min-severity high

# PR review only spelling errors
/pr-review --pr-id 123 --repo-id "repo-guid" --focus spelling

# PR review focusing on regex patterns
/pr-review --pr-id 123 --repo-id "repo-guid" --focus regex

# PR review focusing on Font Awesome usage
/pr-review --pr-id 123 --repo-id "repo-guid" --focus fontawesome

# PR review focusing on component extraction opportunities
/pr-review --pr-id 123 --repo-id "repo-guid" --focus component-extraction

# PR review focusing on inline style usage
/pr-review --pr-id 123 --repo-id "repo-guid" --focus inline-styles

# PR review focusing on type assertions
/pr-review --pr-id 123 --repo-id "repo-guid" --focus type-assertions

# PR review without posting comments (dry run)
/pr-review --pr-id 123 --repo-id "repo-guid" --dry-run

# PR review and auto-post comments
/pr-review --pr-id 123 --repo-id "repo-guid" --auto-post
```

## Configuration Options

### Review Scope
- **File filtering**: Include/exclude specific file patterns
- **Severity threshold**: Only report issues above certain severity
- **Category filtering**: Focus on specific categories (security, performance, spelling, regex, fontawesome, component-extraction, inline-styles, type-assertions, etc.)
- **Depth**: Surface-level vs deep analysis
- **Spelling dictionary**: Custom dictionary for project-specific terms and technical vocabulary
- **Regex analysis**: Detect and analyze regex patterns for optimization opportunities and code quality issues
- **Font Awesome analysis**: Detect Font Awesome CSS class usage and recommend using `<FontAwesome />` React components
- **Component extraction analysis**: Identify opportunities to break large components into smaller, more maintainable components
- **Inline style analysis**: Detect overuse of inline `style` attributes and recommend using CSS classes and specific selectors instead
- **Type assertion analysis**: Detect type assertions and recommend proper type guards or type definitions

### Output Format
- **Console output**: Real-time analysis display
- **Report file**: Save detailed report to markdown file
- **PR comments**: Post findings directly to PR
- **Summary only**: Show only high-level summary

### Integration
- **Azure DevOps**: Direct integration with ADO MCP tools (PR Review Mode)
- **PowerShell**: All local commands executed using PowerShell on Windows
- **Git**: Compare with base branch for accurate diffs using PowerShell git commands (both modes). All git commands use `--no-pager` flag to prevent vim from opening.
- **Local Git**: Uses local git repository for diff analysis via PowerShell (Local Review Mode). Git pager is disabled for all commands.
- **dotnet build**: Automatically runs `dotnet build` to catch compilation errors (Local Review Mode only)
- **dotnet test**: Optionally runs `dotnet test` for test results (Local Review Mode only)
- **Spell Checkers**: Integrate with spell checking tools (cspell, etc.) if available
- **Tests**: Include test results in review

## Project-Specific Rules

This command respects the following project conventions:

- **Code Style**: C# conventions, nullable reference types, async patterns
- **Blazor Patterns**: Code-behind separation, service injection, Radzen components
- **Testing**: MSTest, bUnit for Blazor components
- **Constants**: EntityNames, FieldNames for entity/field references
- **File Organization**: .razor + .razor.cs for pages, Services in BusinessLogic
- **Accessibility**: WCAG AA compliance
- **Icons**: Material Symbols via Radzen; no Bootstrap/Font Awesome

### Blazor Rules Validation

The PR review command validates Blazor/C# files against rules in `.cursor/rules/`:

- **Rule Sources**: Code-behind separation, approved icons, string constants, domain values
- **Key rules**: `code-behind-separation-rules.mdc`, `approved-icons.mdc`, `string-constants.mdc`

- **Validation Process**:
  1. Identify all Razor and C# files in the changeset
  2. For each file, check against applicable Blazor/.NET rules
  3. Flag violations with severity levels (Critical, High, Medium, Low)
  4. Provide rule references and suggested fixes
  5. Include code examples showing correct patterns

- **Integration**: Blazor rules violations are integrated into the analysis report and PR comments (PR Review Mode) or console output (Local Review Mode)

## Notes

- All analysis respects existing project patterns and conventions
- Findings include educational explanations and impact assessments
- Suggestions include code examples and implementation guidance
- False positives can be dismissed during user review
- **PR Review Mode**: Comments are posted only after user approval. Review can be run multiple times as PR evolves. Previous comments are not duplicated (checks existing threads).
- **Local Review Mode**: No comments are posted (no PR exists). Review generates console output and optional report file. Perfect for pre-PR quality checks. Automatically runs `dotnet build` (and optionally `dotnet test`) to catch compilation and test errors before creating a PR.
- **Spelling Checks**: Context-aware spelling detection respects technical terms, domain vocabulary, and project naming conventions. Code element spelling errors (variables, functions) are prioritized higher than comment/documentation spelling errors.
- **Regex Analysis**: The review automatically detects and analyzes regex patterns for optimization opportunities and code quality issues. Regex usage often indicates inconsistent code practices or missing structured data formats. The analysis identifies performance issues (catastrophic backtracking, repeated compilation), simplification opportunities (using string methods instead), and architectural concerns (regex as workaround for missing data contracts).
- **Approved Icons Analysis**: The review detects Bootstrap or Font Awesome icon usage in Blazor and recommends Material Symbols per `approved-icons.mdc`. Ensures consistency with Radzen.Blazor icon set.
- **Blazor Component Extraction**: The review identifies opportunities to extract large Razor components, move logic to code-behind or services, and split components with multiple concerns. Provides extraction recommendations with file locations per project structure.
- **Inline Style Analysis**: The review automatically detects overuse of inline `style` attributes and recommends using CSS classes and specific selectors instead. This includes identifying static style objects that should be CSS classes, repeated style patterns, and complex inline styles. The analysis distinguishes between acceptable dynamic inline styles and static styles that should be migrated to CSS classes, provides CSS Module migration examples, and explains the benefits (performance, maintainability, better override capabilities, smaller bundle size).
- **C# Type Safety Analysis**: The review detects unsafe casts (`as`, `!`), nullable misuse, and record/dictionary access patterns. Recommends pattern matching, type guards, and proper null handling. Identifies IRestClient in pages and hard-coded entity/field names.
- **PR Link Format**: The preferred format for referencing PRs is the Azure DevOps link format: `"Pull Request 19798: [Title]"`. This format can be copied directly from Azure DevOps and includes both the PR number and title for easy identification. The command will automatically parse this format to extract the PR number.
- **Local Review Format**: Use `local <base-branch>` to review local changes. The base branch can be any branch name (e.g., `master`, `main`, `develop`). The command compares your current branch against the specified base branch.
- **PowerShell Environment**: This command is designed for Windows PowerShell. All git commands, dotnet commands, and file operations use PowerShell syntax. Ensure PowerShell 7+ is available for optimal compatibility.
- **Git Pager Prevention**: All git commands use `--no-pager` flag or `GIT_PAGER=cat` environment variable to prevent vim from opening during non-interactive execution. This ensures git commands complete without requiring manual intervention.
- **Latest PR Code**: PR Review Mode always fetches the latest PR state and uses the most recent commit SHA from the PR's source branch to ensure the review analyzes the most up-to-date code, including any recent commits or updates to the PR.
