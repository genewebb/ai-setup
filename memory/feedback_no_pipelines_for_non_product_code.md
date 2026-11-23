---
name: feedback-no-pipelines-for-non-product-code
description: "Policy: no CI/test pipelines for non-product code (speed-merchants, Speedy, internal test tooling). Don't recommend or flag a missing pipeline there as an action item."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4dd5f09a-5ddb-4cb7-8a77-b1ee5237e704
  modified: 2026-11-23T16:35:02.373Z
---

Gene, 2026-11-23: "We are not currently doing pipeline for non product code." This covers test pipelines for Speedy and speed-merchants: "not sure when or if that will get done".

**Why:** a team policy. Only Profisee product code gets build and test pipelines. Internal test tooling relies on other checks, such as Speedy's integrator Tier 1 and its nightly Tier 2.

**How to apply:**
- In assessments against the agent-verification framework, record a missing pipeline on non-product repos as an accepted gap under owner policy, not as a finding to fix.
- Never list "add azure-pipelines.yml" as an action item for these repos. For example, speed-merchants ADO definition 675 has no YAML file; this is accepted.
- Product repos (rest-api, mcp, Portal, etc.) are not covered by this rule.

Related: [[project-speedy-agent-verification-requirements-2026-11-22]].
