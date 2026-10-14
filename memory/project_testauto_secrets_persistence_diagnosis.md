---
name: testauto-secrets-persistence-diagnosis
description: "Why TestAuto service secrets seemed to \"not persist on 2nd round\" (2026-08-09) — three causes, all resolved in commit 28107baf; verification checklist for future reports"
metadata: 
  node_type: memory
  type: project
  originSessionId: 42705a5a-fb23-47d4-a4e4-c0913d6a696a
  modified: 2026-08-10T00:16:59.554Z
---

2026-08-09: user reported TestAuto (Windows Service) secret bootstrap "works first round, not persisted on 2nd round / desktop icon shows bootstrap again". Diagnosis on CORPLTR94 (deployed exe 15:50 = commit 28107baf):

Three distinct causes, all hit that day:
1. **Legacy-migration resurrection** — pre-fix build re-ran %APPDATA%→%ProgramData% master.json migration whenever the store file was missing, resurrecting a stale dev store after a reset. Fixed with one-shot `.legacy-migration-done` marker in `MasterConfigPathResolver.ResolveMasterFilePath`.
2. **Degraded-mode startup crashes** — with secrets not loaded, service DIED on start (evidence `%ProgramData%\TestAuto\startup-crash.log` 10:50–10:55): (a) `UseHangfireDashboard` called with Hangfire skipped, (b) `WebRecurringJobsService.StartAsync` threw when HangfireDB missing. Both now gated on `HangfireAvailability.Enabled`.
3. **By design** — middleware `SecretsBootstrapMiddleware` has a THIRD gate: `RuntimeSecretsStatus.SecretsLoaded` (computed once at startup from `RestClients:ScenarioMgt:BaseUrl/ApiKey` presence). Between "import succeeded" and "service restarted", EVERY page redirects to /secrets/bootstrap. Desktop icon (= `TestAuto Web UI.url` → http://localhost:8080, a browser shortcut, not a process) before restart → bootstrap again → reads as "didn't reload".

Verification checklist for future "secrets didn't persist" reports:
- `%ProgramData%\TestAuto\startup-crash.log` — early-death breadcrumbs.
- Service log `LogFiles\SystemLog.log`: "SECRETS LOADING" box + middleware line "Secrets not ready (Password: X, ScenarioMgt: Y, LoadedThisProcess: Z)" names the failing gate.
- Process start time vs master.json LastWriteTime — if process older, third gate explains it; restart required.
- Env var `TESTAUTO_SECRETS_FOLDER` invisible to SCM-started services until reboot — harmless (tier-2 fallback resolves same %ProgramData%\TestAuto folder).

**Round 2 (same day, 18:24 startup, v1.18 build):** user's screenshot ("bootstrap page again, 4 config warnings, can't navigate, unhandled error") was NOT a persistence failure. Log: `Secrets not ready (Password: true, ScenarioMgt: true, LoadedThisProcess: false)` — master.json fine; `LoadEntitySecrets` got HTTP 503 because ALL `speedmerchants-*` IIS app pools were stopped: pool identity `corp\svc_web` (SpecificUser, pw set 2015) was LOCKED OUT (WAS 5021 → 5057/5059 pool disabled). Domain lockout duration = **Never** → manual IT unlock required; user has no AD write access. Healthy `Profisee-*` pools run `corp\agenewe`.

Follow-up bug (fresh-box retest, same evening, FIXED): the load-failure notice gated on LIVE IMasterPasswordManager checks, which flip true mid-wizard after Step 1 saves the password — stale startup reason surfaced as "already set up: master password not configured yet". Fix: `RuntimeSecretsStatus.ConfiguredAtStartup` snapshot (set by LoadEntitySecrets after the two not-configured bails; loaded implies true); notice + MainLayout banner gate on the snapshot only; generic config-warnings banner suppressed while `!SecretsLoaded` (its 4 warnings are secrets-derived noise). Rule: any "configured but failed" UI must use startup snapshots, never live password-manager checks.

Product gaps below FIXED 2026-08-09 evening (uncommitted working tree; user builds/deploys): `RuntimeSecretsStatus.FailureReason` threaded from every `LoadEntitySecrets` bail path; bootstrap page "already set up — secrets failed to load: <reason>" notice + restart button (`ShowLoadFailureNotice`); MainLayout red banner for configured-but-unloaded + circuit-level secrets gate (`EnforceSecretsGate` — Blazor in-circuit nav bypasses the middleware); `QuerySecretsWithRetry` (2 fast-fail retries, 3s apart, only when attempt <5s so SCM 30s window safe); bootstrap Test Connection timeout 10s→30s with warmup-aware message. Unit suite green (850 pass; one CurlExecutor flake on first run, env per [[curlexecutor-port-flakiness]]).

Original gap list (for context):
1. **Load-failure reason invisible**: `LoadEntitySecrets` logs before Serilog file sink exists (logging = step 6, secrets = step 2 in RegisterAllServices) → reason console-only, lost under SCM. Should stash outcome/reason in `RuntimeSecretsStatus`/`IAppStartupStatus` and show on bootstrap page + banner ("secrets stored but could not be loaded: <reason>; fix + restart").
2. **Degraded-mode DI crash**: component activating `WebUiRepository` needs `Func<RestSubjectArea,IRestClient>` — not registered when `hasMinimumConfig` false → Blazor circuit unhandled exception on secrets pages.
3. Bootstrap page misleads when configured-but-unloaded: shows first-time wizard instead of "config present, load failed" state.
4. No secrets reload/retry after startup — one failed query poisons process until manual service restart.

Related: [[testauto-service-install-plan]] (memory file project_testauto_service_install_plan.md), [[corpltr94-svc-web-lockout]].
