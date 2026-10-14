---
name: newtonsoft-extensiondata-vs-missingmember
description: "Verified fact — [JsonExtensionData] does NOT exempt a type from MissingMemberHandling.Error (Newtonsoft 13.0.4); Error wins and throws"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 7dc6c870-9aa7-4891-a85e-d99e95480385
  modified: 2026-07-28T15:50:56.074Z
---

Verified twice with independent probes against the pinned Newtonsoft 13.0.4 (via both `JsonConvert.DeserializeObject` and `serializer.Populate`, the path `UtilityStepConverter.ReadJson` uses): **the missing-member check runs BEFORE the extension-data setter**, so `MissingMemberHandling.Error` throws on an unmapped property even when the type declares `[JsonExtensionData]`.

Consequences for this repo:
- `MissingMemberHandling.Error` is too *strict*, not too lenient — it cannot distinguish a typo from forward-compat data and rejects both, which would stop an older build opening a newer step's JSON.
- It is serializer-wide and recurses into nested steps, so "strict container, lenient nested step" is impossible from one `JsonSerializerSettings`.
- Therefore `JsonDefinitionValidator` binds **leniently** for anything nesting a `UtilityStepBase` (so `ExtensionData` populates and the delta rule can diff it), uses `StrictSettings` only for graphs with no extension bag (`RunRecord`), and hand-checks known keys on `StepFile`/`WorkloadStepEntry`.

Also: `JToken.Value<string>()` on a `JObject`/`JArray` throws `InvalidCastException` — NOT a `JsonException` — so it escapes `catch (JsonException)` and, in a Blazor event handler, tears down the circuit. Pattern-match instead: `token is JValue { Type: JTokenType.String } v ? (string?)v : null`. The same latent hazard exists Engine-wide in `JTokenCaseInsensitiveExtensions.ValueCI<T>` (flagged, not fixed).

Related: [[crewchief-raw-json-panes]], [[json-case-insensitivity-audit]].
