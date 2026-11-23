---
name: project_isolation_decisions_2026-11-23
description: "Gene's 11/23 isolation decisions - bulk closed by U5 multiqueue (queues = vCPUs) + 11 h P7 after P5, gate rules, scan follow-up, Connect 1K time test, 9th drive slot question"
metadata:
  node_type: memory
  type: project
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-23T14:52:30.520Z
---

Gene, 2026-11-23 09:35-09:43 (AskUserQuestion), CorpProxMox01 isolation:

- Network bulk: NOT the pooled 3-day result. Install TAI 14.8.0 (guest queue read-back `guest.net_queues`, T3) after P5, set U5 virtio multiqueue = queues per card equal to vCPUs (instances 12, far end 4, harness caps), deploy, Short check gate, then one 11 h P7 with bulk judged.
- Gate fails (bulk noise too high, bulk own-load control still blind on iso1/iso2, or another judged figure moves): undo U5 (back to one queue), record, stop and ask Gene in the morning. No P7.
- Gate passes: U5 stays in the final setup; verdict must say soak/cold start/reboot/P5/3 pooled P7 days ran on single queue; add U5 to note 10 and the Executive Summary Changes table.
- SQL scan 21% faster since the 11/23 reboot: investigate after the verdict (host huge pages against scan, 1 GB pages).
- 2-pair vs 4-pair time test (Windows phase): Connect 1K pack, 3 runs per size alternating.
- During P5 (no host access): Windows phase plan doc, SQL slow mode offline analysis, final report draft.
- 09:43 Gene: adding 1 internal 4 TB drive for container and DB storage. I recommended slot 2 (node 0, keeps nodes 1-3 at 2 drives; Speedy on node 0 chiplet 0), fitted after the final verdict, thick LVM. Gene APPROVED 10:13 (slot 2; use = staging for container images and DB backups). Gene also approved the U5 gate rules (note 11, 10:00 entry): baseline gate run on one queue, then U5, then gate run; pass needs read-backs 12,12 / 4,4, bulk noise lower than baseline on all three and <=10 pairs to decide, iso1 AND iso2 own-load slows bulk (lower bound >0), other judged figures within 5% and 0 Not isolated.

**Why:** bulk's own-load control only works on iso3, so pooled bulk was weak evidence; Gene wants it proven.
**How to apply:** follow the gate rules exactly overnight; never install TAI while a test runs; deploy after install before any test. Related: [[project_isolation_test_plan_page_2026-11-17]], [[project_isolation_windows_containers_adjustable_2026-11-22]].
