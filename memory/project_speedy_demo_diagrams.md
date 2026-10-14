---
name: project-speedy-demo-diagrams
description: "Speedy architecture diagrams + walkthrough video + click-through demo; /speedy-demo skill, HowToUpdate.md in the vault, capture.mjs full-height capture"
metadata:
  node_type: memory
  type: project
  originSessionId: 83ddbcc4-8e2a-4705-a951-671bf70c6124
  modified: 2026-09-24T19:28:57.221Z
---

Speedy architecture doc set (6 Archify diagrams, narrated MP4 v3, click-through demo) is updated with `/speedy-demo <request>` (skill in work-ai, linked 2026-09-24). Procedure = vault `99 Documentation\speedy\Diagrams\HowToUpdate.md`; working copy = git-ignored `C:\devops\repos\speedmerchants\.vs\diagrams`; published `tooling\` + `source\` + `walkthrough\narration\` are the backup; retired assets in `_archive\`.

**Why:** 9/24 review found the doc lived as a STRAY committed file inside the speedmerchants repo (`SynologyDS918\obsidian\...`) because a tool dropped the leading `\\` of the UNC path; the vault had no copy. Deleted from the working tree (user commits the removal).

**How to apply:**
- A repo folder named after a host (`SynologyDS918\`) = a UNC path written relative. Check for it after any tool writes to `\\host\...`.
- Archify re-lays out with viewport HEIGHT (01 widens 930->1806 px at 1400 high); screenshot and label boxes must come from the same page state -> `capture.mjs`, never Edge `--screenshot` + a separate measure.
- `build_v2.py` TTS cache is keyed on text (`.said` sidecar); `build_demo.py` reuses it.
- Headless Edge `--dump-dom` printed nothing here and UNC `file://` URLs don't load; use `tooling\probe.mjs` on a local copy.
- Related: [[reference-obsidian-smb-vault-watcher-blind]] (vault writes via Write-VaultFile).

**2026-09-24:** Standalone 'Why Speedy' intro added: `.vs\diagrams\intro.json` + `video\build_intro.py` -> `walkthrough\speedy-intro.mp4` (8 laps x 2 reasons, racing humor, ~3m47s). NOT yet joined to walkthrough; streams match so concat can stream-copy. Procedure 6.9 in HowToUpdate.md.
