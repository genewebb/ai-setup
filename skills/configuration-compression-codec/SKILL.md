---
name: configuration-compression-codec
description: >
  TemplateStorage compression codec in TestAuto.Shared for scenario and template JSON exceeding
  Profisee's 4000-character attribute limit. Use when serializing/deserializing
  ScenarioData/TemplateData values, BROTLI: vs GZIP: prefixes, double-encoding issues, reconciling
  against the newer chunked CHUNKREF store, DecompressFully on unknown layer depth, or diagnosing a
  value that got compressed more than once (CountCompressionLayers counts the layers — it is a
  diagnostic helper with no production callers, not part of a wired repair path).
---

Repo: speed-merchants (paths below are repo-relative)

# Configuration Compression Codec (`TemplateStorage`)

> **Scope**: speed-merchants (TestAuto.Shared)
> **Source**: `TestAuto.Shared/Services/TemplateStorage.cs`

Profisee limits attribute values to 4000 characters. `TemplateStorage` is a static service that compresses scenario configurations (JSON objects) and template data using Brotli + Base64, then prefixes the result to identify the compression format. This is required for any non-trivial `ScenarioData` or `TemplateData` attribute value.

---

## Why This Exists

The `TemplateData` and `ScenarioData` Profisee attributes have a 4000-character limit. Serialized scenario JSON routinely exceeds this. `TemplateStorage` compresses before writing and decompresses after reading.

---

## Format Detection

All compressed strings carry a prefix that identifies the codec:

| Prefix | Codec | Status |
|---|---|---|
| `BROTLI:` | Brotli + Base64 | Legacy template/scenario compression (still written by the `compress-*` migration) |
| `GZIP:` | GZip + Base64 | Legacy (read-only support) |
| _(no prefix)_ | Uncompressed JSON | Oldest — backward compat only |

---

## Relationship to the Chunked Config Store (CHUNKREF)

For **scenario configurations** (the `ScenarioData` / `ScenarioConfiguration` attributes), single-blob compression has been **superseded** by the chunked config store — see [[testauto-scenario-config-store]]. That store writes **inline raw JSON** (small) or splits across chunk records and writes a **`CHUNKREF:` sentinel** (large). It does **not** produce `BROTLI:`/`GZIP:` values.

So a stored scenario-config value can be any of:

| Shape | Produced by | Read with |
|---|---|---|
| inline raw JSON | `ScenarioConfigStore` (small config) | as-is |
| `CHUNKREF:<groupKey>:<n>` | `ScenarioConfigStore` (large config) | reassemble chunks |
| `BROTLI:` / `GZIP:` | legacy data / `compress-*` migration | `TemplateStorage` (this skill) |

`ScenarioConfigStore.ResolveRawAsync` still calls `TemplateStorage.DecompressFully()` to decode any legacy `BROTLI:`/`GZIP:` value it encounters — so this codec remains the **read path for legacy blobs**, while new writes go through the chunk store. `TemplateData` (templates) still uses this codec directly. The one-time normalization of legacy blobs into the chunk store is [[testauto-config-store-migration]].

---

## API

### `SerializeForStorage<T>(T obj) → string`

Serializes an object to JSON (Newtonsoft, `Formatting.None`) and compresses with Brotli.

```csharp
var compressed = TemplateStorage.SerializeForStorage(scenarioConfig);
// → "BROTLI:<base64>"
// Store this string in the TemplateData attribute
```

Returns `string.Empty` if `obj` is null.

---

### `TryDeserializeFromStorage<T>(string compressedJson) → T?`

Decompresses and deserializes. Handles all three formats automatically. Returns `default(T)` on any failure (never throws).

```csharp
var config = TemplateStorage.TryDeserializeFromStorage<ScenarioConfiguration>(attributeValue);
if (config == null)
{
    // attribute was empty or corrupted
}
```

**Double-encoding detection**: If the decompressed string starts and ends with `"`, it is treated as a JSON-encoded string and unwrapped before final deserialization. This handles legacy data that was serialized twice.

---

### `GetDisplayText(string compressedJson) → string`

Decompresses and returns the first 4000 characters of the raw JSON. Used for diagnostic display in the UI — never for round-trip deserialization.

```csharp
var preview = TemplateStorage.GetDisplayText(attributeValue);
```

---

### `CompressRawContent(string content) → string`

For raw string content that should **not** be JSON-wrapped (avoids the extra quote-escaping overhead of `SerializeForStorage`). Minifies valid JSON before compressing.

```csharp
var compressed = TemplateStorage.CompressRawContent(jsonFileContents);
// Use instead of SerializeForStorage when content is already a string
```

Returns `string.Empty` if content is null or empty.

---

