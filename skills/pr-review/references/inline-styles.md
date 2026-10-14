# Inline Style Usage Analysis

Detect overuse of inline `style` attributes and recommend using CSS classes and specific selectors instead:

## Inline Style Detection

- Identify all inline `style` attribute usage in JSX:
  - Static style objects: `style={{ color: 'red', padding: '10px' }}`
  - Dynamic style objects: `style={{ color: isActive ? 'blue' : 'red' }}`
  - Style objects from variables: `style={customStyle}`
  - Conditional style objects: `style={condition ? style1 : style2}`
  - Template literal styles: `` style={`color: ${color}`} `` (less common, but should be flagged)
- Count inline style occurrences per component:
  - Components with >5 inline style attributes
  - Files with >10 inline style usages
  - Repeated style patterns across multiple elements
- Analyze style complexity:
  - Style objects with >5 properties
  - Complex style calculations inline
  - Repeated style patterns that could be CSS classes

## Inline Style Usage Issues

### Overuse of Static Styles

- Static style objects that should be CSS classes
- Examples to flag:
  - `style={{ display: 'flex', alignItems: 'center', gap: '5px' }}`
  - `style={{ padding: '5px 25px', height: '30px', cursor: 'pointer' }}`
  - `style={{ fontSize: '12px', color: 'rgba(var(--contentPrimaryFi900), 1)' }}`
  - Repeated style patterns across multiple elements

### Complex Inline Styles

- Style objects with many properties (>5 properties)
- Nested style calculations
- Style objects that mix static and dynamic values unnecessarily

### Repeated Style Patterns

- Same style object used in multiple places
- Similar style patterns with slight variations
- Styles that could be shared via CSS classes

### Performance Concerns

- Inline styles prevent CSS optimization and caching
- Inline styles increase bundle size
- Inline styles prevent browser CSS optimizations
- Inline styles make it harder to override styles via CSS

## When Inline Styles Are Acceptable

### Dynamic Styles Based on Props/State

- Styles that change based on component props or state
- Examples of acceptable inline styles:
  - `style={{ width: `${percentage}%` }}` (dynamic width)
  - `style={{ backgroundColor: isActive ? 'blue' : 'transparent' }}` (dynamic color)
  - `style={{ transform: `translateX(${offset}px)` }}` (dynamic transform)
  - `style={{ opacity: isVisible ? 1 : 0 }}` (dynamic visibility)

### One-off Styles

- Truly unique styles used only once
- Styles that are component-specific and not reusable
- Styles that are part of a component's core functionality

### Third-party Component Overrides

- Styles needed to override third-party component styles
- Styles for positioning or layout that are component-specific

## Recommended Approach

### Use CSS Modules (Project Standard)

- Import CSS Module: `import css from "./Component.module.scss"`
- Use class names: `className={css.container}`
- Define styles in `.module.scss` file
- Use CSS variables for theming: `color: rgba(var(--contentPrimaryFi900), 1)`

### Use CSS Classes for Static Styles

- Move static style objects to CSS classes
- Use semantic class names that describe purpose, not appearance
- Leverage CSS specificity and selectors for styling
- Use CSS custom properties (CSS variables) for dynamic values

### Hybrid Approach for Dynamic Styles

- Use CSS classes for base styles
- Use inline styles only for truly dynamic values
- Combine: `className={css.base} style={{ width: `${percentage}%` }}`

### Benefits of CSS Classes

- Better performance (CSS is cached and optimized by browser)
- Easier maintenance (styles in one place)
- Better override capabilities (CSS specificity)
- Smaller bundle size (CSS can be minified and tree-shaken)
- Better developer experience (CSS syntax highlighting, autocomplete)
- Easier theming and customization
- Better separation of concerns

## Common Inline Style Anti-patterns

### Static Layout Styles

- Pattern: `style={{ display: 'flex', alignItems: 'center', gap: '10px' }}`
- Solution: Move to CSS class: `.container { display: flex; align-items: center; gap: 10px; }`

### Repeated Color/Sizing Styles

