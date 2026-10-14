---
name: task-generator
description: >
  Azure DevOps task work item generator from User Stories. Use when breaking
  down stories into tasks, creating ADO tasks, or generating task breakdowns
  from acceptance criteria.
---

# Task Generator

This skill generates tasks in Azure DevOps (ADO) based on User Stories. It retrieves a story from Azure DevOps, analyzes its requirements and acceptance criteria, and works with the user to create well-structured task work items linked to the story.

## Quick Summary

The task generator operates in **two distinct modes**:

1. **Story-Based Mode** (`--story-id` flag): Provide a User Story ID, and the command will retrieve the story, analyze its requirements, and generate tasks based on acceptance criteria and implementation details.

2. **Manual Mode** (`--manual` flag): Manually specify task details without referencing a story.

Choose the mode that best fits your workflow!

## Invocation

```
# Generate tasks from a story
task-generator --story-id 149267

# Generate tasks with custom area/iteration
task-generator --story-id 149267 --area "Products\\Development" --iteration "Products\\Development\\26R1\\26R1 S3"

# Create a standalone task manually
task-generator --manual --title "Implement hierarchy context menu" --description "Add right-click menu option for hierarchy control" --area "Products\\Development"
```

## Usage Modes

### Mode 1: Story-Based Mode (AI-Assisted)

Use the `--story-id` flag to provide a User Story ID. The command will:
- Retrieve the story from Azure DevOps
- Parse the story description, acceptance criteria, and implementation details
- Analyze requirements using AI to identify logical task breakdowns
- Generate draft tasks with inferred information
- Present tasks for user review and approval
- Create tasks linked to the story as child work items

**When to Use:**
- When starting work on a User Story
- When you want AI assistance to break down story requirements into tasks
- For consistent task creation following story acceptance criteria
- When you need tasks automatically linked to the parent story

### Mode 2: Manual Mode (Exact Specification)

Use the `--manual` flag with specific task details. The command will:
- Use the provided information directly (no story retrieval)
- Validate all provided fields
- Prompt only for missing required fields
- Create tasks with minimal interaction

**When to Use:**
- When creating standalone tasks not linked to a story
- When you have all task details ready
- For precise control over task content

## Objectives

- **Streamline Task Creation**: Quickly create well-structured task work items in Azure DevOps
- **Ensure Completeness**: Guide users to provide all necessary task details
- **Standardize Format**: Create consistent tasks following project standards
- **Link to Stories**: Automatically link tasks to parent User Stories
- **Break Down Stories**: Intelligently decompose story requirements into actionable tasks
- **Assign Appropriately**: Assign tasks to the correct team or individual
- **Capture Context**: Include acceptance criteria, implementation details, and related information

## Prerequisites

### Required
- Azure DevOps MCP server must be configured and accessible
- User must have permissions to create work items in the target project
- User Story ID must be available (for Story-Based Mode)
- Project name or ID must be available (will be prompted if not provided)

### Optional but Recommended
- Story acceptance criteria document (if referenced in story)
- Related work items or dependencies
- Implementation notes or technical specifications

## Step-by-Step Process

### Step 1: Determine Input Mode

The command determines the input mode based on the arguments provided:

1. **Story-Based Mode**: If `--story-id` flag is provided
   - Command retrieves story from Azure DevOps
   - Parses story description, acceptance criteria, and implementation details
   - Uses AI to analyze requirements and generate task breakdown
   - Presents draft tasks for user review
   - Creates tasks after user approval

2. **Manual Mode**: If `--manual` flag is provided
   - Command uses provided task details directly
   - Validates all provided fields
   - Prompts only for missing required fields
   - Creates task with provided information

### Step 2: Retrieve and Parse Story (Story-Based Mode)

When `--story-id` is provided:

1. **Retrieve Story**:
   - Use `mcp_ado_wit_get_work_item` to fetch the story
   - Extract story fields: Title, Description, Acceptance Criteria, Area Path, Iteration Path
   - Display story summary to user

2. **Parse Story Content**:
   - Extract English Description
   - Extract User Problem
   - Extract User Story narrative
   - Extract Acceptance Criteria (from description field or separate field)
   - Extract Implementation Details
   - Identify Figma design links
   - Extract any referenced work items

