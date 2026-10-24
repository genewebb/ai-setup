# Machine-portable AI configuration: design

Status: revision 4 (build decisions folded in), 2026-10-01. Owner: Gene. Live on the laptop (CORPLTR94) and SMVMTR1. SMVMTR2 and SMVMTR3 wait for Gene's go-ahead; the procedure is `99_Frequent\HowToInstall.md` in the work vault.

## 1. Goal

Any skill, agent, hook, script or Claude setting can move to another machine whose paths differ. On a new machine:

1. Make the corpus reachable: a share, a copy or a clone. It is needed only at install and apply time.
2. Edit one file: that machine's `ProfileMachineConfig.md`.
3. Run one command: `Install-AIMachine.ps1`. It installs the local runtime, asks which MCP servers to set up, copies secrets from the source machine, and writes settings and the `ai` launcher.
4. From then on, start Claude with `ai`. A profile change is applied at the next launch.

After that, every skill, script, hook, permission and statusline resolves. No shared file contains an absolute machine path or a drive letter.

**Success criteria**

- `Test-NoHardPaths.ps1` reports 0 absolute paths in shared files, outside its allowlist.
- On a fake machine whose config uses other drives and roots, the generated `settings.json` contains none of the laptop's paths.
- A fresh Claude session on the laptop works as before:
  - hooks fire and the statusline renders;
  - the same skill count is listed (186 on 2026-09-30);
  - no new permission prompts appear on routine work;
  - the `00 Credentials` deny rules still block.
