---
name: reference_testauto_https_localhost_name_mismatch
description: TestAuto browser shows Not secure on https://localhost:8443 even though HTTPS bound correctly - machine cert SANs never include localhost
metadata: 
  node_type: memory
  type: reference
  originSessionId: 02caa20e-5e33-4ece-b132-07431cd7a8cb
  modified: 2026-08-10T14:28:23.945Z
---

**"TestAuto is not starting as HTTPS" is usually a URL problem, not a binding problem.** Verified on CORPLTR94 2026-08-10: the box's own `SystemLog.log` showed `HTTPS certificate thumbprint resolved: 00cc5a5f...`, `Certificate found: Subject=, HasPrivateKey=true`, and `Kestrel listening on: https://[::]:8443` — HTTPS was fully healthy. The screenshot symptom was the browser's red **Not secure** against `https://localhost:8443`, which is a pure **name mismatch**: an AD-autoenrolled machine certificate lists only the FQDN in its SAN (here `CorpLTR94.corp.profisee.com`) and never `localhost`.

Diagnosis order that works — do NOT infer from the secrets profile:
1. `Get-ChildItem 'C:\Deploy\TestAuto\web' -Filter *.log -Recurse` → the log lives at `web\LogFiles\SystemLog.log`, **not** `web\logs`.
2. Grep it for `thumbprint|HTTPS|Kestrel listening`. If `Kestrel listening on: https://` is present, binding is fine and the problem is the address being opened.
3. `Get-Content 'C:\Deploy\TestAuto\TestAuto Web UI.url'` — the installed shortcut is the thing that actually sends operators to the wrong host.

Two contributing defects, both fixed 2026-08-10:
- The installed shortcut read `URL=http://localhost:8080`. `TestAuto.iss` `ComputeLaunchBase` probes the cert store, but its **inline `powershell -Command` one-liner fails under PS 5.1 quoting** (returns exit 1 with a perfectly good store), forcing the http fallback. Rewritten to write a temp `.ps1` and run it with `-File`.
- Nothing corrected the host at runtime. `UseHttpsRedirection` cannot: it upgrades the scheme but **keeps the typed host**, so `http://localhost:8080` lands on `https://localhost:8443` and warns identically. Added a canonical-host redirect in `PipelineExtensions` ahead of `UseHttpsRedirection`, gated on the new `IHttpsRuntimeStatus` marker, GET + `Accept: text/html` only, skipping `/api`, `/swagger`, `/_blazor`, `/_framework` and static assets.

Also verified and NOT the cause: the corp issuing CA (`CN=corp-CORPIT01-CA`) **is** trusted in `LocalMachine\Root` (valid to 2029), and the pinned cert **does** carry the Server Authentication EKU. Chain build reports only `RevocationStatusUnknown`/`OfflineRevocation`, which browsers soft-fail — not a warning source.

Related: [[reference_testauto_cert_thumbprint_autorenewal]], [[project_testauto_service_install_plan]], [[reference_testauto_service_boot_7009_timeout]]
