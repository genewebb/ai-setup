---
name: testauto-https-hosting
description: >
  TestAuto.Web's HTTPS story — certificate auto-discovery and ranking, the HTTP-only-on-failure Kestrel
  rule, and the canonical-host redirect that fires before UseHttpsRedirection. Use when HTTPS will not come
  up, when the browser says "Not secure" on a machine that has a valid certificate, when choosing or
  rotating the WebUI certificate thumbprint, when working on KestrelExtensions / HttpsCertificateResolver /
  PipelineExtensions, or when diagnosing a redirect to an unexpected host name.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto HTTPS Hosting

How TestAuto.Web decides whether to serve HTTPS, which certificate to use, and which host name to send a
browser to. The short version: **a configured thumbprint is an override, not a prerequisite**, and **every
failure path serves HTTP rather than dying**.

## When to Use

- "HTTPS isn't coming up on this box."
- "The browser says Not secure but the certificate is valid."
- Rotating or choosing `WebUI:Certificate:Thumbprint`.
- Working on `HttpsCertificateResolver`, `KestrelExtensions`, or the canonical-host redirect.
- "Why did it redirect me to a different host name?"

## Resolution order — configured thumbprint FIRST, then discovery

`HttpsCertificateResolver` (`TestAuto.Web/Services/HttpsCertificateResolver.cs`):

1. **Configured `WebUI:Certificate:Thumbprint`**, if it resolves and passes the hard filters (`:122-193`).
2. Otherwise **auto-discovery** from `LocalMachine\My`, ranked by preferred-host order, then latest expiry
   (`:203-272`).

Hard filters applied to every candidate — a certificate failing any of them is rejected, configured or not:

| Filter | Note |
|---|---|
| Inside its validity window | — |
| **Private key readable** | Probed *the way Kestrel will*, not merely "is a key present" |
| **Server Authentication EKU** | OID `1.3.6.1.5.5.7.3.1` (`:91`, `:460-485`) |
| Not archived | The store is read **without** `IncludeArchived` (`:87`), so a superseded certificate can never be resurrected by discovery |

Host names come from `BuildPreferredHostNames` (`:350`), and **`localhost` is deliberately excluded**
(`:362`): a localhost-only certificate would bind HTTPS successfully and then fail for every real client,
which is worse than not binding at all. `GetDnsNames` (`:496`) reads SANs first and tolerates a blank
Subject.

## Failure means HTTP — there is NO dev-cert fallback

> [!important] Every HTTPS failure path skips the listener and serves HTTP on `WebUI:HttpPort`
> `KestrelExtensions.cs:50-54` states the rule; `:146-151` is the else-branch that warns and does not call
> `UseHttps`. Operator boxes installed from `Setup.exe` have **no dotnet SDK and no dev certificate**, so
> `UseHttps()` without a certificate would throw during bind and kill the entire app — under the SCM, a dead
> service with nothing at all in the browser. HTTP always survives.

Diagnosis goes through `IHttpsRuntimeStatus.Notices`, an **ordered** list of why each candidate was
rejected, surfaced both in the startup log and on the `/secrets` page. That marker is registered by whoever
*decided* — no consumer re-derives HTTPS state from the certificate store (see the runtime-availability
marker convention in [[testauto-windows-service-hosting]]).

## The canonical-host redirect — and why `UseHttpsRedirection` is not enough

`PipelineExtensions.cs:93-130` installs a redirect that runs **before** `UseHttpsRedirection()`.

The problem it solves: `UseHttpsRedirection` upgrades the *scheme* but keeps the *typed host*. So a user
who typed `http://localhost:8080` on a machine holding an FQDN-only certificate gets sent to
`https://localhost:8443` — and the browser correctly reports "Not secure", because the certificate does not
cover `localhost`. The machine is fine; the URL is wrong.

Rules:

- The redirect target is the name in the **certificate** (`KestrelExtensions.cs:101-107`), **never**
  `WebUI:HostName`.
- It fires only for **GET + `Accept: text/html`** (`IsBrowserNavigation`, `:224-256`), bypassing
  `/api`, `/swagger`, `/_framework`, `/_blazor`, `/_content`, `/css`, `/js`, `/lib` and static suffixes —
  the same bypass shape as [[secrets-bootstrap-middleware]].
- **Loop safety** comes from the canonical host always matching itself; `IsCoveredByCertificate`
  (`:263-284`) handles single-label wildcard SANs.

## Sources

- `TestAuto.Web\Services\HttpsCertificateResolver.cs`
- `TestAuto.Web\Services\HttpsRuntimeStatus.cs`
- `TestAuto.Web\ServiceExtensions\KestrelExtensions.cs`
- `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs`
- `TestAuto.Web\Services\ConfigurationValidationService.cs`
- `Testing.SpeedMerchants.Unit\Web\Services\HttpsCertificateResolverTests.cs`
- `TestAuto.Web\Documentation\CertificateRenewal.md`, `HowToExportCertificate.md`

## Related

[[testauto-windows-service-hosting]] · [[testauto-deployed-machine-diagnostics]] · [[testauto-secrets-management]] · [[secrets-bootstrap-middleware]] · [[inno-setup-installer]]