3. **Analyze Requirements**:
   - Use AI to identify logical task breakdowns
   - Group related acceptance criteria into tasks
   - Identify technical implementation areas
   - Determine task dependencies
   - Estimate task complexity

### Step 3: Generate Task Breakdown

The command will analyze the story and generate tasks:

1. **Identify Task Categories**:
   - UI/UX Implementation tasks (based on Figma designs)
   - Backend/API tasks (based on acceptance criteria)
   - Integration tasks (API integration, data flow)
   - Testing tasks (unit tests, integration tests)
   - Documentation tasks (if needed)

2. **Generate Draft Tasks**:
   - Create task titles based on acceptance criteria
   - Generate task descriptions from story requirements
   - Assign tasks to appropriate areas/components
   - Set task priorities based on dependencies
   - Link tasks to story as children

3. **Task Structure**:
   - Each task should be independently actionable
   - Tasks should align with acceptance criteria
   - Tasks should follow a logical implementation order
   - Tasks should be appropriately sized (not too large or too small)

### Step 4: Present Tasks for Review

Display all generated tasks to the user:

```
# Task Breakdown for Story 149267

## Story: AITW: Forms: Hierarchy Context Menu, Properties Panel, and Actions

### Generated Tasks:

1. **Task: Implement Hierarchy Context Menu**
   - Description: Add right-click and hover menu options for adding hierarchy controls under Tab Layout and Column nodes
   - Acceptance Criteria: Hierarchy can be added only under Tab Layout or Column nodes via right-click or hover
   - Area: Products\Development
   - Priority: High

2. **Task: Create Hierarchy Properties Panel**
   - Description: Implement Properties Panel with Context, Display, and Layout sections for hierarchy configuration
   - Acceptance Criteria: Properties Panel displays Context, Display, and Layout sections; changes apply instantly to tree and preview
   - Area: Products\Development
   - Priority: High

[... more tasks ...]

---

Review these tasks? (yes/no/edit)
```

### Step 5: User Review and Approval

1. **Display Tasks**: Show all generated tasks with:
   - Task titles and descriptions
   - Related acceptance criteria
   - Suggested area paths and priorities
   - Task dependencies (if any)

2. **Allow Edits**: User can:
   - Edit task titles and descriptions
   - Add or remove tasks
   - Reorder tasks
   - Change area paths or priorities
   - Add additional details or notes
   - Split large tasks into smaller ones
   - Merge related tasks

3. **Confirm Creation**: 
   - Present final task list
   - Ask for explicit approval: "Ready to create these tasks in Azure DevOps?"
   - If approved, proceed to creation
   - If not approved, allow further edits or cancellation

### Step 6: Create Tasks in Azure DevOps

After user approval:

1. **Prepare Task Fields**:
   - Get current user information for assignment
   - Map task information to ADO work item fields:
     - `System.Title`: Task title
     - `System.Description`: Task description with HTML formatting
     - `System.AreaPath`: Area path (from story or user-specified)
     - `System.IterationPath`: Iteration path (from story or user-specified)
     - `System.AssignedTo`: Assigned user (defaults to user creating tasks, can be overridden)
     - `Microsoft.VSTS.Common.Priority`: Priority level (1-4)
     - `Microsoft.VSTS.Common.Activity`: Activity type (Development, Testing, etc.)
     - `System.Tags`: Tags for categorization

2. **Create Tasks**:
   - For each task:
     - Use `mcp_ado_wit_create_work_item` with:
       - Project: Identified project
       - WorkItemType: "Task"
       - Fields: All mapped fields

3. **Link Tasks to Story**:
   - For each created task:
     - Use `mcp_ado_wit_work_items_link` to create parent-child link
     - Set link type: "Child" (task is child of story)
     - Add link comment describing relationship

4. **Handle Creation Result**:
   - If successful:
     - Display created task IDs and URLs
     - Show links to view tasks in Azure DevOps
     - Confirm all tasks were created and linked correctly
   - If failed:
     - Display error message
     - Identify which task caused the issue
     - Allow user to correct and retry

### Step 7: Post-Creation Actions

After tasks are created:

