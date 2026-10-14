# File Conventions, Plugin Build, and Extending the Utilities Module

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Scripts/JsonData Folder — CURL & Body Files

The `TestAuto.Utilities/Scripts/JsonData/` folder stores reusable HTTP request files for MultiStep HTTP steps.

> ⚠️ **Authoring-time only — this is NOT a runtime file reference.** The Import Curl **File** mode (still live: `HttpRequestStepEditorCard.razor.cs:402` registers the `.curl`/`.json` browser extensions) reads the file **in the editor** and copies URL/method/headers/body **into the step's inline fields**. The saved step contains the inlined content; the `.curl` file is never read at execution time and the step has no `BodyFilePath`. Do not confuse this with the retired runtime `ScriptKey`/`BodyFilePath` mechanism — if the step "works in the editor but not at run time", the file is not the cause.

### File Standards

- **Extension**: All curl command files **must** use the `.curl` extension.
- **Format**: Files must contain curl commands in **Postman export format** (the output of Postman's Code → cURL option).

### Creating a `.curl` File

1. Build and test your request in Postman.
2. Click the **Code** button (`</>` icon) → select **cURL**.
3. Copy the entire command.
4. Save to a `.curl` file under `Scripts/JsonData/`.

Example Postman-format content:

```bash
curl --location 'https://{{$config:RestClients:Profisee:BaseUrl}}rest/v1/Records/MyEntity' \
--header 'Content-Type: application/json' \
--header 'x-api-key: {{$config:RestClients:Profisee:ApiKey}}' \
--data '[{"Code": "001", "Name": "{{EntityName}}"}]'
```

### Importing in the HTTP Step UI

1. In the HTTP step editor, click **Import Curl**.
2. Toggle between **Paste** (default) or **File** mode.
   - **Paste**: paste the curl command directly from Postman.
   - **File**: select a `.curl` file from the list or enter a custom path.
3. URL, method, headers, and body auto-populate.
4. Replace hardcoded values with `{{Token}}` placeholders.

### Token Substitution in Files

Both `.curl` and `.json` files support the same token syntax as inline configs:

| Token | Source |
|---|---|
| `{{$config:RestClients:Profisee:BaseUrl}}` | `appsettings.json` |
| `{{$config:RestClients:Profisee:ApiKey}}` | `appsettings.json` |
| `{{ParameterName}}` | Step or global `Parameters` dictionary |

### Build/Deploy Note

Files in this folder are automatically copied to the output and publish directories via MSBuild. After adding new files, **rebuild the application** to copy them to the runtime location (`.run/speed-merchants/Scripts/JsonData/`).

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| New `.curl` file not in file browser | File copied on build only | Rebuild/republish the application |
| `Invalid JSON: Expected end of string` with `'\''` | Postman's bash escape for literal single-quotes inside single-quoted strings | Parser strips this automatically on latest build; if it persists, verify build is up to date |
| Strange `???` characters in JSON | File saved with UTF-8 BOM | Parser strips BOM automatically; re-save without BOM in VS Code (File → Save with Encoding → UTF-8) |

---

## Plugin Build & Troubleshooting

`TestAuto.Utilities` is a **plugin assembly** — it is not referenced directly by the hosts. After changing any executor, DTO, or service, you must rebuild so that `CopyToHosts` copies the updated DLL into `TestAuto.Web/Plugins/`, `TestAuto/Plugins/`, and `TestAuto.Testing/Plugins/`.

**Stale-Plugins symptom**: Your change appears to have no effect. Step behavior is unchanged, or the new step type is unrecognized.

**Fix**: Build the full solution (or at minimum `TestAuto.Utilities`) so MSBuild runs the `CopyToHosts` target. Verify the DLL timestamp in `TestAuto.Web/Plugins/` matches your build.

---

## Adding a New Step Type (Checklist)

When adding a new step type to `TestAuto.Utilities`, complete all 8 steps:

1. **DTO** — Create `XxxStep : UtilityStepBase` in `Common/DTOs/` with `[JsonProperty]` names matching JSON (typically camelCase).
2. **Converter** — Extend `UtilityStepConverter.ReadJson` switch **and** `UtilityStepBase.CreateFromJToken` — keep them aligned or deserialization will silently break.
3. **Executor** — Implement `IStepExecutor` with a **unique** `StepType` string. Adding a duplicate `StepType` causes the last DI registration to silently override earlier ones (see CURL/HTTP note above).
4. **DI** — Register in `UtilitiesModuleRegistrar`: `services.AddTransient<IStepExecutor, XxxExecutor>();`
5. **Aliases** — Add any alternate JSON names via `UtilityOrchestrator.AddExecutorAlias(...)`.
6. **Metrics** — If the step needs richer metrics than `UtilityStepDetail`, extend `MultiStepUtilityScenario.ProcessBatchAsync` (see CLUStep/HttpRequestStep branches as examples).
7. **Sample** — Add an example JSON config to `Samples/`.
8. **Tests** — Add or extend tests in `TestAuto.Utilities.Tests`. Use full DI (`RegisterAllServices`) — not manually constructed services.

---

---

## Adding a Second Utilities Scenario Class

`MultiStepUtilityScenario` is currently the only scenario in `TestAuto.Utilities`. Adding a second requires:

1. New class implementing `IScenario` with the correct `[ScenarioTypes(...)]` attribute.
2. Plugin discovery is unchanged — same assembly, auto-discovered.
3. If the new scenario needs its own custom parms UI, add a new `CustomParmsEditorType` enum value and a corresponding Blazor editor component in `TestAuto.Web`.
4. Register any additional validators if the scenario uses `IValidationService`.

---

## Utilities Logging Quirk

Much of the utilities pipeline (orchestrator + several executors) logs under `LogTagConstants.SqlScript`, not a dedicated "Utilities" tag. When filtering logs, use the `SqlScript` tag to find orchestration and executor output.

---
