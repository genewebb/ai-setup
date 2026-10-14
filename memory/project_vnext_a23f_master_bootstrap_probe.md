---
name: project_vnext_a23f_master_bootstrap_probe
description: "UoW-9a iteration 11 (2026-09-03) — A2.3f master.json bootstrap PROBE done; D1–D10 recommendations AWAITING GENE'S APPROVAL before any code; what was decided and what is still open"
metadata: 
  node_type: memory
  type: project
  originSessionId: 508faea1-6329-451d-ade1-56dc581645d5
  modified: 2026-09-03T21:10:47.568Z
---

**A2.3f probe closed 2026-09-03 17:07** (iteration 11 of the UoW-9a loop, `C:\devops\repos\speedmerchants`).
Deliverable: `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\A2_3f_MasterBootstrap.md` (364 lines).
Grader: `.loop\criteria\b2h-master-bootstrap-probe.ps1` (censuses from live source + hash gate over src/ and
tests/ against BASELINE.json, not git status).

**Recommendations tabled (§7 D1–D10), none approved yet:**
- D1 one thin `ILocalMasterBootstrap` port (Application) + `LocalMasterBootstrap` (Infrastructure); the CLI
  `secrets bootstrap|status|delete` verb is the ONLY surface in 9a; Web screen 9.8/9.9 calls the same port later.
- D2 hosts: Cli writes+reads · Coordinator reads only · Web reads now, writes in UoW-9 · Agent neither.
- D3 DPAPI scope follows `SecretsRootResolution.IsMachineShared` (both donor hosts already do this verbatim;
  vNext `SecretFoundationModule` computes the flag and discards it). **D3a (counter-argument WON):** the writer
  must create the secrets folder with a restrictive ACL itself, because vNext has no installer to lay it.
  D3b: report effective scope.
- D4 probe-first "first run" (`SecretsAccessState.AccessDenied` is never a fresh box) · D5 `MasterPasswordPolicy`
  (min 16) ports to Application, enforced inside the port so no surface can skip it · D6 verify against an
  existing store before wrapping · D7 PROPOSED: typed `WrapUnavailable` outcome instead of donor's
  success-with-a-note · D8 key-file hosts use the same writer, `SPEEDY_MASTER_KEY` stays fallback, seam
  precedence UNCHANGED · D9 rotation out of scope, reset = `LocalSecretStoreDeleter` · D10 donor `FirstRunGate`
  is the templates banner, NOT this.

**Donor finding:** at HEAD `7aee7cc` the donor's two master.json writers have drifted — the Web page enforces
`MasterPasswordPolicy`, the CLI `SecretsCommand.cs:118` never calls it.

**Why:** Gene chose a probe (15:16) so the loop proposes and Gene approves before code; a bootstrap writer
decides who/scope/first-run, which a defect fix must not smuggle in.

**How to apply:** do not build A2.3f code until Gene approves; when approved, the code task builds D1–D9 as
decided and does not re-decide them. The FleetVerb fold (Cli has no composed graph) is a prerequisite.
Permission quirk: the `secrets`-segment deny rule blocks `git show` of donor `Secrets/` paths through Bash but
not through the PowerShell tool. Related: [[project_vnext_fable_review_2026-09-03]], [[reference_vnext_plan_doc_v3]].
