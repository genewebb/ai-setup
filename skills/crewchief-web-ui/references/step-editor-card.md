# The Mega StepEditorCard and the Configure Step Wizard

Reference for the `crewchief-web-ui` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## The mega `StepEditorCard` (`Controls/StepEditorCard.razor.cs` 2093 lines + `.razor` 2258 lines, as of 2026-07-27)
One code-behind renders **every** step type's field editor. It does NOT use TestAuto's
enum-editor-routing model — instead it dispatches with `Step is XxxStep` pattern-match branches
(and typed casts like `((HttpRequestStep)Step).Method`) directly against the concrete step classes.
- **Bound step**: `[Parameter, EditorRequired] UtilityStepBase Step` + `EventCallback<UtilityStepBase>
  StepChanged`; every edit calls `NotifyChangedAsync()`. Step params are `Step.Parameters`
  (`Dictionary<string,string>`), accessed through `StepParameters` which null-coalesces so a JSON
  round-trip with `"parameters": null` never NREs.
- **Inline "Test"** (gated by `[Parameter] EnableInlineExecute = true`): runs the current (even
  unsaved) step as a **one-step scenario** via `IUtilityOrchestrator.ExecuteScenarioAsync`, wrapped
  in `Task.Run` so a synchronous executor never blocks the render thread. Before running,
  `FindMissingTokens()` scans the serialized step for `{{token}}`s unresolved by step params +
  `GlobalParameters` + `$config:`/`$env:`; any missing tokens open a **token-prompt dialog** whose
  values overlay the globals for that run. Results/output render in an in-card panel
  (`TruncateOutput`, capped by `CrewChief:MaxStepOutputChars`, **default 100000** — the code fallback
  is `StepEditorCard.razor.cs:2084`, matching `Web/Program.cs:276`, `Cli/Program.cs:106`, and the
  `100000` shipped in `CrewChief.Web/appsettings.json:47` + `CrewChief.Cli/appsettings.json:6`. Two
  DeveloperPack markdown files still say 20000; they are stale — the four live values agree on 100000).
- **Edit-time warnings**: `UnresolvedTokens()` (serializes the step, calls
  `TextTemplater.ValidateTokens`), `StepReadinessIssues()` (unresolved-token count + an
  elevation warning when `Step.Type ∈ ElevationStepTypes` and `!ElevationStatus.IsElevated`).
  `ElevationStepTypes` = ServiceControl/AppPool/Install/Uninstall/Configure/IisReset (both canonical
  and short aliases). Advisory only — never blocks editing.
- **Live remote enumeration**: ServiceControl uses `IRemoteServiceInventory.GetServicesAsync`;
  AppPool uses `IRemoteAppPoolInventory.GetAppPoolNamesAsync`. **Both signatures now take a
  `RemoteCredential?`** (in addition to the machine): the card resolves a design-time credential via
  `CredentialResolver.Resolve(ResolveCredentialRef(step.CredentialSecretName))` and passes it, so a
  non-null credential enumerates over the credentialed WSMan path (works when CrewChief runs as
  LocalSystem) while a null credential keeps the legacy ambient-identity path. The card injects
  `IRemoteCredentialResolver` for this. A failure leaves the free-text/textarea fallback usable and
  surfaces an error string (WinRM 5985/5986 + admin-rights guidance). There are also design-time
  SQL/endpoint "Test" buttons (`IConnectionTester`/`IEndpointTester`) and a server-side
  `FileBrowserDialog` for Install MSI / Configure exe/license paths — see "Remote Browse…" below.
- **Design-time target/credential helpers** (`.razor.cs:129` and `:161`): `ResolveTargetMachine` resolves
  a target field and returns null for a local machine (via `MapShareExecutor.IsLocalTarget`, so
  local targets skip WSMan); `ResolveRunAsCredential` builds a `RemoteCredential?` from the
  two-field User/Password pair (`CredentialResolver.Resolve(ResolveValueRef(user),
  ResolveValueRef(password))`) with a fallback to the legacy flattened `credentialSecretName`.
  Every design-time remote call (enumeration, version picker, Browse) goes through this pair.
