---
name: feedback-prompts-full-paths-with-suggestions
description: Every paste-in prompt Claude writes uses full absolute paths (to the prompt file and inside it) and opens with a when-to-run / when-to-hold suggestion
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0ea61e79-068c-4a42-9300-94ed42155416
  modified: 2026-09-24T16:38:12.526Z
---

When Claude writes a prompt for Gene to paste into another session (review, fix, approval, repair):
- Give the prompt file's full absolute path, for example `Q:\Work\Work\99 Documentation\speedy\requirements\review\...md`.
- Use full absolute paths inside the prompt too, never paths relative to the corpus root.
- Put a **Suggestion** block at the top: when to run it, the approve/hold conditions, and the recommended choice.

**Why:** Gene, 2026-09-24: "Give me approval prompts with suggestions always give me full paths for prompts". A relative path fails in a fresh session started in a different working directory.

**How to apply:** save each prompt as its own file under the corpus `review\` folder, published through Write-VaultFile.ps1 and verified by hash, then list the full paths in the reply. Related: [[project-testdata-closeout-plan-2026-09-24]].
