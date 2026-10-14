---
name: json-formatting-conventions
description: >
  JSON formatting conventions for scenario configs, sample files, and TestAuto
  JSON — 2-space indent, arrays of objects expanded one-per-line, no trailing
  commas. Use when creating or editing JSON config files, reviewing JSON diff
  readability, or formatting Samples/TestCases/** files.
---

Repo: speed-merchants (paths below are repo-relative)

# JSON Formatting Conventions

This skill defines how JSON files are formatted across the speed-merchants codebase — especially scenario configuration files under `Samples/TestCases/` and `TestAuto.Metadata/Samples/`. Consistent formatting keeps diffs reviewable and matches the existing committed style.

## When to Use

- "Format this JSON."
- "Beautify / pretty-print this scenario config."
- Creating or significantly editing scenario configuration JSON.
- The JSON is minified or hard to read and readability matters.
- A diff is unreadable because objects collapsed onto single lines.

---

## Formatting style

| Rule | Value |
|---|---|
| **Indentation** | 2 spaces per nesting level |
| **Line breaks** | One property per line for object members |
| **Arrays of objects** | Every object expanded — each object on its own line(s), each property on its own line. **No inline objects** like `{ "name": "X", "action": "Add" }`. |
| **Arrays of primitives** | Short primitive arrays may stay on one line (e.g. `[0, 2, 3, 4]`) |
| **Braces / brackets** | Opening `{` and `[` on the same line as the key; closing `}` and `]` on their own line, indented to match the opening |
| **Trailing commas** | Not allowed (standard JSON) |
| **Quotes** | Double quotes for all strings |

---

## Example — scenario config style

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

Note how `entities` and `attributes` each expand their member objects across multiple lines — that is the canonical form, never `{"entity":"X","name":"Y"}`.

---

## How to format

| Method | Command | When |
|---|---|---|
| **Preferred — `jq`** | `jq '.' file.json > file.formatted.json && mv file.formatted.json file.json` | `jq` is installed and the file fits in memory |
| **Alternative — Python** | `python -c "import json,sys; d=json.load(sys.stdin); json.dump(d, sys.stdout, indent=2)" < file.json > file.formatted.json` | No `jq`, but Python 3 is available |
| **Manual** | Rewrite with 2-space indent, one property per line | Inside an editor, small fragments, or when `jq`/Python would mangle key order |

When formatting manually, match the style of an existing well-formatted file in the repo (e.g., `UnifiedMatching_Scenario2_OperationalBatch_Small.json`, `MetadataManagementAdd.json`) rather than inventing a new style.

---

## Common pitfalls

| Pitfall | Why it's a problem |
|---|---|
| Inline array-of-objects like `[{"name":"X"},{"name":"Y"}]` | Diffs become unreadable when one element changes; reviewers must mentally re-format. |
| Trailing comma after the last element | Not valid standard JSON; parsers reject. |
| Single quotes around strings | Not valid JSON; some tooling silently fixes, others reject. |
| Mixing 2-space and 4-space indent in the same file | Causes whole-file reformat diffs on every save. |
| `jq` re-ordering keys alphabetically | Use `jq --sort-keys` deliberately, otherwise prefer Python which preserves order. Some configs rely on a meaningful order (e.g., `Name`/`Description`/`ScenarioConfiguration` top-level). |
| Reformatting a file you didn't touch | Creates noisy diffs unrelated to your change. Format only files you are actively editing. |

---

## Decision: format-or-not

```
Did the user explicitly ask to format / beautify the JSON?
├── YES → Format.
└── NO  → Are you editing this file as part of the current task?
          ├── YES → Match the existing style; if file is already well-formatted, preserve it.
          └── NO  → Do NOT format. Leave the file alone.
```

---

## Displaying double-encoded JSON

Some stored JSON fields contain a string value that is itself a JSON object or array — e.g. ConnEx `artifactJson` stored as an escaped string inside `importData`. Rendering these as raw escaped blobs makes them unreadable. `JsonViewHelper` in `TestAuto.Web/Helpers/JsonViewHelper.cs` handles this for the UI.

### API

```csharp
// Namespace: TestAuto.Web.Helpers
public static string PrettyPrint(string? json, bool expandEmbeddedJson = false)
public static JToken InflateEmbeddedJson(JToken token)   // public; called by PrettyPrint
// TryParseEmbedded is private — not part of the callable surface
```

- `PrettyPrint(json, expandEmbeddedJson: true)` — pretty-prints the JSON and, when `expandEmbeddedJson` is `true`, calls `InflateEmbeddedJson` to recursively replace escaped-string values with real nested JSON nodes so backslash escapes never appear in the UI.
- `InflateEmbeddedJson(token)` — walks the token tree; for every `JTokenType.String` value it calls `TryParseEmbedded`. If the string parses as a valid JSON object or array it is replaced with the parsed node (and walked recursively). Non-string tokens (numbers, booleans, `null`) are cloned untouched.
- `TryParseEmbedded` (private) — only attempts a parse when the string's first non-whitespace character is `{` or `[`, so date strings, numbers, and `{{Token}}` placeholders are never reinterpreted.

### View-only rule

**Never persist the inflated form.** The stored escaped string is what the executor sends (e.g. as ConnEx `importData`). Saving the inflated/expanded form back to the database would corrupt the round-trip. Inflation is for display only.

### Example

`artifactJson` as stored (escaped string inside `importData`):

```json
{
  "importData": "{\"ConnectionString\":\"Server=...\"}"
}
```

Rendered via `PrettyPrint(..., expandEmbeddedJson: true)`:

```json
{
  "importData": {
    "ConnectionString": "Server=..."
  }
}
```

---

## Sources

- `.cursor\rules\base\formatting\format-json.mdc` (deleted 2026-05-16)
