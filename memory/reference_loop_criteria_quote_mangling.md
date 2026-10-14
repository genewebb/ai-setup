---
name: loop-criteria-quote-mangling
description: "Orchestrator-worker loop Test-Criteria.ps1 eats nested double quotes in stored criterion commands — write criteria quote-free (rg \\x22 hex escape); preflight can't distinguish malformed-command from artifact-missing"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8b538ad9-4cb6-4be6-9686-f70e537e4d13
  modified: 2026-08-10T00:16:37.325Z
---

Found 2026-08-09 (production-sync loop, iteration 10): a Done-when criterion `rg -q '@page "/production-sync"' <dir>` PASSED when run directly in pwsh but FAILED inside `Test-Criteria.ps1` — the harness's inner invocation strips the nested double quotes, turning the pattern into `@page /production-sync` (matches nothing).

**Why preflight missed it**: at baseline the criterion failed for TWO overlapping reasons (artifact missing AND malformed quoting) — indistinguishable until the artifact exists. This is the general "fails for the RIGHT reason" trap from the skill.

**How to apply**: write loop criteria commands with NO nested double quotes. For rg patterns needing a literal `"` use the hex escape: `rg -q '@page \x22/production-sync\x22' <dir>`. Fixing a mangled command mid-loop is a COMMAND repair, not a scope/intent amendment — log it in PROGRESS as such. Consider fixing Test-Criteria.ps1 quoting properly in [[orchestrator-worker-loop-hardening]].
