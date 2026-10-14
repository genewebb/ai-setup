
Repo: speed-merchants (paths below are repo-relative)

# Source Files

Reference for the `crewchief-remote-box-prep` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Sources
- `CrewChief\CrewChief.Engine\Executors\DefaultRemoteCommandRunner.cs`
- `CrewChief\CrewChief.Engine\Executors\IRemoteCommandRunner.cs`
- `CrewChief\CrewChief.Engine\Executors\RemoteWindowsOps.cs` (op-script layer for the service/app-pool/IIS credentialed paths + `BuildFileBrowseScript`)
- `CrewChief\CrewChief.Engine\Executors\IRemoteFileBrowser.cs` + `CrewChief.Web\Components\Controls\FileBrowserDialog.razor` (design-time remote Browse consumer)
- `CrewChief\CrewChief.Engine\Services\IRemoteCredentialResolver.cs`
- `CrewChief\CrewChief.Engine\Executors\InstallExecutor.cs` + `Steps\InstallStep.cs`
- `CrewChief\CrewChief.Engine\Executors\UninstallExecutor.cs` + `Steps\UninstallStep.cs`
- `CrewChief\CrewChief.Engine\Executors\ConfigureExecutor.cs` + `Steps\ConfigureStep.cs`
- `CrewChief\CrewChief.Engine\Executors\IisResetExecutor.cs` + `Steps\IisResetStep.cs`
- `CrewChief\CrewChief.Engine\Executors\ServiceControlExecutor.cs` + `Steps\ServiceControlStep.cs`
- `CrewChief\CrewChief.Engine\Executors\AppPoolExecutor.cs` + `Steps\AppPoolStep.cs`
- `CrewChief\CrewChief.Engine\Executors\IProcessRunner.cs`, `ElevationStatus.cs`
- `CrewChief\CrewChief.Engine\Executors\IProductInstallRunner.cs` (`InstallAsync(IReadOnlyList<string>)`, `SplitArguments`)
- `CrewChief\CrewChief.Engine\Executors\IInstalledProductInventory.cs` + `IProductUninstallRunner.cs` (`InstalledProduct.InstallLocation`)
- `CrewChief\CrewChief.Engine\Executors\MapShareExecutor.cs` (the single `IsLocalTarget` implementation, `:296`; local-only MapShareStep guard `:101-106`)
- `CrewChief\CrewChief.Engine\Executors\ShareCredential.cs` (`ShareCredentialType`, `ShareMount`) + `ShareCredentialResolver.cs` (`IShareCredentialResolver`, `ShareRoot`)
- `CrewChief\CrewChief.Tests.Unit\Engine\IsLocalTargetTests.cs`
- `CrewChief\CrewChief.Engine\Orchestration\UtilityOrchestrator.cs` (~545–630 validation)
- `CrewChief\CrewChief.Engine\EngineServiceCollectionExtensions.cs` (lines 49–50 inventory, 70 resolver / 74 runner)
- `CrewChief\CrewChief.Web\Documentation\43_OpsRemoteBoxPrep.md` (§5 CredSSP what/why/how)
- `CrewChief\CrewChief.Tests.Integration\Engine\RemoteCommandRunnerIntegrationTests.cs`
- `CrewChief\CrewChief.Tests.Integration\Engine\CredentialedRemoteOpsIntegrationTests.cs` + `CrewChief.Tests.Integration\TestHelpers\IntegrationConfig.cs`
- `CrewChief\CrewChief.Tests.Unit\Engine\RemoteWindowsOpsTests.cs`, `CrewChief.Tests.Unit\Engine\RemoteCredentialResolverTests.cs`, `CrewChief.Tests.Unit\Engine\InstalledProductInventoryTests.cs`
