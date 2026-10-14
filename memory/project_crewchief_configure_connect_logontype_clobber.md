---
name: crewchief-configure-connect-logontype-clobber
description: Connect providers not loading after CrewChief ConfigureStep — Configuration.exe CLI writes blank FileRepositoryLogonType (no UI-style default) AND LoadConfig() clobbers CLI attachment switches on re-configure of an existing instance
metadata: 
  node_type: memory
  type: project
  originSessionId: 5f9dd021-cc8d-4aec-a06c-39b9067fbcd4
  modified: 2026-07-31T15:08:21.765Z
---

Connect providers fail to load after a CrewChief ConfigureStep run because the ConnEx appsettings `FileRepositoryLogonType` ends up blank. Two compounding platform (Configuration.exe) defects, found 2026-07-31:

1. **No CLI default**: `Program.cs` reads `/AttachmentRepositoryLogonType:` raw (`switches.SwitchValue` → `""` when absent) and assigns it straight to `FileRepositoryRepository.LogonType`. The UI path instead runs `FileRepositoryModel.initializeLogonType()` which forces blank → `default(WindowsLogonType).ToString()` ("Interactive"). So UI/dev-utilities-configured instances always have it populated; a CLI run without the switch writes blank.
2. **LoadConfig clobber (why adding the switch didn't heal)**: in both the normal branch (Program.cs ~881-892) and addToCluster branch (~815-821), the four `AttachmentRepository*` switch values are assigned BEFORE `context.LoadConfig()`. On an already-configured instance (Monolith appsettings `AuthUrl` non-empty), `LoadConfig` (WebAppConfigurationContext.cs:382-385) overwrites Location/LogonType/Username/Password from the existing Monolith appsettings — so the persisted blank wins forever on every re-configure.

Write chain: switch → `FileRepositoryRepository.LogonType` → `SaveConfigSettings` → `writeConnExSettings` → `getConnectFolderSettings` (WebAppConfigurationContext.cs:2617) → ConnEx appsettings `FileRepositoryLogonType` (also Proflow + Workflow variants). ConnEx `DefaultServiceConfigurationImporter` compares `== "Interactive"` **case-sensitively** to pick AuthenticationScheme.AD (else Basic); `FileOperationHandler` ThrowIfNull's it. Provider/config import runs in `ImportDefaultArtifactsHostedService.StartAsync` — a throw there means no providers.

Heal an affected box: set `FileRepositoryLogonType: "Interactive"` in `Services\Monolith\appsettings.json` (the file LoadConfig reads), then re-run configure to propagate; editing only ConnEx appsettings works until the next configure clobbers it. Real fix is platform-side (assign switches AFTER LoadConfig, or default blank like the UI). Uninstall/reinstall NOT required — fresh Monolith appsettings has empty AuthUrl so the clobber branch is skipped.

**CrewChief mitigation (2026-07-31, shipped)**: `ConfigureStep.ComposeArgumentString` now ALWAYS emits `/AttachmentRepositoryLogonType` non-blank on a full configure run (gated on `licenseFile` switch presence — the platform branch that writes file-repo settings requires it): injected as `Interactive` when missing, substituted when blank or token-resolves blank; explicit non-blank values respected; mode/partial runs without licenseFile untouched (except enabled-but-blank logon type, still substituted). Public consts `AttachmentRepositoryLogonTypeSwitch`/`DefaultAttachmentRepositoryLogonType` on ConfigureStep. Exact case "Interactive" is load-bearing (ConnEx case-sensitive compare). Tests in ConfigureStepTests (always-default region). This guarantees fresh configures; it cannot defeat the reconfigure clobber. Related: [[Configuration.exe Failure Modes]], [[CrewChief Configure Switches]].
