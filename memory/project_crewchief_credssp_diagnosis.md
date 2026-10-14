---
name: project_crewchief_credssp_diagnosis
description: Setup Verification now diagnoses WHICH CredSSP precondition failed (client role / delegation list / missing WSMAN SPN / target role) instead of reprinting both Enable-WSManCredSSP commands
metadata: 
  node_type: memory
  type: project
  originSessionId: 23c64c4d-7617-4cc7-8c1d-56566aee172f
  modified: 2026-08-05T14:24:17.607Z
---

Shipped 2026-08-05 (uncommitted; user rebuilds). Driven by [[reference_corpsql03_missing_wsman_spn]] — the
page told an operator to run two commands they had already run.

**New seam:** `CrewChief.Engine/Executors/ICredSspHostDiagnostics.cs` — `CredSspHostState` +
`DefaultCredSspHostDiagnostics`, one `powershell.exe` shell-out returning compact JSON (client `Auth\CredSSP`,
`AllowFreshCredentials` / `AllowFreshCredentialsWhenNTLMOnly` toggles and entries, and a
`klist get WSMAN/<fqdn>` ticket probe). No registry-package dependency; wildcard entry matching uses
`FileSystemName.MatchesSimpleExpression` (DOS `*`/`?` only — no `-like` character classes).

`DefaultRemoteAccessChecker` takes it as an optional 5th ctor param (`credSspDiagnostics`), consulted ONLY
when the CredSSP light fails. Null keeps the old generic advice — that is why unit tests never shell out.
Four new remediation branches in `RemoteAccessRemediation`: `CredSspClientRole`, `CredSspTargetRole`,
`CredSspSpnMissing` (ranks SPN write / SQL-auth / NTLM-only stopgap), plus the original `CredSsp` as the
unknown-state fallback.

**Defect fixed in the same pass:** `LooksLikeCredentialRejection` matched a CredSSP delegation refusal,
because that message contains the word "credentials". It recorded a network-logon failure the account never
suffered, so the NEXT Run Check demanded confirmation to spend an attempt that was never spent. Carve-out
now returns false for "does not allow the delegation" / "policy does not allow" / "because the computer is
not trusted".

Lockstep sites all updated (see [[project_crewchief_remote_setup_script]] — the rule is four places):
`IRemoteAccessChecker.cs`, `43_OpsRemoteBoxPrep.md` §5 (new "When both roles are set and CredSSP still
fails" subsection), `44_OpsRemoteManagementSetup.md`, and `installer/Enable-CrewChiefRemoteManagement.ps1`
(new `-WarnOnly`, no-`-Fix` step "Target WSMAN service principal resolves"). 2681 unit tests green.
