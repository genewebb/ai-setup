---
name: project_secrets_bootstrap_middleware_not_wired
description: "RESOLVED 2026-08-08: SecretsBootstrapMiddleware is now WIRED (PipelineExtensions, after UseAntiforgery); browser redirect to /secrets/bootstrap is the primary setup path"
metadata:
  node_type: memory
  type: project
  originSessionId: 394d09ac-8db3-4412-b444-4e675b0df823
  modified: 2026-08-09T01:57:50.177Z
---

**RESOLVED 2026-08-08** as Phase 1 of the TestAuto service-install work ([[testauto-service-install-plan]]): `app.UseSecretsBootstrapRedirect()` is now called in `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs` (right after `UseAntiforgery()`), and `/api` + `/swagger` were added to the middleware's bypass prefixes. The browser redirect to `/secrets/bootstrap` IS active and is the primary first-time-setup path; the console prompt in `Program.cs` runs only on interactive launches (skipped under the Windows Service).

Historical context (true 2026-06-08 → 2026-08-08): the middleware existed but nothing called it, first-time setup was console-only, and docs/skill were corrected to say so. Those corrections have been re-corrected the other way (docs sweep + `secrets-bootstrap-middleware` and `testauto-secrets-management` skills updated 2026-08-08).

**How to apply:** Claim the redirect is active. When adding a new top-level route that must work on an unconfigured box, extend `AllowedPathPrefixes` in the middleware or it will redirect-loop.
