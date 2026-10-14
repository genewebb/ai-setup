---
name: testauto-scenario-config-store
description: >
  Chunked scenario-config persistence (IScenarioConfigStore) that beats Profisee's 4000-char
  attribute ceiling. Use when persisting or loading a ScenarioConfiguration, storing config for a
  scenario or workflow template/execution detail, ConfigChunkSentinel (CHUNKREF), ConfigOwnerType,
  the chunk entity, inline-vs-chunked storage, reading a value that may be raw JSON / CHUNKREF /
  legacy BROTLI: blob, or an editor creating new config-owning rows.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Scenario Config Store

`IScenarioConfigStore` persists a `ScenarioConfiguration` as **raw JSON**, transparently working around Profisee's 4000-character per-attribute ceiling. Small configs are stored **inline** (the returned string *is* the JSON). Large configs are **split into chunk records** in a dedicated Profisee entity, and the store returns a short `CHUNKREF:` **sentinel** that points at the chunk group. On read, the store reassembles chunks, decompresses legacy blobs, or passes inline JSON straight through.

This is the runtime read/write layer. The one-time conversion of pre-existing data into this format is a separate concern — see [[testauto-config-store-migration]].

## When to Use

- "How do I save a scenario config that's bigger than 4000 chars?"
- "What is a `CHUNKREF:` value in `ScenarioData` / `ScenarioConfiguration`?"
- "How does config get split across `TestAutoScenarioConfiguration` rows?"
- "Persist this config for a workflow-template detail / execution detail."
- "I read a config value and it starts with `CHUNKREF:` / `BROTLI:` — how do I resolve it?"
- "Why does loading a config throw 'Expected N chunk(s) but retrieved M'?"

## The Interface

```csharp
public interface IScenarioConfigStore
{
    // Serialize + persist. Returns the stored value: inline JSON OR a "CHUNKREF:" sentinel.
    Task<string> PersistAsync(ScenarioConfiguration config, ConfigOwnerType ownerType, string ownerCode, CancellationToken ct = default);

    // Stored value -> ScenarioConfiguration. null if storedValue null/whitespace.
    Task<ScenarioConfiguration?> LoadAsync(string? storedValue, CancellationToken ct = default);

    // Stored value -> raw JSON WITHOUT deserializing. null if storedValue null/whitespace.
    Task<string?> ResolveRawAsync(string? storedValue, CancellationToken ct = default);

    // Delete all chunk records for an owner. No-op if none exist.
    Task DeleteAsync(ConfigOwnerType ownerType, string ownerCode, CancellationToken ct = default);
}
```

`ScenarioConfigStore` is the only implementation. Its sole dependency is an `IRestClient` bound to the **ScenarioMgt** subject area (see DI below).

## Three Storage Shapes (what a stored value can be)

A single `ScenarioData` / `ScenarioConfiguration` attribute can hold any of three shapes. `ResolveRawAsync` dispatches on the prefix:

| Shape | Looks like | How it's read |
|---|---|---|
| **Inline JSON** | `{ ... }` (raw, indented) | returned as-is |
| **Chunked** | `CHUNKREF:<groupKey>:<count>` | reassemble N chunk rows |
| **Legacy compressed** | `BROTLI:...` (current codec) or `GZIP:...` (older) | `TemplateStorage.DecompressFully()` |

`ConfigChunkSentinel` provides the prefix tests: `IsChunked()`, `IsLegacyCompressed()`, plus `Build(groupKey, count)` and `Parse(sentinel) → (GroupKey, Count)`.

> New writes never produce a `BROTLI:`/`GZIP:` value — the store only writes inline JSON or chunks. Legacy compressed values exist only in pre-migration data and are read-only-decoded for backward compatibility. Compression mechanics live in [[configuration-compression-codec]].

## Inline vs Chunked Decision

In `PersistAsync`, the config is serialized with `JsonConvert.SerializeObject(config, Formatting.Indented)`, then:

- **`json.Length <= 3900` (`InlineLimit`)** → inline path. Any stale chunks for this owner are deleted (`DeleteAsync`), and the raw JSON string is returned. No chunk rows are created.
- **`json.Length > 3900`** → chunked path (below).

Both `InlineLimit` and `ChunkSize` are **3900** (`ScenarioConfigConstants`) — deliberately under the 4000 ceiling to leave headroom.

## The Chunk Entity

Chunks live in the `TestAutoScenarioConfiguration` Profisee entity. Each chunk row:

| Attribute | Value |
|---|---|
| `Code` / `Name` | `{groupKey}-{seq}` (e.g. `Scenario-ABC123-1`) |
| `GroupKey` | `{ownerType}-{ownerCode}` (e.g. `Scenario-ABC123`) |
| `EntityType` | the owner type code (`Scenario` / `WorkflowTemplate` / `WorkflowExecution`) |
| `Seq` | 1-based slice index |
| `ScenarioJsonData` | the ≤3900-char JSON slice |

