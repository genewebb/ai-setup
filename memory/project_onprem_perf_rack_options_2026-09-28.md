---
name: project-onprem-perf-rack-options-2026-09-28
description: "Replace 9 IaaS perf-test VMs ($15K/mo) with on-prem hardware; two options live in Lucid doc PerfRack2; user decisions on licences, switches, control plane, SQL"
metadata:
  node_type: memory
  type: project
  originSessionId: c7e2ebe3-f07a-4081-a9b6-261bfe39d308
  modified: 2026-09-28T22:57:25.616Z
---

Replacing 9 IaaS perf-test VMs (32c/256GB each, $15K/month) with on-prem. Lucid doc "PerfRack2" https://lucid.app/lucidchart/2710c4e7-9e94-47ec-85c4-48bb09ba0419/edit has two pages:
- Option A - 9 Server Rack: 9x Supermicro 1U EPYC 32c/256GB (~$21K each), new 42U rack, UPS, PDUs. ~$215,550 HW.
- Option B - Big Server: duplicate of CORPSQL03 (~$135K HW) hosting 9 VMs; only fits 9 at ~20 vCPU/150GB. ~$141,050 HW.
Mermaid sources: C:\tmp\PerfRack.mmd (A), C:\tmp\PerfRack-OptionB.mmd (B); edit, Set-Clipboard, paste into Lucid "Diagram as code" panel (Elk layout). Lucid draw.io/.mmd file import does NOT work.

User decisions 9/28: licences all under enterprise agreement (show $0/none); CORPSQL03 already owned; no 9 SQL servers on CORPSQL03 — workers are a MIX of Windows + SQL Developer Edition and app-only (split TBD); switches 2x MikroTik CRS326 10GbE (no $20K 25GbE); 1 control-plane node, add 2 later; cheap 1GbE mgmt switch. Electrical + A/C are TBD placeholders.

Vault notes: `52 Technical\Containers\NewHardware\` (Overview, Option A/B, Isolation = critical-path setup+test guide, Orchestration = Hyper-V+Packer+Ansible). Speedy integration PROPOSAL: `99 Documentation\speedy\perf-method\Speedy-Perf-Method-Design.md` — Experiment (arms, ABBA, reset), stats verdict, noise floor, engine counters, trends. Decided 9/28: 5 reps/arm, Welch t + bootstrap CI, headline = median+throughput+logical reads, P1 = new group after G6; P0 manual null test now. Not yet FEAT yaml — needs requirements-system review.

**Why:** perf-test capacity, cut IaaS spend. **How to apply:** keep both options alive; all prices are Claude estimates, not quotes.
