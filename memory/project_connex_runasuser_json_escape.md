---
name: connex-runasuser-json-escape
description: "ConnEx import step 16 failed \"Bad JSON escape \\q\" on runAsUser; config/secret-resolved param values weren't JSON-escaped into the artifact (only literals were, at import). Fixed in ParameterResolver."
metadata: 
  node_type: memory
  type: project
  originSessionId: eb01a776-6b0d-4aaa-b554-77c7110453c3
---

ConnEx Import step (e.g. exec 10000164 step 16, "Connect - Step 1: Import") threw
`Artifact is not valid JSON after parameter substitution. Bad JSON escape sequence: \q ... Path 'integrationStrategyRecord.Configuration.runAsUser'` at `ConnExExecutor.cs:253` (`JToken.Parse`) — a LOCAL parse failure in TestAuto, BEFORE the gateway is called (so a model-security grant for the runAsUser account does NOT fix it — that only matters once JSON is valid and the import runs).

**Root cause:** `runAsUser` is a two-hop token: artifact `"runAsUser":"{{RunAsUser}}"` → GlobalParameter `RunAsUser` = `{{$config:ConnectRuntime:ConnectRunAsUser}}` → secret = a Windows account `CORP\QAAutomation`. `UtilityOrchestrator` (line 188) resolves `{{$config:...}}` in-place via `ParameterResolver.ResolveSpecialParameterValues` to the RAW value, then `ConnExExecutor` textually substitutes it into the raw artifact JSON. The backslash was never JSON-escaped → `CORP\Q...` = invalid escape. Import-time `ArtifactTokenizer.Escape` (doubles `\`, escapes `"`) covers LITERAL values only, and explicitly NOT `ValueSource.Secret` (stored as the raw `{{$config:...}}` ref) — so runtime-resolved config/secret/template values bypassed all escaping.

**Why:** escaping was done at the wrong layer (import-time, per-source) instead of uniformly at the JSON-injection boundary. Same class as [[reference_json_case_insensitivity_audit]] and [[project_chunk_boundary_whitespace_trim]] — a value crossing a serialization boundary without normalizing for the target format.

**How to apply / fix shipped:** `IParameterResolver.ResolveSpecialParameterValues` gained `bool escapeForJson = false`; when true it JSON-escapes the resolved value (mirrors `ArtifactTokenizer.Escape` exactly). `UtilityOrchestrator` passes `escapeForJson: step is ConnExStep`. Literals are skipped (no `{{$config}}`/`{{$env}}` token) so no double-escape; SQL/PowerShell/Curl steps get raw values. Regression tests: `ParameterResolverTests`. Fix is in the RUNTIME resolution path, so **no config regeneration / re-import needed** — just rebuild/republish and re-run from the failed step. Pairs with [[connex-import-tokenization]].