- Pattern: `style={{ color: 'rgba(var(--contentPrimaryFi900), 1)', fontSize: '12px' }}` used multiple times
- Solution: Create CSS class or use CSS variables

### Complex Style Objects

- Pattern: `style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '20px', height: '20px' }}`
- Solution: Extract to CSS class with semantic name like `.iconContainer`

### Mixed Static and Dynamic

- Pattern: `style={{ padding: '5px', backgroundColor: isActive ? 'blue' : 'transparent' }}`
- Solution: Use CSS class for padding, inline style only for dynamic backgroundColor

### Style Objects in Variables

- Pattern: `const wrapperStyle = { display: 'flex', ... }; <div style={wrapperStyle} />`
- Solution: Move to CSS class unless styles are truly dynamic

## Detection Strategies

### Pattern Matching

- Search for `style=\{\{` patterns in JSX
- Identify style objects with multiple properties (>3 properties)
- Find repeated style patterns across elements
- Detect style objects that are mostly static

### Code Metrics

- Count inline style occurrences per file
- Measure style object complexity (number of properties)
- Identify repeated style patterns
- Calculate ratio of inline styles to CSS classes

### Context Analysis

- Check if styles are static or dynamic
- Determine if styles are repeated across elements
- Assess if styles could be CSS classes
- Consider if styles are component-specific or reusable

## Severity Classification

- **High**: 
  - Components with >10 inline style attributes
  - Repeated static style patterns (>3 occurrences)
  - Complex style objects (>8 properties) that should be CSS classes
  - Files with >15 inline style usages
- **Medium**: 
  - Components with 5-10 inline style attributes
  - Static style objects with 5-8 properties
  - Repeated style patterns (2-3 occurrences)
  - Files with 10-15 inline style usages
- **Low**: 
  - Components with 3-5 inline style attributes
  - Static style objects with 3-5 properties
  - Occasional use of inline styles for static values
- **Info**: 
  - Acceptable use of inline styles for dynamic values
  - One-off styles that are component-specific

## Reporting Format

- For each inline style usage issue, include:
  - File path and line numbers
  - Code snippet showing inline style usage
  - Suggested CSS class name and location
  - Proposed CSS class definition
  - Before/after code example showing migration to CSS class
  - Benefits of using CSS class (performance, maintainability, etc.)
  - Severity level
  - Note if style is dynamic (acceptable) or static (should be CSS class)

## Example Detection Scenarios

### Scenario 1: Repeated Static Styles

- Detects: `style={{ display: 'flex', alignItems: 'center', gap: '5px' }}` used 5+ times
- Suggests: Create `.flex-center` CSS class
- Provides: CSS class definition and usage example

### Scenario 2: Complex Style Object

- Detects: `style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '20px', height: '20px', padding: '5px' }}`
- Suggests: Extract to `.iconContainer` CSS class
- Provides: CSS class definition and component update

### Scenario 3: Mixed Static and Dynamic

- Detects: `style={{ padding: '5px 25px', backgroundColor: isActive ? 'blue' : 'transparent' }}`
- Suggests: Use CSS class for padding, inline style only for backgroundColor
- Provides: Hybrid approach example

### Scenario 4: Style Object Variable

- Detects: `const wrapperStyle = { display: 'flex', ... }; <div style={wrapperStyle} />`
- Suggests: Move to CSS class unless truly dynamic
- Provides: CSS class migration example

## Migration Guidance

### Step 1: Identify Static vs Dynamic

- Separate static styles from dynamic styles
- Static styles → CSS classes
- Dynamic styles → Keep inline or use CSS variables

### Step 2: Create CSS Module

- Create `.module.scss` file if it doesn't exist
- Define CSS classes with semantic names
- Use CSS variables for theming values

### Step 3: Update Component

- Import CSS Module: `import css from "./Component.module.scss"`
- Replace inline styles with CSS classes
- Keep only truly dynamic styles inline
- Combine CSS classes with dynamic inline styles when needed

### Step 4: Refactor Repeated Patterns

- Extract common style patterns to shared CSS classes
- Use CSS specificity for component-specific overrides
- Leverage CSS selectors for conditional styling when possible
