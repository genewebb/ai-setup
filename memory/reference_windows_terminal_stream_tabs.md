---
name: reference-windows-terminal-stream-tabs
description: "ALL profile tab commands (addStreams/addStreamTab from 10/5, addtab/addnew from 10/12) use Windows Terminal; how tabs open, retitle and close"
metadata:
  node_type: memory
  type: reference
  originSessionId: 255fb53d-466b-409f-bc9b-7939d0b51e6b
  modified: 2026-10-12T15:32:57.199Z
---

On 2026-10-05 the owner moved stream tabs to Windows Terminal (1.24, installed on the laptop and SMVMTR1). Wave was dropped because wsh 0.14.5 can't create or name tabs, only panes in the current tab. WezTerm was dropped because its tabs had no close button, rename or force close.

- Open: `wt -w Streams new-tab --title <T> --tabColor <hex> -d <repo> pwsh -NoExit -EncodedCommand <b64>`. The tab's pwsh loads the profile.
- Title: set from inside the tab with `[Console]::Title`. `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` (verified present in the claude binary) stops Claude Code overwriting it. The runner's Set-RunnerTabTitle checks WT_SESSION first.
- Close: WT can't list or close tabs from outside. A tab closes when its shell exits 0. stopStreams and removeStreamTab write `.streams\tabs\close\<tab>`, and the tab's shell (a Timers.Timer event via Watch-GeneStreamTabClose) exits. Live test: closed in 2 s.
- Stopped runner tabs are recorded in `.streams\tabs\stopped\<tab>.json` for numbering and removeStreamTab.
- A tab launched from Wave inherits WAVETERM_* env. The tab prefix strips it, or the runner would retitle Wave.

**addtab/addnew (2026-10-12):** Windows Terminal too, no WezTerm/Wave, but KEPT SEPARATE from stream tabs (owner: "addTab should just open named tabs with colors NOT the stream"). Own helper New-GeneTab: `wt -w 0 new-tab -d <dir> --title <T> --suppressApplicationTitle --tabColor <c>`, default profile, runs nothing. Colors = $global:GeneTabColorRules title-prefix rules ported from .wezterm.lua (status/plan/author/build/integrat/kit/coordinat/git/compile/general; default #58a6ff). Only shares Test-GeneWt/Get-GeneWtPath. Never route addtab through New-GeneWtTab or GeneStreamTabColors. WezTerm helpers deleted. Synced laptop -> SMVMTR1 (hash 580F4BE2…). Machine-sync runs from the laptop; needs D: (\\SynologyDS918\devopslocal) reconnected first.

Supersedes [[reference-wave-wsh-stream-blocks]]. Related: [[project-stream-tabs-profile-2026-10-04]]

**Window choice (owner 2026-10-05):** tabs open in the WT window the command is typed in (`wt -w 0` = current/most recent window), never a named or new window. Owner groups tabs by picking the terminal. Commands refuse outside WT (`WT_SESSION` unset). Verified live: probe from a fresh window landed as 2nd tab in it, window count stayed 1.

**"Administrator: " prefix (2026-10-05):** elevated child `pwsh -File` that exits in the tab's console leaves the title `Administrator: <title>` (verified in WT: tab running `pwsh -File x.ps1` that set its own title came back "Administrator: start"). Planner etc. run claude straight from the tab shell and stay clean; runner tabs spawn children. Fix: Start-StreamRunner `Restore-RunnerTabTitle` re-sets the title every 1 s tick of the unit loop (WT only, skipped under STREAM_RUNNER_TITLE_LOG test stub). Before/after-unit set alone was NOT enough.
**Real culprit (verified live 10/5 12:15):** a child pwsh RUNNING in the tab's console owns the title meanwhile ("Administrator: Author 1" during, clean after). Runner launch check `pwsh -File ai.ps1 --version` (slow on TR1) did it after GATE. Fix: `Invoke-HiddenPwsh` (ProcessStartInfo CreateNoWindow + redirected output) for the launch check; title stays clean during. Many tabs truncate "Administrator: Author 3" to "Administrator" — looks like ALL tabs lost their names.
**Closing a WT window kills its runners (10/5):** no finally runs, state file stays in .streams\runners. Kit lib `Test-RunnerProcess` (pid must be pwsh started <= state.started+2min; recycled pid = dead) used by Get-RunnerUnits; watchdog `Move-DeadRunnerStates` moves dead files to logs\runner\<runner>\state.json (a note, not a decision). Must run ON the host: pid checks are local.