The **group key** is `{ownerType.ToCode()}-{ownerCode}`. `ConfigOwnerType` is `{ Scenario, WorkflowTemplate, WorkflowExecution }`; `ToCode()` maps each to its literal string.

## The Write Order (no data-loss window)

`PersistAsync`'s chunked path is ordered to survive a mid-write crash:

```
1. Split JSON into ≤3900-char slices with SplitIntoChunks (whitespace-safe boundaries —
   see below) → build one Record per slice (Seq 1..N).
2. UPSERT the new chunks FIRST (UpdateRecordsAsync(..., isUpsert: true)).
   ↳ Old chunks remain intact until the new ones are fully written.
     A failure here leaves the PRIOR chunks still resolvable — no data loss.
3. DELETE only stale leftover chunks (Seq > N from a previously larger config).
   ↳ Best-effort. Orphan chunks are harmless — the sentinel only reads Seq 1..N.
4. Return ConfigChunkSentinel.Build(groupKey, N)  →  "CHUNKREF:<groupKey>:<N>".
```

**Why this order matters:** writing new chunks before deleting old ones means there is no instant where the config is half-deleted-half-written. If step 2 throws, the previously stored config is untouched.

## Whitespace-Safe Chunk Boundaries (hard invariant)

> **Invariant: no chunk may begin or end with a whitespace character.**

**Why.** Profisee silently trims leading and trailing whitespace from *every* attribute value. A
slice written into `ScenarioJsonData` that ends with a space — or whose successor starts with one —
comes back one character shorter. Reassembly is a plain concatenation, so the two adjacent tokens
get mashed together. The real-world failure was an inline SQL step whose `DROP TABLE` became
`DROPTABLE`, surfacing as SQL syntax error **102** far downstream from the actual corruption. The
stored config *looked* fine; only the round trip was lossy.

**How `SplitIntoChunks` enforces it** (`ScenarioConfigStore.cs:245`, private static):

```csharp
// cut is the START of the next chunk, so the current chunk's last char is source[cut - 1]
// and the next chunk's first char is source[cut].
var cut = i + chunkSize;

// Back the cut up until NEITHER side of the boundary is whitespace.
while (cut > i + 1 &&
       (char.IsWhiteSpace(source[cut - 1]) || char.IsWhiteSpace(source[cut])))
{
    cut--;
}

// Degenerate fallback: a whitespace run longer than chunkSize left no safe cut
// (impossible for serialized JSON, but guarded). Use the hard limit.
if (cut <= i + 1) cut = i + chunkSize;
```

Consequences worth knowing:

- Chunks are **≤ 3900 chars, not exactly 3900**. Never assume a fixed slice length, and never
  reconstruct offsets arithmetically from `Seq × ChunkSize` — always concatenate in `Seq` order.
- The trailing slice is emitted whole when `source.Length - i <= chunkSize`, before any boundary
  search runs.
- Backing a cut up can only shrink a chunk, so a whitespace-safe split may produce **one more
  chunk** than a naive split of the same payload.
- **The read path is deliberately unchanged.** `ReassembleChunksAsync` (`ScenarioConfigStore.cs:144`)
  is still a plain ordered concatenation, so configs chunked by the *old* naive splitter still load
  exactly as before. This was a write-side-only fix — it does **not** repair already-corrupted
  stored configs. Those must be re-saved or re-imported.

**Regression test:** `Persist_ChunkBoundaryWhitespace_SurvivesProfiseeTrim`
(`Testing.SpeedMerchants.Unit\Web\Services\ScenarioConfigStore\ScenarioConfigStoreTests.cs:448`).
It sweeps payload lengths `extra = 0..40`, prepending `extra` non-whitespace chars to a ~12 KB
`"DROP TABLE Foo "`-repeated payload so every 3900-char boundary slides one position at a time
across the spacey region. Per iteration it asserts (a) no upserted chunk starts or ends with
whitespace, then (b) simulates Profisee by `.Trim()`-ing each stored chunk and asserts the reloaded
`ScenarioName` is byte-identical. A naive index split fails at least one length in the sweep.

**If you touch the split:** keep the sweep test, and keep reassembly as plain concatenation. Any
"optimization" that cuts on a fixed index — or that trims/normalizes a slice before writing —
reintroduces this bug class. See memory `project_chunk_boundary_whitespace_trim`.

## Reading Chunks (and the dangling-chunk throw)

`ResolveRawAsync` → `ReassembleChunksAsync`:

1. Parse the sentinel → `(groupKey, count)`.
2. Fetch chunk rows by code `{groupKey}-1 .. {groupKey}-count` (`GetRecordsByCodesAsync`).
3. **If fetched count != expected count → throw `InvalidOperationException`** ("Expected N chunk(s) ... but retrieved M"). This is a **dangling CHUNKREF** — chunk rows are missing.
4. Order by `Seq`, concat `ScenarioJsonData` → full raw JSON.

