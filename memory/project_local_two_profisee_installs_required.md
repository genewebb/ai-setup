---
name: project_local_two_profisee_installs_required
description: "CORPLTR94 local Profisee instances: /Profisee = 26R3 GA (Matching rewrite target, Gene 11/05), /ProfiseeImport 26.3.0, /MyDevProfisee (master source build); Gene decides which run, never stop/start them myself"
metadata:
  node_type: memory
  type: project
  modified: 2026-11-05T14:35:04.678Z
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
---

Local box CORPLTR94 Profisee instances (11/04/2026):
- `/Profisee` 26.2.0 + Windows service `Profisee 26.2.0 (Profisee)`, DB `Profisee`
- `/ProfiseeImport` 26.3.0, no service, DB `ProfiseeConnectImports`
- `/MyDevProfisee` source build of `C:\devops\repos\platform` master (IIS paths into the repo), no service, DB `MyDevProfisee`. Had issues 11/04; NOT the Matching Main.
(The old 26.1.0 `speedmerchants` install from 09/2026 is gone.)

**11/05 (Gene confirmed): https://corpltr94.corp.profisee.com/profisee is 26R3 GA and is the target for the Matching rewrite 1K runs.**

Gene does not want three running at once. 11/04 19:42: MyDevProfisee had issues; Gene is upgrading /Profisee to 26R3 and it becomes the Matching rewrite Main. Version label **26R3T** (not 26R3): T = test runs that will all be deleted later. Gene decides which others run.

**Why:** Gene owns which instances run (RAM; other local tests use them).
**How to apply:** Never start, stop, recycle or delete the non-target instances or their DBs. If one is running when work needs the box, ask (AskUserQuestion). Related: [[project_matching_rewrite_local_1k_2026-11-04]].
