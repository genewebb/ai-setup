# Installed-Product Inventory, Elevation Readiness, and Tests

Reference for the `crewchief-remote-box-prep` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Remote installed-product inventory

`Executors/IInstalledProductInventory.cs` — `IInstalledProductInventory` / `DefaultInstalledProductInventory` enumerates installed products (`InstalledProduct { ProductCode, DisplayName, InstallLocation }` — `InstallLocation` comes from the Uninstall key and lives on the type in `IProductUninstallRunner.cs:23-24`) and resolves a `Configuration.exe` path on a target:
- **Local** target → reads the 64/32-bit Uninstall registry keys in-process.
- **Remote** target → runs `RemoteWindowsOps.BuildInstalledProductsScript()` / `BuildResolveConfigurationExeScript(hint)` over the credentialed WSMan transport; a missing Run As credential throws `InstalledProductInventoryException` ("…requires a Run As credential (User ID / Password)", `IInstalledProductInventory.cs:90,138`) — unlike the executors, this service throws (the UI catches it).
- **Consumers**: `UninstallExecutor` uses the same builders inline for its remote name→code resolution; `StepEditorCard` uses the service for the installed-Profisee-version picker and Configuration.exe auto-locate.
- **DI**: `EngineServiceCollectionExtensions.cs:57-58` registers `IInstalledProductInventory → DefaultInstalledProductInventory(IRemoteCommandRunner)`.
- Unit-tested with a fake runner in `InstalledProductInventoryTests.cs`.

## Elevation readiness

`Executors/ElevationStatus.cs` — `ElevationStatus.IsElevated` computes once (cached) whether the process runs as a Windows administrator (`WindowsPrincipal.IsInRole(Administrator)`; non-Windows/failure → false). It is advisory: the editor's per-step readiness badge warns when authoring a step type that needs elevation (e.g. IisReset, install) on a non-elevated app. It does not block execution.

## Testing

The concrete transport is covered by a **RemoteLab-gated** integration test: `CrewChief.Tests.Integration/Engine/RemoteCommandRunnerIntegrationTests.cs`. Two tests exercise the fail-fast guards with no infrastructure (unreachable `.invalid` host → "not reachable"; null credential → "credential"). The `[TestCategory("RemoteLab")]` test touches a real WinRM host only when `CREWCHIEF_REMOTE_TEST_HOST`/`_USER`/`_PW` are configured (via `IntegrationConfig`), else `Assert.Inconclusive` keeps the suite green. The credentialed service/app-pool paths add `CredentialedRemoteOpsIntegrationTests.cs` (same RemoteLab gate; a Spooler Stop→Start roundtrip proves control rights, credential sourced explicitly OR from the real Local Secrets store via `CREWCHIEF_REMOTE_TEST_CRED_SECRET`). The pure `RemoteWindowsOps` builders/parsers are covered infra-free by `RemoteWindowsOpsTests.cs`. Executor decision logic is unit-tested against a fake `IRemoteCommandRunner`. See [[crewchief-testing]].
