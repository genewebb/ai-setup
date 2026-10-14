---
name: feedback_taskupdate_is_the_status_page
description: "Gene watches speedy\taskupdate\TaskUpdate.html (file:// in a browser), NOT the vNext schedule Artifact; a failed TaskUpdate write is a status outage, never a quiet WARNING"
metadata:
  type: feedback
---

Gene, 2026-09-13 09:50: "Why is the TaskUpdate.html not being updated but the old vNext schedule is — I think you are confusing the two."

**Why:** Write-TaskUpdate.ps1 had failed with a sharing violation (0x80070020) at every regen from 2026-09-12 19:42 (plan page) / 21:05 (list) until 09:5x the next morning. RowCommon's Invoke-ScheduleRegen prints only a WARNING, and I kept republishing schedule.html to Artifact 402006bb as if that were the status publish. Gene's page was frozen ~13 h through three rejections, a close and a dispatch. He views it at file:///Q:/Work/Work/99%20Documentation/speedy/taskupdate/TaskUpdate.html.

**How to apply:**
- In [[project_myfable_foreman]] loops, TaskUpdate.html + CrewChief-Section-Plan.html are THE status surface. The schedule Artifact is secondary.
- Any `WARNING: Write-TaskUpdate.ps1 failed` line: say so in the SAME turn's message, every time, with the page's last-written time; do not bury it as "retry later".
- Diagnose a lock by error code (0x80070020 = sharing violation), a fresh-file write+delete probe in the same folder, and the NAS's own open-files list (DSM) — the client cannot name a lock holder on an SMB share without handle.exe.

**Root cause + fix (2026-09-13 10:19):** the holder was **Obsidian** (vault = `Q:\Work\Work`). Evidence: no local handle (Restart Manager, elevated handle64), Offline Files not caching the NAS, a Q: remap did not free it; the moment Obsidian was closed all three files were writable. Gene: "update via the api not directly". `Write-TaskUpdate.ps1` now PUTs each vault page to the Obsidian Local REST API (`/vault/<rel>`), bearer key read at run time from the obsidian MCP entry in `~/.claude.json`, and falls back to a direct write only when the API is down; its summary line prints `(api)` or `(direct)` per page. Never print that MCP entry: a redaction regex missed the `Authorization` header once and leaked the key to the transcript.
