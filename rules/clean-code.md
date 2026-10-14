# Clean Code Guidelines

## Follow Established patterns
- Write clean, maintainable code following project conventions
- Follow established naming conventions and file structure
- Follow established folder structure and naming conventions
- Follow existing code patterns and architectural decisions

## Constants Over Magic Numbers
- Replace hard-coded values with named constants
- Use descriptive constant names that explain the value's purpose
- Keep constants at the top of the file or in a dedicated constants file

## Meaningful Names
- Variables, functions, and classes should reveal their purpose
- Names should explain why something exists and how it's used
- Avoid abbreviations unless they're universally understood

## Smart Comments
- Don't comment on what the code does - make the code self-documenting
- Use comments to explain why something is done a certain way
- Document APIs, complex algorithms, complex interfaces, and non-obvious side effects

## Single Responsibility
- Keep files focused on single responsibilities
- Each function should do exactly one thing
- Functions should be small and focused
- If a function needs a comment to explain what it does, it should be split

## DRY (Don't Repeat Yourself)
- Extract reusable logic into appropriate utilities to avoid duplication and improve testability
- Share common logic through proper abstraction
- Maintain single sources of truth

## Clean Structure
- Keep related code together
- Organize code in a logical hierarchy
- Use consistent file and folder naming conventions
- Optimize for maintainability over cleverness
- Group related functionality logically

## Encapsulation
- Hide implementation details
- Expose clear interfaces
- Move nested conditionals into well-named functions

## Error Handling
- Implement proper error handling and edge case management

## Code Quality Maintenance
- Refactor continuously for code clarity, maintainability, and to reduce duplication
- Fix technical debt early
- Leave code cleaner than you found it

## Testing
- Write tests before fixing bugs
- Keep tests readable and maintainable
- Test edge cases and error conditions

## Version Control
- Write clear commit messages
- Make small, focused commits
- Use meaningful branch names 

# Communication Guidelines

## When Seeking Clarification

- **Provide context** about what you've discovered during implementation
- **Suggest alternatives** if the planned approach has issues
- **Include code examples** or file references for clarity

## When Reporting Issues

- **Explain what was attempted** and why it failed
- **Document the problem** clearly with reproduction steps
- **Explain the impact** on the current step or future steps
- **Suggest potential solutions** or workarounds
- **Preserve any partial work** with clear documentation

# Documentation

- Always use Markdown for documentation and README files
- Maintain the existing structure of the README.md file
- Keep examples synchronized with code
- Update references to external docs
- Maintain links between related files
- Document breaking changes
