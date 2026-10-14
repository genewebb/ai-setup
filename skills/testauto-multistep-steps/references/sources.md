
Repo: speed-merchants (paths below are repo-relative)

# Source Files

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Sources

- `TestAuto.Web\Documentation\StepGuide_Index.md`
- `TestAuto.Web\Documentation\StepGuide_SqlStep.md`
- `TestAuto.Web\Documentation\StepGuide_HttpRequest.md`
- `TestAuto.Web\Documentation\StepGuide_PowerShellStep.md`
- `TestAuto.Web\Documentation\StepGuide_CommandLineStep.md`
- `TestAuto.Web\Documentation\StepGuide_CLUStep.md`
- `TestAuto.Web\Documentation\StepGuide_ConnExStep.md`
- `TestAuto.Web\Documentation\StepGuide_MonitorStep.md`
- `TestAuto.Utilities\Scripts\JsonData\README.md`
- `TestAuto.Utilities\Documentation\CLU_UserGuide.md`
- `TestAuto.Utilities\Agents.md` — *source removed 2026-07-27; content migrated to work-ai, this skill is now canonical*
- `TestAuto.Utilities\Services\TextTemplater.cs` (prefix-driven `ResolveTokenValue` / `CanResolveToken`)
- `TestAuto.Utilities\Services\UtilityOrchestrator.cs` (global→step parameter merge)
- `TestAuto.Utilities\Common\DTOs\HttpRequestStep.cs` (`MaxTimeSeconds ?? TimeoutSeconds`, `UseRestMethod`)
- `TestAuto.Utilities\Helpers\HttpStepTimeoutCalculator.cs` (outer process-kill bound + `ProcessKillGraceSeconds`)
- `TestAuto.Utilities\Executors\PowerShellRestExecutor.cs`, `CurlExecutor.cs`
- `TestAuto.Utilities\Services\CLUCommandBuilder.cs` (per-TaskType validation/argument building)
- `TestAuto.Utilities\Common\DTOs\SqlStep.cs`, `Executors\SqlScriptExecutor.cs`
- `TestAuto.Shared\Constants\ProfiseeAppSettingsConfigurationKeys.cs` (`SqlConnectionStringSecretAliases`)
- `TestAuto.Utilities\Common\DTOs\CLUStep.cs`
- `TestAuto.Utilities\Common\DTOs\CLUTaskType.cs`
- `TestAuto.Utilities\Executors\ConnExExecutor.cs`
- `TestAuto.Utilities\Common\ConnExConstants.cs`
- `TestAuto.Utilities\Common\DTOs\ConnExStep.cs`
- `TestAuto.Utilities\Common\DTOs\StepExecutionResult.cs`
- `TestAuto.Utilities\Helpers\ConnExErrorParser.cs`
- `TestAuto.Web\Services\ConnExScenarioFactory.cs`

---
