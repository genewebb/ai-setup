---
name: feedback-no-direct-commits-to-main-pr-only
description: "Shared ADO repos (speed-merchants-dba etc.): never commit or push straight to main; a branch + pull request only"
metadata:
  node_type: memory
  type: feedback
  originSessionId: e936bbac-19b6-4306-a230-cd7db2104ac3
  modified: 2026-10-25T11:28:10.908Z
---

Never commit directly to main in the shared ADO repos (speed-merchants-dba, the coworker share repo): every change goes on a branch and reaches main through a pull request. Gene, 10/25: "You can not commit directly to main per our rules". The dba repo history agrees: every change since the first commit is a "Merged PR N".

**Why:** team rule; main is PR-only (branch policy suspected, not verified via API).

**How to apply:** any printed git sequence for those repos = `switch -c <branch>`, add, commit, `push -u origin <branch>`, then the ADO PR link `<origin>/pullrequestcreate?sourceRef=<branch>&targetRef=main`. `prof setup share` does this since ce0ddce (`share/profile-<stamp>` / `share/skills-<stamp>`). The ai-setup repo's own flow (work/<change> branch, local merge --no-ff into main, Gene pushes) is separate: see [[project_ai_setup_branch_workflow_2026-10-18]]. Related: [[feedback_no_commits]], [[project_prof_share_design_2026-10-23]].
