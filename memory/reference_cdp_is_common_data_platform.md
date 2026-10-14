---
name: reference-cdp-is-common-data-platform
description: "CDP = Profisee Common Data Platform (repository-pattern data layer under all apps, tested by direct request/response calls) — NEVER Chrome DevTools Protocol; browser testing = generic \"browser control\""
metadata:
  node_type: memory
  type: reference
  originSessionId: 87fb8af5-38c0-40da-8437-49fc39802b1c
  modified: 2026-09-24T22:04:57.081Z
---

**CDP = Common Data Platform**: Profisee's repository-pattern data layer beneath every application (`Profisee.Platform.Cdp.*`, `ICdpService`). Speedy load-tests it directly with request/response calls. It is NOT the Chrome DevTools Protocol.

Browser-driven testing is called **browser control**, generically. Never say "Chrome" or "DevTools" in Speedy product copy; the browser used underneath is an implementation detail.

**Why:** 2026-09-24 the Speedy diagrams narration and intro said "browser executor that drives Chrome using the Chrome DevTools Protocol, or CDP". Gene corrected it and had it fixed everywhere.

**How to apply:** When CDP appears in requirements ("dial REST, CDP or other targets") or plans, read it as the data layer. Tooling that really uses DevTools (Archify `record.mjs`, Playwright) is unrelated. Related: [[feedback-call-it-speedy-with-speed-humor]], [[project_speedy_demo_diagrams]].
