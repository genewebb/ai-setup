---
name: crewchief-workload-runas-inheritance-carveout
description: CrewChief workload-level Run As inherits to the SEVEN box-prep steps only (WebSiteStep added 2026-08-06) — DatabaseOperationsStep and SetApiKeyStep never inherit and must set credentialUserId/Password themselves
metadata: 
  node_type: memory
  type: project
  originSessionId: e5c24a2f-da92-4542-98a8-0a9bfdd08f22
  modified: 2026-08-07T02:42:31.770Z
---

Setting a workload-level Run As (`credentialUserId`/`credentialPassword` at the top of a `*.workload.json`)
does **not** cover every step. `WorkloadRunAsInheritance.InheritIfBoxPrep` enumerates exactly **seven** types —
`ServiceControlStep`, `IisResetStep`, `AppPoolStep`, `WebSiteStep` (added 2026-08-06), `InstallStep`,
`UninstallStep`, `ConfigureStep`. Everything else is `_ => null` (no inheritance).

**`DatabaseOperationsStep` and `SetApiKeyStep` are a DELIBERATE carve-out**, not an oversight
(`WorkloadRunAsInheritance.cs:80-88`): their identically-named `credentialUserId`/`credentialPassword` mean the
identity of an OUTBOUND SQL connection, and under `authMode: "Sql"` it isn't even a Windows account. One
inherited value can't be right for both families, and handing a SQL login to `LogonUser` is nonsense.

**Consequence — the silent one.** On `DatabaseOperationsStep`, `authMode: null` = Windows-integrated and a blank
credential pair means *run as the CrewChief process identity*. So a workload with a perfectly good global Run As
still runs its Drop/Restore steps as CrewChief's own identity, with no error and no warning. If the DB server is
a different box, SQL sees the wrong principal.

**Correct authoring pattern** (canonical: `SampleContent\workloads\26r2-parm-driven-crud.workload.json:87-91`):
box-prep steps keep `credentialUserId: null` — that null is what ENABLES inheritance, so do not "helpfully"
populate it — while every `DatabaseOperationsStep` sets `credentialUserId: "{{profisee_admin_user}}"` /
`credentialPassword: "{{profisee_admin_password}}"` and leaves `authMode: null`.

Applied to `C:\deploy\crewchief\web\data\workloads\26r2-parm-driven-matching.workload.json` on 2026-07-30 (its
two DB steps were the only gap; that workload exists ONLY in the deployed data folder, not in SampleContent).

Audit any workload with:
`credentialUserId` non-null on a box-prep step = suspicious (defeats the workload setting);
`credentialUserId` null on a `DatabaseOperationsStep`/`SetApiKeyStep` = runs as the CrewChief identity.

Related: [[project_crewchief_localrunas_cmdline_1024]], [[project_crewchief_credentialed_remote_ops]],
[[project_crewchief_param_in_param]]
