---
name: project-ai-setup-private-git-repo-2026-10-14
description: "10/14 decision: whole AI setup moves to PRIVATE github.com/genewebb/ai-setup (git = the only sync; install.ps1 = pull + Install-AIMachine, publish.ps1 = scan+commit+rebase+push); work sharing = one-way promote via share.yaml to a work marketplace; product code stays in corporate ADO"
metadata:
  node_type: memory
  type: project
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-14T18:18:00.318Z
---

Gene 10/14/2026: replace Q:/share corpus + machine-sync 3-way + Write-AIFile corpus writes with ONE private git repo,
`genewebb/ai-setup` (personal account, private), local clone `{ReposRoot}\ai-setup` (laptop `C:\devops\repos\ai-setup`).

- Division: AI setup (skills, agents, commands, CLAUDE.md, hooks, settings template, permissions, memory in its own
  folder, stream kit) = private repo. ALL product code stays in corporate ADO repos.
- Flow: edit anywhere -> `publish.ps1` (secret scan via tools\Find-Secrets.ps1, commit, pull --rebase, push);
  other machine -> `install.ps1` (pull --ff-only + setup\Install-AIMachine.ps1 -CorpusRoot <clone>).
- NO plugin packaging of my own skills (plugin skills load as /plugin:skill, would rename the stream kit).
- Work sharing: keep everything private, SELECTIVELY promote via `share.yaml` + `tools\Promote-ToWork.ps1`
  (blocks personal hosts/accounts/paths, {Key} tokens, [[memory]] links, secrets, unpromoted private-skill deps;
  never commits the target). Target marketplace not chosen yet (ai-profisee or own ADO repo).
- Laptop profile git policy row added 10/14: `{ReposRoot}\ai-setup` commit yes, push yes, worktrees no.
- GitHub plugin MCP is authed as GeneWebbProfisee, NOT genewebb: repo creation + first push (GCM browser login,
  non-elevated terminal) are Gene's.

**State 2026-10-14 18:40:** seed pushed (6df0e34, Gene ran commit+push); laptop profile AIWorkRoot -> `C:\devops\repos\ai-setup`; real install.ps1 (memory junction) NOT run: auto-mode classifier blocked it (Data Exfiltration) and the seed commit (Sensitive-Source Provenance): Gene runs those himself. Docs retired locally (machine-sync stub, machine-config rules, ai-repo-management rewrite), unpublished. Promotion target = Martin ai-profisee. Other machines: roll out when next used.

**CUTOVER COMPLETE 2026-10-14 19:05:** laptop + CORPVM17 both run from the clone (AIWorkRoot = C:\devops\repos\ai-setup, memory junction -> repo memory\, CORPVM17 StreamHostDir = C:\tmp\stream-host). Old copies DELETED after verified archives in C:\DataArchive\ai-setup-retire-20261014 (q-work-ai, deploymyai-corpus incl old .git, q-speedy-requirements): Q: work-ai, D:\DeployMyAI\corpus, CORPVM17 C:\AIWork\work-ai, Q: speedy\requirements. Rest of D:\DeployMyAI kept. Laptop memory.pre-git-20261014-185408 kept until 2026-10-21, then delete. install.ps1 must run as the account that runs Claude (agenewe); from a Claude prompt use ! with FORWARD slashes. Other machines: clone + profile AIWorkRoot + install when next used.

**Why:** "no more complicated sync": pull + one install script on every machine (laptop, CORPVM17, SMVMTR1...).
**How to apply:** seed from Q: work-ai once Q: reconnects; reconcile CORPVM17 stream edits by clone + copy live
files over + git diff. Supersedes [[project-machine-sync-skill-2026-10-01]] and the Q: publish path in
[[project-machine-config-laptop-live-2026-10-01]] once cut over.