### `DecompressRawContent(string compressed) → string`

Reverse of `CompressRawContent`. Supports BROTLI: and GZIP: prefixes. Returns the input unchanged if no prefix is detected.

```csharp
var original = TemplateStorage.DecompressRawContent(compressed);
```

---

### `DecompressFully(string value) → string`

**Signature** (`TemplateStorage.cs:171`, expression-bodied static):

```csharp
public static string DecompressFully(string value) =>
    string.IsNullOrWhiteSpace(value) ? string.Empty : PeelCore(value).Content;
```

The **read entry point for any stored value whose layer count you don't trust**. It peels
*every* `BROTLI:`/`GZIP:` envelope in a loop rather than assuming a single layer.

Why it exists: a migration-job bug — a skip-check that matched only `"GZIP:"` — re-compressed
already-`BROTLI:` data on **every run**, stacking many layers on the same value. `DecompressFully`
tolerates that historical damage without needing a data repair first.

How the peel loop (`PeelCore`, `TemplateStorage.cs:183`) works:

1. Bounded to **64 passes** — it can never loop unbounded.
2. Each pass first checks for a **JSON-string-encoded envelope**: if the value starts and ends
   with `"`, it deserializes the quotes away — but **only when the unwrapped inner value is itself
   a `BROTLI:`/`GZIP:` envelope**. A legitimately double-encoded *final* JSON string is left
   quoted for the caller to handle.
3. Then it strips one `BROTLI:` or `GZIP:` prefix, Base64-decodes and decompresses, and increments
   the layer count.
4. It stops when no compression prefix remains (fully decompressed) or when a layer throws
   (corrupt/truncated) — in the failure case it **returns what it has so far rather than
   throwing**. Silent partial output is the failure mode to watch for.

Empty/whitespace in → `string.Empty` out. Never throws.

**How it differs from the other decompress paths:**

| Method | Layers peeled | Returns | Throws? |
|---|---|---|---|
| `DecompressFully` | all (≤64) | raw string | no |
| `DecompressRawContent` | all (≤64) — **routes to the same `PeelCore`** | raw string | no |
| `TryDeserializeFromStorage<T>` | all (≤64), then deserializes to `T` | `T?` (`default` on failure) | no |
| `GetDisplayText` | all (≤64), then truncates to 4000 chars | display string | no |

> `DecompressRawContent` and `DecompressFully` are **behaviourally identical today** — both are
> thin wrappers over `PeelCore(value).Content` with the same null/whitespace guard
> (`TemplateStorage.cs:155-161` vs `:171-172`). They differ only in intent: `DecompressRawContent`
> is the documented inverse of `CompressRawContent`; `DecompressFully` is the "I don't know how
> many layers this has" reader. Don't assume one is single-layer — neither is.

**Live callers:**

| Caller | Why |
|---|---|
| `ScenarioConfigStore.ResolveRawAsync` — `TestAuto.Web\Services\ScenarioConfigStore\ScenarioConfigStore.cs:102` | the legacy branch: once `ConfigChunkSentinel.IsLegacyCompressed(storedValue)` is true, decode the `BROTLI:`/`GZIP:` blob to raw JSON |
| `ConfigurationMigrationJob` step 3 — `TestAuto.Web\Jobs\ConfigurationMigrationJob.cs:364` | normalize a stored value to raw JSON before re-persisting through the chunk store (`isLegacy ? DecompressFully(stored) : isChunked ? await ResolveRawAsync(stored) : stored`) |

### `CountCompressionLayers(string value) → int`

Companion diagnostic (`TemplateStorage.cs:178`), same `PeelCore` walk but returns the layer count
instead of the content: `0` = uncompressed/plain, `1` = normal single-layer storage, `>1` =
over-compressed and in need of repair. Use it to *detect* the stacked-layer damage that
`DecompressFully` merely tolerates.

---

## When to Use Which Method

| Scenario | Use |
|---|---|
| Storing a C# object (config, scenario) | `SerializeForStorage<T>` / `TryDeserializeFromStorage<T>` |
| Storing raw file contents or pre-serialized JSON | `CompressRawContent` / `DecompressRawContent` |
| Reading a stored value of unknown/untrusted layer depth (legacy blob, migration input) | `DecompressFully` |
| Auditing whether a value is over-compressed | `CountCompressionLayers` |
| Showing compressed data in the UI | `GetDisplayText` |

---

## Sources

- `TestAuto.Shared\Services\TemplateStorage.cs`
- `TestAuto.Web\Services\ScenarioConfigStore\ScenarioConfigStore.cs` (DecompressFully caller, ~:102)
- `TestAuto.Web\Jobs\ConfigurationMigrationJob.cs` (DecompressFully caller, ~:364)
