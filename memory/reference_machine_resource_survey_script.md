---
name: reference_machine_resource_survey_script
description: "getmachineresources.ps1 - read-only machine survey (NUMA via kernel32 P/Invoke, storage, boot, tenancy, SQL DMVs) with -ComputerName remote mode; two gotchas: GetNewClosure kills function visibility, SQL soft-NUMA disagrees with kernel32 by design"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 20823a52-9dc4-437d-b376-c1594585db4a
  modified: 2026-08-17T14:37:48.180Z
---

`C:\devopslocal\powershellscripts\getmachineresources.ps1` — read-only survey of a machine's
CPU/NUMA topology, memory channel population, storage devices, boot configuration, tenancy and
SQL Server layout. Writes `machine-resources_<HOST>_<stamp>.txt` + `.json` (+ `_msinfo32.txt`)
to `-OutputPath` (default `C:\Temp`). Switches: `-Quick`, `-SkipSql`, `-AllowDownload`,
`-CoreinfoPath`, `-ComputerName`/`-Credential`.

Remote mode copies the script to the target's `$env:TEMP`, runs it there, copies the outputs back,
and deletes the remote copy. **Run elevated** or BitLocker/TPM/`bcdedit`/SSD-wear probes skip.

**Why P/Invoke instead of WMI:** Windows has no WMI class for NUMA nodes. Node count, group count,
per-node core masks and per-node free memory come from `kernel32`:
`GetNumaHighestNodeNumber`, `GetActiveProcessorGroupCount`, `GetNumaNodeProcessorMaskEx`,
`GetNumaAvailableMemoryNodeEx`, plus a `GetLogicalProcessorInformationEx` walk that counts records
by `Relationship` to get physical cores / sockets / dies. Validated on a known hybrid CPU: it
correctly split 8 P-cores (`smtFlag=1, efficiencyClass=1`) from 16 E-cores (`smtFlag=0,
efficiencyClass=0`).

## Two gotchas worth remembering

1. **`.GetNewClosure()` on a scriptblock breaks helper-function visibility.** It rebinds the block
   into a fresh module scope, so script-scoped functions (`Invoke-SqlProbe`) become
   "not recognized as a name of a cmdlet". It was also unnecessary — the probe runner executes
   `& $Body` synchronously inside the same loop iteration, so loop variables are already current.
   Only defer-then-execute patterns need a closure.

2. **`sys.dm_os_sys_info.numa_node_count` legitimately disagrees with kernel32.** Automatic
   soft-NUMA splits schedulers above 8 cores, so SQL reports *more* nodes than the hardware has
   (seen: 16 SQL nodes over 4 hardware nodes; 2 over 1). `sys.dm_os_nodes.memory_node_id` maps
   soft nodes back to real ones. **kernel32 is the hardware truth; the DMVs are what SQL believes.**
   Treat a mismatch as information, not a bug.

**How to apply:** reach for this for "what is actually in this box", "is this machine dedicated",
"are these drives real devices or a RAID volume", or before any dual-boot / firmware / pinning work.
First real use: [[reference_corpsql03_hardware_profile]].
