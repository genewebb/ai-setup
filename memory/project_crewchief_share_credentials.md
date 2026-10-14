---
name: project_crewchief_share_credentials
description: "CrewChief credentialed remote share access (Azure File key + Windows SMB) — Install wizard, reusable ShareMount mechanism, MapShareStep + Browse adoption"
metadata: 
  node_type: memory
  type: project
  originSessionId: e25dbfb4-02af-4011-8c05-18e207b68e9c
  modified: 2026-07-23T00:06:51.911Z
---

Solves "can't browse/read attached drives on remote machines" for CrewChief box-prep. Root cause = the
**second-hop credential wall**: a WinRM network logon can't reach an Azure File share (`\\<acct>.file.core.windows.net\<share>`)
because that share authenticates with the **storage-account key** (`net use /user:localhost\<account> <key>`),
which lives in another logon session. WMI `Win32_MappedLogicalDisk` surfaces the mapping (letter+UNC) where
session-scoped scans don't, but discovery ≠ read — the key must be injected in-session before listing.

**Shipped (committed by user in `11cd0c7d`, then a 2nd completion pass; build clean, unit suite 1516/1516):**
- Reusable engine seam: `Executors/ShareCredential.cs` (`ShareCredentialType` None/AzureFile/WindowsShare +
  `ShareMount`), `RemoteWindowsOps.DeriveAzureShareUser` (→ `localhost\<account>`), `BuildNetUseMountStatement`/
  `BuildNetUseUnmountStatement` (single canonical net use), `BuildShareMountScript`, `ShareCredentialResolver`
  (+ `ShareRoot` public), and `RemoteRunRequest.ShareMount` — the transport (`DefaultRemoteCommandRunner`) wraps
  every remote run mount→run→unmount via `CC_SHARE_*` env vars + `$using:` (key never on a command line, cleared
  after read, torn down in `finally`). The driver fills `__CC_SHARE_MOUNT__`/`__CC_SHARE_UNMOUNT__` sentinels
  from the shared builders so it can't drift.
- `InstallStep` share fields + msiexec-against-UNC (drops host staging when a share cred is present).
- 4-page Install **wizard** in `StepEditorCard` (Target/Credentials/Installer/Review) + reusable
  `ShareCredentialEditor.razor` control (has `ShowSharePath` param).
- **Browse mounts the share** too (`IRemoteFileBrowser.ListAsync` takes `ShareMount?`; dialog + `BrowseInstallMsiAsync` thread it).
- **MapShareStep** reuses it: `shareCredentialType` field, Azure auto-derive in `MapShareExecutor`, editor uses
  `ShareCredentialEditor` (ShowSharePath=false); still LOCAL-ONLY; legacy blank-type+creds still works.
- Validation: AzureFile/WindowsShare require a password/key; WindowsShare also requires a user.

**Proven manually** vs SMVM3 (from SMVMTR3) over `Invoke-Command`: `net use \\smshareddrive.file.core.windows.net\sharedfiles /user:localhost\smshareddrive <key>` then `Get-ChildItem` lists files.

**Still pending:** a LIVE SMVM3 smoke of the transport `net use` path (gated `RemoteLab`, not in CI) + eyes-on
wizard/MapShare UI click-through. **Deferred:** a *surviving* MapDrive step (needs one persistent PSSession per
workload — the "tie/order problem"); Configure license-from-share (mechanism is reusable for it).
Spec: `99 Documentation\speed-merchants\planning\Design_InstallShareCredentials.md`.
Related: [[project_crewchief_remote_boxprep_transport]], [[project_crewchief_credentialed_remote_ops]], [[feedback_workflow_parallelizes_agents]].
