---
name: ai-repo-management
description: >
  Where my skills, agents and commands live and how a change reaches every machine: the private ai-setup git
  repo cloned at {AIWorkRoot}, the ai-manifest.json runtime inventory, install.ps1 / publish.ps1, and the
  generated Overview README. Use when creating, renaming, retiring or migrating a skill, agent or command,
  when a skill is not loading in Claude Code, or when asked where a skill's source is.
---

# AI Repository Management

`{AIWorkRoot}` is a local clone of the private `ai-setup` git repo. It is the only source. `{ClaudeHome}` holds
installed COPIES; an edit made there is drift and is overwritten (and reported) by the next install.

## Layout

```text
{AIWorkRoot}\
├── skills\<name>\SKILL.md       # every folder is installed unless excluded in ai-manifest.json
├── agents\<name>.md
├── commands\<name>.md
├── claude\                      # CLAUDE.md, settings template, permissions.yaml, hook scripts, statusline
├── lib\  setup\                 # machine-config modules and installer
├── memory\                      # auto-memory; {ClaudeHome}\memory is a junction to it
├── pwsh\                        # PowerShell profiles, own modules, PSGallery module list
├── stream-host\                 # placed into the profile's StreamHostDir
├── ai-manifest.json             # runtime inventory: what the installer copies where
├── install.ps1  publish.ps1     # the whole sync model
└── share.yaml  tools\           # one-way promotion of chosen items to a work marketplace
```

## Add, change or retire a skill

1. Create or edit `{AIWorkRoot}\skills\<name>\SKILL.md` (frontmatter `name` = folder name, `description` =
   what it is + "Use when ..."). No registration step: the manifest installs every skills folder.
2. Regenerate the Overview README (generated, never hand-edited):
   ```powershell
   pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1"
   pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1" -Check   # exit 0 = current
   ```
3. Install on this machine: `pwsh -NoProfile -File {AIWorkRoot}\install.ps1 -NoPull` (or the `ai` launcher).
   Skills are indexed at session start: start a new session.
4. Send it to the other machines: `pwsh -NoProfile -File {AIWorkRoot}\publish.ps1 -Message "<what changed>"`.

Retire = delete the folder (git history keeps it), regenerate the README, install, publish.
A skill found only in `{ClaudeHome}\skills` (not in the clone) is the only copy: move it into the clone first,
never delete it.

## Skill not loading

1. `Test-Path "{AIWorkRoot}\skills\<name>\SKILL.md"` and check the frontmatter parses (`name`, `description`).
2. Not excluded in `ai-manifest.json` (`dir-each` skills entry, `exclude` list).
3. `pwsh -NoProfile -File {ClaudeHome}\bin\Install-AIMachine.ps1 -Check` reports drift or a missing install;
   run `install.ps1` and start a new session.

## Sharing at work

Items stay private unless listed in `share.yaml`; `tools\Promote-ToWork.ps1 -TargetRepo <work marketplace clone>`
copies them one way after its checks. Never edit the promoted copy in the work repo.
