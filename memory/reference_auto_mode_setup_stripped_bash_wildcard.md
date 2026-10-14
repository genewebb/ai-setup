---
name: reference_auto_mode_setup_stripped_bash_wildcard
description: 2026-09-03 12:34 /auto-mode-setup (run right after 2.1.258→2.1.259 update) removed Bash(*)/PowerShell(*) from ~/.claude/settings.json and wrote autoMode.environment naming ONLY C:\devops\myworkspace as trusted repo — every shell command in C:\devops\repos\* now goes to the classifier and prompts
metadata:
  type: reference
---

**What changed (verified by diffing `settings.json.bak-2026-08-01-cavemandedup` against live):**
- `permissions.allow` lost exactly two entries: `Bash(*)` and `PowerShell(*)` (the 2026-07-30
  "allow-all-unless-destructive" floor, see [[reference-permissions-sync]]).
- `permissions.deny` gained 18 secret-file rules (`Read(**/.env)`, `**/*.pem|key|pfx|p12`,
  `**/secrets/**`, `**/credentials/**`, `**/.ssh/**`, `**/.aws/**`, `**/.azure/**`, `**/.gnupg/**`,
  `id_rsa`, `id_ed25519`, plus `00 Credentials` in both path forms).
- A new `autoMode.environment` block whose Trusted repo / Source control entries name only
  `C:\devops\myworkspace` ("no remotes configured"). Written WITHOUT `"$defaults"`.
- `defaultMode: "auto"` was ALREADY set on 2026-08-01 — auto mode itself is not new.

**Mechanism (docs, code.claude.com/docs/en/auto-mode-config + permission-modes):**
- Auto mode drops broad allow rules (`Bash(*)`, `PowerShell(*)`, wildcarded interpreters, `Agent`,
  `Monitor`) while active; `/auto-mode-setup` additionally *offers to delete them from settings*.
  That offer is what removed them permanently.
- The classifier "trusts only the working directory and the current repo's configured remotes".
  `permissions.additionalDirectories` covers Read/Edit only; it does not extend classifier trust.
  So a `dotnet test` or `git -C C:\devops\repos\speedmerchants ...` from the myworkspace launch pad
  is "outside the trusted repo" and gets reviewed / prompted.

