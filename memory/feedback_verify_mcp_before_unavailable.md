---
name: feedback-verify-mcp-before-unavailable
description: "If Profisee MCP servers appear in the tool list, use them; never claim unavailable without checking the actual tool list"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 644f2317-0d3b-4825-9aab-24140b0a46ed
---

If Profisee MCP servers (e.g. `speedMcpLocal`, `speedMcpRemote`, `profiseeMcpLocal`) appear in the session tool list, **use them** for model, metadata, and data operations. Never claim an MCP capability is unavailable without first verifying against the actual tool list (use ToolSearch — it waits for still-connecting servers).

**Why:** Migrated from the repo-root `AGENTS.md` "Learned User Preferences" (2026-05-31). Matches the harness rule about searching connecting MCP servers before reporting a capability missing.

**How to apply:** Before saying "I can't reach X," run ToolSearch with a relevant keyword. For Profisee model/metadata/data tasks, reach for the speed/profisee MCP tools rather than improvising.