---
name: microservice-startup-analysis-final
description: Startup analysis doc (rev 2) at 99 Documentation\microservices\ — all 4 services + utilities verified current; container/K8s review with Issues 7-14
metadata: 
  node_type: memory
  type: project
  originSessionId: b0946b04-079d-415e-b953-b69f4e3bfcdc
---

`99 Documentation\microservices\Microservice_Startup_Analysis_Final.md` (Final rev 3, 2026-07-10) consolidates the four backup revisions AND verifies all services against current code: governance main@4f67167, matching main@f0873d436, connex main@564a8b23, platform master@aba72c47d2, utilities repo (shared libs source).

Rev 3 (post PR 24497, platform 2026-07-10): **legacy net.tcp Windows-service hosting RETIRED from Config Manager standard flow** — service switches deleted, ServiceURL → IIS-hosted https://…/api/service.svc, service.Start() block removed from SaveService → Jan Issue 4 (start-before-config) fully resolved. New `saveConfigSettingsOnly` switch mode (regenerates all appsettings.json from existing instance). Container branch still stop/starts a legacy Windows service (correct order, but unguarded `service.Status` null deref at Program.cs:1244-1245).

Key verified findings (Issues 7-14 in the doc):
- **Governance zombie (Issue 7, critical for K8s)**: startup catch-all → ServiceStatus=Unconfigured, process lives, and health check returns **Healthy for Unconfigured** → failed startup = 200 on /health forever. Request gate 503s but probes see 200.
- **Config Manager: Jan issues 2 & 3 already FIXED** (dual config writes removed — "Task 6" comment at WebAppConfigurationContext.cs:3546; validation now gated on IsGovernanceServiceInstalled + validateGovernanceNoneProviderAsync). New StartupOrchestrator with per-pool readiness probes (PR 22416). Windows service still starts inside SaveService before SaveConfigSettings (Issue 4 residue). Validation failures warn-only, exit code 0.
- **Matching**: NEW ApplicationReadyBehavior (re-queues messages 5s until IsAppReady) — receive-side gate pattern, adoption candidate for shared lib. IsAppDead set but never read; MatchingMessagingService.StopAsync NREs if broadcast start failed.
- **Connect**: broadcast endpoint started inline, Start() swallows all exceptions (zombie), Subscribe fire-and-forget, never stopped; TransactionCreated DROPPED before HangfireServerManager.IsInitialized; HangfireServerManager.StopAsync LockRecursionException; Dockerfile publishes -c Debug (only repo with container artifacts).
- **No stdout logging anywhere**: shared Utilities.Logging Logger.addSinks = file always + MSSQL if LoggingDBConnection set + Seq if SeqUrl; NO console sink → kubectl logs empty. Connect defaults LoggingDBConnection="" → explains tSystemLog silence ([[connex-service-store-and-logs]]).
- No liveness/readiness split; shared MapAllHealthChecks = /health, /health/databases, /health/services; 200/207/503.
- HostOptions.ShutdownTimeout default = **30s** (verified by reflection on Microsoft.Extensions.Hosting 8.0.1 — NOT 5s); Governance StopAsync waits up to 60s (exceeds budget).
- Governance drift vs Jan doc: SignalReady-only messaging svc (stale XML comment), 3rd hosted service CacheRefreshService, provider health checks, RequestGatewayMiddleware, ADR-008 (Purview→cache-miss) contradicts code (SupportsBulkCacheLoad=true at PurviewGovernanceProvider.cs:115). DeepDivePack 06 health-semantics claim also stale.

Configuration Manager lives at `C:\devops\repos\platform\Server\Configuration` (no standalone repo). Shared Profisee.Platform.Utilities.* source: `C:\devops\repos\utilities` (services pin NuGet versions — possible skew).
