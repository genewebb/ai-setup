---
name: project_stream_plan_g2_g6_released_2026-09-27
description: "Speedy stream-plan 9/27 released G3 Steps, G4 Workflows, G5 TestAuto, G6 Dial (335 tasks) with record page links; G3/G4 swapped order"
metadata:
  node_type: memory
  type: project
  originSessionId: b98ab34c-abb7-4f40-9f1e-73fb3681cf76
  modified: 2026-09-28T01:12:12.735Z
---

On 2026-09-27, stream-plan released G3 Steps, G4 Workflows, G5 TestAuto and G6 Dial into speedmerchants `.streams\tasks.json` (335 tasks). G2's record page was published the same day.

- Group order: G3 = Steps and G4 = Workflows. This swapped the 17:26 order. The secrets / identity / installer / preflight / value-sources set is in G3 by the first-needer rule.
- Record pages:
  - G2: https://claude.ai/artifact/TXGwWf2bETvr8bJZS1Xs6W
  - G3: https://claude.ai/artifact/UUN8eJgfQdPPTJPpkJgE9o
  - G4: https://claude.ai/artifact/1s9FPZVdBgJaxupRQ7E55D
  - G5: https://claude.ai/artifact/A2gHhfVKe7BP4tVWzpfmrW
  - G6: https://claude.ai/artifact/DR6MUHrV7rMXLKx3GAEajJ
- Gap evidence is in `.streams\plans\gap\`. Every answer is in `.streams\decisions.md`.
- Key decisions:
  - Retire the legacy shared-master Secrets tier.
  - Worker-routed probes and Windows dispatch are built in G6 with the channel.
  - The whole worker channel is released.
  - REQ-CLI-009 is not planned, because FEAT-CLI-001 is excluded.

**Why:** later /stream-plan revise and status sessions need the group-to-page map, and the reason G3/G4 differ from earlier scope files.
**How to apply:** use `/stream-plan revise <group>` for changes, and republish the page from the same scratch generator pattern. Related: [[project_stream_kit_replaces_myloop]], [[feedback_stream_plan_no_approval_step]], [[feedback_auto_approve_recommendations_speedy_build]].
