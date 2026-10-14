---
name: crewchief-file-persistence
description: >
  Files-only persistence conventions for CrewChief (per-entity JSON stores, the single shared runs.json history, and Newtonsoft DTO rules). Use when the broken-file stub doctrine and the IsUnreadable check every caller owes before judging, saving or running a workload, the nested folder segment in the on-disk path and the TWO-part path-traversal guard (FolderPath.ResolveUnder, not the kebab check), reading/writing StepFileStore, WorkloadFileStore, or RunHistoryFile, adding a persisted entity or DTO, renaming a step or workload, changing the on-disk file layout, the recycle-bin soft-delete of a step (the StepFileStore useRecycleBin flag), the every-entry-must-be-Inline save invariant and the LegacyWorkloadRefGuard load refusal, or diagnosing atomic-write / cross-process-lock / truncation / kebab-name behavior.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief File Persistence

CrewChief is a standalone .NET 10 files-only step/workload tool (no DB, no TestAuto refs; Newtonsoft + Serilog). All durable state is JSON on disk under a configured `<dataFolder>`. There are two persistence shapes:

1. **Per-entity file store** — one `<kebab-name>.<kind>.json` file per entity (`StepFileStore` → `steps/`, `WorkloadFileStore` → `workloads/`).
2. **Single-file run history** — every `RunRecord` in one `runs.json` array (`RunHistoryFile`).

This is CrewChief's counterpart to TestAuto's DB-backed stores. See [[dotnet-sql-data-access]] for the DB world CrewChief deliberately does NOT use.

## When to Use
- Adding or editing `StepFileStore`, `WorkloadFileStore`, or `RunHistoryFile`.
- Introducing a new persisted entity type or a new Newtonsoft DTO for CrewChief.
- Changing the on-disk file layout, filename convention, or serializer settings.
- Diagnosing atomic-write, corruption-recovery, kebab-name/path-traversal, or cross-process-lock behavior.
- Deciding where step-output truncation must happen (there is exactly one place).

## Per-entity file store conventions
`StepFileStore` and `WorkloadFileStore` are near-identical by design; treat the pattern as one:

| Aspect | Rule |
|---|---|
| File path | `<dataFolder>/<kind>/[<folder>/...]<name>.<kind>.json` — steps → `steps/**/*.step.json`, workloads → `workloads/**/*.workload.json`. **An optional nested folder segment sits between the kind and the name** (added 2026-09-01); enumeration walks `SearchOption.AllDirectories` via `LibraryFolderIndex.Build`, and `StepFileStore` builds the path as `Path.Combine(FolderPath.ResolveUnder(_stepsFolder, folder), name + FileSuffix)`. See [[crewchief-library-folders]]. |
| Key | The kebab-case `Name` IS the key AND the filename stem — Get/Save/Delete/Rename round-trip by name alone |
| Name validation | Regex `^[a-z0-9]+(-[a-z0-9]+)*$` via `IsValidName`; blank/non-kebab rejected |
| Path-traversal guard | **TWO checks, and the second is the load-bearing one.** The name kebab check alone WAS the entire guard until folders existed; `FolderPath.cs:11-17` states that once a folder joins the path "that is no longer sufficient". Every folder argument now passes through `FolderPath`: each segment is kebab-validated, **and `FolderPath.ResolveUnder` additionally asserts the resolved path still sits inside the library root** — described in-source as "the one that holds even if the grammar is later relaxed — do not drop it." Do not treat the kebab check as the guard. |
| Atomic write | Write to `<path>.tmp`, then `File.Move(tmp, path, overwrite: true)` — never leaves a half-written file |
| Concurrency | DI **singleton** shared across Blazor circuits; all I/O serialized behind a coarse `_sync` `lock` (correctness over throughput for v1) |
| Tolerant reads | `GetAll` skips a malformed file and logs `Log.Warning`; `Get` returns `null` on a read/parse failure |
| `AllTags()` | Delegates to `GetAll()` (takes the lock once); distinct, ordinal-sorted |

