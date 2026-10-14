---
name: ps51-latin1-body-encoding
description: PowerShell 5.1 Invoke-RestMethod sends a string body as Latin-1 when Content-Type has no charset — one non-ASCII char corrupts the request and the server reports a parse error far from the real character
metadata: 
  node_type: memory
  type: project
  originSessionId: f1b61155-526e-4a83-8b2c-aa27ab714829
  modified: 2026-08-01T12:38:59.111Z
---

**ROOT CAUSE of the step-16 SynonymList 400 (found 2026-08-01), and a trap for every HTTP step.**

Windows PowerShell 5.1's `Invoke-RestMethod -Body '<string>'` encodes the body as **Latin-1** when the
`-ContentType` carries no `charset` parameter. Any non-ASCII character is then sent as a single high
byte instead of its UTF-8 sequence. A UTF-8 decoder on the far side treats that byte as a lead byte,
consumes the following characters as continuation bytes, and the JSON token stream desynchronises.

**Measured byte-for-byte** (loopback repro, `scratchpad/repro-encoding.ps1`):
```
body: workflow 10000156 step 16, 34,028 chars, exactly ONE non-ASCII char: "türkiye" (Country list)

without charset : expected 34,029 bytes, received 34,028   offset 28503: expected 0xC3, got 0xFC
with charset    : 34,029 / 34,029   BYTE-IDENTICAL
```

**The error the gateway reports is nowhere near the real character** — that is what made this so hard:
```
{"errors":{"[6].synonyms[0].searchTerm":["Invalid character after parsing property name.
  Expected ':' but got: u. line 1197, position 28"],
 "[6].synonyms[0].searchTerm.6":["Invalid JavaScript property identifier character: \" ..."]},
 "title":"One or more validation errors occurred.","status":400}
```
It names `synonyms[0]` while the offending `ü` sits ~100 lines later in the same list. Do not trust
the reported position on an encoding fault — scan the whole payload for non-ASCII instead:
`[regex]::Matches($body,'[^\x00-\x7F]')`.

**FIX:** `HttpRequestStep.EnsureUtf8Charset` appends `; charset=utf-8` to a Content-Type that lacks
one, in BOTH products (`TestAuto.Utilities/Common/DTOs/HttpRequestStep.cs`,
`CrewChief.Engine/Steps/HttpRequestStep.cs`). An explicitly supplied charset is respected. Tests:
`GenerateExecutionCommand_ContentTypeWithoutCharset_AddsUtf8` /
`..._ContentTypeWithExplicitCharset_IsLeftAlone`. NOTE this changed the long-standing assertion in
`PowerShellCommand_ContentTypeHeader_BecomesDedicatedContentTypeParameter`, which pinned the old
`-ContentType 'application/json'` — that update is intentional.

**Why it worked in June and not now:** the June runs sent this body via `bodyFilePath`, which bypasses
PowerShell string encoding entirely. The file-reference retirement
([[project_file_reference_retirement]]) moved every body inline, which routed them through the
Latin-1 path. So the regression came from the inline-body migration, NOT from the 26R2 upgrade —
correcting the earlier hypothesis in [[project_synonymlist_put_400_26r2]].

**Also proven along the way:** the payload itself is fine. Replaying it with a plain
`Invoke-RestMethod` (which passes `-Body` as a variable, not an embedded literal) returned 204 and
really created all 7 lists in `matching.tSynonymLists`.

Verified: TestAuto 772 passed / 1 skipped; CrewChief 2646 passed; all builds 0 warnings / 0 errors.
