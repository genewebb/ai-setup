---
name: reference-testautomanager-teams-mail-account
description: "TestAutoManager Teams messages by mail: which SMTP account works, which is refused, and the channel setting needed (proven on SMVMTR1 11/11/2026)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0acc58d9-fcc9-41fd-b298-2f733f9e654e
  modified: 2026-11-11T23:39:35.735Z
---

TestAutoManager (SMVMTR1) Teams messages go as mail to a channel address. Proven 11/11/2026 with Gene:

- Works: `smtp.office365.com`, port 587, SSL on, user AND sender both `tfsalerts@profisee.com`.
- Refused: user `speedmerchants@profisee.com` gets `535 5.7.3 Authentication unsuccessful` (basic SMTP sign-in not allowed for that mailbox; Outlook works because it uses modern sign-in).
- Sender must equal the signed-in user: `tfsalerts` sending as another address gets `5.2.252 SendAsDenied`.
- A group chat has no email address; only a channel has one (channel menu, Get email address).
- "Test message sent" but nothing in the channel = the channel's own rule on who may mail it (Get email address, advanced settings). Gene had to change it before posts arrived.
- Settings must be changed on the page (Settings, Teams messages): the service holds settings in memory, a hand edit of `settings.json` is not read and gets overwritten.
- "Saved." is the Save button; a real test says "Test message sent to <address>.".
- 11/12-13 Office 365 outage: 9.0.2 lost 47 messages (logs only failures, `[WRN] Teams message (<kind>) not sent`; no retry). 9.0.3 (built 11/13, uncommitted, NOT deployed) keeps refused sends in `Teams:Outbox` (settings.json, redacted), retries each runner pass after 1/2/5/10/15 min, new messages queue behind, "Sent late" note, drop after 24 h / beyond 200. Gene 11/13: deploy to SMVMTR1 after the 26R4 mid-release round ends, not mid-round.

Related: [[project-mid-release-round-runner-plan-2026-11-07]]
