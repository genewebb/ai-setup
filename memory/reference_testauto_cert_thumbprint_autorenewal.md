---
name: reference_testauto_cert_thumbprint_autorenewal
description: "TestAuto HTTPS startup crash after AD autoenrollment renews the machine cert - thumbprint pinned in secrets goes stale, and the dev-cert fallback kills the host"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 820b84e9-4070-4604-bb5f-1450d120f337
  modified: 2026-08-05T16:27:24.858Z
---

TestAuto.Web pins an HTTPS cert **thumbprint** in the TestAutoSecrets record (`Certificates.values.LocalHttpCertificateThumbprint`, token `{{Certificates:LocalHttpCertificateThumbprint}}`, resolved at `TestAuto.Web/Program.cs:240`). AD Certificate Services autoenrollment renews the machine cert on its own schedule (~80% of a 1-year lifetime), which generates a **new key pair** and therefore a new thumbprint, then **archives** the superseded cert. Result: `Certificate with thumbprint <old> not found in LocalMachine\My store`.

Two traps that cost time on 2026-08-05 (SMVMTR2):

1. **It looks like the deploy caused it.** The store changes while the app is running with no failure; the outage lands at the next restart, so it correlates with whatever was deployed. Check `git log` on `KestrelExtensions.cs` / `Program.cs` before believing a code cause - that code has been static since 2026-04-28.
2. **Autoenrollment issues certs in PAIRS, 1-2 seconds apart**, and only one has Server Authentication EKU (`1.3.6.1.5.5.7.3.1`). The Client-Auth-only sibling looks equally plausible (same SAN, same CA) and Kestrel rejects it. Blank `Subject` with the FQDN only in the SAN is **normal** for these certs - not a disqualifier.

Confirm auto-replacement from the box, don't infer: `Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational`, event **1001 = replaced**, 1006 = installed, 1005 = archived; Details name old and new thumbprints. Archived certs are invisible to `Get-ChildItem Cert:\` and to `X509Store.Open` without `IncludeArchived` - use `certutil -store My <thumb>` to see one.

Tooling: `C:\devopslocal\powershellscripts\Find-HttpsCertificate.ps1` (`-ComputerName`, `-CurrentThumbprint`) ranks eligible certs per machine. How-to: vault `52 Technical\Powershell\Get Certificate for Test Auto.md`.

Known open code weakness: the missing-cert fallback at `KestrelExtensions.cs:72` and `:106` calls `lo.UseHttps()` with no cert, which needs an ASP.NET dev cert no server has - so a stale thumbprint crashes the host at `builder.Build()` instead of degrading. Its own comment claims it degrades gracefully. Fix would be HTTP-only + `AppStartupStatus` banner, plus SAN/EKU-based lookup with thumbprint as override. Not implemented as of 2026-08-05.

Related: [[project_crewchief_https_certonly_and_iisreset_rename]], [[reference_bare_http_error_means_stale_build]]