A dangling CHUNKREF is unrecoverable at read time: the config must be re-saved or re-imported. Consumers that walk many configs (e.g. export, audit) should wrap `ResolveRawAsync` in try/catch and report *which* owner broke, rather than aborting — see how `WorkflowTransferService.BuildBundleAsync` and the audit job do it.

## DI Registration

Scoped, bound to the ScenarioMgt rest client (`WebModuleRegistrar.cs`):

```csharp
services.AddScoped<IScenarioConfigStore>(sp =>
{
    var clientFor = sp.GetRequiredService<Func<RestSubjectArea, IRestClient>>();
    return new ScenarioConfigStore(clientFor(RestSubjectArea.ScenarioMgt));
});
```

## Display-Field Gotcha

The full config lives in the data attribute (inline or chunked). A *separate* `ScenarioDataDisplay` preview attribute is capped at 4000 chars and must be truncated when written — see [[reference_scenariodatadisplay_4000_ceiling]] and the migration job's write-back, which does `raw.Length > 4000 ? raw[..4000] : raw`. Never write the full (possibly multi-KB) config into a display attribute.

## Consumer Save-Path Convention (idempotent create of new owner rows)

When an editor creates a **new** record whose config goes through the store (e.g. a new
`TestAutoWorkflowDetail` scenario row), follow the `WorkflowScenariosEditor` convention —
it is the durable fix for the "duplicate scenarios on save/retry" bug class:

1. **Pre-assign `Guid.NewGuid().ToString()` as the owner `Code` up front** (at copy/add time,
   never `string.Empty`). Both the config chunks (`PersistAsync(config, ownerType, ownerCode)`)
   and the record create key off this code, so a retried save **reuses** the same code instead
   of spawning duplicate rows.
2. **Treat "8603 already exists" as success when the code was ours**: on bulk create, if the
   only failures are 8603s for codes this editor pre-assigned, adopt the existing rows and
   clear `IsNew` — this self-heals a previously stuck/half-saved copy instead of looping on
   a false "1 unsaved change".
3. **Fail soft per row**: a row whose record body can't be built (`BuildWorkflowDetailRecordAsync`
   returns null) stays dirty and is reported, but does not abort the rest of the batch. Guard
   against persisting chunks for an empty `Code`.

```csharp
var newScenario = new ScenarioDetailItem
{
    // Pre-assign a unique code up front. Both the config chunk store and the record
    // create key off this code, and a stable value makes the create idempotent on retry
    // (a re-save reuses the same code instead of spawning duplicate rows).
    Code = Guid.NewGuid().ToString(),
    ...
    IsNew = true, IsDirty = true
};
```

See memory `project_workflow_copy_duplicate_save_bug` for the incident this convention fixed.

## Pitfalls

| Pitfall | Reality |
|---|---|
| Treating a stored value as always-JSON | It may be `CHUNKREF:`, `BROTLI:`, `GZIP:`, or inline JSON. Always go through `ResolveRawAsync`/`LoadAsync`. |
| Calling `ResolveRawAsync` on a possibly-dangling CHUNKREF without try/catch | A missing chunk throws `InvalidOperationException`. Pre-check the row count or catch and report. |
| Caching the resolved `ScenarioConfiguration` | The project forbids caching `ScenarioConfiguration` — see [[testauto-project]]. Resolve per use. |
| Hand-writing a config larger than 4000 chars directly to the attribute | Profisee rejects it (8610). Persist through the store so it chunks. |

## Sources

- `TestAuto.Web\Services\ScenarioConfigStore\ScenarioConfigStore.cs`
- `TestAuto.Web\Services\ScenarioConfigStore\IScenarioConfigStore.cs`
- `TestAuto.Web\Services\ScenarioConfigStore\ConfigChunkSentinel.cs`
- `TestAuto.Web\Services\ScenarioConfigStore\ConfigOwnerType.cs`
- `TestAuto.Web\Services\ScenarioConfigStore\ScenarioConfigConstants.cs`
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs` (DI)
- `Testing.SpeedMerchants.Unit\Web\Services\ScenarioConfigStore\ScenarioConfigStoreTests.cs`
- `Testing.SpeedMerchants.Unit\Web\Services\ScenarioConfigStore\ConfigChunkSentinelTests.cs`
- `Testing.SpeedMerchants.Integration\Web\Integration\ScenarioConfigStoreIntegrationTests.cs`
- `TestAuto.Web\Components\Pages\WorkflowScenariosEditor.razor.cs` (save-path convention: pre-assigned GUID Code ~828-841, 8603-as-success ~1311-1360, fail-soft builder ~1452-1530)
