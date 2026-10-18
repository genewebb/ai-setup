---
name: reference_gcm_two_github_accounts_pin_username
description: Git Credential Manager on the laptop holds TWO GitHub accounts (GeneWebbProfisee + genewebb) and pops an account picker on fetch/push; pin the account in the remote URL (https://genewebb@github.com/...) and no picker appears, even non-interactive
metadata:
  type: reference
---

GCM 2.9.1 on CORPLTR94 lists two GitHub accounts (`git credential-manager github list`): `GeneWebbProfisee` (work) and `genewebb` (personal). A remote URL without a user makes GCM ask which account on fetch/push: a picker in Gene's terminal, a hang where there is no console (Claude's shell, WinRM). Commits never prompt; only network operations do.

**Fix (verified 2026-10-17):** put the user in the URL. `git remote set-url origin https://genewebb@github.com/genewebb/ai-setup.git`, then `GCM_INTERACTIVE=never git push --dry-run origin main` authenticated with no prompt. ai-setup's origin is now pinned; `publish.ps1` re-pins it on any clone whose origin lacks the user, and the README clone line includes `genewebb@`.

**How to apply:** any repo under the personal account: `https://genewebb@github.com/...`; work GitHub repos: `https://GeneWebbProfisee@github.com/...`. Test without risk: `GCM_INTERACTIVE=never GIT_TERMINAL_PROMPT=0 git ls-remote <url> HEAD`. See [[git-github-config]], [[project_ai_setup_private_git_repo_2026-10-14]].

**Azure DevOps (work repos speedmerchants, speed-merchants, ai-profisee, platform on profisee.visualstudio.com):** bound the org to the work account: `git credential-manager azure-repos bind profisee gene.webb@profisee.com` (writes global `credential.azrepos:org/profisee.username`); all three `ls-remote` with `GCM_INTERACTIVE=never` succeed. Undo: `git credential-manager azure-repos unbind profisee`. Per Windows user: SMVMTR1 genewe is not bound.
