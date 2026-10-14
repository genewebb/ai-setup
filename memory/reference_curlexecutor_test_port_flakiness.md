---
name: reference_curlexecutor_test_port_flakiness
description: "CrewChief CurlExecutorTests binds a real HttpListener on an ephemeral port; transient \"conflicts with an existing registration\" Setup failures are environmental, not code — re-run to confirm"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 777a7eea-fcad-44ae-9256-e6de518573d5
  modified: 2026-07-25T13:48:57.394Z
---

CrewChief.Tests.Unit `CurlExecutorTests.Setup` (and similar HttpListener-based tests) bind a real
`HttpListener` on an ephemeral `http://127.0.0.1:<port>/`. Under parallel test execution or when a
leftover `testhost`/`dotnet` process from a prior run still holds a port ACL, Setup can throw
`System.Net.HttpListenerException: Failed to listen on prefix ... because it conflicts with an existing
registration on the machine.`

This is **environmental flakiness, not a code failure**. When a full-suite run shows 1–2 such failures
while a targeted run of the same class passes: just re-run the full suite (the ephemeral port is
reselected). Seen 2026-07-25 — 2 Curl Setup failures on one run, 0 on an immediate re-run with no code
change. Don't chase it as a real regression; if persistent, check for stale `dotnet`/`testhost`
processes holding ports.
