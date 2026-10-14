---
name: testauto-config-store-migration
description: >
  The one-time, idempotent ConfigurationMigrationJob that normalizes pre-existing scenario/workflow
  configs into the chunk store and audits remaining file references before the
  file-reference-retirement removal ships. Use when running the config migration job, the
  /api/migration endpoints, inlining legacy bodyFilePath step bodies, the RepairResult counters, the
  Convert→Audit deploy gate, or diagnosing dangling CHUNKREFs and unresolved file references.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Config Store Migration

`ConfigurationMigrationJob` is the **one-time, idempotent** data-maintenance job that brings *pre-existing* stored configs up to the current format and proves it is safe to ship the file-reference-retirement runtime removal. It is the operational counterpart to the runtime store in [[testauto-scenario-config-store]] and the data half of [[project_file_reference_retirement]].

It exposes four operations, all reachable via `MigrationController` (`/api/migration/*`) and all driven against the single Profisee instance the WebUI is connected to.

## When to Use

- "Run the config chunk-store conversion / `convert-config-chunks`."
- "Run the file-reference audit / is it safe to deploy runtime removal?"
- "How do I migrate old configs to the chunk store?"
- "What do `ConfigsConverted` / `FileBodiesInlined` / `DanglingChunkRefs` mean?"
- "Why didn't the second migration run convert anything?" (idempotency)
- "A step still has a `bodyFilePath` — how does migration inline it?"

## The Deploy Gate: Convert → Audit → ship removal

The file-reference retirement removes runtime support for file-backed step bodies. Before that build ships **on a given instance**, that instance must be clean:

```
1. POST /api/migration/convert-config-chunks   → ConvertConfigsToChunkStoreAsync
      Normalizes every stored config + inlines bodyFilePath bodies.
2. POST /api/migration/audit-file-references    → AuditFileReferencesAsync  (read-only)
      Counts steps that STILL carry scriptKey / bodyFilePath, plus dangling CHUNKREFs.
3. Gate: AuditSummary says "SAFE to deploy runtime removal."
      ONLY when FileReferencesRemaining == 0 AND DanglingChunkRefs == 0.
      Otherwise "NOT safe — run Convert first."
```

This is a **per-instance** gate — run it on every instance that will receive the removal build.

## The Four Operations

| Endpoint | Method | What it does | Writes? |
|---|---|---|---|
| `compress-configurations` | `MigrateAllConfigurationsAsync` | legacy: compress TemplateData + ScenarioData to `BROTLI:` + populate display | yes |
| `compress-templates` / `compress-scenarios` | `MigrateTemplatesAsync` / `MigrateScenariosAsync` | same, scoped | yes |
| `convert-config-chunks` | `ConvertConfigsToChunkStoreAsync` | normalize to chunk store + inline file bodies | yes |
| `audit-file-references` | `AuditFileReferencesAsync` | scan for remaining file refs + dangling chunks | **no (read-only)** |

The `compress-*` operations are the *older* codec-compression migration (covered by [[configuration-compression-codec]]); they skip any value already starting `GZIP:` **or** `BROTLI:` (checking only `GZIP:` would double-compress already-BROTLI data → undeserializable, non-idempotent). The chunk-store conversion is the current path.

## `ConvertConfigsToChunkStoreAsync` — the conversion

Walks **all three owner types** and re-persists each through `IScenarioConfigStore`:

- Scenarios (`ScenarioData` + `ScenarioDataDisplay`) → `ConfigOwnerType.Scenario`
- `TestAutoWorkflowDetail` (`ScenarioConfiguration`) → `ConfigOwnerType.WorkflowTemplate`
- `TestAutoWorkflowExecutionDetail` (`ScenarioConfiguration`) → `ConfigOwnerType.WorkflowExecution`

Per record (`ConvertOneRecordAsync`):

1. Blank stored value → `ConfigsSkipped++`, return.
2. **Classify**: `isLegacy` (`BROTLI:`/`GZIP:`), `isChunked` (`CHUNKREF:`), `isInlineJson` (trims to `{`). `alreadyConverted = isChunked || isInlineJson`.
3. **Normalize to raw JSON**: legacy → `TemplateStorage.DecompressFully`; chunked → `ResolveRawAsync`; inline → as-is.
4. **Idempotency guard** (the subtle bit): an `alreadyConverted` record is skipped **unless `HasRemainingBodyFilePath(rawJson)` is true** — i.e. a re-run only re-touches an already-converted record when it still has a `bodyFilePath` a re-run can finish. This lets a re-run complete records an earlier run left half-done **without restoring the DB**.
5. Deserialize (`Errors++` + skip on failure/null).
6. `InlineFileReferences(config)` — walk `ScenarioRuntime.CustomParms["Steps"]` and inline each step.
7. `PersistAsync(config, ownerType, record.Code)` → new stored value.
8. Write back the data field; for scenarios, also write a `ScenarioDataDisplay` preview **truncated to 4000 chars** (`raw[..4000]`) — see [[reference_scenariodatadisplay_4000_ceiling]].

