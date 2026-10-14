---
name: project_crewchief_remaining_port_2026-09-23
description: "Gene 9/23 approved coding ALL 16 remaining CrewChief requirement docs (REVIEW/DRAFT) into Speedy; defaults chosen for Windows host, layout, REST/Email/Teams"
metadata:
  node_type: memory
  type: project
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-23T19:13:23.520Z
---

Gene, 2026-09-23 09:05: "All are approved for coding" — the 16 docs (PROCESS, BUILD, UI-STEPS, UI-WORKLOADS, SETAPI, WAIT, WINDOWS, CLU, PREPARATION, CLI, UI-ACTIVITY, DATABASE, EXECUTORS, CONNEX-TOKENIZATION, MODEL-IMPORT, UI-SHELL; REQ-UISHELL-003 excluded).

Baseline 9/23: Speedy had only 5 executors (CommandLine, PowerShell, Sql, Curl, ConnEx); no Windows step worker, no WinRM/RunAs runner, no workload editor/Activity/Model Import/Connect wizard.

Windows host (Gene 9/23 09:05 "use your local machine"): the local Windows box (CORPLTR94) running Speedy natively is the Windows execution host; real local + WSMan-from-local routes, verified here. Layout: hybrid AGREED by Gene 9/23 09:06 (ScreenScaffold, Steps 5/7, Workload editor full-width); include REST HttpRequestStep/Email/Teams.

Boundary (Gene 9/23 "4 yes"): include REST HttpRequestStep/Email/Teams; Help = CrewChief 63 files + new Speedy pages now; Activity = step/workload families now.

**How to apply:** don't re-ask approval; record results honestly as unapproved-revision implementation. Related [[feedback_speedy_workflow_layout_full_width]].

**Status 9/23 13:00:** coded and committed in speedmerchants (e68e17c..df1d2c5): CLI run verbs, 28 executors, Model Import, Connect conversion, Help (63 docs + catalog), shell error states, file browser, per-library folders. Unit 6232 / Web 581 / Arch 21 green. Open for Gene: SetApiKey unusable (no run-profile binding to executors), build stages refuse remote/RunAs, narrow shell squeezes content (~200px at 700px, pre-existing), TestAuto/generation/mutation help not mapped, admin CLI secrets-* verbs vs UI-only rule, DocumentFormat.OpenXml added. No independent verifier has run any VERIFY-* plan.

**Status 9/23 15:30:** all Gene's open choices applied and committed through 52747e0: run identity into executors, build stages remote/RunAs, off-canvas drawer, admin CLI verbs removed (Testbed.Define harness for proofs), Help 75 docs + mermaid, Windows preflight, abandoned-run recovery, share-mount browse. Coverage published: 43 rows verified (48 evidence records under evidence/<FEAT>/<rev>/, actor = Gene's 'PReviously verified update as verified'), 24 implemented (no test names their ACs: UI-ACTIVITY all, UI-STEPS/WORKLOADS screens, CLI AC-002..005, STEP-PROCESS WINEXEC-002..005 + PSCRIPT-004 + PROCINPUT-003, EXECUTORS AC-EXEC-001/002, CNX-013/029, UISHELL-001/002), 1 not applicable. Generator: scratchpad cov_*.py. Real platform never exercised (WSMan, RunAs, SetApiKey DB, SMTP/Teams, destructive Windows ops, ADO transfer).