### Rename
Both stores expose `Rename(oldName, newName)` (mirrored on `IStepFileStore`/`IWorkloadFileStore`):
- **Kebab-validates BOTH names** (`ArgumentException`); `oldName == newName` (ordinal) is a silent no-op.
- **Refuses, under the lock**: throws `InvalidOperationException` if the old file does not exist OR the target name already exists — never overwrites an existing entity.
- **Keeps identity in sync**: loads the old file, rewrites the embedded `.Name` to `newName` (name IS the key, so file stem and content must agree), writes the new file atomically (`.tmp` + `File.Move` with `overwrite: false` — unlike `Save`'s `overwrite: true`, belt-and-braces on the exists check), then deletes the old file with a plain `File.Delete` (StepFileStore's recycle-bin `Delete` option is not used here).

`IStepFileStore.Rename` moves ONLY the step's own file — and that is now the whole story. **There is no workload follow-up call.** Workload entries hold an independent inline copy of the step, not a live reference, so renaming a library step cannot affect any workload. The old `WorkloadFileStore.UpdateStepReferences(oldStepName, newStepName)` was deleted along with `WorkloadStepEntry.Ref`; the identifier has **zero hits repo-wide**, so do not go looking for it or pair `Rename` with anything.

### Soft-delete via Recycle Bin (`StepFileStore` AND `WorkloadFileStore`)
Both stores take the same **ctor flag** — `StepFileStore(string dataFolder, bool useRecycleBin = false)` and `WorkloadFileStore(string dataFolder, bool useRecycleBin = false)`. Both real composition roots opt BOTH in: Web (`CrewChief.Web/Program.cs`) and CLI (`CrewChief.Cli/Program.cs`) register `useRecycleBin: true` — the default `false` is for tests, so a test never touches the shell.
- `Delete(name)` (after the kebab-guard + existence check) prefers `RecycleBin.TrySend(path)` when the flag is set, so an operator-deleted step or workload lands in the **Windows Recycle Bin** (recoverable) rather than vanishing.
- `RecycleBin.TrySend` (`CrewChief.Data/Stores/RecycleBin.cs`, internal, ONE copy shared by both stores) = `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(path, OnlyErrorDialogs, RecycleOption.SendToRecycleBin)`. It is **Windows-only** (returns `false` immediately off-Windows) and wraps the shell call in try/catch — any failure logs `Log.Warning` and returns `false`.
- **Permanent-delete fallback**: when the flag is off, off-Windows, or the shell op returned `false`, `Delete` falls through to a plain `File.Delete(path)`. So a delete never fails just because the Recycle Bin is unavailable (e.g. no interactive session).
- **Rename does NOT use this** — the old file removed during `Rename` is always a plain `File.Delete` (its content lives on under the new name, so there is nothing to recover).

### Step-entry invariants live in Save, not the DTO
`WorkloadStepEntry` now has exactly two properties — `Inline` (the full step body as raw `JObject`) and `Label` (an optional per-instance display rename). The retired `Ref`/`Overrides` library-reference pair is gone; see [[crewchief-orchestration]] for the materialize-on-add model.

`WorkloadFileStore.Save` calls `ValidateStepEntries` (`WorkloadFileStore.cs:229`) and throws `ArgumentException` when an entry breaks the one remaining contract:
- **Every entry must carry an `Inline` body.** There is no library reference to fall back on, so a body-less entry is an empty step that would run as a silent no-op.

The `WorkloadStepEntry` DTO itself carries no validation — the store is the single enforcement point. (`StepFileStore.Save` has no equivalent entry validation; it only validates the kebab name.)

**The load side has its own, separate guard.** `ReadWorkload` (`:113-121`) parses the file to a `JObject` and runs `LegacyWorkloadRefGuard.ThrowIfLegacyRef(root, name)` **before** `ToObject<WorkloadFile>()`. This ordering is the point: Newtonsoft silently ignores unknown properties, so a legacy `{"ref": "..."}` entry would otherwise deserialize cleanly into an entry with a null `Inline` — and `Save`'s invariant only fires on write, not read. The guard throws `LegacyWorkloadRefException` naming the workload and the 1-based step number. `WorkloadTransferService` runs the same guard on bundle import.