- VS Code, Cursor and other non-Claude client material is gone from config, docs and disk, after archive and confirmation.
- All Claude scratch and temp output (Claude's own temp folder, subprocess temp files, streaming throwaway work) goes under the profile's `ScratchRoot`.
- Streaming runs on a machine with no NAS mounts and no vault.
- Permissions follow the machine: the allow list comes from the profile's access table, the shared rules from the corpus, and new "always allow" clicks are harvested back into the shared rules.

## 2. Inventory (measured 2026-09-30 on CORPLTR94)

The scan covered 2,416 text files in the work-ai corpus (Q:), `~\.claude\scripts`, `hooks`, `commands`, `settings.json`, `~\.agents\skills` and the native (unlinked) skills. It found 1,584 absolute paths in 301 files.

| Group | Hits | Notes |
|---|---|---|
| `speed-merchants` repo source refs | ~867 | Almost all are `SKILL.md` references to code files. They need only a repo-relative path |
| `speedmerchants` repo | ~102 | The stream kit and myloop: start prompts, worktrees, `.loop` |
| `C:\devops\repos\myrepo` | 70 | Illustrative examples |
| Q: vault paths | 173 | Vault root, work-ai, `99 Documentation` |
| `C:\Users\agenewe` | 54 | Home-relative; should be `~` or derived |
| `C:\devopslocal\ObsidianVaults` | 37 | Retired location; the vault is now on Q: |
| Dead on this laptop | ~90 | `C:\tmp\loop-test*` (58), `C:\devopslocal\Documentation` (10), `c:\devopslocal\repos` (6), `C:\Deploy\TestAuto.Web` (6), `C:\tmp\ConnectExports`, and others |
| Examples or regex false positives | ~40 | `\\server\share`, `C:\scratch\x.md`, `\\r\n` |

By area, the most hits are in: `skills\myloop` (282), `~\.claude\settings.json` (68), `~\.claude\scripts` (62), `crewchief-web-ui` (41) and `orchestrator-worker-loop` (35). The stream kit has 16 hits locally; TR1 has its own copy.

Hits by file type: `.md` 1,120, `.ps1` 369, `.json` 69, `.mjs`/`.js`/`.cjs` 24, `.py` 2.

**Drive letters are not stable across machines.** On this laptop, `D:`, `F:`, `O:` and `Q:` are all mapped NAS shares (`D:` = `\\SynologyDS918\devopslocal`), not local disks. On the VMs, `D:` is a local disk used only for containers. No design element may assume any drive letter.

### settings.json today

- 26 `additionalDirectories`. 13 are Git Bash duplicates (`/c/devops/repos`) that do not exist as Windows paths.
- About 55 path-based permission rules, each written twice (`C:\...` and `/c/...`).
- 11 hook commands and the statusline, all hardcoded to `C:/Users/agenewe/.claude/...`.

What the Claude Code docs say (code.claude.com/docs/en/permissions, /settings and /hooks; checked 2026-09-30):

- In a Read/Edit rule, `//c/...` is an absolute path, `~/...` is under home, and a single leading `/` is relative to the folder of the settings file. So in user settings, `Read(/c/devops/repos/**)` means `~/.claude/c/devops/repos/**`. **All 27 `/c/`-form rules are no-ops today.**
- Rules are case-sensitive. Windows paths are normalised to `/c/...` before matching.
- `settings.json` has no variable substitution, except hook placeholders such as `${CLAUDE_PROJECT_DIR}`.
- There is no user-level `settings.local.json`. A machine-only rule must therefore come from machine config, not from an overrides file.
- `env` block values are visible to tool commands and to hooks.

### Overlapping config systems today

| System | Where | Fate |
|---|---|---|
| pwsh profile machine table | `C:\Deploy\Setup\ProfileMachineConfig.md` | **Kept**: becomes the single per-machine file |
| Old multi-client repo | `~\AI`: `local.yaml`, `permissions.yaml`, `sync.ps1`, `setup.ps1` | Fold the rules in, then archive |
| Skill linker | `<AIWorkRoot>\link-to-ai.ps1` | Replaced by `Install-AIMachine.ps1` |
| S: migration staging | `C:\tmp\AIWork` (`Install-AIWork.ps1`, `settings.template.json`), paused since 9/15 | Fold in the token template idea, then archive |

## 3. Decisions (approved by Gene, 2026-09-30)

| # | Decision |
|---|---|
| D1 | The per-machine source of truth is `ProfileMachineConfig.md`, extended with AI keys |
| D2 | Repo source references in skills become repo-relative |
| D3 | The only target is Claude Code. Drop VS Code, Cursor, Copilot (VS Code and CLI), Cline, Kilo and OpenCode. Their removal from disk is a separate optional step (R17) |
| D4 | Fold `~\AI` and `C:\tmp\AIWork` into the new system, then retire both |
| D5 | Scripts read paths through a shared helper, `Get-AIPath`, with an env-var override |
| D6 | Claude learns machine paths from a SessionStart hook that prints the resolved table |
| D7 | `settings.json` is generated from a template in the corpus |
| D8 | Stale references: repoint where a successor exists, delete when the target is gone for good, and turn examples into placeholders. Every change is logged |
| D9 | The corpus rewrite runs on a local copy. It is synced to Q: in one hash-checked pass |
| D10 | No drive letter or absolute path in any shared file. Machine paths live only in the machine profile. The archive target is a profile key: if it is missing or blank, the step stops and asks |
| D11 | NAS mounts (`D:`, `F:`, `O:`, `Q:` on the laptop) exist on no other machine. Nothing streaming needs may live on them |
| D12 | Everything streaming needs (state, graders, plans, mockups, evidence) lives under the repo. The stream skills themselves are user-level and are installed from the corpus |
| D13 | No `.claude\` content is checked into any repo. There are no project skills and no project settings. `-Check` flags any `.claude\` folder it finds in a repo |
| D14 | The scratch area is a required profile row, `ScratchRoot` (`C:\tmp` on the laptop; usually `D:\tmp` elsewhere). Claude's own temp folder, subprocess temp files and streaming's throwaway work all go under it |
| D15 | Everything Claude needs from a machine, including the access whitelist, comes from the same machine profile |
| D16 | Mockups go to `<repo>\Documentation\mockups\<task>\`. HTML, CSS and SVG are committed. PNGs and other binaries may sit there but are gitignored (R22) |
| D17 | The status page goes to the `StatusPageDir` profile row (wherever IIS lives on that machine). If the row is blank, it goes to `<repo>\.streams\status.html` |
| D19 | Git policy lives in the profile, as a per-repo table with separate `Commit`, `Push` and `Worktrees` columns. A repo that is missing gets none of them. Work inside a worktree follows its main repo's `Commit` and `Push`. Worktrees are created only under `{WorktreesRoot}`. A `git-guard` PreToolUse hook enforces it. Laptop: `speedmerchants` Commit yes, Push **no** (Gene, 10/1: push stays manual on the laptop), Worktrees yes. `speed-merchants` and every other repo get no row, so nothing is allowed |
| D20 | Permissions have two sources:<br>- the **profile** holds only the working folders (`## Claude access`) and the git policy;<br>- `{AIWorkRoot}\claude\permissions.yaml` holds every rule that has no machine path, and is identical on every machine.<br>`settings.json` is rewritten by the `ai` launcher when the installation identity changes (R1), and on demand through `/machine-config apply` |
| D18 | Kit maintenance writes to `{AIWorkRoot}` through `Publish-KitFile`. That calls `Write-AIFile`, which follows the resource route (R5): Obsidian API inside a vault, a hash-checked direct write otherwise. There is never a fallback |

### Review 2 decisions (2026-09-30; these replace earlier text where the two conflict)

Source: `machine-config-recommendations.md` (review 2). Its product claims were re-checked against code.claude.com on 9/30:

- confirmed:
  - SessionStart cannot block a session;
  - a removed env var persists in a running session;
  - `agent_id` is present in subagent hook input;
  - in extra directories, edits follow the permission mode;
  - "don't ask again" is saved per repo;
- confirmed in the laptop profile code: the parser scans every table row and warns on unknown keys;
- measured on 2.1.286 (9/30, see R26): `CLAUDE_CODE_TMPDIR` is honoured from the process env and from settings `env`.

| # | Decision |
|---|---|
| R1 | Changes are applied by a local `ai` launcher before `claude` starts. SessionStart only reports and detects a stale or direct launch |
| R2 | A failed validation at launch stops the launch with a diagnostic. The last good files stay for recovery and are not reported as active |
| R3 | The profile is authoritative. `AI_*` vars are outputs only. Overrides exist only behind an explicit `-TestOverride` switch, for tests |
| R4 | The runtime (skills, agents, commands, hooks, lib) is a local versioned copy with a manifest. You edit the corpus, then apply |
| R5 | Each resource row has `Route` = `direct` or `obsidian`. The path is the same either way; the route only picks the write mechanism. One helper, `Write-AIFile`, applies it. A path inside a vault inherits `obsidian`. If the API is down, the write stops and never falls back to direct |
| R6 | A vault's Obsidian endpoint is a profile value. The token is read from the obsidian MCP entry |
| R7 | An unreachable configured resource keeps its rules and routes and is reported as unavailable. Only a blank row removes it |
| R8 | Planning moves into the repo, gitignored (`<repo>\.planning\`), and is done on the stream host. Stream hosts never need a vault |
| R9 | Harvest classifies each approval exactly and never drops one by path containment (4.3a) |
| R10 | Claude-created repo `.claude\settings.local.json` files are allowed, as pending approvals. Anything else in a repo `.claude\` breaks D13 |
| R11 | Read-only access rows render an explicit `Edit` deny. The guarantee covers Claude's file tools and the guard hooks, not shell commands |
| R12 | Settings ownership is property by property. Each rule has exactly one owner |
| R13 | A fresh machine gets a full manifest-driven install: skills, agents, commands, hooks, plugins, marketplaces, MCP servers. Native-only skills are moved into the corpus or explicitly excluded |
| R14 | Every apply is a transaction: stage, validate, lock, check destinations, apply, write state last; roll back on failure |
| R15 | MCP servers: setup asks, per server, which ones move. The answers are recorded in the profile |
| R16 | Claude's own secrets (MCP tokens in `~\.claude.json`, and the secret user env vars) move by export and import. `Export-AISecrets` writes one AES file protected by a passphrase that Gene types and that is never stored. `Install-AIMachine -SecretsFile` imports it. The corpus lists secret **names** only. No value is ever placed in the corpus, a repo or the profile |
| R24 | App secret exports (TestAuto and CrewChief JSON) live in the `SecretsDir` profile row: `C:\Deploy\Secrets` on the laptop. The `D:\Secrets` (NAS) files are merged into it only after Gene confirms each one. The apps' own import flows are unchanged: import the export file and type the master password (from 1Password). The DPAPI-bound stores (TestAuto `master.json`, `%APPDATA%\CrewChief`) are never copied |
| R17 | Retiring the other clients and the old systems is a separate, optional step, after the laptop is green. Each item is confirmed and archived to `ArchiveRoot` first |
| R18 | `Worktrees = yes` requires `Commit = yes`. A mismatch is a validation error |
| R19 | git-guard fails closed (denies) for state-changing git when it cannot evaluate a command, and allows read-only git. "Workers never commit" stays in the skills |
| R20 | The profile records `TestedClaudeVersion`. `check` warns when the running version is older or untested. No version is forced |
| R21 | `ArchiveRoot` on the laptop is `C:\DataArchive` (local disk; Gene, 9/30, replacing the NAS `D:\DataArchive` proposal). Retirements go to `{ArchiveRoot}\ai-config-<yyyy-MM-dd>` |
| R22 | Mockup PNGs may sit in `<repo>\Documentation\mockups`, but images and other binaries are gitignored there. HTML, CSS and SVG are committed |
| R23 | The profile parser in the pwsh profile is changed to read only its first table, and to stop warning on the AI keys. The change is narrow and comes with tests |

### Build decisions (rev 4, 2026-09-30 to 2026-10-01; these replace earlier text where the two conflict)

| # | Decision |
|---|---|
| R25 | Built-in worktrees (`EnterWorktree`, `isolation: "worktree"`, `--worktree`) are **redirected** by a `WorktreeCreate` hook to `{WorktreesRoot}\<repo>\<name>` when the repo's `Worktrees = yes`, and refused otherwise. A `WorktreeRemove` hook refuses a dirty worktree. The hook prints the path on stdout; a non-zero exit fails creation (hooks.md, fetched 9/30) |
| R26 | `CLAUDE_CODE_TMPDIR` = `{ScratchRoot}`. Measured on 2.1.286: Claude reads it from the process env and from settings `env`, and appends `\claude` itself, so the scratchpad lands in `{ScratchRoot}\claude`. `TEMP`/`TMP` = `{ScratchRoot}\temp`. Settings `env` also reaches the tool shells of a running session after an apply |
| R27 | MyLoop is retired (replaced by the stream kit, 9/27). `skills\myloop`, the `myloop.md` and `myfable.md` commands and the `myfable-foreman-prev-2026-09-13` copy are not in the corpus or the runtime. Local copies go to `{ArchiveRoot}\myloop-retired-2026-10-01`; the Q: originals are listed for Gene before removal (4.7 step 5) |
| R28 | Permission merge outcomes: the `rm`/`rmdir` ask rules and the secret-file ask rules are not carried; `{ClaudeHome}\skills` gets `read, edit`; the live `git push` deny rules are dropped because git-guard owns push (D19). Rules in `permissions.yaml` use `{Key}`: in `Read`/`Edit`/`Write` it renders as `//c/...`; in `Bash`/`PowerShell` it renders literally, once with `\` and once with `/`; a rule whose key is blank is skipped (a skipped deny is reported). The vault credentials folder gets an `Edit` deny; `Read` is blocked by the credentials-guard hook, because any `Read()` deny makes Claude prompt on `cd <dir> && git ...` compounds |
| R29 | The hard-path gate (`Test-NoHardPaths.ps1`) accepts markers: `<!-- history -->` / `# history` (a line describing the past), `<!-- example-path -->` / `# example-path` (one line), `<!-- example-paths -->` on the line before a code fence (the whole block), plus `setup\hardpaths-allowlist.txt` for vendored data. `\d:\d` regex fragments and `{Key}\\x` are not paths |
| R30 | Stream scratch lives in `{ScratchRoot}\streams\<repo>` (`STREAM_SCRATCH_ROOT` overrides it in tests); the watchdog sweeps folders there with no write for 24 h. Scratch worktrees go to `{WorktreesRoot}\<repo>-scratch\<task>-<purpose>`; git-guard allows them and the watchdog reports them but never reaps them. The status page mirrors to `{StatusPageDir}\status.html` when the row is set |
| R31 | A `machine-config` skill (`show`, `check`, `apply`, `harvest`) fronts `Show-AIMachine.ps1`, `Install-AIMachine.ps1 -Check`, the apply and `Invoke-AIHarvest.ps1` (`propose`, `accept -Id`, `reject`, `finalize`; queue in `{ClaudeHome}\machine-config.harvest.json`) |
| R32 | `Write-AIFile` replaces `Write-VaultFile.ps1` everywhere, including skill prose. Its body is always sent as bytes (a typed `[byte[]]`; an untyped if-expression would send the numbers as text) |
| R33 | When a first apply replaces a linked folder (the old `~\AI` junctions) with a real copy, **every** file under it is written, even when it reads identical through the link. Found at the live `-WhatIf` (232 files planned instead of 752); covered by an installer test with a counterfactual |
| R34 | The `permissions-yaml` skill and the `CLAUDE.md` trigger point at `{AIWorkRoot}\claude\permissions.yaml` and `/machine-config apply`. The multi-client file and its drift checker are retired with `~\AI` (R17) |
| R35 | Hook and stream-kit self-tests build their trusted-root cases from the machine profile, so the same tests pass on any machine |
| R36 | `## Claude access` rows take an optional `delete` right (`read, edit, delete`; delete without edit is a validation error). The destructive-path-guard trusts `ReposRoot`, `WorktreesRoot`, `ScratchRoot`, the user's temp and every `delete` row. This carries TR1's whole-tree policy (Gene 9/28: `D:\devops`, `C:\temp`) and the `{ClaudeHome}` grant (Gene 9/29; both machines, Gene 10/1). The guard expands the current user's 8.3 profile name (TR1 fix) |
| R37 | The S:\AIWork linker layout links each skill/agent/command individually. The apply replaces every per-item link it writes into with a real copy, so nothing is written through a link into a shared target; links the corpus does not cover are kept and reported. Covered by `NestedLinks.Tests.ps1` with a counterfactual. With `SkillsLinkRoot` set, R38 applies instead |
| R38 | Optional profile key `SkillsLinkRoot` (Gene 10/1). When set (TR1: `S:\AIWork`, the Azure Files tree TR2 and TR3 share), every corpus skill, agent and command in ClaudeHome is a symbolic link to `{SkillsLinkRoot}\<kind>\<name>`. The corpus wins: before linking, the apply writes the corpus content into that tree and removes files there that the corpus lacks. Those files, and any local entry the link replaces, go into the rollback snapshot. An edit made in the tree by another machine shows as drift (exit 3). Blank (the laptop) means real copies, as in R37; blanking it later drops the links and never touches the tree. Items the corpus lacks keep their links (R37). The key must be reachable and outside ClaudeHome. Covered by `LinkRoot.Tests.ps1` (9 cases; the counterfactual fails 8 of 9 on the R37 installer) |
| R39 | `SkillsLinkRoot` may name the machine's own corpus copy (`{AIWorkRoot}`), so the machine edits a tree only it writes (Gene 10/1: TR1 stops linking to the share). A linked item's files are then corpus files: editing one is a corpus edit (it changes the identity and the next start applies it), not drift. Any other link tree keeps the drift check. Covered by the 10th `LinkRoot.Tests.ps1` case; the R38 installer fails it |
| R40 | Machine sync (Gene 10/1). `{DeployRoot}\steps\Sync-Machine.ps1 -Source -Target` (skill `machine-sync`) carries the corpus, the shared pwsh profile and the stream-host scripts between any two machines in `{DeployRoot}\machines.json`, either direction. It compares each file on both sides against the base, the content both last agreed on (`{DeployRoot}\sync-base\`): changed on the source only is copied; changed on the target only is left alone; changed on both is a conflict, left alone unless `-Force`. Deletions need `-Delete`. Default is a dry run; every overwritten file is backed up first. `Stage-Machine.ps1` records the base after a stage and refuses to mirror over a target edited since then (or with no base) unless `-Force`. New profile key `DeployRoot` (blank on target-only machines). Covered by `steps\tests\Sync-Machine.Tests.ps1` (7 cases) |

## 4. Design

### 4.1 Machine config: `ProfileMachineConfig.md`

The file keeps its existing format: `| Key | Value | Used by | Status |`, with `%VAR%` expansion, and a blank value means "not on this machine".

Its location is the one fixed convention in the system: `C:\Deploy\Setup\ProfileMachineConfig.md`. The `AI_MACHINE_CONFIG` env var overrides it.

New rows:

| Key | Laptop value (this machine only) | Meaning |
|---|---|---|
| `AIWorkRoot` | `Q:\Work\Work\03 Shared\work-ai` | Corpus root (skills, agents, commands, claude\, lib\, setup\) |
| `ClaudeHome` | `%USERPROFILE%\.claude` | Claude config dir |
| `WorktreesRoot` | `C:\devops\worktrees` | **Required.** Git worktrees for every repo, in `{WorktreesRoot}\<repo>\<name>`. Temporary; never inside a repo |
| `ScratchRoot` | `C:\tmp` | **Required.** All scratch work. It holds:<br>- `{ScratchRoot}\claude`: Claude's own temp folder, via `CLAUDE_CODE_TMPDIR`<br>- `{ScratchRoot}\temp`: `TEMP`/`TMP` for subprocesses<br>- `{ScratchRoot}\streams\<repo>`: skeptic rounds, probes and staging copies<br>On other machines it is usually `D:\tmp` |
| `StatusPageDir` | blank on the laptop; the IIS folder on TR1 | Where `/stream-status` writes the status page. Blank means `<repo>\.streams\status.html` |
| `VaultWorkRoot` | `Q:\Work\Work` | Work Obsidian vault |
| `VaultPersonalRoot` | `Q:\Personal\MyPersonalVault` | Personal vault |
| `SecretsDir` | `C:\Deploy\Secrets` | App secret export files (TestAuto and CrewChief JSON). Local disk. Blank where there are none (R24) |
| `ArchiveRoot` | `C:\DataArchive` | Where retirements are archived (R21). Blank means archiving stops and asks |

Rows that already exist are reused: `ReposRoot`, `SpeedyRepo`, `SpeedMerchantsRepo`, `PowershellScriptsDir`, `VaultDocsRoot`.

`CursorRulesDir` and `DocumentationDir` are not profile keys (D3): nothing reads them.

**Resources and routes (R5, R6).** Each resource key (`VaultWorkRoot`, `VaultPersonalRoot`, `AIWorkRoot`, `ScratchRoot` and so on) gets a `## Resources` table row:

| Key | Route | Obsidian endpoint |
|---|---|---|
| `VaultWorkRoot` | obsidian | `https://127.0.0.1:27124` (laptop example) |
| `ScratchRoot` | direct | |

- A key with no row is `direct`.
- A path inside a vault inherits `obsidian`.
- The token always comes from the obsidian MCP entry.

**Profile parser (R23).** Today the pwsh profile's `Read-GeneMachineConfig` scans every table row and warns on unknown keys (checked 9/30). It is changed to read only the first table and to accept the AI keys, with tests.

**Access whitelist (D15).** The profile gets a second table, `## Claude access`. After the R23 fix, the profile's own parser ignores it.

| Path | Access | Note |
|---|---|---|
| `{ReposRoot}` | read, edit | every repo on this machine |
| `{WorktreesRoot}` | read, edit | |
| `{ScratchRoot}` | read, edit | |
| `{VaultWorkRoot}` | read, edit | |
| `{VaultPersonalRoot}` | read, edit | |
| `{SecretsDir}` | read | |
| `%USERPROFILE%\Documents\PowerShell` | read, edit | |

- `Path` is either a `{Key}` or a literal path. Literal paths are allowed here, because this file is machine-only.
- `Access` is one or more of `read`, `edit` or `deny`.
- Every row with `read` or `edit` also becomes an `additionalDirectories` entry.
- A row whose key is blank on this machine is skipped and reported.
- Shared deny rules that must hold on every machine, such as `{VaultWorkRoot}\00 Credentials`, stay in the corpus `permissions.yaml`. They take precedence over any row here.
- Command rules that contain no path (`Bash(git status*)` and the like) also stay in the corpus `permissions.yaml`.

**Git policy (D19).** A third table, `## Git policy`:

| Repo | Commit | Push | Worktrees | Note |
|---|---|---|---|---|
| `{SpeedyRepo}` | yes | yes | yes | laptop starting row; streaming needs worktrees |
| `C:\devops\repos\other` | yes | no | no | example: commit locally, never push, no worktrees |

- **A missing repo gets no commit, no push and no worktrees.** That is the default for every repo; `speed-merchants` has no row on the laptop.
- `Repo` is a `{Key}` or a literal path, compared after full path normalisation, case-insensitive on Windows.
- A worktree is mapped to its main repo through `git rev-parse --git-common-dir`. Work inside it follows the main repo's `Commit` and `Push`.
- **`Worktrees`:**
  - `yes` allows `git worktree add`, `remove` and `prune`. It requires `Commit = yes` (R18); a row with `Worktrees = yes` and `Commit = no` fails validation. `worktree list` is always allowed.
  - Cleanup never removes a worktree that is dirty or claimed by a task.
  - The new worktree's path must be under `{WorktreesRoot}`. Anything else, including a path inside the repo, is denied.
  - Claude Code's built-in worktree tools (`EnterWorktree`, and `isolation: "worktree"` on agents) go through the same check. Where they would place the tree is not verified. The plan's first step checks this. If they place it inside the repo, the hook denies them on every repo, and sessions use `{WorktreesRoot}` through git instead.
  - Skills that can use worktrees (the stream skills, `using-git-worktrees`) read the column first. Where it is `no`, they work in the main tree and say so.
- **Enforcement: the `git-guard` hook**, run by `hook-dispatch.ps1 -Id git-guard` on PreToolUse for the Bash and PowerShell tools and for the worktree tools.
  - It finds git verbs in the command text, including the `git -C <path>` form and commands chained with `;`, `&&` or `|`.
  - It works out the target repo from `-C`, or from the command's working directory.
  - It then denies with a reason that names the repo and the profile file.
  - **Verbs that need `Commit`:** every git verb that changes the repo, the index or the worktree state:
    - `commit`, `merge`, `rebase`, `cherry-pick`, `revert`, `am`, `tag`;
    - `add`, `rm`, `mv`, `restore`, `checkout`, `switch`, `reset`, `stash`, `branch` (create or delete), `clean`, `apply --index`.
    `worktree add/remove/prune` falls under `Worktrees` instead.
    This matches the existing rule that a repo without permission gets no git state changes at all, and Gene stages by hand.
  - **Verbs that need `Push`:** `push`.
  - **Fails closed (R19):** if the hook cannot evaluate a command (a parse error, or an unreadable profile), it denies state-changing git and allows read-only git. The deny message says why.
  - **Always allowed:** read-only git, for example `status`, `log`, `diff`, `show`, `ls-files`, `rev-parse`, `branch --list`, `worktree list`.
  - **Rule kept in the skills, not the hook:** executor and worker subagents never commit, whatever the table says. That rule lives in the stream skills and `CLAUDE.md`, because a hook cannot tell a worker from an orchestrator.
- **Known limit:** command-text matching is heuristic. A verb built at run time (`git $v`) can get past it. That is accepted; the tests cover the common shapes.
- The session-start `machine-paths` output and `-Check` both print the git policy table.
- **`CLAUDE.md` change:** "Never commit" becomes "Commit, push or create worktrees only where the machine profile's git policy table allows it. The git-guard hook enforces this." The workflow skills that say "skip any commit step" get the same wording.

The profile keeps its own parser and its laptop defaults for the existing profile keys. Those defaults are out of scope, apart from the TR1 drift fix in the rollout. **The AI keys have no defaults.**

### 4.2 Resolver: `<AIWorkRoot>\lib\MachineConfig.psm1`

```powershell
Get-AIPath -Name WorktreesRoot            # returns the path or throws
Get-AIPath -Name SecretsDir -Optional     # returns $null when the value is blank
Get-AIConfig                              # every key: value, source, exists, share-or-local
```

Resolution order:

1. The `Value` cell in the table, with `%VAR%` expanded. The profile is authoritative (R3). `AI_*` env vars are never read, except under the explicit `-TestOverride` switch used by tests.
2. One derivation only: `ClaudeHome` = `$HOME\.claude`. Every other key, `WorktreesRoot` and `ScratchRoot` included, must be set explicitly in the profile.
3. Otherwise it throws: `Machine config key 'X' is not set. Add a row to <config path>.`

**Temporary roots stay out of repos.** `ScratchRoot` and `WorktreesRoot` hold only temporary files. `-Check` warns, and `Install-AIMachine.ps1` refuses to write settings, when either one:
- resolves inside `ReposRoot` or inside any repo in the git policy table; or
- is inside the other one.
To override, add `AllowTempInRepo | yes` to the profile. You must choose this explicitly; nothing falls back to it.

The `share-or-local` value is worked out at run time from `Get-PSDrive` (`DisplayRoot`); there is no extra column. A disconnected mapped drive is reported as `share (disconnected)`. When `install.ps1` runs over WinRM (prof setup marks it with `PROF_REMOTE_SESSION=1`), an unreachable share or a letter that is not a drive there is `not checked (remote session)`: a remote session holds no credentials for a second machine (Windows second hop) and has no mapped drives, so the check says nothing about the share. It is an info line, not a warning.

Consumers that cannot import a PowerShell module (`.mjs`, bash) read the `AI_*` env vars. The applicator writes those into the `settings.json` `env` block (4.3). **These exports are outputs only (R3).** The resolver never reads them back.

**How a script finds the module:** everything runs from the local installed runtime (R4). Scripts use a path relative to their own folder or to `${CLAUDE_SKILL_DIR}`, so nothing loads from `AIWorkRoot` at run time.

### 4.3 Applicator: `Install-AIMachine.ps1` (installed locally; first run from the corpus)

One applicator does three jobs: first setup, `/machine-config apply`, and the launcher's apply step (R1). Every run is a transaction (R14):

1. Read the inputs once:
   - the profile;
   - the corpus release, identified by its manifest hash;
   - the template and generator versions.
2. Stage every output in a staging folder under `ClaudeHome`.
3. Validate the staged outputs (4.3b). Any failure means a nonzero exit, and nothing is changed.
4. Take the per-install lock (`ClaudeHome\machine-config.lock`).
5. Check that no destination changed since step 1. A changed destination counts as unexplained drift (4.3a): it is reported, its content preserved, and the apply stops.
6. Apply the outputs.
7. Write the state record **last**. If any step fails, the previous install is restored from staging.

`-WhatIf` and `-Check` change nothing. Applying identical inputs twice produces no effective change.

**Outputs:**

1. **Local runtime (R4).** A versioned copy, not links, of the manifest's skills, agents, commands, `CLAUDE.md`, hook scripts, statusline and `lib\` into `ClaudeHome`, plus `ClaudeHome\ai-runtime.manifest.json` (file names and hashes).
   - A share outage never breaks a session.
   - You edit the corpus, then apply.
   - A runtime file edited in place is reported as drift, not overwritten silently.
   - Native-only skills are either moved into the corpus manifest or excluded explicitly (R13). Nothing is left implicit.
2. **MCP servers and secrets (R15, R16).**
   - The corpus manifest lists every MCP server as a template, with `{Key}` and secret-name placeholders.
   - Setup asks, per server, whether it is installed on this machine. The answers are recorded in the profile as `## MCP servers` rows.
   - Endpoint values (Obsidian URL, DB host and name) come from the profile.
   - **Secrets (R16):**
     - On the source machine, `Export-AISecrets` gathers the MCP secret fields and the secret user env vars that the corpus manifest names into one passphrase-encrypted file.
     - On the target, `Install-AIMachine -SecretsFile <file>` asks for the passphrase and writes the values into `~\.claude.json` and the user environment.
     - A secret the manifest names but the file lacks is listed as missing, never guessed.
     - The import deletes the file afterwards only when Gene confirms.
   - **App secrets (R24):** the TestAuto and CrewChief export files are copied into `{SecretsDir}`. Install then reminds Gene to run each app's own import, which needs the master password.
3. **Generate `settings.json`.**
   - Inputs:
     - `claude\settings.template.json`: hooks, statusLine and env shape only.
     - `claude\permissions.yaml`: every path-free rule (commands, MCP, WebFetch) plus shared denies by key. A rule has exactly one owner (R12).
   - Path rules come from two places:
     - the profile's `## Claude access` table, for this machine's allow list;
     - the corpus `permissions.yaml`, for shared deny and ask rules, written by key:
     ```yaml
     file_access:
       - { key: VaultWorkRoot, sub: '00 Credentials', deny: [Read, Edit] }
     ```
   - **Read-only rows (R11):** an access row marked `read` renders as `Read` allow **plus an explicit `Edit` deny**. Without the deny, the extra directories would let edits through under auto or acceptEdits mode. Where rows overlap, the most specific one wins, and the render report lists every overlap.
     - **Scope of the guarantee:** Claude's file tools and the guard hooks. Shell commands are not covered, because `Bash(*)` and `PowerShell(*)` are allowed.
   - Harvest is described in 4.3a.
   - Rendering:
     - Each resolved path is written once, in `//c/...` form.
     - A key that is blank on this machine skips its rule. A `deny` rule on a blank key is reported, never dropped silently.
     - Command rules that contain a script path (`pwsh -NoProfile -File <path>/*`) are rendered literally, in both `\` and `/` forms, because they match the literal command text.
     - `additionalDirectories` come from the access table, Windows form only.
     - The `env` block gets:
       - every resolved key, as `AI_<KEY>`;
       - `TEMP` and `TMP` = `{ScratchRoot}\temp`, so subprocesses (dotnet, pwsh, npm) put their temp files there and not on the system drive.
   - **Claude's own temp folder:** `CLAUDE_CODE_TMPDIR` = `{ScratchRoot}\claude` is set in two places: by the launcher, in the environment it starts `claude` with, and in the settings `env` block. Two sources disagree on whether the settings copy is honoured (the 9/30 docs-check agent and review 2), and the doc pages fetched on 9/30 did not show the entry. The scratch test confirms the effective location on the recorded Claude version.
   - Also written into settings: `cleanupPeriodDays`, from an optional `TranscriptRetentionDays` profile row.
   - Skills call their own scripts through `${CLAUDE_SKILL_DIR}` (a documented skill placeholder), never through `~\.claude\skills\...`.
   - **Ownership is set property by property (R12).** The applicator owns exactly these properties:
     - `permissions.allow`, `permissions.ask`, `permissions.deny`, `permissions.additionalDirectories`;
     - `hooks`, `statusLine`;
     - the `env` keys it writes (`AI_*`, `TEMP`, `TMP`, `CLAUDE_CODE_TMPDIR`);
     - `cleanupPeriodDays`.
     Every other property, nested values included, is preserved semantically.
   - **Safety:** it writes a timestamped backup (`settings.json.bak-<stamp>`) and prints a diff before writing.

### 4.3b Validation (required before any apply)

Each of these stops the apply, and at launch stops the launch, with a diagnostic (R2):

- a required key is missing (`AIWorkRoot`, `ScratchRoot`, `WorktreesRoot`, `ReposRoot`);
- `ScratchRoot` or `WorktreesRoot` is inside a repo or inside the other one, without `AllowTempInRepo`;
- **`Worktrees = yes` with `Commit = no`** on any git policy row (R18). Worktrees are allowed only where commits are;
- the access table, git policy or resource routes have a row that cannot be parsed;
- resource routes conflict: a `direct` row inside a vault declared `obsidian`;
- the running Claude version is older than the profile's `TestedClaudeVersion` (R20). This one is a warning only.

A configured resource that is **unreachable** (a disconnected share) is not a failure. Its rules and routes are kept, and it is reported as unavailable (R7). Only an explicitly blank row removes a resource.

### 4.3c Launcher: `ai` (R1)

`ai` is a small local script on `PATH`, installed by the applicator. `Start-MyStreaming`, `New-AgentTab` and the `/loop` host prompts call it instead of `claude`.

1. Resolve the profile path (`C:\Deploy\Setup\ProfileMachineConfig.md`, or `AI_MACHINE_CONFIG`, the only environment input).
2. Compute the installation identity:
   - the profile path and hash;
   - the effective expanded inputs;
   - the corpus manifest hash;
   - the template and generator versions.
3. If the identity differs from the state record, run the applicator under its lock. Two launchers started together serialize on the lock, and the second sees the new state and skips.
4. If validation fails, stop with the diagnostic. The previous install remains for recovery but is not reported as active.
5. Start `claude` with `CLAUDE_CODE_TMPDIR` set, passing its arguments through.

**SessionStart's role:**
- report the active revision and resource availability;
- warn when the session was started without `ai` (a direct launch) or on a stale revision.
It never applies anything.

**Running sessions** keep their startup settings for anything startup-only, and keep removed env vars. `apply` therefore reports two lists, "written" and "active only after a fresh launch". Other running sessions are listed as needing a restart.

The state record (`ClaudeHome\machine-config.state.json`) holds three things:
- the source revision;
- the installed revision;
- the revision each launcher-started session was given, keyed by session start.
It never claims that a running session holds values it was not started with.

`-Check` mode writes nothing. It reports:

- config keys that are missing or blank, and roots that are missing or disconnected;
- links that are broken or point elsewhere;
- drift between the generated and the actual `settings.json`;
- hook scripts that differ from the corpus copy.

### 4.3a Permission sources: today and after

**Today (measured on the laptop, 2026-09-30):**

| # | Source | What it holds | State |
|---|---|---|---|
| 1 | `~\.claude\settings.json` | The **live** rules: 109 allow, 65 ask, 56 deny, plus 26 `additionalDirectories` | Hand-edited since 9/14. 27 `/c/` rules are no-ops |
| 2 | `~\AI\permissions\permissions.yaml` (last edited 9/14) | The multi-client "canonical" file: 11 deny / 55 ask / 374 allow command patterns, `file_access` (including `{{HOME}}/**` allow), 13 dirs, MCP `auto_approve` lists, `claude_code_extras` (`Bash(*)`, `PowerShell(*)`, WebFetch domains) | Nothing generates from it. `Check-PermissionsDrift.ps1` reports "all clients match", but it compares only command tiers: live deny is 56 against its 11. It is not a complete check |
| 3 | `C:\tmp\AIWork\claude\settings.template.json` | A 9/15 snapshot of #1 (111/65/56), with tokens | Stale staging |
| 4 | `.claude\` in repos | `speedmerchants\.claude\settings.local.json` (8/1/1); `test\.claude\settings.json` and `.local`; `D:\repos\cursor-rules-templates\.claude\settings.json` and `.local` | Against D13 |
| 5 | Hook scripts in `~\.claude\scripts` | Permission logic as code: `test-loop-autoapprove.ps1` (auto-approves), `destructive-path-guard.ps1`, `credentials-guard.ps1`, `gateguard.ps1` (not wired; streaming tabs disable it) | Unbacked, laptop only |
| 6 | `~\.claude.json` | No `allowedTools` (0 in 11 projects). Holds 11 MCP server definitions, some with secrets | Fine as is; never copied or generated |
| 7 | Other clients: VS Code, Cursor, OpenCode, Copilot | Their own copies of #2 | Retired (D3) |
| - | Managed settings | None (`C:\ProgramData\ClaudeCode\managed-settings.json` absent) | n/a |

**After:** there are exactly three sources, and one generated output.

| Source | Holds | Shared? |
|---|---|---|
| `{AIWorkRoot}\claude\permissions.yaml` | Claude-only. Command rules for allow, ask and deny (Bash and PowerShell), MCP auto-approve, WebFetch domains, and shared path denies by key (`{VaultWorkRoot}\00 Credentials`) | Yes, every machine |
| The profile's `## Claude access` and `## Git policy` tables | This machine's path allows, `additionalDirectories`, and commit/push/worktree rights | No, one per machine |
| `{AIWorkRoot}\claude\scripts\*` | The guard and auto-approve hooks (#5), copied to `ClaudeHome\scripts` at install | Yes |
| **Output:** `~\.claude\settings.json` | Generated. Never hand-edited | Rendered per machine |

**One-time merge (the first implementation step for permissions).** `Merge-PermissionSources.ps1` reads #1 to #4 and writes:

1. A proposed corpus `permissions.yaml`:
   - the union of all Claude rules;
   - paths rewritten as keys;
   - `/c/` no-ops and the duplicate `C:\` + `/c/` pairs dropped;
   - VS Code-only and other client-only entries dropped.
2. A review report:
   - **conflicts:** the same pattern in different tiers across sources;
   - **broad rules to confirm:** `{{HOME}}/**` allow, `Bash(*)`, `PowerShell(*)`;
   - **rules found only in the live settings,** meaning hand-added after 9/14;
   - **rules found only in repo files.**

Gene approves the report. The proposed file becomes the corpus file, and #2 to #4 are archived (repo `.claude\` folders removed after confirmation, D13).

**Applying changes (D20, as revised by R1).** Changes are applied by the `ai` launcher before Claude starts (4.3c), or on demand.

**Skill `/machine-config`:**
- `apply`: runs the same applicator, diff first. It reports changes written and changes that need a fresh launch.
- `check`: writes nothing. It reports:
  - invalid input and unavailable resources;
  - drift;
  - pending approvals;
  - the active revision against the installed one.
- `harvest` (R9):
  - It classifies each clicked approval by tool, operation, scope (repo) and full pattern.
  - An approval is dropped only when the generated policy provably covers **the same operation and scope**. Path containment alone never drops one: a script-run approval inside a repo stays a command rule, and an edit approval under a read-only row is not redundant.
  - A command rule containing a path gets a proposed `{Key}` form.
  - The repo scope is kept unless Gene chooses global.
  - The original rule text and the repo name stay in the proposal.
  - Rejected rules and unrelated local settings are preserved.
  - An exact entry is removed only after its replacement is applied and verified.
- `show`: prints the resolved paths, resources and routes, access list, git policy and MCP servers.

**Repo `.claude\settings.local.json` files that Claude Code itself creates are allowed, as pending approvals (R10).** `check` reports them as "pending harvest". Claude Code gitignores them automatically. Anything else in a repo `.claude\` (`settings.json`, skills, a tracked file) breaks D13.

**Drift contract.** Drift is detected, reported and reconciled; it is not assumed impossible.
- `check` diffs the live `settings.json` and runtime files against the installed revision.
- Before any apply replaces a changed file, unexplained edits and pending approvals are preserved and reported. They are never silently promoted to shared policy, and their only copy is never erased.
- Known clicked approvals go into the harvest queue (`ClaudeHome\machine-config.pending.json`), which survives applies.

### 4.4 Machine paths in Claude's context: SessionStart hook

`hook-dispatch.ps1 -Id machine-paths` prints the resolved table once per session, about 15 short lines:

```
Machine paths (CORPLTR94, from C:\Deploy\Setup\ProfileMachineConfig.md):
  AIWorkRoot     Q:\Work\Work\03 Shared\work-ai   share
  WorktreesRoot  C:\devops\worktrees              local
  SecretsDir     (blank: not on this machine)
  ...
```

Skill prose refers to machine paths as `{KeyName}`, for example "create the worktree under `{WorktreesRoot}\<repo>`". `CLAUDE.md` gains one line: "`{Key}` in a skill means the machine path for Key from the session's Machine paths table; if it is missing, run `Get-AIConfig`."

### 4.5 Corpus rewrite rules

The rewrite is applied to a local copy, `{ScratchRoot}\ai-config-work\corpus`, then synced to Q: (4.7).

| Found | Becomes |
|---|---|
| `C:\devops\repos\speed-merchants\X\Y.cs` in a skill | `X\Y.cs`, plus one `Repo: speed-merchants (paths below are repo-relative)` line near the top of the skill, if it has none |
| Same, for the `speedmerchants` repo | Same, with `Repo: speedmerchants` |
| Machine path in prose: worktrees, tmp, vault, secrets, docs | `{Key}` or `{Key}\rest` |
| Machine path in `.ps1` | `Get-AIPath Key`; there is never a literal default |
| Machine path in `.mjs`/`.js` | `process.env.AI_<KEY>`, failing loudly when unset |
| `C:\Users\agenewe\...` | `~\...` in prose; `$HOME` / `Get-AIPath ClaudeHome` in code |
| Retired location with a successor (`C:\devopslocal\ObsidianVaults\...`) | The successor key path |
| Target gone for good (`C:\tmp\loop-test*`, `C:\devopslocal\Documentation`) | The reference is deleted. If the surrounding sentence loses its meaning, it is rewritten or removed |
| Illustrative example (`C:\devops\repos\myrepo`, `\\server\share`, `C:\scratch\x.md`) | An obvious placeholder: `<repo>`, `<share>`, `<file>` |
| A past event in a history or decision note ("on 9/26 C:\tmp held...") | Kept as written. It records what happened. The gate allowlists it with a marker |
| `/loop` start prompts (`repo: C:\devops\repos\speedmerchants`) | `repo: {SpeedyRepo}` |

**Streaming self-containment (D11, D12, D16 to D18).** On SMVMTR1 on 2026-09-30, the stream kit's dependencies outside the repo were:

| Dependency | Becomes |
|---|---|
| Mockup screens written to the vault (`stream-build` "Mockup tasks") | `<repo>\Documentation\mockups\<task>\` as HTML/CSS/SVG, committed. The gallery artifact is unchanged |
| Kit maintenance publishing to `Q:\...\work-ai` (`stream-kit` inbox step 4; `stream-coordinator` step 7) | `Publish-KitFile.ps1`, which writes to `{AIWorkRoot}` |
| `C:\inetpub\wwwroot\speedy\status.html` | `{StatusPageDir}\status.html`, or `<repo>\.streams\status.html` when the row is blank |
| Scripts referenced as `~\.claude\skills\stream-kit\scripts\` | `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`, or the installed skill path resolved by `Get-AIPath ClaudeHome` |
| Skeptic, probe and staging folders that sessions created in `C:\tmp` | `{ScratchRoot}\streams\<repo>\<task>-<purpose>`. The skills name this location explicitly, and the watchdog sweeps stale folders there |
| The host temp sweep (`[IO.Path]::GetTempPath()`) | Unchanged in code. It now lands in `{ScratchRoot}\temp` through `TEMP`/`TMP` |
| `/loop` start prompts with an absolute repo path | `repo: {SpeedyRepo}` |
| Test fixture strings (`\\SynologyDS918\obsidian\...`, `D:\tmp\speedy-mockups\...`) | Placeholder rooted paths under the test's own temp root |

After the rewrite, a machine with no NAS and no vault can run every stream role given only three things: the repo, the installed skills and the profile rows.

**The stream kit** follows the same rules. Its worktree root comes from `Get-AIPath WorktreesRoot`, which covers repofix.md finding 1. Its disk check adds the temp and system drive, worked out at run time (repofix finding 2). The TR1 copy is reconciled in the rollout step, not here.

**Change log:** `{ScratchRoot}\ai-config-work\rewrite-log.csv`, with one row per change: `file, line, before, after, rule`. Gene reviews it before the sync.

### 4.6 Gate: `<AIWorkRoot>\setup\Test-NoHardPaths.ps1`

This is the inventory scanner, made permanent.

- It fails on any absolute drive or UNC path in a shared file.
- **Allowlist:**
  - the one config-location convention string;
  - lines marked `<!-- history -->` (md) or `# history` (ps1);
  - `.bak*` files;
  - the `synced\` vendor skill folders;
  - regex literals such as `\\r\n`.
- It prints `file:line: path`.
- Exit code 0 means clean.
- It runs inside `Install-AIMachine.ps1 -Check`, and on its own.

### 4.7 Sync to Q:

1. Hash the Q: tree and the local copy.
2. Put each changed file with `Write-AIFile` (it replaced `Write-VaultFile.ps1`; R32), because a direct write over SMB hits a sharing violation and Obsidian's index does not see it.
3. Re-hash both sides.
4. Re-diff, in case an edit landed during the sync.
5. Files that are deleted or renamed in the corpus are listed for Gene to confirm before removal.

### 4.8 Cleanup and retirement (separate optional step, R17)

This runs only after the laptop is green on the new setup. It is not part of the migration. Everything is archived to `{ArchiveRoot}\ai-config-<yyyy-MM-dd>` first. If `ArchiveRoot` is blank or unreachable, the step stops and asks. Each original is removed only after Gene confirms that item.

| Item | Action |
|---|---|
| `~\.cursor`, `%APPDATA%\Cursor` | Archive, then remove |
| `~\.vscode`, `%APPDATA%\Code\User\mcp.json`, VS Code user `settings.json` AI entries | Archive, then remove. The VS Code install itself is listed for Gene to decide |
| `~\.copilot`, `~\.config\opencode` | Archive, then remove |
| Copilot, Cline, Kilo and OpenCode targets in `permissions.yaml`; `Check-PermissionsDrift.ps1` | Not carried into the new `permissions.yaml`; archived with `~\AI` |
| `CLAUDE.md` mentions of Copilot, OpenCode, Cline and "other clients", and the memory tool-disambiguation table rows for them | Rewritten for Claude Code only |
| `CursorRulesDir` profile key and the `ccursor` command | Removed from the laptop profile and config (profile rollout to the VMs as usual) |
| `~\AI` (after its rules and token ideas are folded in) | Archive, then remove |
| `C:\tmp\AIWork` | Archive, then remove |
| `<AIWorkRoot>\link-to-ai.ps1`, `Set-SkillProfile.ps1` | Replaced by `Install-AIMachine.ps1`; archived |

## 5. Testing

All tests use scratch roots and fake configs, and clean up after themselves.

1. **Resolver tests:**
   - the profile wins over any `AI_*` env var (R3); a missing `WorktreesRoot` or `ScratchRoot` throws, with no fallback;
   - a `ScratchRoot` or `WorktreesRoot` inside a repo is refused unless `AllowTempInRepo` is `yes`;
   - a missing key throws and names the key and the file;
   - `-Optional` with a blank value returns `$null`;
   - `%VAR%` expansion;
   - a disconnected mapped drive is reported, not crashed on.
2. **Generator golden test.** It uses a fake machine config where every root is under a scratch folder on another drive layout. It checks that:
   - the output has no laptop path;
   - rules are only in `//x/` form;
   - blank keys drop their rules;
   - a blank deny key is reported;
   - non-owned keys are preserved byte for byte.
3. **Gate test:** a seeded file with each path shape is flagged, and allowlisted shapes pass.
4. **Laptop dry run:** `Install-AIMachine.ps1 -WhatIf`. Gene reviews the diff of `settings.json` and the link plan.
5. **Laptop live run, then a fresh-session smoke test:**
   - the hooks fire: greeting, done chime, destructive-path-guard, credentials-guard;
   - the statusline renders;
   - the `machine-paths` table appears;
   - 186 skills are listed;
   - routine reads and edits under the repos, vault and tmp do not prompt;
   - a Read of a file under `{VaultWorkRoot}\00 Credentials` is denied.
6. **Gate run:** `Test-NoHardPaths.ps1` reports 0 on the synced corpus.
7. **Scratch test.** After the installer runs and a new terminal opens, start a session and check:
   - its scratchpad is under `{ScratchRoot}\claude`;
   - `pwsh -c [IO.Path]::GetTempPath()` from a tool call returns `{ScratchRoot}\temp`;
   - nothing new is written to `%LOCALAPPDATA%\Temp\claude`.
8. **NAS-free streaming test.**
   - Point a scratch profile at a scratch repo clone with no vault keys set (`VaultWorkRoot` and `VaultPersonalRoot` blank) and NAS drives absent from every value.
   - Run `Test-StreamKit.ps1` and `Test-StreamKitRecovery.ps1`, and the gate on the stream skills.
   - Pass means 0 fails and no reference to a blank key.
9. **Git-guard test.** Using a scratch profile and three scratch repos (all yes; commit only; absent), plus a worktree of the first:
   - every verb is allowed or denied as the table says, in the plain, `git -C`, chained and worktree forms;
   - `worktree add` is allowed on the first repo, and denied on the others and for any path outside `{WorktreesRoot}`, including `..` traversal;
   - a profile row with `Worktrees = yes` and `Commit = no` fails validation;
   - a command the hook cannot parse is denied when it changes state and allowed when it is read-only;
   - a deny message names the repo and the profile file;
   - read-only git (`status`, `log`, `diff`) is never blocked.
10. **Harvest semantics.** Seed:
    - a script-run approval inside a repo;
    - a file-read approval and a file-edit approval under a read-only row;
    - a repo-scoped command;
    - an unrelated local setting.
    Check that none of them is dropped or broadened just because a path matches an access root, that the repo scope is kept, that the unrelated setting survives, and that an entry is removed only after its replacement is applied and verified.
11. **Stale exports.** Apply with `VaultWorkRoot` = A, edit the profile to B, then launch through `ai` from a process that still carries A's `AI_*` exports. The settings and a child process must use B. Repeat with an optional vault row made blank.
12. **Rejected revocation.** Remove an allowed folder and add an invalid required key. `ai` must stop the launch. No session may start on the old access.
13. **Complete change detection.** Change only the template, then only a guard script, then only the generator. Each change is detected through the manifest or version identity, and installed.
14. **Concurrency and interrupted apply.** Start two `ai` launches at once, and inject a failure between writing the outputs and writing the state record. Each case must end on a consistent revision or roll back to the prior install.
15. **Write routing.** Use one ordinary mapped folder (`direct`) and two vaults (`obsidian`, with separate endpoints). Write the same file to each through `Write-AIFile`. Then make one API unavailable: the write must stop, with no direct fallback.
16. **Fresh machine.** Use an empty Claude home, a different user name and roots, and no undeclared laptop files. Install from the manifest, answer the MCP prompts, and copy the secrets. Verify the declared inventory by names and hashes.
17. **Source unavailable.** After setup, make the corpus unreachable from an isolated test install. Hooks, statusline, skills, and a stream with all its repo inputs must work. Vault-dependent work must report the missing capability instead.
18. **Read-only and repeatability.** A read-only row denies Edit in auto and acceptEdits modes. `-WhatIf` and `-Check` change nothing. Applying twice with identical inputs makes no effective change.
19. **Activation.** After an apply, check the settings on disk, the env in the first tool call, and the "needs a fresh launch" report, for an added, a changed and a removed value.

Every test runs in an isolated location. None disconnects a live share or changes Gene's live permissions.

## 6. Rollout

1. Laptop, as above.
2. SMVMTR1 and SMVMTR2, as a separate step. TR1 changes over only in a quiet window: no stream claims and no running builders. Before the switch, its live stream kit copy is reconciled into the corpus.
   - fill in each VM's config rows, including the TR1 fix of `SpeedyRepo`/`ReposRoot` to `D:\devops\...` (repofix.md N2);
   - restore C: in the TR1 profile defaults (N3);
   - run `Install-AIMachine.ps1 -Check`, then a live run;
   - reconcile TR1's stream kit copy with the corpus (repofix finding 6).
   The rest of repofix.md (renaming the C: copies, retiring `Move-StreamHostLayout.ps1`) stays in that file's own fix order.

## 7. Out of scope

- The S: migration decision. `AIWorkRoot` simply points wherever the corpus lives.
- The profile's own defaults, apart from the `CursorRulesDir` removal. The parser change in R23 is in scope.
- Moving the corpus itself off the NAS. Today `AIWorkRoot` is on Q:, and TR1 holds real copies. Whatever later hosts the corpus (S:, a git remote) just becomes the `AIWorkRoot` value. Runtime installs are local copies (R4), so a machine needs the corpus only at apply time.
- `~\.claude.json` as a whole file. Only its MCP server entries and their secrets move (R15, R16), copied directly between Gene's machines. The per-machine project state in that file is never copied.

## 8. Risks

| Risk | Mitigation |
|---|---|
| A generated `settings.json` drops a permission and sessions start prompting, or a deny is lost | The golden test, the diff review before the live write, the backup file, and the smoke test including the deny check |
| The bulk rewrite changes meaning in prose | The local copy, the per-change log reviewed before sync, and history lines kept |
| A share is down at session start (Q: after a reboot) | Hooks are local copies; the resolver reports a disconnected share instead of crashing; `-Check` flags it |
| TR1 keeps editing the stream kit during the work | Its local copy is not touched here; it is reconciled in rollout step 2 with hash checks |
| `CLAUDE_CODE_TMPDIR` and `${CLAUDE_SKILL_DIR}` behave differently from what a docs-check agent reported on 2026-09-30 (not yet confirmed first-hand) | Scratch test (step 7). One skill script is called through `${CLAUDE_SKILL_DIR}` in the smoke test before the bulk rewrite depends on it |
| `ArchiveRoot` is blank or unreachable on a machine | Cleanup is the last step, and it stops and asks if the row is blank |
| Claude Code permission matching has behaviour the docs leave out (for example drive-letter case) | The smoke test checks one allow rule and one deny rule live. If either fails, the rendering is changed before rollout |
