---
name: handoff
description: >
  Conversation-to-handoff-document compaction for picking work up in a fresh session. Use when asked
  for a handoff, a session summary another agent can continue from, or a "where I left off" document;
  when a session is ending with work unfinished; or when context is about to be compacted and the
  state needs to survive it. Writes to the OS temp directory, references existing artifacts instead of
  duplicating them, and redacts secrets.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
