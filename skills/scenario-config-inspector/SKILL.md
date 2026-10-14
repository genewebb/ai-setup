---
name: scenario-config-inspector
description: >
  Inspect a TestAuto workflow's actual stored config by decompressing the Brotli/GZip
  ScenarioConfiguration / ScenarioData blobs from the ScenarioMgt (speedmerchants) database into
  readable JSON. Use when reconciling what is stored vs the editor view, auditing per-step
  CustomParms, or extracting a step's configuration. Decodes BROTLI:/GZIP:/plain only — CHUNKREF
  reassembly is not implemented and returns verbatim.
---

# Scenario Config Inspector

> **Scope**: speed-merchants — ScenarioMgt instance = the `speedmerchants` database on the local
> SQL server (`localhost`), accessed with integrated auth. No MCP dependency.
> **Script**: `{PowershellScriptsDir}\inspect-config.ps1`

The TestAuto editor only shows *rendered* config. The underlying values are stored compressed:
- per workflow step → `data.tTestAutoWorkflowDetail.ScenarioConfiguration`
- per scenario → `data.tTestAutoScenarios.ScenarioData`

A stored value is one of three shapes (see [[testauto-scenario-config-store]]):
- **`BROTLI:` / `GZIP:`** + base64 of compressed JSON (codec = `TestAuto.Shared/Services/TemplateStorage.cs`) — legacy blobs.
- **inline raw JSON** — new small configs, no prefix, used as-is.
- **`CHUNKREF:<groupKey>:<count>`** — new large configs, split across rows (see below).

This skill reads and decodes them.

## Chunked configs (`CHUNKREF:`) — NOT YET IMPLEMENTED in the script

> **Current state (verified against `inspect-config.ps1`)**: the script's `Expand-Config` function
> handles only three cases — `BROTLI:`, `GZIP:`, and an else-branch that returns the raw value
> unchanged. There is **no CHUNKREF branch and no chunk-table query**. So when a stored value is a
> `CHUNKREF:<groupKey>:<count>` sentinel, the script returns the sentinel string verbatim and the
> downstream `ConvertFrom-Json` fails (it is not JSON). The inspector **cannot** currently read a
> chunked config. You must either extend the script (add the branch below) or read the chunk rows
> another way (e.g. a direct SQL query).

New large configs are no longer single compressed blobs — they are split across rows in the `TestAutoScenarioConfiguration` entity and the stored attribute holds a sentinel `CHUNKREF:<groupKey>:<count>`. **What an extension would need to do** (reassemble, not decode):

1. Parse the sentinel → `groupKey` and `count` (the body after `CHUNKREF:`, split on the last `:`).
2. Query the chunk table — `data.tTestAutoScenarioConfiguration` — for rows where `GroupKey = <groupKey>` (or by `Code` = `<groupKey>-1 .. <groupKey>-<count>`).
3. Order by the `Seq` column and concatenate the `ScenarioJsonData` column values.
4. The concatenation **is** the raw JSON — no decompression step.

> A row count that does not match `<count>` is a **dangling CHUNKREF** — the config is incomplete and cannot be reconstructed until it is re-saved. Report it rather than emitting partial JSON.

## Usage

```powershell
pwsh -File "{PowershellScriptsDir}\inspect-config.ps1" -WorkflowCode 10000124 -CustomParmsOnly
```

```powershell
pwsh -File "{PowershellScriptsDir}\inspect-config.ps1" -WorkflowCode 10000124 -Step 42
```

```powershell
pwsh -File "{PowershellScriptsDir}\inspect-config.ps1" -ScenarioCode <code> -OutFile {ScratchRoot}\scn.json
```

### Parameters

| Param | Purpose |
|---|---|
| `-WorkflowCode <code>` | Workflow `Code` (e.g. `10000124`) → all steps, ordered by `ExecutionOrder` |
| `-ScenarioCode <code>` | A single `tTestAutoScenarios` record |
| `-Step <n>` | (Workflow mode) limit output to one `ExecutionOrder` |
| `-CustomParmsOnly` | Print only `ScenarioRuntime.CustomParms` per step (the high-signal part) |
| `-OutFile <path>` | Also write the full output to a file |
| `-Database` | DB name (default `speedmerchants`) |
| `-ServerInstance` | SQL server (default `localhost`) |

## How it works

1. Opens an ADO.NET connection (`System.Data.SqlClient`, integrated auth — no creds stored).
2. **Workflow mode:** `tTestAutoWorkflow` (Code → ID) → `tTestAutoWorkflowDetail`
   (`Workflow = ID`, ordered by `ExecutionOrder`), reads `ScenarioConfiguration`.
   **Scenario mode:** `tTestAutoScenarios` reads `ScenarioData`.
3. Decodes each blob: strip `BROTLI:` / `GZIP:` prefix → `FromBase64String` →
   `BrotliStream` / `GZipStream` Decompress → UTF-8. Unprefixed values pass through as-is.
4. Pretty-prints via `ConvertFrom-Json | ConvertTo-Json -Depth 30`; `-CustomParmsOnly` drills
   into `ScenarioRuntime.CustomParms`.
5. Emits `===== ORDER n : <DisplayName> =====` blocks to console and/or `-OutFile`.

## Notes

- **Read-only** — only SELECTs; never writes.
- Missing workflow/scenario code → clear error + non-zero exit.
- Decode failures (bad base64, unexpected prefix) print the raw value + error rather than crashing.
- Legacy `GZIP:` and plain (uncompressed) JSON are both handled.
- This is the executable counterpart to the `configuration-compression-codec` skill (codec
  reference) and the `reference_scenariomgt_db` memory (DB location).
