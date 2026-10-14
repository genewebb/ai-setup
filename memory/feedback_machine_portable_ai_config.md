---
name: feedback-machine-portable-ai-config
description: Rules for the AI and streaming setup - no drive letters or NAS paths in shared files; all machine values in ProfileMachineConfig.md; no .claude files in any repo; scratch root configurable
metadata:
  node_type: memory
  type: feedback
  originSessionId: b2e5c3f1-477c-4a3d-9020-778d297a28c8
  modified: 2026-10-01T02:29:11.284Z
---

Gene's rules for the skills, streaming and Claude config (stated 2026-09-30):

- No absolute path or drive letter in any shared file: skills, scripts, templates, docs. On the laptop `D:`, `F:`, `O:` and `Q:` are Synology NAS mounts (`D:` = `\\SynologyDS918\devopslocal`), and no other machine has them.
- Everything Claude needs from a machine comes from `C:\Deploy\Setup\ProfileMachineConfig.md`. That includes the access whitelist: repo, scratch, worktrees and so on are whitelisted per machine.
- No `.claude\` content is ever checked into any repo: no project skills, no project settings.
- Everything streaming needs lives under the repo. Mockups go in `<repo>\Documentation\mockups`, committed.
- The scratch area (`ScratchRoot`) MUST be configurable: `C:\tmp` on the laptop, usually `D:\tmp` elsewhere. An oversized `C:\tmp` filled the disk.
- Never archive to a drive that may not exist. The archive target is a profile row.
- Clients: Claude Code only. VS Code, Cursor, Copilot, OpenCode, Cline and Kilo are retired.

Review 2 decisions (9/30, spec R1 to R24):
- An `ai` launcher applies changes before Claude starts; a bad profile stops the launch.
- The profile is authoritative; `AI_*` env vars are outputs only.
- The runtime is a local versioned copy, not links.
- Read-only rows emit an Edit deny.
- Harvest never drops an approval by path containment.
- Repo `.claude\settings.local.json` files Claude creates are allowed, as pending approvals.
- Each resource row has a Route (`direct` or `obsidian`; the path stays the same) and the API never falls back to a direct write.
- Planning moves to `<repo>\.planning` (gitignored), on the stream host.
- `Worktrees = yes` requires `Commit = yes`.
- git-guard fails closed.
- Claude's secrets move by passphrase-encrypted export and import; app secret exports sit in the `SecretsDir` row (`C:\Deploy\Secrets` on the laptop).
- Retiring old clients is a separate step.

**Why:** the move from C: to D: on TR1 broke the hardcoded skills and permissions, and a full scratch drive took every session down.

**How to apply:** any path in a shared file becomes a `{Key}` or a `Get-AIPath` call. Design spec: `Q:\Work\Work\03 Shared\work-ai\docs\machine-config-design.md`. Related: [[project-profile-machine-config]], [[project-stream-host-smvmtr1-2026-09-28]]
