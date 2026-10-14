# Font Awesome Usage Analysis

Detect and analyze Font Awesome CSS class usage to ensure consistent use of React components:

## Font Awesome Detection

- Identify all Font Awesome CSS class usage in code:
  - Font Awesome 4 classes: `fa`, `fa-*` (e.g., `fa fa-user`, `fa fa-check`)
  - Font Awesome 5+ classes: `fas`, `far`, `fal`, `fab`, `fad`, `fa-*` (e.g., `fas fa-user`, `far fa-check-circle`)
  - Pattern matching: `className.*["']fa[srldb]?\s+fa-` or `className.*["']fa\s+fa-`
  - CSS-in-JS usage: `className={...}` with Font Awesome classes
  - Template literals containing Font Awesome classes
- Extract Font Awesome class names and their usage contexts
- Identify where Font Awesome classes are used (JSX, CSS files, style objects, etc.)
- Note icon names and style variants (solid, regular, light, brands, duotone)

## Font Awesome Usage Issues

### CSS Class Usage in React Components

- Font Awesome CSS classes used directly in JSX `className` attributes
- Font Awesome classes in CSS Modules or style objects
- Font Awesome classes concatenated with other classes
- Examples to flag:
  - `<i className="fa fa-user" />`
  - `<span className="fas fa-check-circle" />`
  - `<div className={`icon ${isActive ? 'fa fa-check' : 'fa fa-times'}`} />`
  - `className="far fa-star"`

### Inconsistent Patterns

- Mixing Font Awesome CSS classes with `<FontAwesome />` components in the same file
- Font Awesome classes used in new code while project standardizes on `<FontAwesome />` components
- Font Awesome classes in React components that should use the component pattern

## Recommended Replacement Pattern

### Use `<FontAwesome />` React Component

- Replace Font Awesome CSS classes with `<FontAwesome />` component
- Import pattern: `import { FontAwesome } from '@profisee/react-library'` or appropriate import path
- Component usage: `<FontAwesome icon="user" />` or `<FontAwesome icon={faUser} />`
- Style variants handled via props: `style="solid"`, `style="regular"`, `style="light"`, `style="brands"`
- Size and other props handled via component props instead of CSS classes

### Benefits of Using Component

- Type safety (TypeScript support for icon names)
- Better tree-shaking (only imported icons included in bundle)
- Consistent API across the codebase
- Easier refactoring and maintenance
- Better IDE support and autocomplete
- No CSS class conflicts or specificity issues

## Common Font Awesome Anti-patterns

- Using `<i>` or `<span>` elements with Font Awesome classes instead of `<FontAwesome />` component
- Font Awesome classes in CSS files for React components (should use component props)
- Dynamic Font Awesome class construction (should use component props)
- Font Awesome classes in conditional rendering (should use component with conditional props)
- Font Awesome classes concatenated with utility classes (should separate concerns)

## Detection Patterns

- Search for Font Awesome class patterns:
  - `className.*["']fa[srldb]?\s+fa-` (matches `fa fa-*`, `fas fa-*`, `far fa-*`, etc.)
  - `className.*["']fa-` (matches any Font Awesome class)
  - Template literals: `` className={`fa fa-${iconName}`} ``
  - CSS files: `.fa-*` class definitions (if reviewing CSS files)
- Exclude from flagging:
  - Font Awesome classes in CSS files that are part of Font Awesome library itself
  - Font Awesome classes in legacy code that's not being modified
  - Font Awesome classes in test files (if acceptable for test setup)
  - Comments or documentation mentioning Font Awesome classes

## Recommendations

### For New Code

- Always use `<FontAwesome />` component instead of CSS classes
- Import icons explicitly: `import { faUser, faCheck } from '@fortawesome/free-solid-svg-icons'`
- Use component props for styling: `<FontAwesome icon={faUser} size="lg" />`
- Avoid CSS classes for Font Awesome icons in React components

### For Existing Code

- When modifying files with Font Awesome CSS classes, consider refactoring to use `<FontAwesome />` component
- If refactoring is not part of the current change, note it as a future improvement
- Ensure consistency within the file (don't mix CSS classes and components)

### Migration Path

- Identify all Font Awesome CSS class usage in changed files
- Map CSS classes to equivalent `<FontAwesome />` component usage
- Provide code examples showing before/after patterns
- Suggest importing required icons from appropriate Font Awesome packages

## Severity Classification

- **Medium**: Font Awesome CSS classes used in new React components (should use `<FontAwesome />` component)
- **Low**: Font Awesome CSS classes in existing code that's being modified (consider refactoring)
- **Info**: Font Awesome CSS classes in legacy code not being modified (documentation only)

## Reporting Format

- For each Font Awesome CSS class usage, include:
  - File path and line numbers
  - Code snippet showing Font Awesome class usage
  - Suggested replacement using `<FontAwesome />` component
  - Import statement needed for the icon
  - Example of correct usage pattern
  - Severity level
  - Rationale for using component instead of CSS classes
