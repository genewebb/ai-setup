---
name: project_isolation_test_plan_page_2026-11-17
description: "CorpProxMox01 isolation test plan + results page = SMVMTR1 /speedy/IsolationTestPlan.html from D:\devops\repos\speed-merchants\docs\isolation\plan-page\IsolationTestPlan.html (PLAN data block) via publish.sh; update on every test result"
metadata:
  type: project
---

**Moved to SMVMTR1 2026-11-18:** master copy of notes/page/memory now `D:\devops\repos\speed-merchants\docs\isolation` (START-HERE.md has the laptop-to-SMVMTR1 path table; `docs/` is git-ignored). Older laptop paths below: translate via that table.

Gene 11/17 15:23: full isolation test plan, what's done, results, what's left, published on SMVMTR1 under speedy.

- URL: https://smvmtr1.corp.profisee.com/speedy/IsolationTestPlan.html (plain file in `C:\inetpub\wwwroot\speedy\`, tabs Overview / Test plan / Results / Done / To do / Config changes / Setup; `#results` etc. deep-link).
- Source: `D:\devops\repos\speed-merchants\docs\isolation\plan-page\IsolationTestPlan.html`. All content in `const PLAN = {...}` (asOf, now, phases P0-P9 with s done|run|wait|later|fail, verdict, results[], log, todo, config.it/us, setup). Edit data only.
- Publish: `sh /d/devops/repos/speed-merchants/docs/isolation/plan-page/publish.sh` (node --check of the script block, copy over SMB, prints HTTP status).
- Config tab mirrors vault note `CORPSQL03 Proxmox - 10 Config Changes`; keep both in step.
- Results come from TAI `http://smvmtr1.corp.profisee.com:5080/files/<testId>/report.md` (and summary.json).

**How to apply:** after every isolation test or host change: add results entry + log line, move phase status, update todo/config, bump asOf, republish. Gene 11/17 19:00: page has tab **Changes and lessons** (`PLAN.changes` = one entry per change with before/after rows, s done|fail|run|wait; `PLAN.lessons` = [lesson, what showed it]); add/fill a change entry for EVERY change and a lesson when learned; he will publish the lessons learned. Related [[project_testautoisolation_2026-11-13]], [[project_corpsql03_proxmox_conversion_2026-11-09]].

11/17 15:35 state: P0-P2 done (smoke 20261117-150619 passed 35/35); P3 next = per-instance noise-floor run (iso1 noisy: small tx 41.5%, net 17.5%, write 8.0%).

11/17 17:10 state: P3 run 2 (161840) Test invalid on net round-trip noise; SQL oltp slowdown recurs ~11 min after SQL restart on iso1+iso3 (iso2 never) = not iso1 VM; next = SQL wait stats iso3 vs iso2, don't restart stack.
11/17 17:25: SQL read done (sa+port 14431 from stack json; pyodbc ODBC18 Encrypt=optional, 45 s login timeout needed). DB clean; oltp noise = WRITELOG wake-up beyond disk (0.23 vs 0.37-0.48 ms), all 3 instances; recheck after U1. Next U5/U6.
11/17 17:30: Gene chose oltp report-only until U1; built TAI 13.1.0 = RunProfile.ReportOnly list (Metrics.Choose drops them, Profiles page checkboxes, report item), 281 tests, installer C:\scratch\tai-installer\TestAutoIsolation-Setup-13.1.0.exe, not installed, uncommitted.
11/17 18:00: Gene installed as 13.1.1; P3 run 3 (174522, profile "Plan P3 - Noise per instance Report Only": oltp + net.rt + net.bulk reported only) Completed, six judged figures 0.02-1.6%, neg control inside margin on all 3. Next = U5/U6 network path, then U1+U2+U3 reboot.
11/17 18:42: host read = vhost threads on VM's own CPUs (fine), C2 exit 800 us. U9 = C2 off on 38 test CPU threads (runtime; SMVMTR1 `C:\ProgramData\TestAutoIsolation\host-c2.ps1 off|on`; reboot undoes). Run 4 (182739): oltp back to 71-81 ms all three w/o restart (iso1 was 182), spikes remain; net.rt unchanged 10-19% = not C2. Next suspect U6 far end 2 cores.
11/17 19:00: U6 approved; far end was hard-wired 1 core, built TAI 13.2.0 (PinningRequest.FarEndCores, "Far end: cores" field), 282 tests, installer in C:\scratch\tai-installer, not installed. Pending: Gene installs, sets far end 2 cores on cpm01-smoke, reruns P3 Report Only; fill C7 After.
11/17 19:21: 13.2.1 installed, far end 2 cores (78-79,174-175), C2 off on 40 threads. Run 5 (190607): net.rt FIXED 16-20% to ~3% (iso3 9.5% = cold first pass); oltp slow AGAIN with C2 off (iso1 180 ms) = C2 NOT confirmed (C6 "Not confirmed"), oltp cause unknown, slow state wanders between instances/runs. Next: repeat run, C2 on vs off A/B. Page edits: file is CRLF; python replace scripts must normalise line endings.
11/17 19:42: C2 back ON (U9 dropped, no effect). Run 6 (192718): net.rt 2.2-4.2% all three = far end 2 cores CONFIRMED fix. oltp = two levels (~73 ms vs 130-220 ms), each instance flips by itself, unexplained (not C2/restart/far end/DB). net.bulk iso1 flips 25 vs 32 ms. State: TAI 13.2.1, far end 2 cores, host stock. Next: untick net.rt from Report only (Gene), U5 for bulk, U1+U2+U3 reboot.
11/17 20:10 END OF DAY: run 7 (195209, Gene's profile "Plan P3 - Noise per instance Report v2": oltp + net.bulk reported only, net.rt judged) Completed, no invalid. net.rt 3.0/2.7/4.8%, alone-vs-alone Isolated iso1+iso2, iso3 Not decided on 4 pairs (report: about 14 needed). Seven figures steady and judged. oltp two-level again (iso1 73 ms all run, iso3 183 ms all run, iso2 flipped after 4 passes); net.bulk iso1 12.2%. Page has C1-C9, 13 lessons, 8 results. Nothing running, host stock, TAI 13.2.1, repo uncommitted. Tomorrow Gene picks: (A, recommended) read-only host look at vCPU-to-host-thread mapping during slow vs normal oltp pass (hypothesis, unchecked: vCPUs not pinned one-to-one, guest sees no SMT topology); (B) P4 U1+U2+U3 reboot; (C) U5 for bulk; (D) 14-pair run for iso3 net.rt.

**Restart log (2026-11-17 15:45):** Gene says "restart" = read `D:\devops\repos\speed-merchants\docs\isolation\host\CORPSQL03 Proxmox - 11 Restart Log.md` (Current state + newest Log line) and the page's **Restart** tab (PLAN.restart data). After every result/host change update all three: note 11, page (PLAN + publish.sh), note 10 if config changed. TAI 12.0.0 installer built at C:\scratch\tai-installer\TestAutoIsolation-Setup-12.0.0.exe; next = install, run "Plan P3 - Noise per instance" on cpm01-smoke.
