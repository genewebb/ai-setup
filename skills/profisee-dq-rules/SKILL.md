---
name: profisee-dq-rules
description: >
  Profisee data quality rule expression syntax (DQL) for validation and assignment clauses.
  Use when creating DQ validation rules, building assignment clauses, writing Profisee
  expression language (= / <> comparisons, = NULL null tests, AND/OR/NOT, double-quoted
  strings, bracketed [Attr].[Name] references, CONCAT/TEXT/IF/CONTAINS functions), or
  calling the save_data_quality_rules MCP tool.
---

# Profisee Data Quality Rule Expressions

Profisee data quality rules use a proprietary expression language (grammar name: `DQL`). This skill covers the syntax for validation clauses (rules that flag data issues) and assignment clauses (rules that auto-populate attribute values).

> [!IMPORTANT]
> Syntax below was **verified against the live grammar endpoint on 2026-07-27** (`get_profisee_expression_grammar` + `get_profisee_expression_reference`, plus 20 real rules read via `get_data_quality_rules`). If a rule unexpectedly fails to parse or save, **re-query `get_profisee_expression_grammar` for the target instance rather than trusting this table** — the grammar is served by the running Profisee instance and can change between releases.

## When to Use

- "Create a rule that validates [attribute] is [condition]"
- "Build an assignment rule that sets [field] to [expression]"
- "How do I write Profisee expression language?"
- "What syntax does save_data_quality_rules expect?"
- Calling the `save_data_quality_rules` MCP tool directly

## Rule Structure

A rule targets one entity and one attribute, and contains one or more clauses. `entity_name` + `attribute_name` uniquely identify a rule — saving with the same pair **overwrites** the existing rule.

```json
{
  "entity_name": "WorkloadExecution",
  "attribute_name": "Name",
  "is_enabled": true,
  "assignment_execution_mode": "Always",
  "validation_clauses": [],
  "assignment_clauses": []
}
```

| Field | Required | Description |
|---|---|---|
| `entity_name` | Yes | Profisee entity the rule applies to |
| `attribute_name` | Yes | Attribute the rule applies to; with `entity_name`, the rule identity |
| `is_enabled` | No | Default `true` |
| `assignment_execution_mode` | No | `Create` \| `Update` \| `Always`. Default `Always`. Rule-level, **not** per-clause |
| `validation_clauses` | No | Array of validation clauses |
| `assignment_clauses` | No | Array of assignment clauses |

## Validation Clauses

The `what_expression` must evaluate to `TRUE` for a record to **pass**. A data quality issue is created when it evaluates to `FALSE`.

```json
{
  "what_expression": "[Name] <> NULL",
  "what_display_text": "[Name] <> NULL",
  "when_expression": null,
  "when_display_text": null,
  "is_constraint": false
}
```

| Field | Required | Description |
|---|---|---|
| `what_expression` | Yes | Boolean expression; TRUE = pass, FALSE = DQ issue |
| `what_display_text` | No | Display name; **defaults to the expression text** if omitted |
| `when_expression` | No | Rule only applies when this returns TRUE |
| `when_display_text` | No | Display name for the condition |
| `is_constraint` | No | `false` = DQ issue (default), `true` = record cannot be saved |

## Assignment Clauses

Assignment clauses use the **same `what_expression` / `when_expression` field names** as validation clauses. There is no `assignment_expression` field. The `what_expression` here yields the *value* assigned to the attribute.

```json
{
  "what_expression": "CONCAT([Workload].[Code], \" for Version \", [ProfiseeVersion].[Code])",
  "what_display_text": "Build Name from Workload and Version",
  "when_expression": "[Name] = NULL",
  "when_display_text": "Only when Name is empty"
}
```

| Field | Required | Description |
|---|---|---|
| `what_expression` | Yes | Expression producing the value to assign |
| `what_display_text` | No | Defaults to the expression text |
| `when_expression` | No | Assignment only runs when this returns TRUE |
| `when_display_text` | No | Display name for the condition |

Assignment clauses have **no `is_constraint`** field. When the assignment runs (Create / Update / Always) is controlled by the rule-level `assignment_execution_mode`.

## Expression Language Reference

Keywords and function names are case-insensitive in the grammar; live rules use uppercase.

### Attribute References

Attribute names are wrapped in square brackets. Multi-level (related-entity) references put a **period between each bracketed level** — the brackets do not span the dot:

