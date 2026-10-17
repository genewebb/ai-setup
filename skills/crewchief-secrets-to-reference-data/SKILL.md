---
name: crewchief-secrets-to-reference-data
description: >
  Moves non-sensitive values out of a CrewChief secrets file into reference data (reference-kv parent
  folders with logical sub-files) and rewrites workload/step tokens from {{$config:Section:Key}} to
  {{$ref:parent/sub:Key}}. Use when slimming a CrewChief secrets file, when importing workloads from
  another machine (SMVMTR2, SMVMTR3, a laptop) into a box whose secrets were already slimmed, when a
  workload fails on a missing $config key that now lives in reference data, or when adding a new secret
  and deciding whether it is sensitive.
---

# CrewChief: secrets to reference data

## The rule (Gene, 2026-10-15)

Secrets hold ONLY sensitive values:
- user ids and passwords
- API and REST keys, PATs, client ids and client secrets, private keys
- certificate thumbprints and keys, and file-share keys or tokens

Everything else is reference data:
- host, server and machine names, FQDNs and domains
- instance names and database names
- file-share NAMES
- REST URLs and their timeouts
- connection strings that use Windows authentication (Integrated Security). A connection string that carries a user id and password stays a secret.
- paths

**Define once.** The secrets file keeps `{{Section:Key}}` internal references, so a shared value is written once.

Reference data is NOT re-expanded at run time: `{{$ref:...}}` returns the stored text as-is, in a single pass. So define-once for reference data happens at BUILD time. The source keeps the references, and the build script expands them into literal values.

**Pointers.** Each secret that belongs with reference data carries a section-level `referenceData` attribute, shaped `{ "<secret key>": "<parent>/<sub>:<key>" }`, for example `RestClients` → `"Connect:ApiKey": "rest-urls/rest-clients:Connect:BaseUrl"`.

CrewChief's secrets schema (`SecretSchema.Validate`) ignores unknown section attributes, so the file still imports. Showing the pointers in the secrets UI is future work.

## Layout

```
<data>\reference-kv\
  target-machines\  machine-names, domains, server-names, instance-names, file-shares
  database\         database-names, connection-strings
  rest-urls\        rest-clients (Client:BaseUrl, Client:TimeoutSeconds), external-links (not in replacements), service-providers
  crewchief\        web-host, paths, links (CrewChief's own settings)
```

