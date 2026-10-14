---
name: bug-generator
description: >
  Azure DevOps bug work item generator with AI-assisted and manual input modes.
  Use when creating bugs, filing bug reports, or reporting defects in Azure
  DevOps. Supports description-based, detailed, interactive, and update modes.
---

# Bug Generator

This skill generates bugs in Azure DevOps (ADO) based on information provided by developers and QA engineers. It uses Azure DevOps MCP tools to create well-structured bug work items with all necessary details, links, and attachments.

## Quick Summary

The bug generator operates in **two distinct modes** for creating bugs, plus an **update mode**:

1. **Description Mode** (`--description` flag): Provide a natural language description, and the command will use AI to infer bug details and ask clarifying questions for any missing information.

2. **Detailed Mode** (specific option flags): Provide exact bug details using specific flags, and the command will use your provided values directly, only prompting for missing required fields.

3. **Update Mode** (`--update` flag): Update bugs created in the same conversation context. Reference bugs by ID or use "last" to update the most recently created bug.

Choose the mode that best fits your workflow!

## Invocation

```
# AI-assisted from description
bug-generator --description "User cannot save form data when clicking submit button"

# Detailed with all flags
bug-generator --steps "1. Open form\n2. Fill fields\n3. Click submit" --area "Form Designer" --sub-area "Submit Button" --severity "High" --expected "Form saves" --actual "Error appears"

# Interactive (no arguments)
bug-generator

# Update a previously created bug
bug-generator --update --bug-id "last" --severity "Critical"
```

## Usage Modes

### Mode 1: Description-Based Mode (AI-Assisted)

Use the `--description` flag to provide a natural language description of the bug. The command will:
- Analyze the description using AI
- Infer bug details (area, sub-area, severity, steps, expected/actual behavior)
- Generate a draft bug with inferred information
- Ask clarifying questions for any missing required information
- Create the bug after user review and approval

