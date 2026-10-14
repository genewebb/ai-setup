---
name: reference-smvmtr1-cim-needs-dcom
description: "From CORPLTR94, Get-CimInstance -ComputerName SMVMTR1 fails on WinRM Kerberos (0x80090311); a DCOM CIM session works"
metadata:
  node_type: memory
  type: reference
  originSessionId: b2e5c3f1-477c-4a3d-9020-778d297a28c8
  modified: 2026-10-01T00:30:42.173Z
---

`Get-CimInstance -ComputerName SMVMTR1 ...` from the laptop fails with WinRM Kerberos error 0x80090311 ("domain isn't available"). DCOM works:

```powershell
$cs = New-CimSession -ComputerName SMVMTR1 -SessionOption (New-CimSessionOption -Protocol Dcom)
Get-CimInstance -CimSession $cs Win32_LogicalDisk -Filter "DriveType=3"
Get-CimInstance -CimSession $cs Win32_Process   # CommandLine included
```

Verified 2026-09-30. Use it for disk-free and process or session checks on TR1 without RDP. Related: [[project-stream-host-smvmtr1-2026-09-28]]
