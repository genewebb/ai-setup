---
name: project_testautoisolation_2026-11-13
description: "TestAutoIsolation (speed-merchants/TestAutoIsolation, uncommitted) - noisy-neighbour isolation harness; Proxmox build/pin over SSH key; home Proxmox used as mechanics test bed; judged vs reported-only figures"
metadata:
  node_type: memory
  type: project
  originSessionId: 4bd0ebce-ca6b-4345-a32d-6c9fc773a864
  modified: 2026-11-14T02:54:05.966Z
---

TestAutoIsolation built 2026-11-13 in `speed-merchants/TestAutoIsolation` (Core/Agent/Runner/Web/Tests), **uncommitted** (speed-merchants = never commit). Design + plan docs: vault `99 Documentation/speed-merchants/planning/2026-11-13-testautoisolation-*.md`. README in project root. Web runs from `publish\web` on http://localhost:5080; data under `%LOCALAPPDATA%\TestAutoIsolation`.

State at end of 11/13:
- Agent image tag 1.1.0. Any agent code change = bump tag (Directory.Build.props, build-agent-image.ps1, Stack.cs default, Server.razor) because VMs never re-pull a same tag.
- 7 judged figures (cpu, mem, sql scan/write/seek, single commits, small transactions); 5 reported only (alloc, commit p99, 3 network) - network far end is a loaded instance, tails/alloc vary 4-21% on pinned VMs. Known-truth bar 170/200 (178 actual with 7 judged).
- Proxmox: SSH key login only, no password field; one pinned VM per instance, VMID 9101+, tag `tai`. Requires DHCP bridge, internet at first boot, harness reach to VM :22 + agent port. 1 GB pages never exercised.
- Read-back (incl. host affinity) before AND after every block; change during a block = block thrown away + Refused.
- Home Proxmox proved mechanics only (build, pin read-back, Refused on deliberate unpin, change layout 3 to 2, VM removal). Home numbers never stand for CORPSQL03.

**Why:** Gene asked for isolation proof before multi-instance on the big Proxmox host ([[project_corpsql03_proxmox_conversion_2026-11-09]]).
**How to apply:** Next step is a real run on the lab host once Gene sets it up; first confirm its core count (Gene said 512 cores, vault notes 96 cores/192 threads). Not built: real Profisee workload phase, Windows guests, quiet network far end, host-side tuning (irqaffinity, systemd CPUAffinity, BIOS).
