---
name: reference-ado-mcp-microsoft-pat
description: Claude Code ADO MCP = Microsoft @azure-devops/mcp with PAT auth (base64 of any:pat); replaced cursor-azure-devops-mcp 2026-10-12; tool wit_work_item
metadata:
  node_type: memory
  type: reference
  originSessionId: e2384f5f-b0cc-4688-95c1-6ec829b55825
  modified: 2026-10-12T14:38:09.175Z
---

Since 2026-10-12, the `azure-devops` server in `~/.claude.json` (user scope) is Microsoft's `@azure-devops/mcp`. It replaced `cursor-azure-devops-mcp` because Gene does not use Cursor. `~/.cursor` was archived to `C:\DataArchive\cursor-home-2026-10-12.zip` and removed.

Config: `cmd /c npx -y @azure-devops/mcp profisee -a pat`, with env `PERSONAL_ACCESS_TOKEN` = base64 of `<anything>:<pat>`. The env var holds the encoded pair, never the raw PAT. Org arg `profisee` works for profisee.visualstudio.com. Verified v2.10.0: 40 tools.

- Read a work item with `wit_work_item {action:"get", id, project:"Products", expand:"All"}`. Other actions: get_batch, list_comments, list_revisions, my.
- Results come wrapped in `<<hex>> [UNTRUSTED AZURE DEVOPS ...]` marker lines. Strip them before parsing the JSON.
- To test without restarting Claude, run a stdio JSON-RPC smoke script (initialize, tools/list, tools/call).
- The "Connection closed" failure on 10/12 was an empty `--azure-token` arg. The PAT had been passed as Read-Host's prompt text, not typed at the prompt.

Related: [[project-git-config]]