```
[Name]
[Workload].[Code]
[Order].[Customer].[Region].[Country]
```

Domain-based attributes (DBAs): referenced alone, `[SomeDba]` yields the **code** value. For the display name use `[SomeDba].[Name]`. Prefer names for readability.

```
[Status].[Code] = NULL
[WorkloadExecution].[DBServer].[Name]
```

### Literals

| Kind | Form | Notes |
|---|---|---|
| String | `"USA"` | **Double quotes only.** Single quotes are not string delimiters |
| Number | `1000`, `3.14`, `.5` | |
| Boolean | `TRUE`, `FALSE` | |
| Null | `NULL` | |

Escapes inside strings: `\"`, `\\`, `\'`, `\0`, `\f`, `\n`, `\r`, `\t`.

### Comparison Operators

| Operator | Meaning |
|---|---|
| `=` | equals |
| `<>` | not equals |
| `<` | less than |
| `<=` | less than or equal |
| `>` | greater than |
| `>=` | greater than or equal |

There are no named comparison operators (`eq`, `ne`, `gt`, `lt`, `ge`, `le` are **not** part of the grammar).

### Null Testing

Null is tested with the normal equality operators against the `NULL` literal — there is no `IsNull()` / `IsNotNull()` function:

```
[Name] <> NULL           -- has a value
[ProfiseeRelease] = NULL -- is empty
```

The `NULL` literal is the **right-hand** operand in the grammar's null comparison rules; write `[Attr] = NULL`, not `NULL = [Attr]`. Null comparison is defined for number, string, date, datetime, and boolean expressions.

### Set Membership

```
[Status] IN ("Active", "Inactive", "Pending")
[DqRuleCount] NOT IN (0, 10)
```

Works for string, number, date, and datetime expressions.

### Logical Operators

| Operator | Meaning |
|---|---|
| `AND` | both conditions true |
| `OR` | either condition true |
| `NOT` | negation |

Use parentheses to group: `([A] = 1 OR [B] = 2) AND [C] <> NULL`.

### Conditional

`IF(condition, valueIfTrue, valueIfFalse)` — returns number, string, date, datetime, or boolean depending on the branch types (both branches must be the same type).

```
IF([Product].[Stock] = 0, "Out of Stock", TEXT([Product].[Stock]))
```

### String Functions

| Function | Description |
|---|---|
| `CONCAT(a, b, ...)` | Concatenate two or more strings |
| `a & b` | Concatenation operator (alternative to CONCAT) |
| `CONTAINS(s, sub)` | Boolean — s contains sub |
| `STARTSWITH(s, sub)` | Boolean |
| `ENDSWITH(s, sub)` | Boolean |
| `CONTAINSPATTERN(s, pattern)` | Boolean — pattern match |
| `LEFT(s, n)` / `RIGHT(s, n)` | Leading / trailing n characters |
| `SUBSTRING(s, start, length)` | Substring |
| `TRIM(s)` | Remove leading/trailing whitespace |
| `LENGTH(s)` | Number — string length |
| `INDEXOF(s, sub)` | Number — position of sub |
| `TEXT(x)` | Convert number/date/datetime/boolean to string |
| `TONUMBER(s)` | Convert string to number |
| `NEWGUID` | New GUID string (no parentheses) |

There is no `Upper()` or `Lower()` function in the grammar.

### Date / DateTime Functions

| Function | Description |
|---|---|
| `TODAY` / `NOW` | Current date / current datetime (no parentheses) |
| `DATE(y, m, d)` | Construct a date |
| `DATETIMEUTC(y, m, d, h, mi, s [, ms])` | Construct a UTC datetime |
| `TODATE(s)` / `TODATETIMEUTC(s)` | Parse from string |
| `DATEADD(date, n, DAY\|MONTH\|YEAR)` | Add an interval |
| `DATEDIFF(d1, d2)` | Number — difference between two dates |
| `RELATIVEDATE(date, part)` | `STARTOFWEEK`, `ENDOFWEEK`, `NEXTWEEK`, `STARTOFMONTH`, `ENDOFMONTH`, `NEXTMONTH`, `STARTOFQUARTER`, `ENDOFQUARTER`, `NEXTQUARTER`, `STARTOFYEAR`, `ENDOFYEAR`, `NEXTYEAR` |

### Change-Tracking Functions

Operate on attribute references (not arbitrary expressions):

