---
name: reference-pwsh-webrequestsession-stores-maxredirection
description: PS7 Invoke-WebRequest -MaximumRedirection passed with -WebSession is saved ON the session; later calls with that session stop following redirects
metadata:
  node_type: memory
  type: reference
  originSessionId: 7b7a8c4b-5e40-4390-8aad-92dccba792b7
  modified: 2026-09-26T01:55:35.484Z
---

In PowerShell 7, `Invoke-WebRequest -WebSession $s -MaximumRedirection 0` writes 0 into `$s.MaximumRedirection`. Every later call with `$s` then refuses redirects and throws "Response status code does not indicate success: 302 (Found)", e.g. a form POST that redirects.

Measured 2026-09-25 in `scripts/e2e/Invoke-AbandonedRunIdentityProof.ps1`: the `Wait-ForUrl` probe with `-MaximumRedirection 0` broke the later launch POST. Removing the flag fixed it.

**How to apply:** never combine `-MaximumRedirection` with a shared signed-in session. For a probe that must not follow redirects, use a throwaway session. `SpeedyTestSession.psm1` is safe because `Get-SpeedyTestSession` returns a new session object. Related: [[project-speedy-login-everywhere]]
