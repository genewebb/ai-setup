# Organizational Patterns Analysis

Check adherence to project structure and conventions:

## File Naming

- Components: PascalCase (e.g., `MyComponent.tsx`)
- Utilities: camelCase (e.g., `arrayUtilities.ts`)
- Tests: `.test.ts` or `.test.tsx` suffix
- Consistent naming across related files

## File Organization

- Proper directory structure (components, utils, hooks, types)
- Related files grouped together
- No circular dependencies
- Appropriate separation of concerns

## Import/Export Patterns

- ✅ Named exports (`export const`) instead of default exports
- ✅ Absolute imports for internal modules when possible
- ✅ Grouped imports (external libraries first, then internal)
- ✅ No unused imports
- ✅ Proper import ordering

## Code Structure

- TypeScript interfaces/types defined appropriately
- Components follow React hooks order (useRef → useState → custom hooks → useCallback → useEffect → return)
- Functions use arrow function syntax
- Consistent formatting and indentation
