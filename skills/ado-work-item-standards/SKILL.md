---
name: ado-work-item-standards
description: >
  ADO work item formatting standards and emoji conventions for Stories, Tasks, Bugs, Features,
  and Epics. Use when creating work item descriptions, writing story templates, building Feature
  or Epic work items, formatting ADO markdown, or reviewing work item quality checklists.
---

Repo: speed-merchants (paths below are repo-relative)

# ADO Work Item Standards

Structured rules and emoji conventions for Azure DevOps work items. Ensures clarity, consistency, traceability, and actionable outcomes across all item types.

## When to Use

- "Create a story for X"
- "Write a bug report for Y"
- "Draft an Epic / Feature / Task"
- "What's the format for ADO work items?"
- "Which emoji goes in the acceptance criteria section?"

---

## Emoji Reference

Emojis below render reliably in GitHub-flavored Markdown and Azure DevOps. If ADO doesn't render the shortcode, paste the emoji character directly.

### By Work Item Type

| Section | Story | Task | Bug | Feature | Epic |
|---------|-------|------|-----|---------|------|
| Primary header | 📑 `:bookmark_tabs:` | 🔨⛏️ `:hammer_and_pick:` | 🐛 `:bug:` | ✨ `:sparkles:` | 🌌 `:milky_way:` |
| User Story / Summary | 👥 `:busts_in_silhouette:` | 📄 `:page_facing_up:` | ⚠️ `:warning:` | 👤 `:bust_in_silhouette:` | 👤 `:bust_in_silhouette:` |
| Problem / Opportunity | ⚠️ `:warning:` | — | 🔍 `:mag:` | ⚠️ `:warning:` | ⚠️ `:warning:` |
| Dev / Technical Notes | 🔧 `:hammer_and_wrench:` | 🔧 `:hammer_and_wrench:` | 🔧 `:hammer_and_wrench:` | 🔧 `:hammer_and_wrench:` | 🔧 `:hammer_and_wrench:` |
| Acceptance / Success | ✅ `:white_check_mark:` | ✅ `:white_check_mark:` | ✅ `:white_check_mark:` | ✅ `:white_check_mark:` | ✅ `:white_check_mark:` |
| Expected vs Actual | — | — | 📊 `:bar_chart:` | — | — |
| Best Practices / Scope | 🚩 `:triangular_flag_on_post:` | — | — | — | — |

### Usage Guidelines

- One emoji per section header. No doubling.
- Use plain emoji for inline emphasis sparingly (e.g., 🚀 milestone, 🐞 bug).
- Emoji supports, not distracts from, the content.
- Use checklist `- [ ]` format for all acceptance criteria — never prose or Gherkin.

---

## Story Work Item

Stories represent vertical slices of functionality delivering observable value to end users. Must be completable in a sprint.

### Section Structure

```markdown
## 👥 User Story
As a [user type], I want [feature] so that [benefit].

## ⚠️ User Problem
[Current problem] — it [impacts] — we need to be able to [defined need].

## 🔧 Dev Notes
- [Technical considerations, dependencies, assumptions, risks]

## ✅ Acceptance Criteria
- [ ] [Observable, testable condition 1]
- [ ] [Observable, testable condition 2]
- [ ] [Non-functional consideration: performance, security, accessibility]

## 🚩 Best Practices
- Scoped to a sprint
- Links to a Feature or Epic
```

### Quality Checklist

- [ ] User Story uses *As a… I want… so that…* format
- [ ] Problem and context clearly described
- [ ] Dev Notes include architecture, risks, dependencies
- [ ] Acceptance Criteria complete and observable (checkbox format)
- [ ] Non-functional considerations included
- [ ] Story scoped to a sprint
- [ ] Story links to a Feature or Epic

---

## Task Work Item

Tasks represent implementation steps supporting a Story, Bug, or Feature. One developer effort, ideally < 1 day.

### Section Structure

```markdown
## 📄 Task Summary
[Short technical statement — e.g., "Implement query service for performance metrics"]

## 🔧 Technical Details
[Explicit implementation instructions, dependencies, reusable code references]

## ✅ Acceptance Criteria
- [ ] Code compiles successfully
- [ ] Unit tests implemented and passing
- [ ] Documentation/comments updated
- [ ] PR linked
```

### Quality Checklist

- [ ] Task has a clear parent item (Story, Bug, or Feature)
- [ ] Scope is narrow and achievable in < 1 day
- [ ] Acceptance Criteria are observable
- [ ] Linked PR/code reference provided

---

## Bug Work Item

Bugs represent defects in code, configuration, or environment.

### Section Structure

