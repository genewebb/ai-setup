---
name: secrets-bootstrap-middleware
description: >
  SecretsBootstrapMiddleware in TestAuto.Web that enforces secrets configuration on
  startup. Use when understanding the application bootstrap flow, diagnosing redirect
  loops to /secrets/bootstrap, adding paths that should bypass the middleware, or
  registering the middleware in Program.cs.
---

Repo: speed-merchants (paths below are repo-relative)

# Secrets Bootstrap Middleware

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/Middleware/SecretsBootstrapMiddleware.cs`

> [!important] WIRED INTO THE PIPELINE as of 2026-08-08
> `app.UseSecretsBootstrapRedirect()` is called in
> `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs` (`ConfigurePipeline`), immediately after
> `UseAntiforgery()`. The redirect is LIVE: a box with no master password / ScenarioMgt config sends
> every non-bypassed HTML request to `/secrets/bootstrap`. This is the primary first-time-setup path
> — the console prompt in `Program.cs` runs only on interactive launches (it is skipped under the
> Windows Service / redirected input). The old
> [[project_secrets_bootstrap_middleware_not_wired]] memory is obsolete.

`SecretsBootstrapMiddleware` prevents the application from being used until the master password and ScenarioMgt REST credentials are configured, by redirecting any HTML request to `/secrets/bootstrap` if either check fails.

---

## Redirect Condition

```csharp
// SecretsBootstrapMiddleware.cs:84-86
var needsBootstrap = !passwordManager.IsPasswordConfigured()
                  || !passwordManager.IsScenarioMgtConfigured()
                  || !runtimeSecrets.SecretsLoaded;
```

**All three** must pass. Both `IMasterPasswordManager` and `RuntimeSecretsStatus` are method-injected into
`InvokeAsync` (not constructor-injected).

> [!important] The third condition is about THIS PROCESS, not the disk
> `RuntimeSecretsStatus.SecretsLoaded` records whether the running process actually loaded a usable secrets
> profile at startup. Secrets load **only at startup**, so a box that is fully configured on disk but has
> not been restarted since the import stays locked to the secrets area. That is deliberate: the app would
> otherwise present itself as ready while holding no credentials, and every downstream call would fail with
> a far less obvious error. The fix is a restart, not a reconfiguration — see
> [[testauto-secrets-management]].

Redirect only fires for requests that include `text/html` in the `Accept` header, or that have no `Accept` header. Non-HTML requests (API calls, SignalR) pass through even when bootstrap is needed.

---

## Bypassed Paths

The following are always allowed through, regardless of bootstrap state:

**Prefix matches** (case-insensitive):
- `/secrets` — **the whole secrets area** (`:35`), not just `/secrets/bootstrap`. It covers the bootstrap
  wizard, the `/secrets` management console, the edit routes, and the restart button, so an operator locked
  out by the third condition above can still reach the page that fixes it.
- `/_framework`
- `/_blazor`
- `/_content`
- `/api` (added 2026-08-08 — API clients keep their own 401/503 semantics, never an HTML redirect)
- `/swagger` (added 2026-08-08)
- `/css`
- `/js`
- `/lib`

**Suffix matches** (static files):
- `.ico`, `.css`, `.js`, `.woff`, `.woff2`, `.ttf`, `.png`, `.jpg`, `.svg`

To add a new bypass path, extend `AllowedPathPrefixes` or `AllowedPathSuffixes` in the middleware.

---

## Registration

Registered in `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs` (`ConfigurePipeline`),
immediately after `app.UseAntiforgery()` and before `UseResponseCompression()`:

```csharp
app.UseSecretsBootstrapRedirect();
```

The extension method is `SecretsBootstrapMiddlewareExtensions.UseSecretsBootstrapRedirect`. It
redirects **all** non-bypassed HTML requests while bootstrap is incomplete — so when adding a new
top-level route that must work on an unconfigured box, extend the bypass list
(`AllowedPathPrefixes`/`AllowedPathSuffixes`) or you get a redirect loop. DI note:
`IMasterPasswordManager` is method-injected into `InvokeAsync` and registered unconditionally in
`RegisterAllServices` (degraded mode included), so the middleware is always resolvable.

---

## Sources

- `TestAuto.Web\Middleware\SecretsBootstrapMiddleware.cs`
- `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs` (wiring)
