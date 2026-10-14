---
name: speedy-demo
description: >
  Slash command that updates the Speedy architecture documentation set: interactive Archify diagrams,
  the narrated MP4 walkthrough, and the click-through demo. It edits specs and narration, validates,
  re-captures, rebuilds, and publishes. Use when the user types `/speedy-demo <request>`, or asks to
  change, add, re-narrate, rebuild, or republish a Speedy architecture diagram, the walkthrough video,
  or the narrated demo.
---

Repo: speedmerchants (paths below are repo-relative)

# /speedy-demo

`/speedy-demo <request>` applies a change to the Speedy diagrams, walkthrough video and click-through demo,
then rebuilds and publishes them. For example: `/speedy-demo Diagram 3: explain retries in more detail. New diagram 07: how ramping load works.`

**The procedure is `HowToUpdate.md`. Read it in full first, every time:**
`{VaultWorkRoot}\99 Documentation\speedy\Diagrams\HowToUpdate.md`
It holds the paths, the facts table, the content rules, and every command. This skill only adds the order of
work and the stop rules. If this skill and that document disagree, the document wins; fix the skill.

## When invoked

The text after the command is the **change request**.

1. **No request given:** ask what should change (per diagram, or a new diagram) and stop.
2. **Preflight:**
   - `Test-Path '{ClaudeHome}\bin\Write-AIFile.ps1'` and `Test-Path '{AIWorkRoot}'`. If the vault share is down (`Get-SmbMapping` shows it `Unavailable`), give the user `net use <LocalPath> <RemotePath> /persistent:yes` with the values from that line, and stop.
   - Check that the working folder `.vs\diagrams` exists. If it is missing, rebuild it from the published `source\`, `walkthrough\narration\` and `tooling\` backups, and say that you did.
3. **Plan:** break the request into concrete per-diagram edits: which spec, which cards, which narration sentences, and any new diagram. For anything that is the user's decision (scope, wording of a product claim, a new diagram's type), ask with AskUserQuestion, with a recommendation.
4. **Verify facts first** (content rules, section 4 of the doc): grep `src` for every technical claim you will add or change. A claim that is neither in the code nor a Product decision row in the facts table is left out. Update the facts table when a fact is new or has changed.
5. **Edit** the spec JSON (6.1/6.2) and `narration\NN.txt` (6.4). For a new diagram, also update `DIAGRAMS`, `ALIASES`, `WIDE`/`SHOW_FRAME` if needed, and the intro count in `build_v2.py`.
6. **Validate** every changed spec with `--quality showcase` until `ok` is true and composition is `pass` with 0 errors.
7. **Deliver and capture** every changed diagram (6.3). If the "how to use" narration or a page it records changed, the builds re-record it; review every clip by eye and fix any `actions overran` warning (6.5). Before narrating any viewer behaviour, record it and look.
8. **Rebuild the demo** (6.7), then **the video** (6.6). Run the video build with `run_in_background` and its output redirected to a log file. It takes about 15 minutes. If it is cancelled or fails, tell the user to run 6.6 in a normal pwsh window, and publish everything else.
9. **Publish** (6.8), then compare `Get-FileHash` of each published text file with its source.
10. **Check** the quality checklist (section 7). Render the published demo's tab list with `node tooling\probe.mjs` against a local copy of `00-narrated-demo.html` + `demo-manifest.js`.
11. **Update `HowToUpdate.md`** if anything in the procedure changed (a new diagram row, a new fact, a new tool), and write it back through `{ClaudeHome}\bin\Write-AIFile.ps1`.
12. **Report:** what changed per diagram, what you verified in the code (with `file:line`), what you left unverified, and whether the video was rebuilt and published.

## Rules

- Edit specs, never the delivered HTML.
- Text goes into the vault through `{ClaudeHome}\bin\Write-AIFile.ps1`; binaries (MP4, MP3, PNG) are copied over the UNC share.
- Never commit. The working folder is git-ignored; the published folder is the backup.
- Never burn subtitles into the video.
- Never delete published files. Retired assets move to `_archive\` only after the user approves it.
