---
name: reference_speedy_live_check_testbed_loopback
description: How to live-check Speedy pages without Gene's authenticator: loopback testbed scheme over a throwaway state dir + a scratch Playwright console app for screenshots/overflow
metadata:
  type: reference
---
Run src/Web/bin/Debug/net10.0/speedy-web.exe on http://127.0.0.1:5290 with a scratch state root (SPEEDY_SECRETS_FOLDER, Speedy__State__Root, Speedy__Libraries__RootPath, Journal, Agent targets, WorkExecutor, Warehouse/Transport at 127.0.0.1,1) plus BOTH `Speedy__WebAccess__Scheme=Testbed` and `Speedy__WebAccess__TestbedAcknowledged=true`. Never point it at C:/tmp/speedy-review (Gene's review host, port 5280).

Chrome extension may be disconnected; a scratch console app referencing Microsoft.Playwright 1.62.0 works (browsers in %LOCALAPPDATA%\ms-playwright). Measure `document.documentElement.scrollWidth` vs viewport for overflow. Git Bash mangles `/route` args: set MSYS_NO_PATHCONV=1. A `sh script.sh` wrapper failed with 127 in background mode; run the inline command instead. Stop the host (Stop-Process by path + StartTime) before rebuilding src/Web.

Related [[reference_blazor_dispose_must_not_resolve_services]], [[reference_playwright_enhanced_nav_waitforloadstate]].
