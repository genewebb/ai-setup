---
name: external-json-case-insensitive-reads
description: >
  Convention for reading EXTERNAL JSON (Profisee gateway REST, ConnEx/Connect, Matching/OAuth)
  case-insensitively in speed-merchants. Use when reading a key off a Newtonsoft JObject/JToken from
  an external API, when a value comes back null though the JSON clearly has it, when adding JSON key
  names as constants, or when replacing raw jObject["Key"] / SelectToken / Value<T> fallback reads.
  Covers JTokenCaseInsensitiveExtensions and GatewayJsonKeys.
---

Repo: speed-merchants (paths below are repo-relative)

# External JSON: Case-Insensitive Reads + Key Constants

External JSON in this codebase is **re-cased by whoever produced it**. The Profisee CDP platform uses
contract resolvers (e.g. a `LowercaseContractResolver` on input, camelCase on record reads), so the same
logical key arrives as `code`, `Code`, or `CODE` depending on the endpoint and platform version.
Newtonsoft's `jObject["Key"]` indexer and `SelectToken("A.B")` are **case-sensitive** and silently return
`null` on a mismatch — which has produced real, hard-to-spot bugs: empty record-create bodies (→ HTTP 400),
artifact versions never read, pollers hanging to their timeout.

This skill is the standing convention that fixes that whole class of bug. It replaced the old scattered
`Value<T>("code") ?? Value<T>("Code")` manual-fallback reads (~26 files) with one centralized utility plus
key constants.

## When to Use

- "Read this field off the gateway/ConnEx/Matching response."
- "A value comes back null but the JSON clearly contains it." (almost always a casing mismatch)
- Adding or reading any key on a Newtonsoft `JObject`/`JToken` that originated from an **external** API.
- Reviewing or replacing raw `jObject["Key"]`, `SelectToken(...)`, or `Value<T>("x") ?? Value<T>("X")` reads.
- Deciding where a new JSON key-name constant belongs.

## The rule

1. **Never** read a key off external JSON with the raw `jObject["Key"]` indexer or `SelectToken`. Use the
   case-insensitive accessors below.
2. **Never** hard-code a key name as a string literal at the call site. Pass it as a **constant**.
3. **Shared** keys (envelope `data`/`errors`/`totalRecords`, record `code`/`name`/`id`, OAuth
   `access_token`, RFC-7807 `title`/`detail`, ConnEx `configuration`/`artifactVersion`) live in
   `GatewayJsonKeys` (`TestAuto.Shared/Rest/GatewayJsonKeys.cs`).
4. **Subsystem-specific** keys live in a `private static class …Keys` nested in the consumer (e.g.
   `MonitorKeys` inside `MonitorActivityCollector`), with a comment pointing shared keys at `GatewayJsonKeys`.
5. Constant *literal values* use the casing the gateway currently emits **purely for readability** — matching
   does not depend on it, so don't "fix" a constant's casing to match a wire sample.

> This codifies the long-standing JSON Case-Insensitivity Audit rule. The bug class it cures includes the
> ConnEx `vaultId` empty-import bug and the Model-Import RefData empty-`[]`-body 400.

## The accessors — `JTokenCaseInsensitiveExtensions`

`TestAuto.Shared/JsonHelpers/JTokenCaseInsensitiveExtensions.cs` — extension methods on `JToken?`:

| Method | Replaces | Behavior |
|---|---|---|
| `token.GetValueCI(key)` → `JToken?` | `token[key]` indexer | Case-insensitive `JObject.GetValue(key, OrdinalIgnoreCase)`. Returns `null` if `token` isn't a `JObject` or the key is absent. |
| `token.ValueCI<T>(key)` → `T?` | `token.Value<T>("k") ?? token.Value<T>("K")` | Case-insensitive typed read. Returns `default` when the key is missing **or** the value is JSON `null`. |
| `token.SelectTokenCI(path)` → `JToken?` | `SelectToken("a.b")` | Case-insensitive dotted-path walk. **Simple paths only** — no array indexers or JSONPath filters. Returns `null` on the first missing/non-object segment. |