- **Authentication picker** (all 6 remote step editors — ServiceControl/AppPool/Uninstall/Install/
  Configure/IisReset): a plain `<select class="form-select">` bound to `step.RemoteAuthentication`
  with options `""` = "Default (Kerberos)", `Negotiate`, and `CredSSP` ("CredSSP (double-hop)"),
  plus help text explaining CredSSP delegation (`Enable-WSManCredSSP` on both machines). The
  values map to the engine's `RemoteAuth` enum via `RemoteAuthParser.Parse`
  (`CrewChief.Engine/Executors/IRemoteCommandRunner.cs`) — every executor parses the (tokenized)
  string the same way. See [[crewchief-remote-box-prep]].
- **Installed-Profisee-version picker** (Configure): `IInstalledProductInventory`
  (`CrewChief.Engine/Executors/IInstalledProductInventory.cs`) enumerates installed products —
  local registry Uninstall keys, or `RemoteWindowsOps.BuildInstalledProductsScript` over the
  credentialed WSMan transport for a remote target. `LoadProfiseeVersionsAsync` fetches products
  containing "Profisee"; `OnProfiseeVersionPicked` calls `ResolveConfigurationExeAsync`
  (InstallLocation hint → standard Profisee folder → bounded search; robust when the registry
  InstallLocation is blank) and autofills `ConfigurationExePath` read-only; `EditConfigureExeManually`
  drops back to a free-text path. Enumeration failures surface as an error string, never throw
  into the render (`InstalledProductInventoryException` carries the human-readable reason).
