# Type Assertion Analysis

Detect and analyze type assertions (`as`, `as unknown as`) to ensure proper type safety and recommend safer alternatives:

## Type Assertion Detection

- **Identify all type assertions in code**:
  - Direct type assertions: `value as SomeType`
  - Double type assertions: `value as unknown as SomeType`
  - Non-null assertions: `value!` (postfix non-null assertion operator)
  - Type assertions in variable declarations: `const x = value as Type`
  - Type assertions in function parameters: `(param as Type) => {}`
  - Type assertions in return statements: `return value as Type`
  - Type assertions in JSX: `<Component prop={value as Type} />`
  - Type assertions in conditional expressions: `condition ? (value as TypeA) : (value as TypeB)`
  - Extract type assertion patterns and their usage contexts
  - Identify where type assertions are used (variable assignments, function calls, return values, etc.)
  - Note the source and target types of each assertion

## Type Assertion Issues

- **Unsafe Type Assertions**:
  - Type assertions without runtime validation
  - Examples to flag:
    - `const user = apiResponse as User` (no validation that apiResponse is actually a User)
    - `const element = document.getElementById('id') as HTMLElement` (could be null)
    - `const data = response.data as MyType` (no validation)
    - `const result = someFunction() as ExpectedType` (assumes function returns ExpectedType)
  - Type assertions that bypass TypeScript's type checking
  - Type assertions used to silence type errors instead of fixing the root cause

- **Double Type Assertions**:
  - Double assertions (`as unknown as SomeType`) indicating type system workarounds
  - Examples to flag:
    - `const value = data as unknown as MyType` (double assertion suggests type mismatch)
    - `const result = apiCall() as unknown as ExpectedType` (indicates type system bypass)
  - Double assertions that mask underlying type issues
  - Double assertions used to force incompatible types together

- **Non-null Assertions**:
  - Non-null assertions (`!` operator) that may hide potential null/undefined issues
  - Examples to flag:
    - `const element = document.getElementById('id')!` (could be null)
    - `const value = array[index]!` (could be undefined)
    - `const prop = obj.property!` (could be undefined)
  - Non-null assertions without proper null checks
  - Non-null assertions used to silence TypeScript warnings

- **Missing Type Guards**:
  - Type assertions used where type guards would be safer
  - Examples to flag:
    - `if (value) { const typed = value as MyType; }` (should use type guard)
    - `const result = data as MyType; if (result.property) { ... }` (should validate before assertion)
  - Type assertions without runtime validation
  - Type assertions that could be replaced with type guards

- **Inconsistent Patterns**:
  - Mixing type assertions with proper type guards in the same file
  - Type assertions used in new code while project standardizes on type guards
  - Type assertions in React components that should use proper prop types

## Recommended Replacement Patterns

- **Use Type Guards Instead of Assertions**:
  - Replace type assertions with type guard functions
  - Import pattern: Create type guard functions that validate at runtime
  - Type guard usage: `if (isUser(value)) { const user = value; /* TypeScript knows value is User */ }`
  - Benefits:
    - Runtime validation ensures type safety
    - TypeScript narrows types automatically
    - Catches type errors at runtime, not just compile time
    - More maintainable and self-documenting

- **Use Proper Type Definitions**:
  - Define proper types/interfaces instead of using assertions
  - Use generic types when appropriate
  - Use discriminated unions for type narrowing
  - Use `unknown` type and narrow down with type guards

- **When Type Assertions Are Acceptable**:
  - Type assertions with proper justification comments
  - Type assertions for DOM elements after null checks: `const element = document.getElementById('id'); if (element) { const htmlElement = element as HTMLElement; }`
  - Type assertions for third-party library types that are known to be correct
  - Type assertions with runtime validation: `if (isValidType(value)) { const typed = value as MyType; }`

## Common Type Assertion Anti-patterns

- Using `as` to silence TypeScript errors instead of fixing the root cause
- Using `as unknown as` to force incompatible types together
- Using `!` operator without null checks
- Type assertions without runtime validation
- Type assertions in hot paths that could cause runtime errors
- Type assertions that bypass API contracts or data schemas

## Detection Patterns

