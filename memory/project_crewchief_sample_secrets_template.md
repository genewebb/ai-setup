---
name: project_crewchief_sample_secrets_template
description: "Sample secrets file shipped as a third template kind (*.secrets.json → secret-samples/), plus copy-to-clipboard on help code blocks"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8ff8b172-9d52-41ad-8c5c-02e4e6136777
  modified: 2026-07-25T15:35:48.667Z
---

2026-07-25: CrewChief ships a **sample secrets file** as a template kind. Source `CrewChief.Web/SampleSecrets/*.secrets.json`, embedded via its own csproj glob, routed by `SampleContentSeeder` (third suffix) to `<DataFolder>/secret-samples/` — **never** the `secrets/` folder, never merged into the encrypted Local Secrets store. Templates-page Kind = `SampleTemplateStatus.SecretsKind` ("Secrets").

**Hard constraint:** the sample must be directly importable, and `LocalSecretStore.Import` runs `SecretSchema.Validate` — so every top-level key must be a v2 section (`category`/`description`/`includeInReplacements`/`values`). That means **no `_shippedUtc`/`_readme`** (they'd be read as sections and fail). Consequence: no shipped date → `SeedGate` treats it as **install-once, never overwritten** — which is what you want for a file the operator fills in. Ship a revised sample under a NEW file name.

Other gotchas: `Import`/`ParseSections` accept an object **or single-element array** (`Export` emits the array form). `{{Section:Key}}` internal refs resolve against the file's own values at import; a ref to a real section with an unknown key is an import error. **Backslashes must be doubled** — `corp\yourmachinename` is an invalid JSON escape (`\y`) and Newtonsoft rejects the whole file; the original sample had this bug in RemoteRuntime only.

Also added: **copy-to-clipboard on every help code block** (`crewchiefHelp.addCopyButtons` in `wwwroot/js/help-docs.js` + `.help-copy-btn` styles in `app.css`), with a `document.execCommand` fallback because `navigator.clipboard` is unavailable on plain-http lab boxes. The sample is reproduced in `37_OpsSecretsSetupAndTesting.md` so it can be copied without installing the template — **keep the doc copy and the shipped file in sync**.

`ShippedSampleSecretsTests` (9 tests) enforces schema validity, no stray metadata keys, resolvable refs, placeholder-only values, install location, and never creating `secrets/`. See [[project_crewchief_templates_selective_install]], [[crewchief-secrets]].
