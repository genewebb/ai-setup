---
name: project_scriptdirectory_token_gotcha
description: "MultiStep HTTP step bodyFilePath must be a relative path, not {{$config:ScriptDirectories}} — that token does not exist"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8db176d8-9242-402e-8dc8-1cb043f4696d
---

A MultiStepUtilityScenario HTTP/REST step that sets `bodyFilePath` (or any script path) to
`{{$config:ScriptDirectories}}/...` fails at run time with: *"The following tokens were found in the
input but have no matching source: {{$config:ScriptDirectories}}"* (thrown by
`TextTemplater.ReplaceTokens`, surfaced via `PowerShellRestExecutor.ExecuteViaRestAsync`).

**Why:** there is no config key named `ScriptDirectories`. The scripts root is
`DirectoryPaths:ScriptDirectory` (see `TestAuto.Shared/Configuration/ScriptDirectoryOptions.cs`,
`ConfigurationKey = "DirectoryPaths:ScriptDirectory"`), stored in secrets. `$config:` token resolution
requires a non-empty scalar; the bogus key resolves to empty → fail-fast.

**How to apply:** use a **relative** path and let the executor prepend the root —
`ScriptDirectoryOptions.ResolveRelativePath` (called in PowerShellRestExecutor for non-rooted paths)
does this automatically. e.g. `"bodyFilePath": "Matching/Commands/RetailClientEnableContinuousMatching.json"`
(files live under `<deploy>\Scripts\Matching\Commands\`). Avoid BOTH antipatterns seen in stored
configs: the bad `{{$config:ScriptDirectories}}` token AND machine-specific absolute dev paths like
`C:\devops\...\.run\...\Scripts\JsonData\...`. If you must tokenize, the correct form is
`{{$config:DirectoryPaths:ScriptDirectory}}` — but relative is preferred.

Misleading log: the `[SQL_SCRIPT] ... failed for URL {{$config:...BaseUrl}}` line shows the URL raw
because `StepKey = curlStep.Url` is stamped before templating — the real failure is the bodyFilePath
token (stack trace line is authoritative). Related: [[reference_scenario_config_token_prefix]],
[[project_getrecords_pagesize_truncation]].