- Search for type assertion patterns:
  - `\bas\s+\w+` (matches `as Type`)
  - `\bas\s+unknown\s+as\s+\w+` (matches `as unknown as Type`)
  - `\w+!` (matches non-null assertions, but be careful with exclamation marks in strings/comments)
  - Template literals: `` `value as ${typeName}` ``
  - Type assertions in function calls: `someFunction(value as Type)`
- Exclude from flagging:
  - Type assertions in test files (if acceptable for test setup)
  - Type assertions with proper justification comments
  - Type assertions after proper null checks or type guards
  - Comments or documentation mentioning type assertions

## Recommendations

- **For New Code**:
  - Always prefer type guards over type assertions
  - Use proper type definitions instead of assertions
  - Add runtime validation when type assertions are necessary
  - Add explanatory comments when type assertions are unavoidable
  - Use `unknown` type and narrow down with type guards

- **For Existing Code**:
  - When modifying files with type assertions, consider refactoring to use type guards
  - If refactoring is not part of the current change, note it as a future improvement
  - Ensure consistency within the file (don't mix assertions and type guards unnecessarily)
  - Add comments explaining why type assertions are necessary

- **Migration Path**:
  - Identify all type assertions in changed files
  - Map type assertions to equivalent type guard usage
  - Provide code examples showing before/after patterns
  - Suggest creating type guard functions for common patterns

## Severity Classification

- **High**: 
  - Unsafe type assertions without runtime validation that could cause runtime errors
  - Double type assertions (`as unknown as`) indicating type system workarounds
  - Non-null assertions (`!`) without null checks
  - Type assertions in critical code paths

- **Medium**: 
  - Type assertions that could be replaced with type guards
  - Type assertions without explanatory comments
  - Type assertions in new code (should use type guards)

- **Low**: 
  - Type assertions with proper justification comments
  - Type assertions after null checks or type guards
  - Type assertions in existing code being modified (consider refactoring)

- **Info**: 
  - Type assertions in test files (if acceptable)
  - Type assertions with proper runtime validation

## Reporting Format

- For each type assertion usage, include:
  - File path and line numbers
  - Code snippet showing type assertion usage
  - Suggested replacement using type guard or proper typing
  - Type guard function example (if applicable)
  - Example of correct usage pattern
  - Severity level
  - Rationale for using type guard instead of assertion
  - If assertion is necessary, suggest adding explanatory comment

## Example Detection Scenarios

- **Scenario 1: Unsafe Type Assertion**:
  - Detects: `const user = apiResponse as User`
  - Suggests: Create type guard function `isUser(value: unknown): value is User`
  - Provides: Type guard implementation and usage example

- **Scenario 2: Double Type Assertion**:
  - Detects: `const value = data as unknown as MyType`
  - Suggests: Fix underlying type issue or use proper type guard
  - Provides: Explanation of why double assertion indicates a problem

- **Scenario 3: Non-null Assertion**:
  - Detects: `const element = document.getElementById('id')!`
  - Suggests: Add null check: `const element = document.getElementById('id'); if (element) { ... }`
  - Provides: Safe null-checking pattern

- **Scenario 4: Type Assertion Without Comment**:
  - Detects: `const result = someFunction() as ExpectedType`
  - Suggests: Add explanatory comment or use type guard
  - Provides: Comment template: `// Type assertion: someFunction() is known to return ExpectedType based on [reason]`

## Automatic Comment Generation

When type assertions are necessary and cannot be replaced with type guards, the analysis should automatically suggest adding explanatory comments:

- **Comment Template for Direct Assertions**:
  ```typescript
  // Type assertion: [reason why assertion is safe/necessary]
  // Example: API contract guarantees this type, or runtime validation performed above
  const value = data as MyType;
  ```

- **Comment Template for Double Assertions**:
  ```typescript
  // Double type assertion: [explanation of why double assertion is needed]
  // Example: Type incompatibility between library types that are structurally compatible
  const value = data as unknown as MyType;
  ```

- **Comment Template for Non-null Assertions**:
  ```typescript
  // Non-null assertion: [reason why value cannot be null/undefined]
  // Example: Element guaranteed to exist due to [condition], or checked above
  const element = document.getElementById('id')!;
  ```

- **Comment Requirements**:
  - Comments should explain why the assertion is safe
  - Comments should reference any runtime validation performed
  - Comments should note any assumptions being made
  - Comments should be placed directly above the assertion
