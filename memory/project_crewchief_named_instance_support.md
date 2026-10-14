---
name: project_crewchief_named_instance_support
description: CrewChief serverName now supports named instances; docker named-instance test fixture + native-vs-managed SNI catch
metadata: 
  node_type: memory
  type: project
  originSessionId: 90841b47-3f5e-4da7-a18e-d11dff8353d5
  modified: 2026-08-14T20:06:06.004Z
---

2026-08-14: Removed the "instance names not supported" restriction from CrewChief `DatabaseOperationsStep`/`SetApiKeyStep` `serverName`. It was DOC-ONLY — `SqlConnectionStringBuilder.DataSource` already passed `HOST\INSTANCE` and `HOST,port` through. Updated doc comments, executor error hint, `StepEditorCard.razor` placeholder/help, `21_StepGuideDatabaseOperations.md`; added 7 unit rows (67/67 pass) asserting the forms reach Data Source verbatim.

**Docker named-instance test fixture** (`C:\tmp\sql2022-named`, image `sql2022-named`): Linux SQL Server has NO named instances (`SERVERPROPERTY('InstanceName')` always NULL). A ~40-line python SSRP responder on UDP 1434 makes the container answer `HOST\INSTANCE`. Run with `-p 14222:1433 -p 1434:1434/udp`.

**Decisive catch — native vs managed SNI:** `Microsoft.Data.SqlClient` **managed SNI** SSRP parser only checks byte0=0x05, size==len-3, splits on `;`, finds `tcp`, takes next as port — does NOT validate instance name, so the minimal responder works. **Native SNI (`SNI.dll`, Windows default) REJECTS** the minimal emulator ("requested instance was not available" / error 26) even though wire bytes are spec-correct. Real Windows SQL Browser works under native SNI; the emulator does not. → Windows clients must force managed SNI (`Switch.Microsoft.Data.SqlClient.UseManagedNetworkingOnWindows=true`); Linux always uses managed. Also: connect via `127.0.0.1` not `localhost` (IPv6 `::1` masks as error 26); explicit `HOST,port` bypasses SSRP entirely.

Gated integration test `NamedInstanceSqlIntegrationTests` (env `CREWCHIEF_IT_NAMED_SQL_SERVER/_USER/_PW`, plus `CREWCHIEF_IT_FORCE_MANAGED_SNI=1` via `ManagedSniToggle` ModuleInitializer) — PASSES against the self-contained image (CreateDatabase+DropDatabase). Full write-up: vault `52 Technical\Containers\Named Instance SQL Server 2022 Container.md` + `Container Setup and Troubleshooting.md`. See [[project_crewchief_secrets_shipped]], [[reference_docker_aspire_class_setup]].
