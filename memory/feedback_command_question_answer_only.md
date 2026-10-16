---
name: feedback-command-question-answer-only
description: "What is the command" questions = reply with the command only; run nothing, not even read-only checks
metadata:
  type: feedback
---

When Gene asks "what is the command" (e.g. how to pull a repo), answer with the command text only. Run no tool calls, including read-only probes like `git status`.

**Why:** 10/16/2026 Gene asked for the pull command for speed-merchants; I ran `git status -sb` first to check upstream. Gene: "Do not run I only want the command".

**How to apply:** Give the command from known context; state any assumption (e.g. "assumes upstream set") instead of checking it.
