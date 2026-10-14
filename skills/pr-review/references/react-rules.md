# React Rules Compliance Analysis

Verify adherence to React rules defined in `.cursor/rules/react-rules.md`:

## Component Declaration

- ✅ Components use arrow functions (`export const Component = () => {}`)
- ❌ No function declarations (`function Component()`)
- ❌ No default exports (`export default`)
- ❌ No React.FC type annotation
- ✅ Props interfaces are defined separately and exported
- ✅ Props are destructured explicitly in component arguments
- ❌ No rest props (`...props`) usage

## Hooks Usage

- ✅ Hooks follow correct order:
  1. Refs (`useRef` with comment explaining why)
  2. Local state (`useState`, `useReducer`)
  3. Context hooks (`useContext`)
  4. Custom hooks
  5. Memos (`useMemo`)
  6. Callbacks (`useCallback`)
  7. Effects (`useEffect`, `useLayoutEffect`) - always last
- ✅ Every `useRef` includes a comment explaining why it's needed
- ✅ `useEffect` is used sparingly and only for true side effects
- ❌ `useEffect` not used for:
  - Transforming data for rendering (use `useMemo` or compute during render)
  - Resetting state based on props (use key prop)
  - Updating state based on other state (compute during render)
  - Event handlers (use event handler props)
  - Fetching data on mount (use data fetching library)
  - Initializing state from props (use initializer function)

## TypeScript

- ❌ No `any` type usage (ESLint error)
- ✅ Use `unknown` instead of `any` when type is truly unknown
- ✅ Proper event types (`React.MouseEvent`, `React.ChangeEvent`, etc.)
- ✅ Use `Record<string, unknown>` for objects with unknown structure

## Props

- ✅ Props interfaces are exported
- ✅ All props are explicitly destructured
- ❌ No inline props types
- ❌ No non-exported interfaces

## File Structure

- ✅ Code follows order: Imports → Type Definitions → Constants → Helper Functions → Component
- ✅ Helper functions use arrow functions (never function declarations)
- ✅ Constants defined before component

## Styling

- ✅ CSS Modules used (`import css from "./Component.module.scss"`)
- ❌ No inline styles (unless dynamic)
- ❌ No global CSS classes

## Event Handlers

- ✅ Event handlers wrapped in `useCallback`
- ❌ No inline arrow functions in JSX (unless trivial)

## Provider Pattern (when using Context)

- ✅ Context created without default value
- ✅ Custom Provider component created
- ✅ Custom Consumer hook created (e.g., `useCount`)
- ✅ Hook throws error if used outside Provider
- ✅ Context not exported directly
- ✅ Context value memoized if needed
- ✅ `displayName` set on context for debugging

## General Rules

- ✅ `useEffect` used sparingly and only for true side effects
- ✅ Alternatives considered before using `useEffect`:
  - Compute during render
  - Use `useMemo` for expensive computations
  - Use `useCallback` for memoizing functions
  - Use key prop for resetting state
  - Use custom hooks for reusable logic

## Severity Classification for React Rules Violations

- **Critical**: 
  - Use of `any` type (ESLint error)
  - Function declarations instead of arrow functions
  - Default exports
  - React.FC usage
  - Missing error handling in custom hooks (hook used outside Provider)

- **High**:
  - Incorrect hooks order
  - Missing `useRef` comments
  - `useEffect` used for non-side-effect purposes
  - Rest props (`...props`) usage
  - Missing prop interface exports
  - Provider pattern violations (exporting context, missing custom hook)

- **Medium**:
  - Inline props types
  - Non-exported interfaces
  - Missing `useCallback` for event handlers
  - Incorrect file structure order
  - CSS Modules not used

- **Low**:
  - Minor style inconsistencies
  - Missing `displayName` on context
  - Minor documentation issues

## Reporting Format

- For each React rules violation, include:
  - Rule category (Component Declaration, Hooks, TypeScript, etc.)
  - Specific rule violated
  - File path and line numbers
  - Code snippet showing violation
  - Reference to the specific rule file (e.g., `react-rules/component-declaration.md`)
  - Suggested fix with code example
  - Severity level
