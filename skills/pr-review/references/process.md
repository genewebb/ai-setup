# PR Review Process

**📋 This file contains the detailed step-by-step process for executing the `/pr-review` command. Read this file when implementing the command execution flow.**

This document details the step-by-step process for fetching changes, analyzing files, and generating review reports.

**Related Documentation:**
- **Main Command Documentation**: See [main.md](./main.md) for command overview, objectives, and configuration
- **Analysis Sections**: See [analysis/](./analysis/) directory for detailed analysis patterns and detection strategies

## Step 2: Fetch Changes

### Step 2A: Fetch PR Changes (PR Review Mode)

1. **Get Latest PR State**:
   - **CRITICAL**: Always fetch the latest PR information to ensure we're reviewing the most up-to-date code
   - Use `mcp_ado_repo_get_pull_request_by_id` to get the latest PR state (this ensures we have the most recent commit SHA)
   - Extract the latest source branch commit SHA from the PR object (typically `sourceRefName` and latest commit)
   - Verify PR status is Active and note the last updated timestamp

2. **Get Commits**:
   - Use `mcp_ado_repo_search_commits` to get all commits in the PR
   - **IMPORTANT**: Search commits from the PR's source branch (`sourceRefName`) to the target branch (`targetRefName`)
   - Use the latest commit SHA from the PR to ensure we get all commits including recent updates
   - Identify commit range (from merge base to latest commit SHA)

3. **Get Changed Files**:
   - Use `mcp_ado_repo_list_pull_request_threads` to understand discussion context
   - **CRITICAL**: Fetch file changes using the latest commit SHA, not just the initial commits
   - Use `mcp_ado_repo_search_commits` with the latest commit SHA to get the most recent file changes
   - Analyze commit changes to identify all modified files
   - Categorize files by type (TypeScript, C#, tests, config, etc.)

4. **Get File Contents**:
   - For each changed file, read the current version from the repository using the latest commit SHA
   - **IMPORTANT**: Use the latest commit SHA from the PR's source branch to get the most up-to-date file contents
   - **CRITICAL**: When using `mcp_ado_repo_list_pull_request_threads` or other PR-related APIs, ensure you're fetching the latest iteration (don't specify an old iteration ID). If iteration parameter is optional, omit it to get the latest, or explicitly request the latest iteration.
   - Compare with base branch (target branch) to understand changes
   - Note: Azure DevOps MCP may require using commit comparison or file diff APIs with the latest commit SHA

### Step 2B: Fetch Local Changes (Local Review Mode)

1. **Get Git Diff**:
   - Use PowerShell to execute git commands and get diff between current branch and base branch
   - **CRITICAL**: Disable git pager to prevent vim from opening. Use `--no-pager` flag or set `GIT_PAGER=cat` environment variable
   - Execute in PowerShell: `$env:GIT_PAGER='cat'; git --no-pager diff $baseBranch...HEAD` to get all changes
   - Capture output using PowerShell: `$diffOutput = git --no-pager diff $baseBranch...HEAD`
   - Parse diff output to identify modified, added, and deleted files