All three are null-safe on the receiver (`this JToken? token`).

## Key constants

- **`GatewayJsonKeys`** (`TestAuto.Shared/Rest/GatewayJsonKeys.cs`) — shared cross-subsystem keys and a few
  dotted paths (`IdentifierNamePath = "identifier.name"`, `ConfigurationArtifactVersionPath`,
  `ValueConfigurationValuePath`).
- **Private nested `…Keys` class** — subsystem-only keys. Example: `MonitorKeys` in `MonitorActivityCollector`
  holds `StartedTime`/`CompletedTime`/`ActivityType`/… while still using `GatewayJsonKeys.Id/Code/Name/Data`
  for the shared ones.
- **Entity-attribute constant classes** — when reading gateway *record* JSON for a specific Profisee entity,
  the attribute/column names get their own constants too (e.g. `SecretsEntityAttributes` for the
  `TestAutoSecrets` entity: `Code`/`Name`/`MachineName`/`SecretData`/… plus `ActiveYes`/`ActiveNo`). These
  use the entity's declared casing but are still read through the CI accessors.

## Examples

**Before / after — the canonical replacement** (from `MonitorActivityCollector`):

```csharp
// BEFORE — manual lowercase-then-PascalCase fallback, string literals everywhere
Id     = item.Value<string>("id")     ?? item.Value<string>("Id")     ?? string.Empty;
Status = item.Value<string>("status") ?? item.Value<string>("Status") ?? string.Empty;
var data = obj["data"] ?? obj["Data"];

// AFTER — one CI read, key names as constants
Id     = item.ValueCI<string>(GatewayJsonKeys.Id)   ?? string.Empty;
Status = item.ValueCI<string>(MonitorKeys.Status)   ?? string.Empty;   // subsystem-specific key
var data = obj.GetValueCI(GatewayJsonKeys.Data);
```

**Dotted path** (from `EntityJsonConverter` — pulling `identifier.name` when the default deserializer missed it):

```csharp
var nameToken = jObj.SelectTokenCI(GatewayJsonKeys.IdentifierNamePath);   // "identifier.name"
if (nameToken != null)
    entity.Name = nameToken.ToString();
```

**Validating a 207 body** (from `CreatedRecordsResponseExtensions`):

```csharp
var errorsToken = response.ResponseContent.GetValueCI(GatewayJsonKeys.Errors);
var hasErrors   = errorsToken != null && errorsToken.HasValues;
```

## Anti-patterns

| Don't | Do |
|---|---|
| `jObj["code"]` / `jObj.Value<string>("code")` on external JSON | `jObj.ValueCI<string>(GatewayJsonKeys.Code)` |
| `jObj.Value<T>("x") ?? jObj.Value<T>("X")` fallback | `jObj.ValueCI<T>(SomeKeys.X)` |
| `jObj.SelectToken("identifier.name")` | `jObj.SelectTokenCI(GatewayJsonKeys.IdentifierNamePath)` |
| String literal `"artifactVersion"` at the call site | A constant in `GatewayJsonKeys` or a private `…Keys` class |
| Matching on a capitalized `"Code"` constant when the gateway returns lowercase `code` | CI accessor — casing-independent (this exact mismatch produced empty `[]` create bodies → 400) |
| `SelectTokenCI("data[0].name")` (array index / filter) | `SelectTokenCI` is simple-path only; index the `JArray` yourself |

## Sources

- `TestAuto.Shared\JsonHelpers\JTokenCaseInsensitiveExtensions.cs`
- `TestAuto.Shared\Rest\GatewayJsonKeys.cs`
- `TestAuto.Web\Services\SecretsEntityAttributes.cs`
- `TestAuto.Matching\Helpers\MonitorActivityCollector.cs` (private `MonitorKeys`)
- `TestAuto.Shared\JsonHelpers\EntityJsonConverter.cs`
- `TestAuto.Shared\Rest\CreatedRecordsResponseExtensions.cs`
- `Testing.SpeedMerchants.Unit\Shared\JsonHelpers\JTokenCaseInsensitiveExtensionsTests.cs`
