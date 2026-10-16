---
name: feedback-secret-guard-show-and-confirm
description: Gene 2026-10-15 - ai-setup publish secret guard must SHOW the hits and let him push anyway, not hard-block; kit test fixtures trip it
metadata:
  type: feedback
---

Gene: "That guard is more of a pain most of the times it should show me what it thinks is the secrets and allow me to push anyway."

**Why:** stream-kit tests deliberately carry fake credentials (e.g. Test-StreamKitRecovery.ps1 case 76 feeds a fake
conn-password to Add-Lesson to prove it refuses secrets), so the hard block in publish.ps1 stopped real kit fixes on
CORPVM17. He committed by hand to get round it.

**How to apply:** publish.ps1 now lists File/Line/Rule/Match (middle masked by tools\Find-Secrets.ps1) and commits only on
a typed `yes`; redirected input = refuse. Never reintroduce a hard block or a per-line allow marker in ai-setup
publish. Promote-ToWork.ps1 (share to the corporate ai-profisee repo) still hard-blocks on purpose: different audience.
Related: [[project-ai-setup-private-git-repo-2026-10-14]].