2. **Get Changed Files**:
   - Parse git diff output to extract list of changed files
   - Use `git --no-pager diff --name-status $baseBranch...HEAD` to get file status without opening pager
   - Categorize files by type (TypeScript, C#, tests, config, etc.)
   - Identify file status (modified, added, deleted, renamed)

3. **Get File Contents**:
   - For each changed file, read the current version from the local filesystem using PowerShell: `Get-Content -Path $filePath`
   - Read the base version from git using PowerShell: `git --no-pager show ${baseBranch}:${filePath}` (use `--no-pager` to prevent vim from opening)
   - Compare versions to understand changes
   - Handle binary files appropriately (skip or note as binary)

### Step 2C: Run Build and Tests (Local Review Mode Only)

1. **Run dotnet build**:
   - Execute build from solution/project root using PowerShell
   - Run: `dotnet build --no-restore` or `dotnet build` to compile all projects
   - Capture output: `$buildOutput = dotnet build 2>&1`
   - Parse output for compilation errors and warnings
   - Map build errors to changed files and line numbers
   - Include error codes and suggested fixes

2. **Run dotnet test** (optional, for projects with tests):
   - Run: `dotnet test --no-build` or `dotnet test`
   - Capture exit code, stdout, stderr
   - Map test failures to relevant code areas

3. **Integrate Build/Test Results**:
   - Combine build and test findings with file analysis
   - Flag files with compilation errors for priority review
   - Categorize issues by severity (Critical for errors, High for warnings)

4. **Display Summary**:
   - Show total build errors and warnings
   - Show test pass/fail summary
   - List files with build issues
   - Provide quick summary before detailed analysis

### Step 2D: Impact Analysis - Find Dependent Files (Both Modes)

1. **For Each Changed File**:
   - Extract the file path and determine reference patterns:
     - C# namespace: e.g. `TestAuto.Web.BusinessLogic.Services`
     - Class/interface names defined in the file
     - Partial class names (e.g. `Workflows.razor.cs` pairs with `Workflows.razor`)
   - Extract class, interface, and service names for pattern matching

2. **Search for References**:
   - Use `grep` tool to search for usages of each changed file:
     - Search pattern 1: `using.*NamespaceOfChangedFile` (C# using directives)
     - Search pattern 2: `Namespace\.ClassName` (fully qualified type references)
     - Search pattern 3: `@inherits.*ComponentName` (Razor base components)
     - Search pattern 4: `IWorkflowService`, `IScenarioService` (injected service types)
     - Search pattern 5: `EntityNames\.`, `FieldNames\.` (constant usage from changed file)
   - For shared services/utilities, search for interface or class names
   - Exclude bin, obj, and test fixtures when counting impact

3. **Count and Categorize Dependencies**:
   - Count total number of files importing each changed file
   - Categorize by impact level:
     - Critical: >20 dependent files
     - High: 10-20 dependent files
     - Medium: 5-10 dependent files
     - Low: <5 dependent files
   - Collect sample list of dependent files (first 10-15) for reporting
   - Identify if changed file is a core/shared component, utility, or hook

4. **Generate Impact Report**:
   - Sort changed files by impact level (Critical → High → Medium → Low)
   - For each high-impact file, include:
     - File path
     - Impact level and count
     - Sample dependent files list
     - Warning about potential breaking changes
     - Testing recommendations

## Step 4: Cross-File Analysis

Analyze relationships and patterns across multiple files:

- **Impact Analysis (High-Impact File Detection)**:
  - For each changed file, identify all files that reference it (using, inherits, inject)
  - Count the number of dependent files for each changed file
  - Flag files with high reference counts (e.g., >10 dependents) as high-impact
  - Use grep/codebase_search to find references:
    - Search for `using Namespace.From.Changed.File`
    - Search for `[Inject] IServiceType` (when changed file defines the service)
    - Search for `@inherits ChangedComponent` (Razor base)
    - Search for type names and namespace usages
  - Categorize impact levels:
    - **Critical Impact**: >20 dependent files (e.g., shared utilities, core components)
    - **High Impact**: 10-20 dependent files (e.g., commonly used components)
    - **Medium Impact**: 5-10 dependent files (e.g., specialized components)
    - **Low Impact**: <5 dependent files (e.g., isolated components)
  - Report impact analysis in review:
    - List changed files sorted by impact level
    - Show count of dependent files for each changed file
    - List sample dependent files (first 10-15) for high-impact files
    - Warn about potential breaking changes in high-impact files
    - Suggest additional testing for high-impact changes

- **Dependency Analysis**:
  - Circular dependencies between files
  - Unused dependencies
  - Missing dependencies
  - Version conflicts

- **Architectural Patterns**:
  - Consistency across similar files
  - Proper use of shared utilities
  - Adherence to project architecture
  - Breaking changes to shared code

- **Test Coverage**:
  - Overall test coverage for changes
  - Missing test files for new code
  - Test quality and completeness

## Step 6: Generate Review Report

Create comprehensive review report with:

1. **Executive Summary**:
   - Total files changed
   - Total issues found by severity
   - Overall assessment (Approve, Approve with Suggestions, Request Changes)

2. **Detailed Findings**:
   - Grouped by file
   - Each finding includes:
     - Severity level
     - Category (bug, security, performance, etc.)
     - Location (file path, line numbers)
     - Description of the issue
     - Code snippet showing the problem
     - Suggested solution with code example
     - Impact assessment
   - **Impact Analysis Section**:
     - List of changed files sorted by impact level (Critical → High → Medium → Low)
     - For each high-impact file:
       - File path and impact level
       - Number of dependent files
       - Sample list of dependent files (first 10-15)
       - Warning about potential breaking changes
       - Recommendation for additional testing

3. **Positive Feedback**:
   - Well-implemented patterns
   - Good practices followed
   - Clean code examples

4. **Recommendations**:
   - Priority order for fixes
   - Suggested next steps
   - Best practices to follow

## Step 7: User Review of Report

1. **Present Report**:
   - Display comprehensive review report to user
   - Show executive summary with:
     - Total files changed
     - Total issues found by severity
     - Overall assessment (Approve, Approve with Suggestions, Request Changes)
   - Allow user to review detailed findings
   - Provide option to filter by severity or category
   - Display findings grouped by file

2. **User Feedback on Report**:
   - User can review all findings
   - User can dismiss false positives (these won't be included in comments)
   - User can request more details on specific findings
   - User can modify severity levels
   - User can add notes or context

3. **Transition to Comment Preparation**:
   - After user has reviewed the report, proceed to Step 8 to prepare comments
   - Only findings that were not dismissed will be included in comments

## Step 8: Prepare Comments and Post to PR (PR Review Mode Only)

**Note:** This step is skipped for Local Review Mode. Local reviews only generate reports and console output.

1. **Prepare Comment List**:
   - Generate a formatted list of all findings ready to be posted as PR comments
   - For each finding, prepare:
     - File path (if applicable)
     - Line numbers (if applicable)
     - Comment content with:
       - Issue description
       - Severity level
       - Suggested solution
       - Code example (if applicable)
   - Group related findings that should be in the same thread
   - Count total number of comments to be posted

2. **Present Comments to User**:
   - Display the complete list of problems ready to comment
   - Show preview of each comment that will be posted
   - Include:
     - Total number of comments
     - Breakdown by severity
     - File locations
     - Brief summary of each finding
   - Allow user to:
     - Review all comments before posting
     - Skip specific comments
     - Modify comment content
     - Group/ungroup comments

3. **User Approval**:
   - Present final list of comments to be posted
   - Wait for explicit user approval before posting
   - Confirm: "Ready to post X comments to PR #XXXXX?"
   - If user approves, proceed to post comments
   - If user declines, allow them to modify or cancel

4. **Post Comments to PR**:
   - After user approval, use `mcp_ado_repo_create_pull_request_thread` for each approved comment:
     - File path (if applicable)
     - Line numbers (if applicable)
     - Comment content (as approved by user)
     - Appropriate thread status (Active, Fixed, etc.)
   - Post comments in order of severity (Critical → High → Medium → Low)
   - Group related findings in single threads when appropriate

5. **Post Summary Comment**:
   - After all individual comments are posted, post overall summary as general comment
   - Include:
     - Total files changed
     - Total issues found by severity
     - Overall assessment
     - Link to detailed report (if saved)
   - Use `mcp_ado_repo_create_pull_request_thread` without file path for general comment

6. **Confirmation**:
   - Confirm successful posting of all comments
   - Display summary of what was posted
   - Provide links to posted comments if available

## Step 8B: Local Review Output (Local Review Mode Only)

1. **Generate Report**:
   - Create comprehensive review report (same format as PR review)
   - Save report to markdown file (optional, user can request)
   - Display report in console with full details

2. **Actionable Next Steps**:
   - Provide summary of findings
   - Suggest priority order for fixes
   - Recommend creating PR after addressing critical/high issues
   - Offer to save report for reference

3. **Confirmation**:
   - Display summary of review completed
   - Show total issues found by severity
   - Provide option to save report or export findings
