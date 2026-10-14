# C# Type Safety Analysis

Detect and analyze unsafe casting, null handling, and type bypass patterns in C# code:

## Type Assertion / Cast Detection

- **Identify unsafe patterns**:
  - Direct casts: `(MyType)value`, `value as MyType`
  - Null-forgiving: `value!` (postfix)
  - `as` casts that may hide null: `record["Field"] as string`
  - Casts without validation: `(Record)response` when runtime type is unknown
- **Contexts to flag**:
  - Dictionary indexer results cast without `TryGetValue` or null check
  - `object` or `dynamic` cast to specific type without validation
  - `as` used where pattern matching would be safer

## Nullable Reference Types

- **Potential null reference**:
  - Dereference of `string?` or `T?` without null check
  - `!.` when value could reasonably be null
  - Null-forgiving inappropriately used to silence warnings
- **Preferred patterns**:
  - `value ?? throw new ArgumentNullException(...)`
  - Pattern matching: `if (x is not null) { ... }`
  - Null-conditional: `x?.Property`

## Record / Dictionary Access

- **Unsafe**:
  - `record["Field"]?.ToString()` without validating key existence
  - `(string)record["Code"]` when value could be null or wrong type
- **Preferred**:
  - `record.TryGetValue(FieldNames.Code, out var val)`
  - Constants for keys: `EntityNames.*`, `FieldNames.*`
  - Helper extension methods for record access

## JSON / Deserialization

- **Unsafe**:
  - `JObject` or `JsonElement` cast without validation
  - `as` on deserialized data without schema check
- **Project rule**: Use Newtonsoft.Json; convert `JsonElement` to `JToken`/`JObject` promptly

## Recommended Replacements

- **Pattern matching** instead of cast + null check: `if (obj is MyType mt) { ... }`
- **Type guards** for external data: validate before casting
- **Nullable annotations** and proper null handling over `!`
- **Constants** for entity/field names per `string-constants.mdc`