```markdown
## ⚠️ Problem Statement
[Clear description of the defect]

## 🔍 Reproduction Steps
1. [Step to reproduce]
2. [Step to reproduce]

## 📊 Expected vs Actual
**Expected:** [What should happen]
**Actual:** [What actually happens]

## 🔧 Technical Notes
[Suspected cause, logs, environment context, screenshots]

## ✅ Acceptance Criteria
- [ ] Bug no longer reproducible with repro steps
- [ ] Fix validated across affected environments
- [ ] Regression test added
```

### Quality Checklist

- [ ] Repro steps included
- [ ] Expected vs Actual documented
- [ ] Linked Story/Feature/Epic context identified
- [ ] Fix validated by test case

---

## Feature Work Item

Features bundle multiple Stories to achieve a larger outcome. Decomposed into Stories; must link up to an Epic.

### Section Structure

```markdown
## 👤 Business Value
[Benefit at organizational/user level]

## ⚠️ Problem Statement
[Strategic or operational gap being solved]

## 🔧 Technical Notes
[Architectural implications, cross-team dependencies]

## ✅ Success Criteria
- [ ] [Measurable business outcome 1]
- [ ] [Measurable business outcome 2]
```

### Quality Checklist

- [ ] Clear business value stated
- [ ] Broken into Stories
- [ ] Dependencies identified
- [ ] Business outcomes measurable

---

## Epic Work Item

Epics represent high-level initiatives spanning multiple Features. Provide long-term vision alignment.

### Section Structure

```markdown
## 👤 Vision Statement
[Strategic objective — tied to business OKRs]

## ⚠️ Problem/Opportunity
[Market, customer, or technical driver]

## 🔧 Approach/Architecture
[Strategic approach, domains impacted, resourcing]

## ✅ Success Metrics
- [ ] [Business-level metric 1 — time-to-market, cost reduction, adoption]
- [ ] [Business-level metric 2]
```

### Quality Checklist

- [ ] Clear vision statement
- [ ] Problem/opportunity justified
- [ ] Features identified
- [ ] Success metrics are business-level and measurable

---

## Final Notes

- **Traceability:** Every work item must link up/down the hierarchy: Task → Story → Feature → Epic.
- **Documentation:** Update `Plan.md`, `BuildNotes.md`, `TestDocument.md` when items complete.
- **Quality Reviews:** No item moves to Done without passing its quality checklist.
- **Output format:** Produce work items as markdown files; name files descriptively (e.g., `PasswordResetStory.md`).

---

## ADO MCP Tools

The Azure DevOps MCP server (`user-azure-devops`) provides read/write access to ADO. Use these tools when querying or updating ADO from within an AI session.

### Repository & Code

| Tool | Description |
|------|-------------|
| `azure_devops_projects` | List available projects |
| `azure_devops_repositories` | List repositories in a project |
| `azure_devops_branch_file_content` | Read file content from a branch |

### Pull Requests

| Tool | Description |
|------|-------------|
| `azure_devops_pull_requests` | List pull requests |
| `azure_devops_pull_request_by_id` | Get specific PR details |
| `azure_devops_pull_request_changes` | View files changed in a PR |
| `azure_devops_pull_request_file_content` | Read file content from a PR |
| `azure_devops_pull_request_threads` | View PR comments/discussions |
| `azure_devops_create_pr_comment` | Add a comment to a PR |

### Work Items

| Tool | Description |
|------|-------------|
| `azure_devops_work_items` | Query work items |
| `azure_devops_work_item` | Get specific work item details |
| `azure_devops_work_item_comments` | View work item comments |
| `azure_devops_work_item_links` | View linked items |
| `azure_devops_work_item_attachments` | View attachments |
| `azure_devops_linked_work_items` | Get work items linked to a PR |

### Test Management

| Tool | Description |
|------|-------------|
| `azure_devops_test_plans` | List test plans |
| `azure_devops_test_plan` | Get specific test plan |
| `azure_devops_test_suites` | List test suites |
| `azure_devops_test_suite` | Get specific test suite |
| `azure_devops_test_cases` | List test cases |

### Common Workflows

**Review a Pull Request:**
1. `azure_devops_pull_request_by_id` — get PR details
2. `azure_devops_pull_request_changes` — see changed files
3. `azure_devops_pull_request_file_content` — review specific files
4. `azure_devops_linked_work_items` — understand the work item context
5. `azure_devops_create_pr_comment` — leave feedback

**Investigate a Work Item:**
1. `azure_devops_work_item` — get details
2. `azure_devops_work_item_links` — see related items
3. `azure_devops_work_item_comments` — read discussion history

### Best Practices

- Verify project access before querying.
- Use work item links to maintain traceability.
- Reference work item IDs in commit messages and PR descriptions.
- Keep PR comments constructive and actionable.

## Sources

- `AGENTS.md` (work item rules and emoji conventions — source files deleted 2026-05-16)
