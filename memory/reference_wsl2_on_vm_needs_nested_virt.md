---
name: reference-wsl2-on-vm-needs-nested-virt
description: WSL2/Rancher on a lab VM fails HCS_E_HYPERV_NOT_INSTALLED until the HOST exposes virtualization extensions; HypervisorPresent=True in the guest proves nothing
metadata:
  node_type: memory
  type: reference
  originSessionId: e6692ca4-4cf5-4b6c-9bc6-113c26f431a3
  modified: 2026-10-13T12:58:47.805Z
---

CORPVM17 2026-10-13: after `wsl --install --no-distribution` + reboot, Rancher Desktop's first start failed:
`wsl.exe --import rancher-desktop ... exited with code 4294967295`, real text in
`%LOCALAPPDATA%\rancher-desktop\logs\background.log`: "WSL2 is unable to start since virtualization is not enabled" /
`Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_HYPERV_NOT_INSTALLED`.

**Why:** the guest's `Win32_ComputerSystem.HypervisorPresent = True` only means the guest runs under a hypervisor (true on
every VM). It is NOT evidence of nested virtualization. I misread it as a good sign once.

**How to apply:** before installing WSL2/Rancher on a VM, have the host admin enable nested virtualization (Hyper-V host,
VM off: `Set-VMProcessor -VMName <vm> -ExposeVirtualizationExtensions $true`). Rancher logs are readable over
`\\<vm>\c$\Users\<user>\AppData\Local\rancher-desktop\logs` (wsl.log, background.log). Related:
[[project-stream-host-move-corpvm17-2026-10-13]].
