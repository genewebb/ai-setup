
Repo: speed-merchants (paths below are repo-relative)

# Source Files

Reference for the `crewchief-web-ui` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Sources
- `CrewChief\CrewChief.Web\Components\App.razor`
- `CrewChief\CrewChief.Web\Program.cs`
- `CrewChief\CrewChief.Web\Components\Controls\StepEditorCard.razor.cs`
- `CrewChief\CrewChief.Web\Components\Controls\StepEditorCard.razor`
- `CrewChief\CrewChief.Web\Components\Controls\StepEditorCard.razor.css`
- `CrewChief\CrewChief.Web\Components\Controls\SecretValueEditor.razor`
- `CrewChief\CrewChief.Web\Components\Controls\ServerNameEditor.razor`
- `CrewChief\CrewChief.Web\Components\Controls\ServiceNameEditor.razor`
- `CrewChief\CrewChief.Web\Components\Controls\FirstRunBanner.razor`
- `CrewChief\CrewChief.Web\Components\Pages\Templates.razor` (+ `.razor.cs`)
- `CrewChief\CrewChief.Web\Components\Layout\NavMenu.razor`
- `CrewChief\CrewChief.Web\Components\Controls\SegmentedToggle.razor` (+ `.razor.css`)
- `CrewChief\CrewChief.Web\Components\Controls\SegmentedOption.cs`
- `CrewChief\CrewChief.Web\Components\Controls\StepCard.razor.cs`
- `CrewChief\CrewChief.Web\Components\Controls\WorkloadCard.razor.cs`
- `CrewChief\CrewChief.Web\Components\Controls\FileBrowserDialog.razor`
- `CrewChief\CrewChief.Web\Components\Pages\CardViewState.cs` (shared card/list view + cols + guarded paging)
- `CrewChief\CrewChief.Web\Components\Pages\Steps.razor` (+ `.razor.cs` — delegates to `CardViewState`)
- `CrewChief\CrewChief.Web\Components\Pages\Workloads.razor` (+ `.razor.cs`)
- `CrewChief\CrewChief.Web\Components\Pages\WorkloadEditor.razor` (+ `.razor.cs` — card move buttons, picker)
- `CrewChief\CrewChief.Web\Components\Controls\WorkloadRunMonitor.razor` (+ `.razor.cs`)
- `CrewChief\CrewChief.Web\wwwroot\app.css` (card / cc-card-grid CSS)
- `CrewChief\CrewChief.Web\Components\Controls\RefDataPicker.razor`
- `CrewChief\CrewChief.Engine\Executors\IInstalledProductInventory.cs`
- `CrewChief\CrewChief.Engine\Executors\IRemoteFileBrowser.cs`
- `CrewChief\CrewChief.Engine\Executors\IServerFileBrowser.cs`
- `CrewChief\CrewChief.Engine\Executors\RemoteWindowsOps.cs`
- `CrewChief\CrewChief.Tests.Unit\Engine\RemoteWindowsOpsTests.cs` (`BuildFileBrowseScript_*`)
- `CrewChief\CrewChief.Engine\Executors\IRemoteCommandRunner.cs` (RemoteAuth / RemoteAuthParser)
- `CrewChief\CrewChief.Engine\Steps\ConfigureStep.cs` (ComposeArgumentString)
- `CrewChief\CrewChief.Engine\Executors\ConfigureExecutor.cs`
- `CrewChief\CrewChief.Web\Services\Secrets\SecretValueRef.cs`
- `CrewChief\CrewChief.Web\Services\Secrets\SecretCatalog.cs`
- `CrewChief\CrewChief.Web\Services\Secrets\SecretSectionRegistry.cs`
- `CrewChief\CrewChief.Web\Components\Pages\FilterPersistence.cs`
- `CrewChief\CrewChief.Web\Components\Pages\Activity.razor.cs`
- `CrewChief\CrewChief.Web\wwwroot\js\crewchief-io.js`
- `CrewChief\CrewChief.Web\Components\Icon.razor`
- `CrewChief\CrewChief.Web\Components\Icon.razor.cs`
- `CrewChief\CrewChief.Web\Helpers\UtilityStepTypeInfo.cs`
