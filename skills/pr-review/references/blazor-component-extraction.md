# Blazor Component Extraction Opportunities Analysis

Detect opportunities to break large Blazor components into smaller, more maintainable components:

## Component Size Detection

- Identify Razor components that exceed recommended size thresholds:
  - `*.razor` markup >150 lines
  - `*.razor.cs` code-behind >300 lines
  - Inline `@code` blocks >80 lines (prefer `.razor.cs` partial)
  - Component with >10 `@* parameters`
  - Nested markup >5 levels deep with significant complexity
  - Conditional `@if`/`@switch` blocks with >40 lines
- Analyze component complexity:
  - Number of injected services (>4 suggests extraction)
  - Number of `[Parameter]` properties (>8 suggests extraction)
  - Number of private methods (>10 suggests splitting)
  - Cyclomatic complexity of render logic

## Extraction Opportunity Patterns

### Large Inline Markup

- `RenderFragment` parameters with significant inline markup
- `ChildContent` with complex nested structures
- Repeated markup patterns that could be components

### Mixed Concerns

- Page handling both layout and data access (should use services)
- Component mixing multiple UI concerns (forms, grids, dialogs)
- Business logic in code-behind that belongs in services

### Repeated Razor Patterns

- Similar markup repeated 3+ times with slight variations
- `@foreach` blocks with complex inline components
- Repeated `@if`/`@else` structures

### Code-Behind Extraction

- Logic that could move to shared service or helper
- Duplicated filter/query logic (use `FilterBuilder`, `QueryParameterBuilder`)
- Record mapping logic (use `RecordMapper`, `RecordCloner`)

## Component Extraction Guidelines

### When to Extract

- Razor markup >150 lines
- Code-behind >300 lines
- Repeated markup pattern 3+ times
- Component with >8 parameters
- Logic that fits existing service pattern (e.g. new `*Service` method)

### When to Use Partials

- Non-trivial component: use `.razor` + `.razor.cs`
- Complex logic: prefer code-behind over `@code` blocks
- Follow project pattern: `Workflows.razor` + `Workflows.razor.cs`