**Fix options (Gene's call, settings are read at session start):**
1. Add to `autoMode.environment` (keep `"$defaults"` first): a Trusted repo line naming
   `C:\devops\repos\*`, `C:\devopslocal\repos\*`, plus the Q:\ docs path and C:\tmp as trusted
   local destinations. Best fit for the classifier model.
2. Re-add narrow allow rules that survive auto mode (`Bash(dotnet test *)`, `Bash(dotnet build *)`,
   `Bash(git -C * show *)`, `Bash(pwsh -NoProfile -File C:/devops/repos/speedmerchants/.loop/*)`).
   Narrow rules resolve BEFORE the classifier. Re-adding `Bash(*)` is pointless — ignored in auto mode.
3. Check `Read(**/secrets/**)` deny vs `Read(C:\devopslocal\Secrets\**)` allow: deny tier wins
   ([[reference_permission_tier_precedence]]); the vNext loop already works around it with
   `git show` for donor secrets paths.

Drift checker reported "All clients match" while allow count went 385→90 — it does not see this
class of change. Related: [[reference-permissions-drift-checker]], [[reference-path-form-gotcha]].

**APPLIED 2026-09-03 17:15 (Gene: "Do these fixes before I restart the workflow"):**
- Fix 1: `autoMode.environment` now starts with `"$defaults"`; Trusted repo / Source control lines
  name every repo under `C:\devops\repos\` and `C:\devopslocal\repos\`; new "Trusted local
  destinations" line for `Q:\Work\Work\99 Documentation\` and `C:\tmp\`.
- Fix 2: `permissions.allow` gained `Bash(dotnet test *)`, `Bash(dotnet build *)`,
  `Bash(git -C * show *)`, `Bash(pwsh -NoProfile -File C:/devops/repos/speedmerchants/.loop/*)`
  (+ backslash path form). Canonical `permissions.yaml` already had the first three; the `.loop`
  rule was added there too.
- Fix 3: left alone — `Read(**/secrets/**)` deny stays; loop uses `git show` for donor secrets.
- Takes effect at next session start. Verify: first `dotnet test` from myworkspace should not prompt.
- 17:35 addendum (Gene: "add a rule allowing this so it stops prompting you can read anything in c:\devops\repos"):
  Read/Edit(C:\devops\repos\**) allow rules already existed — the prompts were on BASH read commands
  (cat/grep/sed/ls) routed to the classifier. Added narrow read-only rules that survive auto mode:
  `Bash(cat *)`, `grep`, `rg`, `sed -n`, `head`, `tail`, `ls`, `wc`, `find`, `cut`, `echo`, and
  `git -C * {status,log,diff,grep,rev-parse,branch,ls-files,cat-file}`. Canonical permissions.yaml already
  had all of these (cat*/grep*/sed*/ls*…) — settings.json lost them in the 385→90 strip; drift checker
  still reported "All clients match" with canonical 372 allow vs live 95.

**2026-09-04 13:45 — 2.1.260 startup warning + rule removal:**
- Claude Code 2.1.260 validates allow rules at startup and warns for every `Bash(git -C * <sub> *)` rule:
  "has a wildcard before the rest of the command … options such as -c and --exec-path can run arbitrary
  commands". The `*` after `-C` also swallows `-c core.pager=<cmd>`, so the rule is genuinely exploitable.
  Docs (permissions#wildcard-patterns): put the `*` AFTER the subcommand only.
- Removed all 9 `git -C *` allow rules from settings.json (backup `settings.json.bak-2026-09-04-gitC`).
  Not replaced: the built-in read-only set "runs in every mode" and includes read-only git forms; probe
  `git -C C:/devops/repos/matching describe|remote -v|ls-tree` (no allow rule covered them) ran with no
  prompt in auto mode. Whether that was the built-in detector or the classifier is NOT distinguishable
  in auto mode — if `git -C` reads ever prompt in Manual mode, per-repo exact-path rules are the fallback.
- Canonical permissions.yaml keeps its `git -C *` block (VS Code has no built-in read-only git) with a
  "CLAUDE CODE: do NOT sync" comment. Drift checker still exit 0 (it only flags contradictions).
- Deny-tier `git -C * push/commit/...` rules NOT warned (validator only checks allow) — kept.
- Found ask-beats-allow trap: `Bash(rm:*)` + `rm -r*` in user ask tier vs `Bash(rm *)` saved to
  myworkspace `.claude/settings.local.json` on 8/31 via "don't ask again" — that allow can never fire
  ([[reference_permission_tier_precedence]]). Same class as the user's "previously set, still prompts".

**2026-09-04 14:05 — Gene's decision + partial application (settings edit BLOCKED, awaiting explicit OK):**
- Gene (AskUserQuestion): "I dont want to have to approve non destructive bash commands and even those if
  they are in the repo directories are fine" + "Yes, drop rm from ask". Transcripts do NOT record approval
  prompts (only denials), so the exact prompting commands could not be identified; `.claude.json`
  `autoModeEnvSetup.denials` = 5 classifier denials. Latency-as-prompt-proxy is unreliable (loop session
  gaps of 5h were overnight idle; identical `cd repo; grep` calls took 8-26s normally).
- Chosen design = the 7/30 policy re-applied + a path guard:
  1. `permissions.defaultMode` auto -> `default` (auto mode suspends `Bash(*)`, so the floor is dead in auto).
  2. `Bash(*)` + `PowerShell(*)` back in allow; deny tier (112) untouched.
  3. Drop from ask: `Bash(rm:*)`, `rm -rf:*`, `rm -fr:*`, `rm -r:*`, `rmdir:*`, `PowerShell(Remove-Item*-Recurse*)`.
  4. NEW PreToolUse hook `scripts/destructive-path-guard.ps1` (via hook-dispatch -Id destructive-path-guard,
     matcher Bash|PowerShell): emits permissionDecision=ask only when a destructive verb in command position
     (rm/rmdir/rd/del/erase/Remove-Item/ri, find -delete) co-occurs with an absolute path outside
     C:\devops\repos, C:\devopslocal\repos, C:\devops\myworkspace, C:\tmp, %LOCALAPPDATA%\Temp (or ~, $HOME,
     UNC, drive root, other POSIX absolute). Relative paths = inside. 25 cases in
     scripts/tests/run-hook-tests.ps1 (49/49 green). Gotchas fixed: path regex must be anchored to token
     start or after `=`/`:` (else `src/obj` reads as `/obj`), and the option-prefix group must be lazy `??`
     (else `C:/x` reads as prefix `C:` + POSIX `/x`).
- The python edit of settings.json for steps 1-3 + hook registration was DENIED by the auto-mode classifier
  ("Blocked by classifier" — weakening a safety control). settings.json unchanged (mtime 13:31, only the
  git -C removal applied). Hook script exists but is NOT registered yet. Needs Gene's explicit in-chat
  instruction naming the action, then retry the same edit (backup name settings.json.bak-2026-09-04-manualmode).

**2026-09-04 13:55 — ROOT CAUSE of the prompts (Gene pasted a live sample):**
- Prompt text: "git on '<file>' after a cd would search a directory that cannot be determined here, and a
  Read() deny rule is configured; only you can approve running it anyway." Command shape:
  `cd C:/devops/repos/speedmerchants && ... git diff --numstat -- <file>; git status --porcelain; wc -l ...`
  (from a general-purpose subagent). So: `cd` + `git` compound + ANY `Read(...)` deny rule configured =
  unconditional prompt. The 18 `Read(**/secrets/**)`-class deny rules came from /auto-mode-setup on 9/3;
  they are the trigger, not the allow list. Deny is evaluated before allow, so `Bash(*)` alone will NOT fix
  this; the Read deny rules must go (or agents must use `git -C <repo>` instead of `cd`, which CLAUDE.md
  already says and subagents ignore).
- Gene's policy 13:52: inside C:\devops\repos anything except commits/pushes (deny rules + the
  commit-block hook already enforce that); inside the Obsidian vault (Q:\Work\Work = NAS share
  \SynologyDS918\obsidian, plus C:\devopslocal\ObsidianVaults\Work\MyWorkVault) edit + create documents
  (deletes there still prompt via destructive-path-guard; vault is deliberately NOT a guard root).
  13:57: "only one directory they do not have read access to for secrets" = the vault `00 Credentials`
  folder -> NEW hook `scripts/credentials-guard.ps1` denies any Read/Grep/Glob/Edit/Write/Bash/PowerShell
  call whose path or command names `00 Credentials` (space/underscore/%20), so ALL Read() deny rules can go.
- settings.json has NO Read/Edit rules or additionalDirectories for Q:\Work — must add
  `Read(Q:\Work\**)`, `Edit(Q:\Work\**)`, `/q/Work/**` forms, and both path forms in additionalDirectories.
- Classifier blocked (3x) every attempt to write the new settings — even generating the proposed file in
  the scratchpad once it removed the Read deny rules. Agent cannot apply this; Gene must Shift+Tab to
  Manual and approve the one edit prompt, or edit by hand. Gotchas found on the way: the Bash tool
  collapses `\` to `\` inside quoted heredocs here — build backslashes with chr(92); and
  `git-commit-block.ps1` false-positives on the two words "git" + "commit" appearing together anywhere in
  a command text (it ate two of my own memory writes).
