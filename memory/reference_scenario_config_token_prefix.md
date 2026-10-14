---
name: reference_scenario_config_token_prefix
description: "Scenario GlobalParameters/step params must use {{$config:Section:Item}} (with $config: prefix) to reference secrets/config — bare {{Section:Item}} does NOT resolve"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df74bf7b-6453-4a7b-be5d-cc30f76c3a42
---

In a TestAuto **scenario** (GlobalParameters, step Parameters), a reference to a secret/config value MUST use the `{{$config:Section:Item}}` form. The bare `{{Section:Item}}` form (e.g. `{{ServerNames:DatabaseServerName}}`) is the **secrets-file-internal** cross-reference syntax — resolved only at secret *load* time inside the secrets blob — and is **NOT resolved at scenario execution**.

Why: `UtilityOrchestrator.ResolveSpecialParameterValues` only pre-resolves param values containing `{{$config:` or `{{$env:`. `TextTemplater` resolves `$config:`→IConfiguration, `$env:`→env var, everything else → parameters-dictionary lookup. So a bare `{{ServerNames:DatabaseServerName}}` is looked up as a parameter key, not found, and left as a literal token — which then gets substituted verbatim into the ConnEx artifact (e.g. `ServerName` = the literal string `{{ServerNames:DatabaseServerName}}` → broken connection).

Mixed tokens work: `{{$config:ServerNames:DatabaseServerName}}_ModelSource` → `SMVMDB3_ModelSource`.
Verified by `TextTemplaterTests.ConfigToken_RequiresDollarConfigPrefix_BarePrefixIsUnresolvable`.

How to apply: when hand-editing ConnEx import GlobalParameters (DbServer, ServiceConfigName, etc.), always prefix config refs with `$config:`. The dialog's secret picker emits the correct form automatically; the bug appears when typing the token by hand. Note: step `description` is NOT templated — tokens there display literally. Related: [[project_connex_import_vaultid_bug]], [[feedback_connex_artifact_inline_over_file]].
