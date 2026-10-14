# Format JSON Rule

When creating, editing, or beautifying JSON files in this project (especially scenario configuration files under `Samples/TestCases/`, `TestAuto.Metadata/Samples/`, etc.), use the following formatting conventions.

## Formatting Style

- **Indentation**: 2 spaces per nesting level
- **Line breaks**: One property per line for object members
- **Arrays of objects**: Every object in an array must be expanded — each object on its own line(s) with each property on a separate line (same format as `attributes`). Do not use inline objects like `{ "name": "X", "action": "Add" }`.
- **Arrays of primitives**: Short primitive arrays (e.g. `[0, 2, 3, 4]`) may stay on one line
- **Braces/brackets**: Opening `{` and `[` on the same line as the key; closing `}` and `]` on their own line, indented to match the opening
- **No trailing commas** (standard JSON)
- **Quotes**: Double quotes for all strings

## Example (Scenario Config Style)

```json
{
  "Name": "ScenarioName",
  "Description": "Description text",
  "ScenarioConfiguration": {
    "ScenarioName": "SomeScenario",
    "ScenarioTables": {
      "SourceEntityName": "RetailClient",
      "TargetEntityName": "RetailClient"
    },
    "CustomParms": {
      "entities": [
        {
          "name": "RetailClient",
          "action": "Add"
        },
        {
          "name": "Source System",
          "action": "Add"
        }
      ],
      "attributes": [
        {
          "entity": "RetailClient",
          "name": "FirstName",
          "action": "Add",
          "type": "String",
          "length": 100,
          "description": "First name"
        }
      ]
    }
  }
}
```

## How to Format

1. **Preferred**: Use `jq` if available:
   ```bash
   jq '.' file.json > file.formatted.json && mv file.formatted.json file.json
   ```

2. **Alternative**: Use Python:
   ```bash
   python -c "import json,sys; d=json.load(sys.stdin); json.dump(d, sys.stdout, indent=2)" < file.json > file.formatted.json
   ```

3. **Manual**: When editing, rewrite the JSON with 2-space indentation, one property per line, matching the style of existing formatted files (e.g. `UnifiedMatching_Scenario2_OperationalBatch_Small.json`, `MetadataManagementAdd.json`).

## When to Apply

- When the user asks to "format", "beautify", or "pretty-print" JSON
- When creating or significantly editing scenario configuration JSON files
- When JSON is minified or hard to read and readability matters
