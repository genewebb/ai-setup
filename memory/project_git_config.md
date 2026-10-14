---
name: git-github-config
description: Git identity, GitHub account details, and CLI workarounds for speed-merchants
type: reference
---

- Work account: `CORP/agenewe` (owns speed-merchants)
- Personal account: `genewebb` (owns github.com/genewebb/swarm)
- safe.directory needed: `git config --global --add safe.directory C:/devopslocal/repos/Swarm`
- Personal git identity set locally in swarm repo (not global): `gene.webb@live.com` / `Gene Webb`
- `gh` CLI is NOT installed — use `Invoke-RestMethod` + git remote with token for GitHub API operations
- To push as personal account without gh: `git remote set-url origin "https://genewebb:$env:GH_TOKEN@github.com/genewebb/swarm.git"`