## `bodyFilePath` inlining (`InlineBodyFilePath`)

For each step's `bodyFilePath`:

- **If the step already has a non-empty `body`** → that inline body is authoritative; the lingering `bodyFilePath` is dead metadata → strip it, done.
- Else resolve `{{$config:Section:Key}}` tokens in the path. Script-directory keys (canonical `DirectoryPaths:ScriptDirectory`, plus legacy aliases `ScriptDirectories`/`ScriptDirectory`) all resolve to the one secret-backed script root.
- If the resolved path doesn't exist, try **`TryRecoverUnderScriptRoot`**: (1) the path tail after the last `\Scripts\` segment re-rooted under each candidate root, then (2) a *unique* filename match anywhere under the root. Candidate roots in priority order: the configured secret path, then the app's bundled `Scripts` folder (`AppContext.BaseDirectory\Scripts`, deployed with every build → machine-independent). Ambiguous (≠1) match = leave unresolved.
- On success: `step["body"] = content`, remove `bodyFilePath`, `FileBodiesInlined++`.
- Any failure (missing file, empty file, read error) is **non-fatal**: `FileReferencesUnresolved++`, step left untouched.

> **`scriptKey` is deliberately NOT inlined or counted in the idempotency guard.** It is fully retired and cannot be inlined, so treating a lingering `scriptKey` as "remaining work" would make a re-run churn the record forever without converging. The *audit* still reports `scriptKey` (it's a runtime dependency), but conversion can't fix it.

## `AuditFileReferencesAsync` — read-only gate check

Scans all three owner types and, per stored config (`AuditOneStoredConfigAsync`):

- **Chunk-integrity check FIRST** (before `ResolveRawAsync`, which would throw on a dangling CHUNKREF): for a `CHUNKREF:` value, `Parse` → `(groupKey, expectedCount)`, query the `TestAutoScenarioConfiguration` rows by `GroupKey`, compare. Mismatch → `DanglingChunkRefs++`, skip the file-ref scan for that record.
- Otherwise resolve, parse JSON, walk `ScenarioRuntime.CustomParms["Steps"]`. A step counts as a remaining reference when it has a `scriptKey`, **or** a `bodyFilePath` **with no inline `body`** (a `bodyFilePath` next to a populated `body` is dead metadata runtime removal ignores).
- Tally `RecordsWithFileReferences` and `FileReferencesRemaining`.

## RepairResult counters

```
Conversion: ConfigsScanned, ConfigsConverted, ConfigsSkipped, FileBodiesInlined,
            FileReferencesUnresolved (non-fatal skips), Errors (real per-record failures)
Audit:      FileReferencesRemaining, RecordsWithFileReferences, DanglingChunkRefs
Summaries:  ConversionSummary, AuditSummary ("SAFE to deploy runtime removal" iff
            FileReferencesRemaining == 0 && DanglingChunkRefs == 0)
```

`Errors` counts only *real* failures (deserialize/persist). Benign skips (file not found, token unresolved) go to `FileReferencesUnresolved` so they don't inflate the error count.

## Pitfalls

| Pitfall | Reality |
|---|---|
| Re-running convert "did nothing" looks broken | Idempotent by design — already-converted records with no remaining `bodyFilePath` are skipped. That's success. |
| Expecting convert to clear a lingering `scriptKey` | It can't (retired, not inlinable). Audit will still flag it; the config must be re-authored/re-imported. |
| Calling `ResolveRawAsync` on a dangling CHUNKREF during audit | The audit pre-checks chunk row count to avoid the throw. Mirror that pattern in any new walker. |
| Shipping runtime removal before the audit reads SAFE | Per-instance gate — `FileReferencesRemaining` and `DanglingChunkRefs` must both be 0 on *that* instance. |
| Assuming convert restores missing chunks | It can't fabricate missing chunk rows. A dangling CHUNKREF needs a re-save/re-import of that config. |

## Sources

- `TestAuto.Web\Jobs\ConfigurationMigrationJob.cs`
- `TestAuto.Web\Controllers\MigrationController.cs`
- `Testing.SpeedMerchants.Unit\Web\Jobs\ConfigurationMigrationJobChunkTests.cs`
- `Testing.SpeedMerchants.Integration\Web\Integration\MigrationEndpointIntegrationTests.cs`
- `Testing.SpeedMerchants.Integration\Tests\RESTGateway\Entity\ScenarioFilePathAuditTests.cs`
