# Component Extraction Opportunities Analysis

Detect opportunities to break large components into smaller, more maintainable components:

## Component Size Detection

- Identify components or JSX blocks that exceed recommended size thresholds:
  - Inline JSX blocks >50 lines
  - Component prop values that are complex JSX (e.g., `OverrideComponent={<div>...</div>}`)
  - Nested JSX structures >3 levels deep with significant complexity
  - Conditional rendering blocks with >30 lines of JSX
  - Map/reduce functions returning large JSX blocks (>40 lines)
- Analyze component complexity metrics:
  - Number of props (>10 props suggests extraction opportunity)
  - Number of state variables (>5 useState calls suggests extraction)
  - Number of event handlers (>8 handlers suggests extraction)
  - Cyclomatic complexity of render logic
- Identify file size indicators:
  - Files >500 lines (already flagged in Complexity Analysis)
  - Components with multiple responsibilities (UI rendering + business logic + event handling)

## Extraction Opportunity Patterns

### Large Inline JSX in Props

- Props that accept JSX elements with significant complexity
- Examples to flag:
  - `OverrideComponent={<div>...large JSX block...</div>}`
  - `renderItem={(item) => <div>...large JSX...</div>}`
  - `children={<ComplexComponent>...</ComplexComponent>}`
  - Props like `customRenderer`, `itemRenderer`, `overrideComponent` with inline JSX

### Complex Conditional Rendering

- Large ternary operators or conditional blocks (>30 lines)
- Multiple nested conditionals with JSX
- Switch statements returning large JSX blocks

### Repeated JSX Patterns

- Similar JSX structures repeated multiple times with slight variations
- Map functions returning complex JSX (>40 lines per item)
- List rendering with inline complex components

### Mixed Concerns

- Components handling both layout and business logic
- Components with both data fetching and rendering logic
- Components mixing multiple UI concerns (forms, lists, modals, etc.)

## Component Extraction Guidelines

### When to Extract

- Inline JSX block >50 lines
- Complex prop value that's actually a component (>40 lines)
- Repeated JSX pattern used 3+ times
- Component with >10 props (consider splitting into sub-components)
- Component handling multiple distinct UI concerns
- JSX block with >5 event handlers or complex state management
- Conditional rendering block >30 lines

### Extraction Benefits

- Improved readability and maintainability
- Better testability (smaller components easier to test)
- Reusability across codebase
- Reduced cognitive load
- Better performance (smaller components can be optimized independently)
- Easier debugging and error isolation

### Naming Conventions

- Extracted components should follow project naming conventions (PascalCase)
- Name should reflect component's purpose (e.g., `FlyoutMenuItemWrapper` instead of `OverrideComponent`)
- Place extracted components in appropriate directory structure
- Consider co-location if component is only used in one place

## Common Extraction Patterns

### Extract Large Prop Values

- Pattern: `propName={<div>...large JSX...</div>}`
- Solution: Extract to separate component file
- Example:
  ```tsx
  // Before
  <FlyoutMenuItem
    OverrideComponent={
      <div className="wrapper" onClick={...} onMouseEnter={...}>
        {/* 50+ lines of JSX */}
      </div>
    }
  />
  
  // After
  // FlyoutMenuItemWrapper.tsx
  export const FlyoutMenuItemWrapper = ({ item, index, ... }) => {
    return (
      <div className="wrapper" onClick={...} onMouseEnter={...}>
        {/* extracted JSX */}
      </div>
    );
  };
  
  // Usage
  <FlyoutMenuItem
    OverrideComponent={<FlyoutMenuItemWrapper item={item} index={index} />}
  />
  ```

### Extract Conditional Rendering Blocks

- Pattern: Large ternary or conditional blocks
- Solution: Extract to separate component with conditional logic

### Extract List Item Components

- Pattern: Map function returning complex JSX
- Solution: Extract item component to separate file

### Extract Form Sections

- Pattern: Large form with multiple sections
- Solution: Extract each section to separate component

### Extract Modal/Dialog Content

- Pattern: Large modal content inline in parent component
- Solution: Extract modal content to separate component

## Detection Strategies

### Pattern Matching

- Search for JSX props with large inline values: `propName=\{<[^>]+>.*</[^>]+>\}` (multiline)
- Identify props commonly used for component overrides: `OverrideComponent`, `CustomComponent`, `renderItem`, `itemRenderer`, `children`
- Find large JSX blocks in conditional expressions
- Detect map functions with complex return values

### Code Metrics

- Count lines of JSX in prop values
- Measure nesting depth of JSX structures
- Identify components with high prop counts
- Analyze component responsibilities (single responsibility principle)

### Context Analysis

- Check if extracted component would be reusable
- Determine if extraction improves readability
- Assess if component has clear, single responsibility
- Consider if extraction reduces file complexity

## Severity Classification

- **High**: Large inline JSX (>80 lines) in prop values or conditional rendering that significantly impacts readability
- **Medium**: Inline JSX blocks (50-80 lines) that could be extracted for better maintainability
- **Low**: Smaller JSX blocks (30-50 lines) that could benefit from extraction but are acceptable
- **Info**: Components that are well-structured but could be further optimized

## Reporting Format

- For each extraction opportunity, include:
  - File path and line numbers
  - Code snippet showing the large inline JSX or complex component
  - Suggested component name and file location
  - Proposed component structure (props, responsibilities)
  - Before/after code example showing extraction
  - Benefits of extraction (readability, testability, reusability)
  - Severity level
  - Estimated complexity reduction

## Example Detection Scenarios

### Scenario 1: Large OverrideComponent Prop

- Detects: `OverrideComponent={<div>...50+ lines...</div>}`
- Suggests: Extract to `FlyoutMenuItemWrapper.tsx` or similar
- Provides: Component structure with props interface

### Scenario 2: Complex Map Function

- Detects: `items.map(item => <div>...40+ lines...</div>)`
- Suggests: Extract to `ItemComponent.tsx`
- Provides: Component with item prop and event handlers

### Scenario 3: Large Conditional Block

- Detects: `{condition ? <div>...60+ lines...</div> : <div>...40+ lines...</div>}`
- Suggests: Extract each branch to separate component
- Provides: Conditional component structure

### Scenario 4: Mixed Concerns Component

- Detects: Component handling form, validation, submission, and rendering
- Suggests: Extract form sections, validation logic, or submission handler
- Provides: Separation of concerns guidance
