# Regex Usage Analysis

Detect and analyze regex patterns for optimization opportunities and code quality issues:

## Regex Detection

- Identify all regex patterns in code (`/pattern/`, `new RegExp()`, `RegExp()`)
- Extract regex patterns and their usage contexts
- Identify regex flags used (global, case-insensitive, multiline, etc.)
- Note where regex is used (validation, parsing, string manipulation, etc.)

## Regex Optimization Opportunities

### Performance Issues

- Regex patterns compiled inside loops (should be moved outside and reused)
- Catastrophic backtracking patterns (e.g., `(a+)+b` matching `aaaaaaaaac`)
- Excessive quantifiers (`.*`, `.+`, `.{0,}`) that could be more specific
- Missing anchors (`^`, `$`) causing unnecessary backtracking
- Complex alternations that could be optimized

### Simplification Opportunities

- Regex used for simple string operations that could use `includes()`, `startsWith()`, `endsWith()`, `indexOf()`
- Regex patterns that could be replaced with string methods (`split()`, `substring()`, `slice()`)
- Overly complex regex that could be split into multiple simpler checks
- Regex flags that could be optimized (e.g., case-insensitive when case matters)

### Pattern Improvements

- Non-greedy quantifiers (`*?`, `+?`) when greedy (`*`, `+`) would be more efficient
- Unnecessary capturing groups that slow down matching
- Lookahead/lookbehind assertions that could be simplified
- Regex patterns that could use character classes more efficiently

## Regex as Code Smell Indicators

### Inconsistent Data Formats

- Regex parsing inconsistent string formats (suggests need for standardized data contracts)
- Multiple regex patterns parsing similar data differently across files
- Regex extracting structured data from unstructured strings (indicates missing proper data format)
- Regex used to handle multiple variations of the same data format

### Missing Type Safety

- Regex validation that should be handled by TypeScript types or runtime validation libraries
- Regex used to coerce or parse data that should have proper types
- Regex type checking that could use type guards or schema validation

### Architectural Issues

- Regex used as workaround for missing API contracts or data schemas
- Regex parsing that indicates need for dedicated parsing utilities or libraries
- Regex patterns duplicated across multiple files (suggests need for shared utility)
- Regex used to extract data that should come from structured sources (APIs, databases)

## Common Regex Anti-patterns

- Using regex for email validation (use dedicated validation library)
- Using regex for URL parsing (use `URL` constructor or library)
- Using regex for date parsing (use date parsing libraries)
- Using regex for number validation (use `Number()` or `parseInt()` with validation)
- Using regex for HTML parsing (use DOM parser or HTML parsing library)
- Using regex for JSON parsing (use `JSON.parse()`)
- Complex regex patterns that are hard to read and maintain

## Recommendations

- When regex is necessary, ensure patterns are:
  - Compiled once and reused (especially in loops)
  - Well-documented with comments explaining the pattern
  - Tested with edge cases and performance benchmarks
  - Optimized for the specific use case
- Consider alternatives:
  - String methods for simple operations
  - Dedicated parsing libraries for complex formats
  - Type validation libraries instead of regex validation
  - Structured data formats (JSON, XML) instead of regex parsing
- When regex indicates inconsistent practices:
  - Suggest standardizing data formats
  - Recommend creating shared parsing utilities
  - Propose using proper data contracts or schemas
  - Identify opportunities for refactoring to eliminate regex dependency
