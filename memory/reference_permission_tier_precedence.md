---
name: reference_permission_tier_precedence
description: "Claude Code evaluates deny→ask→allow by TIER, not specificity — a broad ask rule beats a narrow allow rule, so \"scoped allow + broad ask\" designs silently do nothing"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4eaf3a67-0962-4b85-944f-423808a7f83f
  modified: 2026-08-01T20:32:10.367Z
---

Claude Code permission rules are evaluated **deny, then ask, then allow. First match wins,
and rule specificity does not change the order** ([permissions
reference](https://code.claude.com/docs/en/permissions)).

Consequence that keeps catching people out:

```json
"ask":   ["PowerShell(Stop-Service*)"],           // this wins
"allow": ["PowerShell(Stop-Service W3SVC*)"]      // never fires
```

The intuitive design — *auto-approve a scoped set, keep the broad pattern in `ask` so
anything unexpected still prompts* — **cannot be expressed with permission rules.** It
looks correct in config and changes nothing at runtime. Glob patterns also can't express
"anything except X".

A `PreToolUse` hook does **not** rescue it: *"a matching ask rule still prompts even when
the hook returned `allow`"*, and a hook exiting 2 blocks regardless of allow rules. The
hook only helps once the broad `ask` rule is **removed**, and then its role inverts — it
is a guard that re-imposes a prompt on non-whitelisted calls, not an approver. That is the
documented pattern ("add `Bash` to your allow list and register a PreToolUse hook that
rejects those specific commands") and how `test-loop-autoapprove.ps1` already works.

So there are only three real options for "mostly silent, occasionally prompt":

1. Remove from `ask` → blanket allow, no guardrail.
2. Remove from `ask` + a `PreToolUse` guard hook → scoped, ~20 lines.
3. Leave the `ask` rule → keep prompting.

**Applied 2026-08-01** (ReducePromptCost item 3): option 1 for `Stop-Service` /
`Restart-Service`. `New-Service`, `Remove-Service`, `Set-Service` stay in `deny`, so
create/reconfigure is still blocked — only stop/restart went silent.

Also note: with `Bash(*)` and `PowerShell(*)` already in `allow`, **removing a pattern
from `ask` is the operative act.** Adding an explicit allow entry is documentation, not
mechanism.

Related: [[reference_permissions_sync]], [[reference_permissions_drift_checker]],
[[reference_prompt_cost_analysis]], [[project_test_loop_autoapprove_hook]]