| Function | Description |
|---|---|
| `CHANGED([Attr] [, [Attr2] ...])` | Boolean — any listed attribute changed |
| `CHANGEDTO([Attr], value [, value ...])` | Boolean — changed to one of the values (`NULL` allowed) |
| `CHANGEDFROM([Attr], value [, value ...])` | Boolean — changed from one of the values (`NULL` allowed) |
| `PRIOR([Attr])` | Previous value of the attribute |
| `ANY([Attr])` | Any value of the attribute |

```
CHANGED([Product].[Price]) AND [Product].[Price] > PRIOR([Product].[Price]) * 1.2
```

### Arithmetic

`+`, `-`, `*`, `/`, unary `+`/`-`, parentheses.

## Examples

### Validation: required attribute

```json
{
  "what_expression": "[Name] <> NULL",
  "what_display_text": "Name is required",
  "is_constraint": false
}
```

### Validation: numeric range

```json
{
  "what_expression": "[Price] <> NULL AND [Price] > 0",
  "what_display_text": "Price must be greater than 0"
}
```

### Validation: domain attribute membership

```json
{
  "what_expression": "[Status].[Code] IN (\"Active\", \"Inactive\", \"Pending\")",
  "what_display_text": "Status must be Active, Inactive, or Pending"
}
```

### Validation: conditional (only applies when Status = Active)

```json
{
  "what_expression": "[StartDate] <> NULL",
  "what_display_text": "StartDate is required for active records",
  "when_expression": "[Status].[Code] = \"Active\"",
  "when_display_text": "When record is Active"
}
```

### Assignment: concatenate fields

```json
{
  "what_expression": "CONCAT([FirstName], \" \", [LastName])",
  "what_display_text": "Build FullName from FirstName and LastName",
  "when_expression": "[FirstName] <> NULL AND [LastName] <> NULL",
  "when_display_text": "When both name fields are populated"
}
```

### Assignment: default only when empty

```json
{
  "what_expression": "\"New\"",
  "what_display_text": "Default Status to New",
  "when_expression": "[Status].[Code] = NULL",
  "when_display_text": "When Status is empty"
}
```

### Assignment: copy from a related entity

```json
{
  "what_expression": "[WorkloadExecution].[DBServer].[Name]",
  "what_display_text": "Copy DB server name from the parent execution"
}
```

## Complete MCP Tool Payload

`save_data_quality_rules` takes a single `request` object containing a `rules` array:

```json
{
  "request": {
    "rules": [
      {
        "entity_name": "WorkloadExecution",
        "attribute_name": "Name",
        "is_enabled": true,
        "assignment_execution_mode": "Always",
        "validation_clauses": [
          {
            "what_expression": "[Name] <> NULL",
            "what_display_text": "Name is required",
            "when_expression": null,
            "when_display_text": null,
            "is_constraint": false
          }
        ],
        "assignment_clauses": [
          {
            "what_expression": "CONCAT([Workload].[Code], \" for Version \", [ProfiseeVersion].[Code])",
            "what_display_text": "Build Name from Workload and Version",
            "when_expression": "[Name] = NULL",
            "when_display_text": "Only when Name is empty"
          }
        ]
      }
    ]
  }
}
```

`get_data_quality_rules` and `delete_data_quality_rules` use the same `request` wrapper.

**Before calling `save_data_quality_rules`**: call `get_profisee_expression_reference` (and `get_profisee_expression_grammar` for anything non-trivial) to confirm the grammar for the target Profisee instance. Saving with an existing `entity_name` + `attribute_name` overwrites the whole rule, including clauses you did not send.

## Pass/Fail Example Records

For validation `what_expression` = `[Price] <> NULL AND [Price] > 0`:

| Price value | Result | Reason |
|---|---|---|
| `10.50` | PASS | Has value, greater than 0 |
| `0.01` | PASS | Has value, greater than 0 |
| `null` | FAIL | `<> NULL` is false |
| `0` | FAIL | Not greater than 0 |
| `-5.00` | FAIL | Not greater than 0 |

## Sources

- `get_profisee_expression_grammar` MCP tool — ANTLR `grammar DQL` (authoritative), read 2026-07-27
- `get_profisee_expression_reference` MCP tool — narrative overview, read 2026-07-27
- `get_data_quality_rules` MCP tool — 20 live rules on the local Profisee instance, read 2026-07-27
- `save_data_quality_rules` MCP tool input schema — payload field names and enums
