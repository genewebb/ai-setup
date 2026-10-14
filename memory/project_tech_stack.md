---
name: tech-stack-rules
description: Mandatory technology choices and library constraints for speed-merchants codebase
type: feedback
---

- **No Entity Framework** — use IRestClient, repositories, SqlHelper

**Why:** Project uses a custom data access layer; EF would conflict with existing patterns.

- **Newtonsoft.Json exclusively** — no System.Text.Json in application code

**Why:** Consistency across the codebase; STJ behavior differences cause subtle bugs.

- **Serilog.ILogger** — not Microsoft.Extensions.Logging.ILogger

**Why:** SEQ logging integration relies on Serilog enrichers and sinks.

- **MSTest** for tests, **bUnit** for Blazor

**How to apply:** Any new test class uses `[TestClass]`/`[TestMethod]`. Blazor component tests use bUnit's `TestContext`.
