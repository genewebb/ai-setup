---
name: reference_shared_bits_smvmtr1_azure_relay
description: "SMVMTR1 S: = Azure Files \\\\smshareddrive.file.core.windows.net\\sharedfiles; laptop port 445 to Azure BLOCKED (IT-level); dp* -Package relays exes through SMVMTR1 (Publish-GeneSharedBits, SharedBits* machine keys)"
metadata:
  node_type: memory
  type: reference
  originSessionId: ff988749-b15f-4005-902f-cfdd32b4756a
  modified: 2026-10-22T02:07:08.858Z
---

SMVMTR1's S: is an Azure Files share, `\\smshareddrive.file.core.windows.net\sharedfiles` (storage-key auth, account `Azure\smshareddrive`). The laptop CANNOT reach it: TCP 445 to Azure (20.209.179.48) fails from CORPLTR94 and works from SMVMTR1 (tested 2026-10-17); a fix would be network/IT, not Gene. A WinRM session on SMVMTR1 also cannot use S: (no Credential Manager in a network logon), so it must connect explicitly.

**Built 2026-10-17 (Gene chose option "remote session reads the key on SMVMTR1"):** `Publish-GeneSharedBits` in the PowerShell profile, called as step 7 of `Publish-SpeedMerchantsPackage` (the -Package tail of dpspeed/dpcrewchief/dpdatagen/dpmutate/dpall; publish only, never a plain build; dpv2 NOT included, its bundle goes to PackageShare\Deployment). Stages the exes to `\\SMVMTR1\C$\ProgramData\GeneSharedBits`, then Invoke-Command on SMVMTR1 reads the `$AccountKey = "..."` line of `C:\PowershellScripts\MapDrive.ps1` there, `net use` the share root for that session only, robocopy, prune strictly-older same-product versions, empty staging, `net use /delete`. Only status lines come back. Keys (laptop ProfileMachineConfig.md, backup `.bak-20261017-sharedbits`): SharedBitsHost, SharedBitsShare (`...\sharedfiles\SpeedmerchantsBits`), SharedBitsKeyScript, SharedBitsStaging; blank SharedBitsHost = off.

**WinRM 0x80090311 "your domain isn't available" (2026-10-21):** NOT connectivity. Laptop logon was a cached logon from before the domain was reachable: `klist` = 0 tickets while `nltest /dsgetdc:corp.profisee.com` finds a DC. SMB staging still works (NTLM fallback), but Invoke-Command without -Credential needs Kerberos and fails. Fix (commit in ai-setup main, merge after 024fa41): on an auth failure the relay asks once for the caller's password (Get-Credential, run only) and retries with -Credential; non-interactive runs still just warn. Signing out/in (or locking/unlocking on the network) also gets a fresh TGT.

**Claude's auto-mode classifier BLOCKS Claude from running anything that reads that key** ("Credential Leakage"): success path VERIFIED by Gene 2026-10-17 (re-publish of CrewChief 7.0.28 landed in S:\SpeedmerchantsBits, folder name confirmed); dpall -Package run next. The key is also plaintext in MapDrive.ps1, committed in genewebb/powershellscripts (private) initial commit e07b0db. Never print it. See [[project_manageprofile_hub_2026-10-17]].