**Placement rule: the type always wins.** A database name goes to `database\` even when only connect uses it. Every Profisee server goes to `target-machines\`.

`connect-run-settings.json` and the other top-level types stay where they are.

Token form: `{{$ref:target-machines/server-names:ApplicationServerName}}`. The `$ref` grammar takes everything up to the first colon as the type, so nested keys keep their colons: `{{$ref:rest-urls/rest-clients:Connect:BaseUrl}}`.

> [!important] Subfolders need the CrewChief change
> CrewChief only reads reference-data types in subfolders once the store and the Reference Data page support folders. That change was approved 2026-10-15. Until that build is deployed:
> - the subfolder files sit on disk, invisible;
> - a `{{$ref:parent/sub:key}}` token does not resolve;
> - so do NOT rewrite live workloads before then.
>
> The same build must also move CrewChief's own by-name reads to reference data: `WebUI:HostName`, `WebUI:ExecutionMachine`, `Documentation:RepoBrowserBaseUrl`, `Profisee:CLU:Path`, `DirectoryPaths:ScriptDirectory`, the Home page `ServerNames` strip, the `RestClients:Connect:BaseUrl` ConnEx fallback, and bare-name `ConnectionStrings:<name>` lookups.

## Tools ({PowershellScriptsDir}\CrewChiefConnect)

| Script | Does |
|---|---|
| `Build-ConnectReferenceData.ps1 -OutputFolder <reference-kv> [-RealSecretsFile <secrets.json>]` | Reads the secrets-format source (default: the masked `{SecretsDir}\crewchief-connect-secrets-structure.json`). It then:<br>- writes the reference-data files, and refuses to overwrite one unless `-Force`;<br>- writes the slim secrets file, with masked values kept masked and pure `{{Section:Key}}` values shown;<br>- writes the token map `connect-reference-map.json`.<br>`-RealSecretsFile` is read only for masked-but-not-sensitive values (`ConnectRuntime:ProfiseeDBName`, `UserCredentials:AzureFileShareName`). Never prints a secret. |
| `Convert-WorkloadSecretsToReference.ps1 -DataFolder <data> [-Include workloads\x] [-Apply]` | Rewrites `{{$config:<moved key>}}` to `{{$ref:...}}` from the map. It is report-only by default. With `-Apply` it backs up every changed file and then fails if any moved key is still referenced. |

The mapping lives in `Get-Target`, `$ReferencePointers` and the configuration bindings inside `Build-ConnectReferenceData.ps1`. Change it there, never in the outputs.

**Real slim secrets file.**
1. `Build-ConnectSecrets.ps1` builds the FULL file.
2. `Build-ConnectReferenceData.ps1 -SourceFile <full> -RealSecretsFile <full> -OutputFolder <staging> -ProposedSecretsFile <box>_..._crewchief.slim.json` writes the slim file. It holds real secrets, so never print it.
3. Diff the staging reference data against the box. It must show 0 differences.

**Folder pane.** The Reference Data page has the same folder pane as Steps and Workloads. Because a type's folder is part of its name, moving a type or a folder there renames it and rewrites its `{{$ref:...}}` tokens and configuration-bindings values. Prefer the pane over hand-moving files: hand-moving rewrites nothing.

**Built-in names.** A type file may carry `"builtIn": "<name>"` (and `"description"`). The store resolves that name to the type in whatever folder it sits, so code, secrets pointers, configuration bindings and `{{$ref:<name>:key}}` tokens keep working after a move with no rewrite. CrewChief's own types (`ReferenceDataSets.BuiltInUses`) always have theirs (implied for an unmarked file at the root name, stamped before its first move) and it is fixed. Operators tag their own in the editor (Details, Tag as built-in); names are unique and CrewChief's are reserved. For anything a secrets pointer must reach, give the type a built-in name and write the pointer/token with it, not the folder path. Export/import carries both fields. The page is list `/reference-data` plus editor `/reference-data/edit/<type or built-in name>`.

**CrewChief side** (speed-merchants, 2026-10-15):
- `KeyValueReferenceStore` accepts folder type names (`KebabName.IsValidPath`).
- `ReferenceDataConfigurationSource` exposes `crewchief/configuration-bindings` under the by-name configuration keys:
  - it sits between appsettings and secrets, so a key still in secrets wins;
  - it reloads on Reference Data page writes.
- A `{{$config:ServerNames:...}}` or `{{$config:ConnectionStrings:...}}` token keeps resolving through those bindings. Other moved sections (`DatabaseNames`, `ProfiseeNames`, `MachineNames`) do NOT, so rewrite them.

## Procedure: imported (non-connect) workloads

Use this after Gene imports workloads from SMVMTR2, SMVMTR3 or a local machine.

1. **Confirm the target box runs the CrewChief build with reference-data subfolders.**
   - Check that its Reference Data page lists `target-machines/server-names`.
   - If it does not, stop.
2. **Back up the data folder's `workloads` and `steps`.**
3. **Check the imported secrets.** If the source machine's secrets have keys the box's slim secrets file lacks, add them:
   - sensitive keys to secrets;
   - everything else to the build-script mapping.

   Then rebuild with `-Force` into a STAGING folder, diff it, and copy it over.
4. **Run the rewrite report-only:** `Convert-WorkloadSecretsToReference.ps1 -DataFolder <data> -Include 'workloads\<imported folder>','steps'`. Review the per-key list.
5. **Re-run with `-Apply`.** Then `crewchief validate all` on a COPY of the data folder.
   - validate shows only the FIRST missing reference per workload. For the full list, statically diff every `{{$config:...}}` and `{{$ref:...}}` token against the secrets keys and the reference-kv entries.
6. **Gene runs one workload from the imported folder** as the smoke test.

## Procedure: connect workloads

They are generated, so fix `New-ConnectWorkloads.ps1` to emit `{{$ref:...}}` for every moved key. Then:
1. dry-run into a scratch data folder;
2. hash-diff against live;
3. run `Convert-WorkloadSecretsToReference.ps1` report-only on the OUTPUT. It must report 0 tokens;
4. deploy.

Do not hand-rewrite generated files: the next generation reverts them.

## Never

- Print a secret value, or a Profisee gateway 401 body (it echoes the API key).
- Write reference data over an existing type file. The build refuses without `-Force`; stage and diff first.
- Import the slim secrets file while any workload on the box still uses a moved `{{$config:...}}` key.
- Put a value that depends on a secret into reference data. The build throws when a reference value references a masked key.