- **Remote Browse…**: `IRemoteFileBrowser`/`DefaultRemoteFileBrowser`
  (`CrewChief.Engine/Executors/IRemoteFileBrowser.cs`) runs `RemoteWindowsOps.BuildFileBrowseScript`
  over the WSMan transport **as the Run As credential**, so the editor's Browse dialogs (Install
  MSI, Configure exe/license) list target-side folders/files. The script folds in mapped drives a
  WinRM *network logon* can't see (per-session drive letters don't exist there): `Get-SmbMapping`,
  persistent mappings under `HKEY_USERS\<sid>\Network`, and Explorer "Network locations" (nethood)
  `.lnk` shortcut targets. Companion local path: `IServerFileBrowser.EnumerateRoots`
  (`IServerFileBrowser.cs:91-118`) includes network drives even when reported not-ready plus
  `HKCU\Network` persistent mappings (`PersistentMappedDriveRoots`) so mapped drives appear when
  CrewChief runs as a service. `FileBrowserDialog` gained `Machine` and `RemoteCredential? Credential`
  parameters — null machine = local browse.
  - **Drive Map wiring (2026-07-22)**: the dialog also injects `IKeyValueReferenceStore` —
    `DriveMapEntries()` reads `ReferenceDataSets.DriveMap` once per dialog open (cached; store
    errors swallow to an empty map) and flows into `IRemoteFileBrowser.ListAsync(machine,
    credential, path, filePattern, driveMap, timeoutSeconds, ct)`. On the target this appends the
    map's UNCs to the roots view, translates typed drive-letter paths (`S:\…` → UNC — session drive <!-- example-path -->
    letters don't exist for a WinRM network logon), and turns an unresolved path into a
    self-diagnosing "Path not found from this remote session…" error ("No Drive Map entry found
    for X:" vs "translated to \<UNC\> but not accessible: \<exception\>") instead of PowerShell's
    baffling "A parameter cannot be found that matches parameter name 'Directory'". The hint text
    tells the operator to set a letter's UNC under **Reference Data → Drive Map**. Full mechanics
    (embed rules, Test-Path guard order, the `-Directory` dynamic-parameter explanation, Azure
    Files auth caveat, `BuildFileBrowseScript_*` tests) live in [[crewchief-remote-box-prep]] —
    reference, don't duplicate.
- **`ResolveConfigRef`** (design-time **host** resolution) resolves **both** `{{$config:Section:Item}}`
  (via `IConfiguration` indexing) **and** `{{$ref:server-names:Key}}` (via the reference store); a
  blank/unresolved value returns null so enumeration falls back to the local machine.
- **`ResolveCredentialRef`** (design-time **credential** resolution — distinct from `ResolveConfigRef`)
  uses a generic `AnyRefRegex` to resolve a `{{$ref:type:key}}` of **any** ref type to the entry's
  value (the secret path), while a `{{$config:...}}` picker form and plain text pass through unchanged
  (the credential resolver strips the wrapper itself). This is what lets the credential field's three
  editor modes each map to a User/Password pair at design time. See [[crewchief-remote-box-prep]].
- **ConnEx artifact file-vs-inline toggle**: `_useFile` selects file vs inline JSON;
  `OnConnExArtifactToggleChanged` **stashes** the inactive field (`_stashedArtifactJson` /
  `_stashedArtifactFile`) and clears it on the step, restoring on toggle-back — so a glance at the
  other mode never silently empties the box.
- **SetApiKey destination editor** (`.razor:1844-1943`, the `else if (Step is SetApiKeyStep setApiKeyStep)`
  branch): `ServerNameEditor` for **SQL Server Name**
  + a plain token-friendly **Database Name** input, a **"Use Windows authentication"**
  `RadzenSwitch` (On = Windows account, Off = SQL login; writes `AuthMode` "Windows"/"Sql" — same
  model as the Database Operations step), a credential pair (`CredentialUserId`/`CredentialPassword`,
  labeled SQL User ID/Password or optional Windows User ID/Password per the switch), and a
  `<details>` **"Advanced: connection override (full connection string)"**
  (`SqlDestinationConnectionSecretName` — overrides Server/Database when set; auto-opens when
  populated; has a design-time "Test connection" button). Username, API Key, both credential fields,
  AND the override all use the **unrestricted three-mode `SecretValueEditor`** — `SecretOnly` was
  dropped from every SetApiKey field, so literal / secret pick / reference data are all valid. A
  `HasTarget` guard renders "A destination is required" when neither Server+Database nor the
  override is set.
- **Reorderable step parameters (rebuilt in order)**: each Step Parameters row has **four** move
  buttons — to-top / up / down / to-bottom, mirroring the WorkloadEditor card toolbar:
  - `MoveParameter(key, ±1)` (`.razor.cs:638`) — single-position nudge.
  - `MoveParameterToTop(key)` / `MoveParameterToBottom(key)` (`.razor.cs:656` / `:662`) — thin wrappers
    over the shared `MoveParameterToEdge(key, toTop)` (`.razor.cs:664`), a **no-op** when the key is
    missing or already at that edge. Markup wires them at `.razor:2114` / `:2126`, `disabled` bound to
    `isFirst` / `isLast` so the end buttons grey out.

  `MoveParameter`, `MoveParameterToEdge`, `RemoveParameter`, and `RenameParameter` all route the
  `Step.Parameters` `Dictionary<string,string>` through `RebuildOrderedParameters` (`.razor.cs:688`) —
  a fresh case-insensitive dictionary whose enumeration order equals the new row sequence, so
  **display order == persisted JSON order**. `RenameParameter` (`:599`) rebuilds **in place** so a
  renamed row keeps its position (it used to jump to the end); `RemoveParameter` (`:621`) rebuilds so a
  later add appends rather than reusing the freed slot mid-list. Purely organizational — token
  resolution never depends on order.
- **Global-parameter mirrors**: the **WorkloadEditor Global Parameters** grid carries the identical
  four-button mechanism against `_workloadFile.GlobalParameters` — `MoveGlobalParameter`
  (`WorkloadEditor.razor.cs:642`), `MoveGlobalParameterToTop` / `…ToBottom` (`:659` / `:665`) over
  `MoveGlobalParameterToEdge` (`:667`), and its **own** copy of `RebuildOrderedParameters` (`:690`);
  markup at `WorkloadEditor.razor:172` / `:184`. The two `RebuildOrderedParameters` are duplicated
  private statics, not a shared helper — **change both** when touching the ordering contract.
- **Database Operations editor** (`DatabaseOperationsStep` branch): beyond the `AuthMode` Windows/SQL
  switch it has two extra `RadzenSwitch`es — **"Relocate & rename files"** (`RelocateFiles`,
  RestoreDatabase-only — move restored files to default folders + rename to match when restoring
  under a new database name) and **"Wait indefinitely (no timeout)"** (`WaitIndefinitely` — drop the
  command timeout for a long restore). The executor-side behavior is in [[crewchief-step-executors]].

### The Configure step WIZARD (`.razor.cs:1480-1956`, `.razor:1415-1843`)
Code-behind anchors: `// ───── Configure ─────` region starts `.razor.cs:1480`;
`BuildConfigurePreview` `:1529`; `ConfigSwitchPageLayout` `:1700`; `ConfigureEditorTabs` `:1800`;
`ConfigStepIndex` `:1823`; `SwitchPrefillValue` `:1888`. (A **separate** Install-step wizard, deliberately
kept in its own state so the two never collide, lives at `.razor.cs:1289`+ / `.razor:1222`+.)
The Configure editor is a **multi-page wizard** (like the matching wizard: a handful of purpose-built
steps, not one tab per catalog micro-group), styled by `cc-wizard-*` classes in `StepEditorCard.razor.css`.
- **Switch pages**: `ConfigSwitchPageLayout` (static tuple array) declares four pages — `sql`
  ("SQL / Database"), `web` ("Web & IIS"), `auth` ("Authentication"), `integrations` — each composed
  from `(Title, Group, SubGroup)` parts against the live `ConfigurationSwitchCatalog.ByGroup`
  (a null SubGroup takes the whole group). `ConfigureSwitchPages` materializes them as
  `ConfigSwitchPage`/`ConfigSection` records; `licenseFile` is excluded (dedicated License page)
  and Mode switches render on the Advanced page via `ConfigureModeSwitches`.
- **Steps**: `ConfigureEditorTabs` = Settings / Target & Run As / License / the 4 switch pages /
  Advanced (one-shot modes + raw `Arguments`) / Review — switch pages badge their **enabled-switch
  count** (`ConfigEditorTab.Count`). Nav: `ConfigStepIndex` (clamped — the list can shrink),
  `ConfigGoToStep` (step-indicator click), `ConfigNextStep`/`ConfigPreviousStep`;
  `ConfigStepClass` styles active/completed indicators.
- **Review page**: `ConfigureReviewGroups` (enabled switches grouped by page label, Modes under
  "Advanced (Modes)"), `ConfigureReviewValue` (secrets show `••••••••` unless the value is a
  `{{token}}`), and stat tiles `ConfigureEnabledSwitchCount`/`ConfigureEnabledSecretCount`.
  `BuildConfigurePreview(reveal)` builds a **copy-paste PowerShell command** (`& "exe"` +
  `/switch:"value"` in name order + raw args, backtick line continuations), resolving
  `{{$config:...}}`/`{{$ref:...}}` to design-time values via `ResolveTokenValue` and masking
  `IsSecret` switches unless `reveal`; `CopyConfigurePreviewAsync` copies it via
  `navigator.clipboard.writeText`. Run As is deliberately NOT part of the command — the operator
  runs it directly on the target.
- **CAUTION**: the preview *resolves then quotes*, while the runtime originally *quoted then
  resolved* — the preview could look right while the real command line was broken. Both now resolve
  first: `ConfigureExecutor` calls `ComposeArgumentString(v => ApplyTokens(v, parameters))`
  (`ConfigureStep.ComposeArgumentString(Func<string,string>? resolveValue)` applies the resolver
  per-value before quoting). Keep them aligned when touching either side.
- **Switch enable/prefill**: enabling a switch adds its key to `ConfigureStep.Switches` prefilled
  from `SwitchPrefillValue` (`.razor.cs:1888`: `configuration-template` reference-data set
  (`ReferenceDataSets.ConfigurationTemplate`) → catalog seed → "FALSE"/empty); disabling removes
  the key entirely. The default-value teal tint compares against the same `SwitchPrefillValue`.
  See [[crewchief-reference-data]].
