---
name: reference-sqlcmd-quoted-identifier-profisee
description: sqlcmd writes to Profisee tables fail with Msg 1934 QUOTED_IDENTIFIER unless -I is passed; backfilling a Monitor marker row
metadata:
  node_type: memory
  type: reference
  originSessionId: d4bd0c0d-0213-45e8-bd0e-aa9042dc5a98
  modified: 2026-10-02T14:04:38.024Z
---

sqlcmd defaults QUOTED_IDENTIFIER OFF. INSERT/UPDATE on Profisee tables (e.g. monitor.tActivity, indexed views/computed cols) fails with
`Msg 1934 ... incorrect settings: 'QUOTED_IDENTIFIER'`. Pass `-I`. Also put SQL containing JSON/quotes in a file and use `-i` — inline `-Q` with `"` breaks PowerShell arg parsing.

Backfilled-marker pattern (2026-10-02, CORPSQL03/Profisee300M): MatchingResultsScenario finds markers by exact Name among `Service='TestAuto'` rows in monitor.tActivity and uses StartedTime as window bound. ActivityPost has no StartedTime, so a late marker can't be backdated via IMonitorActivityWriter; direct INSERT works. Required no-default cols: Code, $EnterUserID, $LastChgUserID. Total Time is measured from Matching activity timestamps, not markers — markers only bound the window.
