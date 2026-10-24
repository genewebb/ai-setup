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
└── share.yaml  tools\           # blockedPatterns for prof setup share; Find-Secrets.ps1
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

Everything stays private until `prof setup share` hands it over: `prof setup share ai-setup` picks skills and writes
them as one plugin per category into the coworker repo (`ShareRepo` machine key, `ai\plugins`, marketplace at the
root); `prof setup share profile` does the same for PowerShell commands. A skill with a `{Key}` path or a reference to
an unshared skill is refused; `share.yaml` `blockedPatterns` hits are listed and confirmed; secrets stop it. share writes
the working tree and prints the git commands. Never edit the shared copy in that repo; change the source and share again.
