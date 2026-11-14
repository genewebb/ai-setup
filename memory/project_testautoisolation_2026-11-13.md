---
name: project_testautoisolation_2026-11-13
description: "TestAutoIsolation (speed-merchants/TestAutoIsolation, uncommitted) - noisy-neighbour isolation harness; Proxmox build/pin over SSH key; home Proxmox used as mechanics test bed; judged vs reported-only figures"
metadata:
  node_type: memory
  type: project
  originSessionId: 4bd0ebce-ca6b-4345-a32d-6c9fc773a864
  modified: 2026-11-14T15:29:32.023Z
---

TestAutoIsolation built 2026-11-13 in `speed-merchants/TestAutoIsolation` (Core/Agent/Runner/Web/Tests), **uncommitted** (speed-merchants = never commit). Design + plan docs: vault `99 Documentation/speed-merchants/planning/2026-11-13-testautoisolation-*.md`. README in project root. Web runs from `publish\web` on http://localhost:5080; data under `%LOCALAPPDATA%\TestAutoIsolation`.

State at end of 11/13:
- Agent image tag 1.1.0 (1.2.0 since 11/14). Any agent code change = bump tag (Directory.Build.props, build-agent-image.ps1, Stack.cs default, Server.razor) because VMs never re-pull a same tag.
- 7 judged figures (cpu, mem, sql scan/write/seek, single commits, small transactions); 5 reported only (alloc, commit p99, 3 network) - network far end is a loaded instance, tails/alloc vary 4-21% on pinned VMs. Known-truth bar 170/200 (178 actual with 7 judged).
- Proxmox: SSH key login only, no password field; one pinned VM per instance, VMID 9101+, tag `tai`. Requires DHCP bridge, internet at first boot, harness reach to VM :22 + agent port. 1 GB pages never exercised.
- Read-back (incl. host affinity) before AND after every block; change during a block = block thrown away + Refused.
- 11/14: Gene committed (eff31c69). In-app docs added (uncommitted by me): 17 `.md` under `TestAutoIsolation.Web/Documentation/`, MD2Razor + YamlDotNet like CrewChief, `/help` home + search, Docs menu item, link strip on Status. DocsTests check every doc indexed, routed, links valid. 143 tests pass.
- 11/14 Phase 2 built (uncommitted), agent tag now **1.2.0**: per-test saved judged set; quiet far end (agent-only, `TAI_ROLE=far-end`; Proxmox VM id first+99, network judged with it, none in "all together"); host tuning read-back `host.tuning.*` gated, `host.facts.*` shown only; fixed addresses (host pool/gateway/DNS, identity check hostname=VM name) + prepared image (builder VM first+98, offline first boot); outside workload (TestAuto workflow execute + poll, judged, errors status-code only). Proven: laptop Docker (far end, outside workload vs self-test), home box tuning reads only. NOT tried: far-end VM, fixed addresses, prepared image on any host; real TestAuto. 177 non-Docker + 8/8 Docker (laptop/WSL2) pass 11/14. Docs/README/design/plan swept; DocsTests pin agent tag and NotBuilt page.
- 11/14 home box (mechanics only): prepared image made (`/root/tai-prepared.qcow2`, Gene: KEEP it), stack homefix (9101/9102 + far end 9200, fixed addresses Gene gave) up offline ~1 min; Short check 35/35. Exposed a false red: 2 instances = neighbour net load hits the measured instance; Gene chose "run it, report only" (`Analyzer.DirectLoad`).
- 11/14 Phase 3 = Gene's top-5 enhancements, built (uncommitted, agent unchanged 1.2.0): host counters (schedstat/io/tap per measured pass, evidence only), outside workload as headline, judge-tails tick, load strengths `neighbour:x@NN` + trend + bound line, leak table + host fix script (never run). Profisee/TestAuto workload built not tested by Gene's call. 203 non-Docker pass.
- Home Proxmox proved mechanics only (build, pin read-back, Refused on deliberate unpin, change layout 3 to 2, VM removal). Home numbers never stand for CORPSQL03.

**Why:** Gene asked for isolation proof before multi-instance on the big Proxmox host ([[project_corpsql03_proxmox_conversion_2026-11-09]]).
**How to apply:** Next step is a real run on the lab host once Gene sets it up; core count settled 11/14: 2x AMD EPYC 9474F (48C/96T each, 256 MB L3 each) = 96 cores / 192 threads, not 512. Still read the host in the harness (NUMA nodes, L3 groups) before sizing. Not built: real Profisee workload as built-in work, Windows guests, setting host tuning (read only), BIOS read.
