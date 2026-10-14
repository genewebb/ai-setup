---
name: logging-migration
description: Console-to-SEQ logging migration status (completed at commit a479a432)
type: project
---

All console logging (except program startup) migrated to SEQ logging patterns.

**Commit:** `a479a432`

**How to apply:** New logging should use Serilog structured logging to SEQ. Console.WriteLine is only acceptable in Program.cs startup.
