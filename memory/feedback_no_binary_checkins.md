---
name: feedback-no-binary-checkins
description: Never commit build output to any repo; .gitignore does not untrack already-tracked files — verify with git ls-files
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 8e3b2f34-cb8e-4f46-999a-5cb099150143
  modified: 2026-09-08T02:58:15.402Z
---

Compiled output is never committed to any of Gene's repos: `*.dll`, `*.pdb`, `*.exe`, `*.nupkg`,
`*.msi`, `*.zip`, and anything an installer script stages or packages (`**/Installer/stage/`,
`**/Installer/output/`, both casings). If a build or package run can produce it, it does not belong in
git history. Permanent rule, stated by Gene 2026-08-30; the full write-up is
`Q:\Work\Work\99 Documentation\speed-merchants\vNext\Rules\Guide_NoBinaryCheckIns.md` (path corrected
2026-09-07: this note previously named the `speed-merchants\` folder, where the file is NOT). It is a VAULT
document, not a repo file — `.gitignore:6`, `regression.ps1:59` and `installer/BUILDING.md` all cite it by
bare name, which is the established convention here; do not "fix" those into paths or conclude the guide is
missing when a repo search comes back empty.

**THE RULE IS ABOUT BUILD OUTPUT, NOT ABOUT FILES THAT HAPPEN TO BE BINARY.** Gene, 2026-09-07 18:36:
"It is fine to check in the icon… The binaries is for actual code binaries, objects, etc." A checked-in
SOURCE ASSET — an installer icon, a font, an image, a test fixture — is not build output and was never in
scope. The test is not "is it binary" but **"can a build or package run regenerate it?"** If yes it is
output and stays out; if a human authored it and nothing regenerates it, it is source and belongs in git
like any other source file. Both donor installers check their `profisee.ico` in for exactly this reason.
Do not treat a source asset as an exception to the rule, and do not ask for permission as though it were —
it simply is not the thing the rule is about. Confirmed in the enforcement too: `regression.ps1`'s census
matches only `*.dll *.pdb *.exe *.nupkg *.msi *.zip` plus the staging paths, so an `.ico` never trips it.

**Why:** on 2026-08-23 the speed-merchants repo had 746 files tracked under
`TestData.Mutation/Installer/stage/`, 610 of them `dll`/`pdb`/`exe` — in a path that was **already in
`.gitignore`**. `.gitignore` is consulted only when git decides whether to start tracking an
*untracked* file; a file already in the index stays tracked forever and its churn arrives as hundreds
of ordinary modifications nobody reads. "It's in .gitignore, so we're fine" is the exact failure.

**How to apply:**
- Verify with `git ls-files '*.dll' '*.pdb' '*.exe'` — must print nothing. Never infer cleanliness from
  `git status` (see [[reference_git_status_vs_diff_no_head]]).
- To fix: `git rm --cached -r <path>` — untracks, leaves the working tree intact. Never plain `git rm`
  on installer output; that deletes it from disk too.
- Then confirm the ignore rule actually matches: `git check-ignore -v <one-of-the-files>`. No output
  means no rule matched and the files return on the next `git add`.
- Leave the staged deletions for Gene — [[feedback_no_commits]] still holds; never commit the fix.
- In the vNext repo (`C:\devops\repos\speedmerchants`) this is enforced every loop iteration by
  `.loop\criteria\regression.ps1`, which fails the gate on any tracked binary or tracked
  `Installer/stage|output` path. See [[project_vnext_due_diligence_2026-08-28]].