1. **Display Summary**:
   - Story ID and title
   - Number of tasks created
   - List of all task IDs and titles
   - Direct links to view tasks in Azure DevOps
   - Confirmation that tasks are linked to story

2. **Offer Additional Actions**:
   - "Would you like to assign tasks to specific team members?"
   - "Would you like to add tasks to a specific sprint?"
   - "Would you like to create subtasks for any of these tasks?"
   - "Would you like to update any task details?"

## Command Options

### Story-Based Mode Options

- `--story-id` or `-s`: **Primary flag for Story-Based Mode** - User Story ID (e.g., 149267)

**Optional Options (for Story-Based Mode):**
- `--project` or `-p`: Azure DevOps project name or ID (if not provided, will be inferred from story)
- `--area` or `-a`: Override area path (defaults to story's area path)
- `--iteration` or `-i`: Override iteration path (defaults to story's iteration path)
- `--assign-to` or `-assign`: User to assign all tasks to (can be overridden per task)
- `--dry-run` or `-dr`: Preview tasks without creating them
- `--max-tasks` or `-mt`: Maximum number of tasks to generate (default: no limit)

### Manual Mode Options

**Required Options (if using --manual):**
- `--title` or `-t`: Task title
- `--description` or `-d`: Task description

**Optional Options (for Manual Mode):**
- `--project` or `-p`: Azure DevOps project name or ID
- `--area` or `-a`: Area path where task belongs
- `--iteration` or `-i`: Iteration path (sprint)
- `--priority` or `-pri`: Priority level (1-4)
- `--assign-to` or `-assign`: User to assign task to
- `--parent-story` or `-ps`: Parent User Story ID to link task to
- `--tags` or `-tag`: Comma-separated tags
- `--activity` or `-act`: Activity type (Development, Testing, Documentation, etc.)

## Usage Examples

### Story-Based Mode Examples

```
# Generate tasks from a story (uses story's area and iteration)
task-generator --story-id 149267

# Generate tasks with custom area and iteration
task-generator --story-id 149267 --area "Products\\Development" --iteration "Products\\Development\\26R1\\26R1 S3"

# Preview tasks without creating (dry run)
task-generator --story-id 149267 --dry-run

# Generate tasks and assign all to specific user
task-generator --story-id 149267 --assign-to "john.doe@company.com"

# Limit number of tasks generated
task-generator --story-id 149267 --max-tasks 5
```

### Manual Mode Examples

```
# Create a standalone task
task-generator --manual --title "Implement hierarchy context menu" --description "Add right-click menu option for hierarchy control" --area "Products\\Development"

# Create a task linked to a story
task-generator --manual --title "Implement hierarchy context menu" --description "Add right-click menu option" --parent-story 149267 --area "Products\\Development"

# Create a task with full details
task-generator --manual --title "Create Hierarchy Properties Panel" --description "Implement Properties Panel with Context, Display, and Layout sections" --area "Products\\Development" --priority 2 --activity "Development" --tags "forms,hierarchy,ui"
```

## Task Generation Guidelines

### Task Breakdown Strategy

When analyzing a story, tasks should be created based on:

1. **Acceptance Criteria**: Each major acceptance criterion may become one or more tasks
2. **Technical Components**: Separate tasks for different technical areas (UI, API, integration)
3. **Dependencies**: Tasks that must be completed before others
4. **Testing**: Separate tasks for unit tests, integration tests, and manual testing
5. **Documentation**: Tasks for documentation if required

### Task Naming Convention

Tasks should follow this format:
```
[Component/Area]: [Action] - [Brief Description]
```

**Examples:**
- `Forms: Hierarchy - Implement context menu for adding hierarchy controls`
- `Forms: Hierarchy - Create Properties Panel with Context section`
- `Forms: Hierarchy - Integrate hierarchy API dropdown`
- `Forms: Hierarchy - Add unit tests for hierarchy component`

### Task Description Format

Task descriptions should include:

```html
<p><strong>Purpose</strong></p>

<p>[Brief description of what this task accomplishes]</p>

<p><strong>Acceptance Criteria</strong></p>

<ul>
<li>[Related acceptance criterion from story]</li>
<li>[Additional acceptance criterion if applicable]</li>
</ul>

<p><strong>Implementation Notes</strong></p>

<p>[Any specific technical details or considerations]</p>

<p><strong>Related Story</strong></p>

<p>User Story <a href="[story-url]">#[story-id]</a>: [Story Title]</p>
```

### Task Dependencies

Tasks should be ordered logically:
- Foundation tasks first (API integration, data models)
- UI tasks next (components, panels)
- Integration tasks (connecting UI to backend)
- Testing tasks (unit tests, integration tests)
- Documentation tasks (if needed)

## Field Mapping and Validation

### Task Fields Used

- `System.Title`: Task title
- `System.Description`: Task description with HTML formatting
- `System.AreaPath`: Area path (from story or user-specified)
- `System.IterationPath`: Iteration path (from story or user-specified)
- `System.AssignedTo`: Assigned user
- `System.State`: Work item state (New, Active, etc.)
- `System.Tags`: Tags for categorization
- `Microsoft.VSTS.Common.Priority`: Priority (1-4)
- `Microsoft.VSTS.Common.Activity`: Activity type (Development, Testing, Documentation, etc.)
- `Microsoft.VSTS.Scheduling.RemainingWork`: Estimated work (hours)
- `Microsoft.VSTS.Scheduling.OriginalEstimate`: Original estimate (hours)

### Link Types Supported

- **Child**: Task is child of parent User Story (primary link type)
- **Related**: General relationship to another work item
- **Predecessor**: Task is blocked by another task
- **Successor**: Task blocks another task

## Configuration Options

### Default Values

- **Default Area Path**: Story's area path (if story-based mode)
- **Default Iteration Path**: Story's iteration path (if story-based mode)
- **Default State**: "New" or "Active" (based on project settings)
- **Default Priority**: 2 (Medium)
- **Default Assigned To**: User creating the tasks (current user)
- **Default Activity**: "Development"

### Customization

Users can:
- Override default area path (defaults to story's area path)
- Override default iteration path (defaults to story's iteration path)
- Set default priority for all tasks
- Configure activity type mapping
- Set default tags based on story area

## Best Practices

### For Story-Based Task Generation

1. **Review Generated Tasks**: Always review AI-generated tasks before creating them
2. **Break Down Large Tasks**: If a task seems too large, split it into smaller, more manageable tasks
3. **Check Dependencies**: Ensure tasks are ordered logically with dependencies identified
4. **Align with Acceptance Criteria**: Each task should relate to one or more acceptance criteria
5. **Consider Testing**: Include testing tasks for each major feature
6. **Update Story State**: Consider updating story state to "Active" or "Committed" after creating tasks

### For Manual Task Creation

1. **Clear Titles**: Use descriptive titles following format `[Component]: [Action] - [Description]`
2. **Complete Descriptions**: Include purpose, acceptance criteria, and implementation notes
3. **Link to Story**: Always link tasks to parent story when applicable
4. **Set Appropriate Priority**: Use priority to indicate task importance
5. **Tag Appropriately**: Use tags for categorization and filtering

### General Guidelines

1. **Task Size**: Tasks should be sized appropriately (typically 1-3 days of work)
2. **Independence**: Tasks should be independently actionable
3. **Testability**: Each task should have clear completion criteria
4. **Documentation**: Include implementation notes in task descriptions
5. **Regular Updates**: Update task status as work progresses

## Error Handling

### Common Errors and Solutions

1. **Story Not Found**: Verify story ID is correct and user has access to the project
2. **Invalid Story Type**: Ensure the provided ID corresponds to a User Story work item
3. **Missing Required Fields**: Command will prompt user for missing fields
4. **Permission Denied**: Inform user and suggest contacting project admin
5. **Task Creation Failed**: Display detailed error, allow retry with corrections

## Notes

- All task creation respects project work item templates and rules
- Tasks are created with proper formatting and structure
- Tasks are automatically linked to parent stories as children
- The command supports both interactive and non-interactive modes
- AI inference is used to break down stories into logical tasks
- All created tasks follow project standards and conventions
- Task IDs and URLs are provided for easy reference

## Related Skills

- **bug-generator**: Create bug work items
- **pr-review**: Review pull requests
