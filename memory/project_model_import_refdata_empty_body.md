---
name: model-import-refdata-empty-body
description: "Model-import \"Add X Reference Data\" 400 = ProjectRecordsForCreate looked for capital \"Code\" but gateway returns lowercase \"code\" → all records dropped → empty [] body → 400"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25f7dbe8-6d99-4da1-a08d-7ed23c825a54
---

Metadata model-import step "Add <Entity> Reference Data" (MultiStepUtilityScenario, `POST v1/Records/{entity}`) failed HTTP 400 even though the source entity had data. Root cause: `ModelMetadataHarvester.ProjectRecordsForCreate` filtered each record on a **case-sensitive** `o["Code"]` (constant `MetadataImportConstants.Json.RecordCode = "Code"`), but the Profisee gateway GET returns record keys **lowercase** (`code`, `name`, `internalId`, `enterDTM`, `canUpdate`, …). So every record failed the Code check → projection returned `[]` → an empty-array POST, which the gateway rejects with 400 (confirmed by probing `POST v1/Records/Dba_001_PDATA` with body `[]`).

Same class as [[connex-import-tokenization]] vaultId bug: gateway emits lowercase JSON, code assumes capitalized key, case-sensitive match silently drops data.

**Why:** unit fixtures hand-built `{"Code":"1"}` (capital) so tests passed while reality (lowercase) always produced empty bodies. The `RecordCode`/`RecordName` constants stay capitalized on purpose — they're SQL column names + attribute-metadata-name comparisons — so the fix is at the consumption site, not the constant.

**ROOT CAUSE (platform-wide):** the CDP platform re-cases JSON via Newtonsoft contract resolvers — `LowercaseContractResolver : DefaultContractResolver` does `ResolvePropertyName => ToLowerInvariant()` (used by `JsonSettings.ForInput()/ForSecurityFilter()/ForSqlParms()`), and the records endpoint emits camelCase (POCO props: `internalId`, `validationStatusID`, `canUpdate`, `code`, `name`). So gateway key casing is a SERIALIZER decision that varies by endpoint/version — consumer code must NEVER assume casing. NOTE the POCO-vs-dictionary split: system fields are POCO properties → re-cased by the resolver (camel/lower); custom attribute values are usually DICTIONARY keys → Newtonsoft does NOT transform them (unless NamingStrategy.ProcessDictionaryKeys) → they keep model casing. That's why `record["Code"]` (system, capital) returns null but `record["SecretData"]` (custom attr) often works.

**How to apply:** when consuming Profisee/ConnEx/Connect gateway JSON, match keys case-insensitively ALWAYS (`o.GetValue(c, OrdinalIgnoreCase)` / `Properties().FirstOrDefault(OrdinalIgnoreCase)` / a `GetValueCI` extension). Never use the raw `jobj["Key"]` indexer or `SelectToken("A.B")` on external JSON. See [[json-case-insensitivity-audit]] for the full audit of remaining offenders. Fix landed in `ProjectRecordsForCreate` (case-insensitive code + strip read-only system fields `MetadataImportConstants.Json.ReadOnlyRecordFields` + drop nulls) and the SQL refdata path `SqlServerDataStoreScriptGenerator` line ~106 (`rec.GetValue(c, OrdinalIgnoreCase)`, else PK column inserted NULL).

**Still open (flagged, not fixed):** (1) a genuinely-empty domain entity still emits a literal `[]` body → will 400 at runtime (the "fillable placeholder" design is not actually runnable). (2) `HttpRequestStep` executor with `UseRestMethod=true` swallows the gateway 400 response body, so only the bare ".NET (400) Bad Request" surfaces — the real reason lives nowhere unless tSystemLog logged it. See [[reference_scenariodatadisplay_4000_ceiling]] sibling import gotchas and [[file_reference_retirement]].
