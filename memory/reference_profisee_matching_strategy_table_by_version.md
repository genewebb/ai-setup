---
name: reference_profisee_matching_strategy_table_by_version
description: "Where a Profisee matching strategy lives depends on platform version - 26R2 keeps it in matching.tMatchingStrategy with attribute sets as Newtonsoft $type/$values JSON in [Configuration]; the older layout uses meta.tMatchingStrategy + tMatchingStrategyDetailSet rows and matching.tMatchingStrategy is EMPTY"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6f0d3904-49de-4741-a701-439ff517a35a
  modified: 2026-09-12T02:46:08.790Z
---

| Layout | Strategy row | Attribute sets | Seen on |
| --- | --- | --- | --- |
| 26R2 | `matching.tMatchingStrategy` (`Name, Code, EntityName, Status, IncludeMatching, StatusID, Configuration`) | `[Configuration]` nvarchar JSON, ~18 KB, `AttributeSets.$values[].Attributes.$values[].Attribute.Name` | CORPLTR94 `profisee`, SMVMDB2 `profisee` |
| older | `meta.tMatchingStrategy` (`StatusID` → `meta.tStrategyStatus`: 1=DISABLED, 4=ENABLED, 98=FINISHED) + `meta.tMatchingStrategyDetailSet` | relational rows | CORPLTR94 `speedmerchants` (the ScenarioMgt instance) — where `matching.tMatchingStrategy` has **zero rows** |

Consequences:
- `MatchingStrategyConfigurationService` (`TableName = [matching].[tMatchingStrategy]`) finds nothing on the older layout. `GetAttributeSetsAsync` therefore returns EMPTY and logs, never throws — the attribute-set startup guard is advisory.
- `Status` (bit-ish) is the enable flag; `StatusID` is the last *process* state (`98 = FINISHED`, not disabled). Don't read 98 as "off".
- Parsing the JSON: every collection is a `{"$type","$values"}` envelope — reading `AttributeSets` as an array yields nothing.
- `PowerShell ConvertFrom-Json` handles it if you index `.'$values'`.

Related: [[project_matching_3a_target_pull_and_quality_dial]].