### Serializer settings differ per store
- `StepFileStore`: `Converters = { new UtilityStepConverter() }` + `Formatting.Indented` — because `StepFile.Step` is a polymorphic `UtilityStepBase` (see [[crewchief-step-type-model]] / [[utility-step-polymorphic-deserialization]]).
- `WorkloadFileStore`: `Formatting.Indented` **only** — a workload's inline step bodies are raw `JObject`, so no converter is needed.
- `RunHistoryFile`: `Formatting.Indented` only.

## Single-file run history (`RunHistoryFile` / `IRunHistory`)
ALL `RunRecord`s live in one `<dataFolder>/runs.json` array (stored oldest-first; `GetAll` reverses to newest-first). Every mutating op is a whole-file read-modify-write. Because both the Web app and the CLI share this one file, it is guarded by **two** nested locks:

- **Cross-process named `Mutex`** — `BuildMutexName` = `"CrewChief_RunHistory_" + <SHA-256 hex of the normalized full runs.json path>`. Deliberately session-local (unprefixed, not `Global\`) so Web + CLI serialize within the interactive session — including across an elevation boundary — without needing `SeCreateGlobalPrivilege`.
- **In-process `_sync` lock** — nested inside the mutex, so concurrent Blazor circuits in the same process also serialize.

Other durability behaviors:
- **Atomic, collision-free write** — per-process/unique tmp name `<path>.<ProcessId>.<guidN>.tmp` (so two concurrent writers never collide on a shared `.tmp`), then `File.Move(overwrite)`. Last-writer-wins on content is expected/accepted.
- **`WithFileRetry`** — bounded retry (5 attempts, `20*attempt` ms backoff) on transient `IOException`/`UnauthorizedAccessException` (antivirus/indexer/concurrent-writer locks on Windows).
- **Corrupt-file rename-aside** — a `JsonException` on parse renames the file to `runs.corrupt-<utcTimestamp>.json`, logs a warning, and starts fresh. A *transient IO* failure that survives retries is NOT treated as corruption — it is re-thrown so the intact file is never renamed aside.
- **`AbandonedMutexException`** — a prior owner process that died without releasing is handled: the mutex is now owned, and the on-disk file is still consistent because writes publish atomically via `Move`.
- **Pruning + truncation** — `Append` prunes oldest beyond `_maxRunHistory` (front of the list = oldest). `TruncateStepOutputs` caps each step's `Output`/`Error` to `_maxStepOutputChars`, applied on both `Append` and `Update`. See the head+tail algorithm below.

### runs.json is the SINGLE truncation point for step output
Step `Output`/`Error` is truncated exactly here, in `RunHistoryFile.TruncateStepOutputs` → `Truncate`, before persistence. Do NOT add a second truncation upstream — executors deliberately capture uncapped output and let persistence own the cap (explicit comments to that effect in `ConfigureExecutor.cs` and `CurlExecutor.cs`). The SMTP notifier separately caps its own error *excerpt* at 500 chars for the email body — that is display-only, not the history truncation.

**The cap is head + tail, NOT a simple head cut.** This is the recurring error: a long tool log (a full `Configuration.exe` run, an MSI log) puts the *failure evidence at the END*, and the original head-only truncation cut exactly the part that mattered. The live algorithm (`RunHistoryFile.Truncate`):

- No-op when the text is null/empty or `Length <= _maxStepOutputChars`.
- Otherwise split the budget in half: `head = _maxStepOutputChars / 2`, `tail = _maxStepOutputChars - head` (tail takes the odd char).
- Result = first `head` chars **+ elision marker + last `tail` chars**.
- **Marker text (exact — U+2026 ellipses, surrounding newlines, and the omitted count):**
  `"\n… ({text.Length - _maxStepOutputChars} chars omitted) …\n"`

So the persisted string is slightly **longer** than the budget — budget plus marker. Any assertion must allow for the marker (the unit tests assert `<= max + 40`), and anything parsing persisted output must expect a marker line in the middle rather than a clean prefix.

`_maxStepOutputChars` comes from config key `CrewChief:MaxStepOutputChars`, **default `100000`** in both composition roots (`CrewChief.Web/Program.cs`, `CrewChief.Cli/Program.cs`) and both `appsettings.json` files. Some older in-repo DeveloperPack docs still say `20000` — stale; trust the code.

## Newtonsoft DTO conventions
Applies to `WorkloadFile`, `StepFile`, `RunRecord`, `WorkloadStepEntry` and any new persisted DTO:

- **`[JsonExtensionData] ExtraParms`** — `WorkloadFile` carries an open custom-parms bag (`IDictionary<string, JToken>`, `OrdinalIgnoreCase`): unknown top-level keys round-trip untouched on save. (`StepFile` has no such bag.)
- **`NullValueHandling.Ignore`** on initialized collections (`Tags`, `Steps`, `GlobalParameters`) — a hand-edited file with `"tags": null` keeps the initialized empty instance instead of NRE-ing downstream consumers.
- **The notes fields deliberately OMIT `NullValueHandling.Ignore`** — `WorkloadFile.GlobalParametersNotes`, `CredentialNotes` and `UtilityStepBase.Notes` are meant to serialize even when empty, so the key is DISCOVERABLE to somebody hand-editing the JSON. A deliberate exception to the rule above, not an oversight.
- **`StringComparer.OrdinalIgnoreCase`** dictionaries (`GlobalParameters`, `ExtraParms`); `WorkloadFile.GlobalParameters` also pins `ObjectCreationHandling.Reuse` (defensive, to preserve the comparer on deserialize).
- **`Formatting.Indented`** everywhere — files are meant to be human-readable and diff-friendly.

## The broken-file stub doctrine

`GetAll` **never throws for a bad file.** An unparseable workload - or the retired `ref`
library-reference shape - comes back as an **inert stub** carrying `Name` + `LoadError` + its `Folder`,
and **zero steps**.

The point: one bad file cannot take down the Workloads list, `crewchief list`, the Home counts or
`AllTags` - **yet the file stays visible**, so an operator can see and fix it.

The stub is **inert by contract**, and every consumer has to honour that:

| Consumer | Must |
|---|---|
| `Save` | **REFUSE** it - writing a zero-step stub would **truncate the real file** |
| The run coordinator | Refuse to run it |
| `ValidateCommand` | **Special-case it** - zero steps would otherwise reconcile **Green** as "No steps" |
| `ReferenceRenameService` | Skip-and-report it |

> **Any new caller that judges, saves or runs a workload must check `IsUnreadable` first.** This is not
> inferable from reading one file, and `WorkloadFile.IsUnreadable` is a different thing from the Web
> editor's per-step `IsUnreadable` - see [[crewchief-workload-and-runs]].

The same reasoning governs the **shadowed-copy** verdict from [[crewchief-library-folders]]: a shadowed
duplicate is listed, and Save-refused.

## Sources
- `CrewChief\CrewChief.Data\Stores\StepFileStore.cs`
- `CrewChief\CrewChief.Data\Stores\WorkloadFileStore.cs`
- `CrewChief\CrewChief.Data\Stores\IStepFileStore.cs`
- `CrewChief\CrewChief.Data\Stores\IWorkloadFileStore.cs`
- `CrewChief\CrewChief.Data\Stores\RunHistoryFile.cs`
- `CrewChief\CrewChief.Data\Models\WorkloadFile.cs`
- `CrewChief\CrewChief.Data\Models\WorkloadStepEntry.cs`
- `CrewChief\CrewChief.Data\Models\StepFile.cs`
- `CrewChief\CrewChief.Data\Models\RunRecord.cs`

## Related
- [[crewchief-workload-and-runs]] — the run/resume model and `RunRecord` lifecycle over runs.json
- [[crewchief-workload-transfer]] — cross-machine bundle export/import over these same stores
- [[crewchief-step-type-model]] — `UtilityStepConverter` polymorphic step serialization
- [[dotnet-sql-data-access]] — the DB counterpart CrewChief deliberately avoids
- [[json-formatting-conventions]]
- Memory: [[project_crewchief_standalone]]