**Important:** Provide as much context as possible in the description to minimize the number of questions asked. Include:
- What component/area is affected
- What the bug is (what's wrong)
- Steps to reproduce (if known)
- Expected vs actual behavior
- Build number or version
- Environment details (browser, OS)
- Any error messages or symptoms

**Examples:**
```
# Minimal description (will result in more questions)
bug-generator --description "User cannot save form data when clicking submit button"

# Detailed description (will result in fewer questions)
bug-generator --description "In Form Designer, when a user fills out the form and clicks the Submit Button, the form fails to save. Expected: Form data should be saved and user redirected to confirmation page. Actual: Error message 'Failed to save form data' appears, data is lost, and user remains on form page. Found in Build 12345 on Chrome 120, Windows 11."
```

### Mode 2: Detailed Mode (Exact Specification)

Use specific option flags to provide exact bug details. The command will:
- Use the provided information directly (no inference)
- Validate all provided fields
- Prompt only for missing required fields
- Create the bug with minimal interaction

**Example:**
```
bug-generator --steps "1. Navigate to form\n2. Fill in required fields\n3. Click submit" --area "Form Designer" --sub-area "Submit Button" --severity "High" --expected "Form saves successfully" --actual "Error message appears" --build-number "Build 12345"
```

### Mode 3: Update Mode

Use the `--update` flag to update bugs created in the same conversation context.

**Examples:**
```
# Update the last bug created
bug-generator --update --bug-id "last" --severity "Critical"

# Update a specific bug by ID
bug-generator --update --bug-id 12345 --steps "1. Updated step\n2. New step"
```

**Note:** You can mix modes - provide `--description` along with specific flags. The command will use provided flags where available and infer from description for missing fields.

## Objectives

- **Streamline Bug Creation**: Quickly create well-structured bug work items in Azure DevOps
- **Ensure Completeness**: Guide users to provide all necessary bug details
- **Standardize Format**: Create consistent bug reports following project standards
- **Link Related Items**: Automatically link bugs to related tickets, support cases, or regression tests
- **Assign Appropriately**: Assign bugs to the correct team or individual based on area
- **Capture Context**: Include screenshots, environment details, and reproduction steps
- **Enable Updates**: Update bugs created in the same conversation context without creating duplicates

## Prerequisites

### Required
- Azure DevOps MCP server must be configured and accessible
- User must have permissions to create work items in the target project
- Project name or ID must be available (will be prompted if not provided)

### Optional but Recommended
- Screenshots or screen recordings of the bug
- Environment information (browser, OS, version)
- Related work items (tickets, support cases, regression tests)
- Log files or error messages

## Step-by-Step Process

### Step 1: Determine Input Mode

The command determines the input mode based on the arguments provided:

1. **Description Mode**: If `--description` flag is provided
2. **Detailed Mode**: If specific option flags are provided (without `--description`)
3. **Mixed Mode**: If both `--description` and specific flags are provided
4. **Interactive Mode**: If no arguments provided
5. **Update Mode**: If `--update` flag is provided

### Step 2: Collect Bug Information

The command will collect the following information (required fields marked with *):

#### Required Fields

- **Title***: Bug title following format: `{AREA}:{sub area} - brief description`
- **Steps to Reproduce***: Detailed, numbered steps to reproduce the bug
- **Expected Behavior***: What should happen when following the steps
- **Actual Behavior***: What actually happens (the bug)
- **Area Path***: Area where the bug was found
- **Sub-Area***: Sub-area or component within the main area
- **Severity***: Bug severity level (Critical, High, Medium, Low)

#### Optional Fields

- **Description**: Additional context or background information
- **Build Number**: Build number where bug was found
- **Environment**: Browser, OS, version (used in SystemInfo field)
- **Screenshots**: Images or screen recordings demonstrating the bug
- **Error Messages**: Console errors, stack traces, or log entries
- **Work Item Links**: Related tickets, support cases, or regression tests
- **Iteration Path**: Sprint or iteration where bug should be addressed
- **Tags**: Custom tags for categorization
- **Acceptance Criteria**: What needs to be fixed for the bug to be considered resolved
- **Additional Context**: Any other relevant information

### Step 2A: Description Mode Processing

The command will:

1. **Parse Description**: Extract key information using AI analysis
2. **Generate Draft Bug**: Create a draft bug with inferred information
3. **Present Draft for Review**: Show draft with confidence levels for inferred values
4. **Ask Clarifying Questions**: For any required fields that couldn't be inferred
5. **Refine Based on User Input**: Update draft with user corrections

### Step 2B: Detailed Mode Processing

The command will:

1. **Validate Provided Fields**: Check all provided flags
2. **Identify Missing Required Fields**: Determine what's still needed
3. **Prompt for Missing Fields**: Ask only for missing required fields
4. **Use Provided Values Directly**: No inference or AI analysis
5. **Collect Optional Fields**: After required fields are complete

### Step 2C: Interactive Mode Processing

The command will prompt for each required field one at a time in logical order.

### Step 3: Validate and Enrich Information

Before creating the bug, validate and enrich the collected information:

#### Validation Checks

- **Title**: Must follow format `{AREA}:{sub area} - brief description`, 15-255 characters
- **Steps to Reproduce**: Minimum 3 steps, numbered sequentially
- **Expected vs Actual**: Both provided and different from each other
- **Area Path**: Valid area path in project
- **Severity**: Valid severity level (Critical, High, Medium, Low)

#### Information Enrichment

- Add current date/time, user information, project context
- Set default iteration path to current iteration (if not specified)
- Format Repro Steps field in HTML format with sections: Description, Repro Steps, Expected, Actual

### Step 4: Determine Project, Area Path, and Iteration

1. **Identify Project**: Use specified project or prompt user
2. **Get Current Iteration**: Use `mcp_ado_work_list_team_iterations` with `timeframe: "current"`
3. **Validate Area Path**: Verify it exists in project
4. **Set Default Values**: Set defaults for iteration, area, assignment

### Step 5: Generate Bug Preview

Create a formatted preview of the bug that will be created, including all fields.

### Step 6: User Review and Approval

1. Display preview, allow edits
2. Ask for explicit approval before creation
3. Allow further edits or cancellation

### Step 7: Create Bug in Azure DevOps

After user approval:

1. **Prepare Work Item Fields**: Map to ADO fields
2. **Create Work Item**: Use `mcp_ado_wit_create_work_item` with WorkItemType: "Bug"
3. **Link Related Work Items**: If provided
4. **Attach Screenshots**: If provided
5. **Set Work Item State**: Initial state to "New" or "Active"

### Step 8: Post-Creation Actions

Display summary with bug ID, URL, and offer additional actions.

### Step 9: Update Bug (Within Same Conversation)

1. Identify bug to update (by ID or "last")
2. Get current bug state
3. Collect update information
4. Apply updates using `mcp_ado_wit_update_work_item`
5. Confirm update

## Command Options

### Description Mode Options

- `--description` or `-d`: Full bug description (AI will infer other fields)

### Detailed Mode Options

**Required (if not using --description):**
- `--steps` or `-s`: Steps to reproduce (multiline with `\n`)
- `--area` or `-a`: Area path where bug was found
- `--sub-area` or `-sa`: Sub-area or component
- `--severity` or `-sev`: Severity level (Critical, High, Medium, Low)
- `--expected` or `-e`: Expected behavior
- `--actual` or `-act`: Actual behavior

**Optional (for both modes):**
- `--title` or `-t`: Bug title in format `{AREA}:{sub area} - brief description`
- `--project` or `-p`: Azure DevOps project name or ID
- `--build-number` or `-bn`: Build number where bug was found
- `--environment` or `-env`: Environment information (browser, OS, version)
- `--screenshots` or `-img`: Paths to screenshot files or image URLs
- `--ticket` or `-tkt`: Related work item ID or URL
- `--support-case` or `-sc`: Support case ID or URL
- `--regression-test` or `-rt`: Regression test ID or URL
- `--iteration` or `-i`: Iteration path (sprint)
- `--tags` or `-tag`: Comma-separated tags
- `--assign-to` or `-assign`: User to assign bug to
- `--priority` or `-pri`: Priority level (1-4, overrides severity-based priority)
- `--acceptance-criteria` or `-ac`: Acceptance criteria for bug resolution
- `--dry-run` or `-dr`: Preview bug without creating it
- `--update` or `-u`: Update an existing bug
- `--bug-id` or `-id`: Bug ID to update (or "last" for most recent)

## Severity Levels

- **Critical**: System crash, data loss, security vulnerability, complete feature failure
- **High**: Major feature broken, significant functionality impaired, workaround difficult
- **Medium**: Feature partially broken, workaround available, minor functionality impaired
- **Low**: Cosmetic issue, minor inconvenience, enhancement request

## Title Format

Bug titles must follow this format:
```
{AREA}:{sub area} - brief description
```

**Examples:**
- `Form Designer:Submit Button - fails to save form data`
- `Data Entry:Validation - incorrect error message displayed`
- `Reports:Export - CSV download fails for large datasets`

## Repro Steps Format (Microsoft.VSTS.TCM.ReproSteps)

Azure DevOps uses **HTML formatting** for the Repro Steps field:

```html
<p><strong>Description</strong></p>

<p>[Explanation of what is wrong]</p>

<p><strong>Repro Steps</strong></p>

<ol>
<li>[Step 1]</li>
<li>[Step 2]</li>
<li>[Step 3]</li>
</ol>

<p><strong>Expected</strong></p>

<p>[Expected behavior]</p>

<p><strong>Actual</strong></p>

<p>[Actual behavior]</p>
```

**Format Rules:**
- Use `<p>` tags for paragraphs (ensures proper paragraph breaks)
- Use `<strong>` tags for section headers
- Use `<code>` tags for file paths and code references
- Use `<ol>` and `<li>` tags for numbered lists
- Include paragraph breaks between sections

## Field Mapping

### Work Item Fields Used

- `System.Title`: Bug title
- `System.AreaPath`: Area path
- `System.IterationPath`: Iteration/sprint
- `System.AssignedTo`: Assigned user
- `System.State`: Work item state (New, Active, etc.)
- `System.Tags`: Tags for categorization
- `Microsoft.VSTS.Common.Severity`: Severity level
- `Microsoft.VSTS.Common.Priority`: Priority (1-4)
- `Microsoft.VSTS.TCM.ReproSteps`: Formatted Repro Steps (HTML)
- `Microsoft.VSTS.TCM.SystemInfo`: Environment information
- `Microsoft.VSTS.Common.AcceptanceCriteria`: Acceptance criteria

### Link Types Supported

- **Related**: General relationship to another work item
- **Duplicate**: Bug is duplicate of another bug
- **Child**: Bug is child of parent work item
- **Predecessor**: Bug blocks another work item
- **Successor**: Bug is blocked by another work item

## Configuration Options

### Default Values

- **Default Iteration**: Current iteration (if not specified)
- **Default Area Path**: Current iteration's area path (if not specified)
- **Default State**: "New" or "Active" (based on project settings)
- **Default Priority**: Inferred from severity (Critical=1, High=2, Medium=3, Low=4)
- **Default Assigned To**: User creating the bug (current user)

## Best Practices

### For Developers

1. **Be Specific**: Provide clear, detailed steps to reproduce
2. **Include Context**: Mention environment, browser, and include build number
3. **Use Paragraph Breaks**: Structure content with paragraph breaks for readability
4. **Attach Evidence**: Include screenshots, logs, or error messages
5. **Link Related Items**: Connect to related features, tasks, or support cases
6. **Set Appropriate Severity**: Use severity guidelines to classify bugs correctly
7. **Detailed Descriptions**: When using `--description`, provide as much context as possible

### For QA Engineers

1. **Test Reproducibility**: Ensure steps can be followed by others
2. **Document Environment**: Always include environment details
3. **Capture Evidence**: Take screenshots or recordings of bugs
4. **Verify Expected Behavior**: Confirm expected behavior is correct
5. **Check for Duplicates**: Search for existing bugs before creating new ones

### General Guidelines

1. **Clear Titles**: Use descriptive titles following format `{AREA}:{sub area} - brief description`
2. **Complete Information**: Fill in all relevant fields
3. **Proper Formatting**: Use HTML formatting for readability with paragraph breaks
4. **Regular Updates**: Update bug status as work progresses
5. **Link Relationships**: Link related bugs, features, and tasks

## Error Handling

### Common Errors and Solutions

1. **Invalid Project**: List available projects and let user select
2. **Invalid Area Path**: Suggest closest matches or allow creation
3. **Missing Required Fields**: Prompt user for missing field
4. **Invalid Severity**: Show valid options and let user select
5. **Permission Denied**: Inform user and suggest contacting project admin
6. **Work Item Creation Failed**: Display detailed error, allow retry with corrections

## Notes

- All bug creation respects project work item templates and rules
- Bugs are created with proper formatting and structure
- Related work items are linked automatically when provided
- Screenshots and attachments are handled appropriately
- The command supports both interactive and non-interactive modes
- AI inference is used when description is provided to reduce manual input
- All created bugs follow project standards and conventions
- Bug IDs and URLs are provided for easy reference

## Related Skills

- **pr-review**: Review pull requests for potential bugs
- **task-generator**: Create task work items
