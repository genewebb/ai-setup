# Potential Bugs Analysis

Identify actual or potential bugs:

## Runtime Errors

- Null reference exceptions
- Undefined property access
- Array out of bounds
- Type coercion issues
- Incorrect type assertions (`as`) that may cause runtime errors when types don't match - See [type-assertions.md](./type-assertions.md) for detailed analysis
- Double type assertions masking type mismatches - See [type-assertions.md](./type-assertions.md) for detailed analysis

## Logic Bugs

- Off-by-one errors
- Incorrect calculations
- Wrong comparison operators
- Missing edge cases

## State Management Bugs

- Stale closures
- Race conditions
- Incorrect state updates
- Missing state initialization
