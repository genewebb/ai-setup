# Potential Issues Analysis

Identify logical and structural problems:

## Logic Errors

- Incorrect conditional logic
- Missing null/undefined checks
- Incorrect state updates
- Race conditions in async code
- Missing error handling

## Type Safety

- Use of `any` type
- Missing type definitions
- Incorrect type assertions
- Type assertions using `as` keyword (should prefer type guards or proper typing) - See [type-assertions.md](./type-assertions.md) for detailed analysis
- Double type assertions (`value as unknown as SomeType`) indicating type system workarounds - See [type-assertions.md](./type-assertions.md) for detailed analysis
- Non-null assertions (`!` operator) that may hide potential null/undefined issues - See [type-assertions.md](./type-assertions.md) for detailed analysis
- Missing type guards - See [type-assertions.md](./type-assertions.md) for detailed analysis

## React-Specific Issues

- Missing dependency arrays in useEffect
- Incorrect use of hooks (conditional hooks, hooks in loops)
- Missing key props in lists
- Direct state mutation
- Unnecessary re-renders
