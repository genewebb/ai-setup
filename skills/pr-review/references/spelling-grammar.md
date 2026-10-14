# Spelling and Grammar Errors Analysis

Check for spelling and grammar mistakes:

## Code Elements

- Misspelled variable names
- Misspelled function names
- Misspelled component names
- Misspelled constants and enums
- Misspelled file names

## Comments and Documentation

- Spelling errors in code comments
- Grammar mistakes in JSDoc comments
- Typos in inline documentation
- Spelling errors in README files

## User-Facing Text

- Spelling errors in hardcoded strings (before MaestroStrings migration)
- Typos in error messages
- Grammar mistakes in UI text
- Inconsistent terminology

## Configuration and Metadata

- Spelling errors in configuration files
- Typos in package.json descriptions
- Misspelled property names in JSON/YAML
- Spelling errors in commit messages (if reviewing commits)

## Common Issues to Flag

- Common typos (e.g., "recieve" → "receive", "seperate" → "separate")
- Incorrect technical terms
- Inconsistent spelling (e.g., "color" vs "colour")
- Abbreviation inconsistencies (e.g., "ID" vs "Id" vs "id")
- Pluralization errors

## Context-Aware Checking

- Ignore technical terms and domain-specific vocabulary
- Respect project-specific naming conventions
- Consider camelCase/PascalCase word boundaries
- Account for abbreviations and acronyms
