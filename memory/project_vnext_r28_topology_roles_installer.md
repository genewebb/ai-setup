---
name: project-vnext-r28-topology-roles-installer
description: "vNext R28 (Gene 2026-09-04 21:21-21:44): roles ApplicationServer/TestServer/DatabaseServer never hostnames; control plane in containers on the TestServer; Windows agent SERVICE on every Windows target (pull from RabbitMQ, no remoting), always local admin (+sysadmin on DB), domain-admin service creds; roles are a SET, one service per distinct account, Combination preset; real Inno installer; no PSRP spike"
metadata: 
  node_type: memory
  type: project
  originSessionId: 301c0733-898b-4526-95d4-829606c98753
  modified: 2026-09-05T01:46:50.556Z
---

Recorded in `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\vNextImplementation_v3.md` §5f (R28) and
`TaskList.md` rows 28/33/34/42/53. Also decided the same evening: R27 Q3 = NAMED centrals in config, local warehouse
always kept (§5e); 11.6/11.7 TestData surfaces are separate deliverables from UoW-12/13 parity (§0).

**Why:** Gene's environment is three roles on one-to-three Windows boxes (Profisee app server stays Windows; the vNext
host runs Rancher Desktop; SQL Server separate), and CrewChief-style box prep must keep working. Remoting into Windows
from a Linux container (no CredSSP, double-hop) was the weak path; a pull-based Windows agent per target reuses vNext's
existing RabbitMQ agent model. Gene wants a REAL install program (Inno, donor pattern), run as domain admin, service
under domain-admin creds via the SCM (no secret file), role presets incl. **Combination** (never label it "developer"),
credentials page with one-service-per-distinct-account grouping.

**How to apply:** never write SMVM*/hostnames into plan, schema, installer or code — roles + operator reference data
only. A6.0 (row 28) re-cuts A6 for process-identity agents (effective identity = the service account; local probers are
startup self-checks). UoW-7 gains role registration + role-tagged work + refusal by name. Row 53 = the installer, after
A6 closes. The A2.3f secrets-folder ACL item is closed into the installer. `secrets-bootstrap` takes the master over
stdin from the installer's bootstrap page — never a command-line argument.

Related: [[project-speedmerchants-run-profile-design]], [[project-vnext-a23f-master-bootstrap-probe]],
[[feedback-iteration-close-print-remaining-tasks]].
