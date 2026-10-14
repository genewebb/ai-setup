---
name: reference_corpsql03_missing_wsman_spn
description: "CredSSP to CORPSQL03 fails because no WSMAN/ SPN exists in corp.profisee.com — HOST/ works, WSMAN/ is principal-unknown; both CredSSP roles were already correct"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 23c64c4d-7617-4cc7-8c1d-56566aee172f
  modified: 2026-08-05T14:07:05.304Z
---

CrewChief on CORPVMHA1 → target CORPSQL03.corp.profisee.com: the /setup CredSSP light fails with
"A computer policy does not allow the delegation of the user credentials to the target computer because the
computer is not trusted." **Both CredSSP roles were already correctly configured** — the message is
misleading (diagnosed 2026-08-05).

Real cause: **no `WSMAN/` SPN exists for CORPSQL03**. CredSSP's stage-2 target-identity check demands a
Kerberos ticket under the `WSMAN` service class; the KDC has no principal for it.

Evidence:
- `setspn -Q WSMAN/CORPSQL03.corp.profisee.com` → `No such SPN found.`
- `setspn -L CORPSQL03` → `HOST/`, `RestrictedKrbHost/`, `MSSQLSvc/`, `TERMSRV/` … no `WSMAN/`.
- `klist get WSMAN/CORPSQL03.corp.profisee.com` → `0xc000018b` / substatus `0x6fb` (KDC_ERR_S_PRINCIPAL_UNKNOWN).
- `klist get HOST/CORPSQL03.corp.profisee.com` → **succeeds**, same logon, same KDC. So TGT, secure channel,
  computer object, and DNS are all healthy — only the service class is missing.
- Host side verified correct: `Client\Auth\CredSSP = true`, `AllowFreshCredentials\3 = wsman/CORPSQL03.corp.profisee.com`,
  `ConcatenateDefaults_AllowFresh = 1`. Target side verified: `Service\Auth\CredSSP = true`.

**The `HOST/` succeeds while `WSMAN/` fails** asymmetry means this domain's `sPNMappings` does not alias
`wsman` onto `host`. It also explains a green Kerberos light next to a red CredSSP light on the same box:
first-hop WinRM accepts the `HOST/` ticket, CredSSP will not.

**How to apply:** the fix ranking depends on [[reference_corp_domain_no_ad_write_access]] — the SPN write is
unavailable, so the usable remedies are (1) stop hopping twice (Configure step `sqlUserName`/`sqlUserPassword`
SQL auth), (2) `AllowFreshCredentialsWhenNTLMOnly` scoped to the one FQDN on the CrewChief host, (3) ticket
the SPN to someone with rights. A red CredSSP light is harmless unless a step genuinely double-hops.
