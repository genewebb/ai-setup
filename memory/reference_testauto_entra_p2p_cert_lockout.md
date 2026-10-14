---
name: reference_testauto_entra_p2p_cert_lockout
description: TestAuto unreachable after a clear-secrets install because cert auto-discovery bound an Entra MS-Organization-P2P-Access device cert and HSTS made the interstitial unbypassable
metadata: 
  node_type: memory
  type: reference
  originSessionId: b3eaccad-5bf3-41b5-8aea-971b41e625af
  modified: 2026-08-10T17:36:47.043Z
---

**"Cannot open TestAuto after a clean install" on an Entra-joined box is a certificate-selection lockout, not a port, service, or CrewChief conflict.** Verified end-to-end on SMVMTR2 2026-08-10 (v1.34.9719.28991, service identity `SMVMTR2\ProfAdmin`).

Chain, each link confirmed from the box:
1. Setup's **clearsecrets** task (`TestAuto.iss` `ClearLocalSecrets`, ~line 669) deletes `%ProgramData%\TestAuto\master.json` and writes `.legacy-migration-done`. Re-running Setup with that task checked RE-CREATES the fault — it can never cure it.
2. Degraded mode ⇒ no `WebUI:Certificate:Thumbprint` and no `WebUI:HostName`.
3. `KestrelExtensions` sourced the DNS suffix from **`USERDNSDOMAIN`**, which winlogon sets only for an INTERACTIVE DOMAIN logon — absent in a service under a LOCAL account. Candidate list collapsed to the short name: log line `Host names tried, in order: SMVMTR2`. Under `CORP\speedmerchants` the same binary had listed the FQDN first (it came from secrets' HostName, not the env var).
4. Corp cert `10BF76CA…` (SAN = `SMVMTR2.corp.profisee.com` only, good to 2027-08-05) therefore did not host-match. Discovery bound instead:
   `issuer=CN=MS-Organization-P2P-Access [2026]`, `SAN: DNS:SMVMTR2, DNS:SMVMTR2, DNS:10.0.0.12`, EKU **TLS Web Server Authentication**, 24-hour validity. An Entra device cert, reissued daily, trusted by nothing. The EKU filter cannot catch it — only chain-building can.
5. `http://…:8080` answered `302 → https://smvmtr2:8443`, and the FQDN served `Strict-Transport-Security: max-age=2592000` during the earlier healthy run. HSTS + untrusted chain = **no "Proceed anyway" link in Chrome/Edge**. The operator cannot reach `/secrets/bootstrap`, the only page that fixes it.

Diagnosis shortcuts that worked (WinRM/Kerberos to SMVMTR2 fails, but `\\SMVMTR2\c$` is readable):
- `\\SMVMTR2\c$\Deploy\TestAuto\web\LogFiles\SystemLog.log` — grep `Host names tried|Automatically selected|Secrets not ready`.
- `%ProgramData%\TestAuto` holding ONLY `.legacy-migration-done` + `dataprotection-keys` = store wiped.
- `openssl s_client -connect <box>:8443 | openssl x509 -noout -issuer -dates -ext subjectAltName,extendedKeyUsage` names the culprit cert in one shot. `curl` exit **60** = untrusted chain.
- NOT CrewChief: it is port 5030 with its own `%ProgramData%\CrewChief\secrets`.

Escape hatch with no box change: type `thisisunsafe` on the Chrome interstitial.

Fixes written 2026-08-10 (working tree, user rebuilds; unit suite 27/27):
- `KestrelExtensions.ResolveDnsDomain()` — `IPGlobalProperties.GetIPGlobalProperties().DomainName`, `USERDNSDOMAIN` only as fallback.
- `HttpsCertificateResolver` — new `IsChainTrusted` (chain build, revocation NoCheck, `RevocationStatusUnknown`/`OfflineRevocation` treated as benign per CORPLTR94), optional `trustProbe` on `ResolveFrom`, and discovery ranking changed to **TrustRank → HostRank → NotAfter**. Untrusted still selectable as last resort but flagged on `HttpsCertificateResolution.IsChainTrusted`.
- `PipelineExtensions` — `UseHsts`, the canonical-host redirect, and `UseHttpsRedirection` all gated on `IHttpsRuntimeStatus.IsChainTrusted`, so an untrusted cert never pushes browsers off reachable HTTP.

Related: [[reference_testauto_https_localhost_name_mismatch]], [[reference_testauto_cert_thumbprint_autorenewal]], [[project_testauto_service_install_plan]], [[project_testauto_secrets_persistence_diagnosis]]
