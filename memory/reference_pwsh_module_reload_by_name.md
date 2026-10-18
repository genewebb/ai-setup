---
name: reference_pwsh_module_reload_by_name
description: Reloading changed module code in a live pwsh window: Import-Module <name> -Force works; Get-Module X | Import-Module -Force does NOT; . $PROFILE now reimports loaded Gene.* modules
metadata:
  type: reference
---

Tested 2026-10-17 with a throwaway module: after the module's files change, `Get-Module Zz.* | Import-Module -Force` keeps the OLD code (it reuses the loaded module object); `Import-Module Zz.Probe -Force` (by name) and `Remove-Module` + `Import-Module` load the new code. From inside a module's function add `-Global`, or the import lands in that module's scope.

Applied: the PowerShell profile ends by re-importing every already-loaded Gene.* module by name, so `. $PROFILE` in any window picks up a `prof setup reload`; `prof setup reload` also re-imports them in its own window. Never advise the piped form again. Note `rp` dot-sources $PROFILE inside its own function scope, so its definitions do not reach the window. See [[project_manageprofile_hub_2026-10-17]].
