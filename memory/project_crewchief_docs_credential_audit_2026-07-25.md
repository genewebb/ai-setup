---
name: project_crewchief_docs_credential_audit_2026-07-25
description: CrewChief help docs audited against step code — two-field Run As pair was undocumented everywhere; new shipping-templates page added
metadata: 
  node_type: memory
  type: project
  originSessionId: 8ff8b172-9d52-41ad-8c5c-02e4e6136777
  modified: 2026-07-25T15:03:24.010Z
---

2026-07-25 audit of `CrewChief.Web/Documentation/*.md` against `CrewChief.Engine/Steps/*.cs`. Every `[JsonProperty]` name on all 19 step types is now documented (verified by diffing property names against doc text).

**Root cause of the drift:** remote credentials moved from the single indirect `credentialSecretName` pointer to the two-field `credentialUserId` + `credentialPassword` pair. Executors resolve `Resolve(userId, password) ?? Resolve(secretName)` — pair wins, legacy is fallback. The docs only ever described the fallback, so the *primary* path was absent from all 46 docs. `remoteAuthentication` (Default/Negotiate/CredSSP) was documented only on Configure.

Also newly documented: DatabaseOperations + SetApiKey `authMode` (Windows/Sql, plus Windows-auth-with-pair = `WindowsImpersonation`), SetApiKey `serverName`+`databaseName` as the *primary* destination (the connection secret is an advanced override, but the doc had it marked required), and the Install/MapShare share-credential family. Install's `shareCredentialType` and MSI staging are **mutually exclusive** (`StageFiles = shareMount is null ? [msiPath] : []`).

New page: `42_ReferenceShippingTemplates.md` → `/help/reference/shipping-templates` — how to add shipped templates (samples + `*.refkv.json`) for distribution.

**How to apply:** re-run the audit as a grep diff of `JsonProperty("...")` names vs doc text — catch the `Required = Required.Always` attribute form too (`JsonProperty("[a-z]*"` without the closing paren). See [[project_crewchief_templates_selective_install]], [[project_crewchief_credentialed_remote_ops]], [[project_crewchief_remote_box_prep_transport]].
