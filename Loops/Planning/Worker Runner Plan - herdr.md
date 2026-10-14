---
title: Worker Runner Plan - herdr
created: 2026-09-13
status: draft
owner: Gene
applies-to: work-ai/skills/myfable-foreman
related:
  - "[[MyFable Loop Fix Plan]]"
  - "[[MyFable-Foreman-Field-Guide.html]]"
---

# Worker Runner Plan — herdr (and the built-in alternative)

## In one paragraph

Today every MyFable worker is a helper **inside** the lead Claude session, so it dies when that session restarts, and you can't watch or unstick it. [herdr](https://herdr.dev/) would run each worker as its own `claude` in a terminal pane owned by a background server: the worker keeps going when the lead session or the Wave tab closes, herdr tells you when a worker is stuck, and you can attach and watch any worker. While checking flags for this plan, `claude --help` (Claude Code 2.1.270) showed that **Claude Code now has its own background sessions** (`claude --bg`, `claude agents`, `claude attach`, `claude logs`) that may give the same main benefit with nothing new to install. **Recommendation: run a short bake-off of the two before building either into the loop, then build the winner behind a switch, starting with a doc row.**

## What herdr is, plainly

- **Not more windows.** You see split panes inside one Wave tab, like tmux.
- **The difference is ownership.** The terminals belong to a herdr background server, not to the window. Close the tab or restart Claude and the processes keep running; reattach later.
- **It watches agents.** For each pane running an agent it shows working, blocked (waiting on a question or permission), idle or done.
- **Scripts can drive it.** `herdr pane run`, `herdr pane read`, `herdr agent wait`, plus a JSON socket API with status-change events.
- **Facts:** version 0.9.0, Apache 2.0, macOS / Linux / Windows x86_64 ("generally available, with documented platform-specific limitations").

> [!note] Your terminal
> Confirmed on 2026-09-13: Claude runs inside Wave Terminal 0.14.5 (`TERM_PROGRAM=waveterm`; process chain Wave.exe → wavesrv → pwsh → claude.exe). herdr inside Wave has not been tried.

## What you would gain

| Gain | Evidence from your loop | Worth |
|------|-------------------------|-------|
| Workers survive a lead-session restart, a model switch or an account switch | 52.P1.3b attempt 1 lost 13 minutes to a restart; memory: a restart loses in-flight workers (2026-09-12 20:30); account switching is routine | Biggest. 1 of 8 attempts lost so far |
| A stuck worker shows up as blocked right away | Today a permission prompt stalls silently until the overdue flag at 3× estimate, about 10× real time | High |
| Watch any worker live, and step in when needed | Today only the harness task list | Medium. Anything you type into a worker must be logged as a deviation note |
| Wake on "worker finished" instead of "grader green" | Fix 04 in [[MyFable Loop Fix Plan]] | Medium |
| One way to run Claude, Codex and Grok workers | fable-foreman needed wrapper agents per vendor | Low for MyFable (opus only) |

## What you would pay

| Cost | Detail |
|------|--------|
| A pre-1.0 tool | 0.9.0; Windows limitations not yet reviewed |
| One more always-on server | Must be running before a dispatch; must be restarted after reboots |
| Not reboot-proof | A herdr server stop or a reboot kills the worker process. herdr reopens the pane with `claude --resume <id>` (needs Claude integration version 6+): the conversation comes back, the work does not continue until nudged |
| Each worker is a full Claude session | See next section. Fixable with a worker profile |
| Status for Claude Code is read from the screen | herdr's docs list Claude Code's state authority as "screen manifest", not a hook. A hint, not proof |
| Harder usage accounting | Interactive `claude` doesn't print token use; minutes come from timestamps, tokens from session transcripts |
| New attack surface for principle 8 | herdr says its CLI "is the same surface agents drive": a worker could open panes itself unless blocked |

## The "full Claude session" problem and the fix

**Today** a worker is a subagent: it starts from `~/.claude/agents/foreman-worker.md` (2,633 characters) plus the ticket, under the lead's permissions, with the Agent tool removed.

**As a separate `claude`**, a worker would start like you opening a new tab. Checked on 2026-09-13:

| Loaded again per worker | Effect on a worker |
|-------------------------|--------------------|
| Global CLAUDE.md, 12,191 characters | Mandatory startup checklist before the ticket. The personality section ("ask before telling", ASCII art) is scoped to main sessions, and the worker now is one |
| MEMORY.md, 15,885 characters | Extra context; instructions to store learnings mean parallel memory writes |
| SessionStart hooks | caveman mode, explanatory style, superpowers rules, remember handoff, cowsay greeting |
| Stop hook claude-done.ps1 | A Windows balloon "Done — ready for input" per worker, per turn |
| Notification hook claude-waiting.ps1 | A balloon "Waiting for your input..." at every permission prompt |
| Stop hooks rationalization-watch, context-watch | Not yet read; may nudge or block a worker at stop |
| 13 plugins, the skills list, MCP servers | Slower start, more tokens |

**Fix: a worker profile.** `claude --help` (2.1.270) lists three relevant switches:

| Switch | What it says it does | Fit |
|--------|----------------------|-----|
| --safe-mode | Disables CLAUDE.md, skills, plugins, hooks, MCP servers, custom agents, output styles; "Auth, model selection, built-in tools, and permissions work normally" | **Best candidate.** Test whether it still honours the permission allowlist and whether MCP can be added back |
| --bare | Skips hooks, CLAUDE.md, auto-memory, plugin sync; **auth strictly ANTHROPIC_API_KEY or apiKeyHelper, OAuth never read** | Only if workers run on an API key, not your subscription login |
| --settings plus --setting-sources | Load a chosen settings file and pick which setting sources load | Fallback: a worker-only settings file with no hooks |

Put together with the worker contract (either pasted into the prompt file, or loaded as an agent via `--agents` JSON plus `--agent foreman-worker`), a launch would look like the block below. **Every flag is from `claude --help`, but the combination is untested.**

#### Example worker launch (untested)
```powershell
claude --safe-mode --model opus --effort high --name 52.P1.4 --permission-mode acceptEdits --disallowedTools "Agent" "Bash(git commit*)" "Bash(git push*)" "Bash(herdr *)" "Read and follow .loop/prompts/52.P1.4-a1.md. Write your report to .loop/reports/52.P1.4-a1.md."
```

**Belt and braces for your own hooks.** Launch workers with an environment marker `MYFABLE_WORKER=1`, and make `hook-dispatch.ps1`, `claude-done.ps1` and `claude-waiting.ps1` exit early when it is set. That protects you even if a switch doesn't behave as described.

## The built-in alternative: Claude Code background sessions

`claude --help` on 2.1.270 lists:

- `--bg, --background` — "Start the session in the background and return immediately. Prints the id that `claude attach`, `logs`, `stop` and `rm` take; `claude agents` lists them."
- `claude attach <id>`, `claude logs <id>`, `claude stop <id>`, `claude respawn [id]`, `claude agents`

**Why it matters.** If these sessions outlive the lead session and the Wave tab, they deliver the biggest herdr gain (survival) with no new software, and they're maintained by the same team as Claude Code.

**What is unknown until tested.** Whether they survive closing Wave, closing the lead session, and a reboot; whether `claude agents` shows a working/blocked/done status a script can wait on; how a script knows a background session has finished.

## Phase 0 — Bake-off (about an hour, when no row is in flight)

Run each test for **herdr** and for **claude --bg** where it applies. Record the answer in the scorecard.

### T1 herdr installs and works inside Wave

#### Install herdr
```powershell
irm https://herdr.dev/install.ps1 | iex
```

#### Install the Claude integration
```powershell
herdr integration install claude
```

#### Check the integration version (needs 6 or newer for resume)
```powershell
herdr integration status
```

Pass: herdr starts in a Wave tab; ctrl+b shortcuts and mouse clicks reach herdr, not Wave.

### T2 Survival — the deciding test

Start a long harmless job as a worker (for example a prompt that counts slowly to 300 with a pause between numbers).

1. Close the lead Claude session. Worker still running?
2. Close the Wave tab. Worker still running?
3. Quit Wave entirely. Open Windows Terminal and check.

#### Check from another terminal (herdr)
```powershell
herdr agent list
```

#### Check from another terminal (built-in)
```powershell
claude agents
```

Pass: the worker is still running after all three. **If a runner fails step 2 or 3, drop that runner.**

### T3 Status is truthful

1. Worker finishes: status goes working → done.
2. Worker hits a permission prompt: status goes blocked.
3. Attach to a done worker, detach: does it become idle? (herdr docs: "done" means finished but not yet viewed.)

Pass: all three observed. Note for design: never wait on "done" alone.

### T4 Worker profile is clean

1. Launch `claude --safe-mode --model opus` in the repo folder and prompt `Reply with exactly: READY`.
2. Run `/context` and write down the startup token count. Do the same with a plain `claude` for comparison.
3. Confirm: no caveman style, no Windows balloons, subscription login works, the worker can still run `pwsh`.

Pass: clean reply, clearly smaller startup, login works.

### T5 Permissions don't stall a worker

Give a worker a ticket that needs PowerShell, an edit inside its write set, and a grader run, under `--permission-mode acceptEdits`, then under `dontAsk`.

Pass: it completes without a prompt, and a denied command (for example `git commit`) is refused, not prompted.

### T6 Restart and reboot behaviour

Stop the runner's server (`herdr server stop`, or reboot for the built-in sessions), start again, and see what comes back.

Pass for the design: the conversation is recoverable and a script can tell "was running, now idle with no report" so Reconcile can nudge it.

### T7 Usage capture

Can minutes and tokens for a finished worker be read by a script (session transcript, `claude logs`, herdr metadata)?

Pass: at least minutes; tokens are a nice-to-have.

### Scorecard

| Test | herdr | claude --bg | Notes |
|------|-------|-------------|-------|
| T1 works in Wave | | n/a | |
| T2 survives lead close | | | |
| T2 survives Wave close | | | |
| T3 status truthful | | | |
| T4 clean profile | | | same test for both |
| T5 no permission stalls | | | same test for both |
| T6 restart recoverable | | | |
| T7 usage capture | | | |

**Decision rule.** Prefer the built-in runner if it passes T2 and gives a usable finished signal (T3), because it is less to install and keep running. Choose herdr if the built-in runner fails T2 or T3 and herdr passes them. If neither passes T2, stop: the main gain isn't there.

## Phase 1 — Build the winner behind a switch

Do this in the staging copy from [[MyFable Loop Fix Plan]], ideally after fixes 04 and 10 there.

1. **`Dispatch-Row.ps1 -Runner agent|herdr|bg`**, default `agent` (today's behaviour, untouched).
2. **Prompt file.** The runner writes the full worker prompt (preamble + class block + ticket + worker contract) to `.loop\prompts\<key>-a<n>.md`. Long prompts never go on a command line: multi-line quoting on Windows breaks (memory: backslash escapes become control bytes).
3. **Report file.** The worker must write its report to `.loop\reports\<key>-a<n>.md`, first line DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED. **The report file, not the status, is the finished signal.**
4. **Launch.**
   - herdr: split a pane in the repo's workspace, rename it to the row key, run the worker launch.
   - bg: `claude --bg` with the same flags; capture the printed id.
5. **Record.** Store the pane id or background session id on `attempts[n]` (replaces `taskId`).
6. **Monitor.** Loop every 60 seconds until the report file exists; wake early if the runner says blocked; time out at 3 × calibrated estimate (fix 03).
7. **Collect.** `Collect-Row.ps1` reads status from the report file's first line and minutes from timestamps.
8. **Reconcile.** Lists runner sessions against row records: running, blocked, finished-without-report, vanished. New action for "idle with no report after a restart": send "continue" (herdr `pane send-text`; bg: attach or resume).
9. **Worker safety.** Deny `Agent`, `git commit`, `git push`, and the runner's own CLI in the launch flags (principles 4 and 8).
10. **SKILL.md.** Document the switch, the prompt/report files, and the rule that typing into a worker is a deviation note.

### Rollout

- [ ] One **doc** row on the new runner (lowest proof tier, no verifier).
- [ ] One **mockup** row.
- [ ] One **code** row, with the verifier still on the Agent runner.
- [ ] Verifier on the new runner (read-only: deny Edit and Write).
- [ ] Two rows in parallel, then the full 7.
- [ ] Only then make the new runner the default. Keep `-Runner agent` as the fallback.

**Rollback:** dispatch with `-Runner agent`. No record format changes are needed to go back.

## Risks

| Risk | Mitigation |
|------|------------|
| Worker profile switch doesn't behave as documented | T4 before any build; environment marker in your own hooks as backup |
| Worker asks a question and sits idle | Blocked/idle detection wakes the lead; ticket preamble says never ask, report NEEDS_CONTEXT instead |
| You steer a worker live and the ticket stops being the contract | Every typed intervention recorded as a deviation note on the row |
| Runner server not running at dispatch | Dispatch checks the runner is up and refuses otherwise |
| Parallel workers share the remember handoff file or memory | Worker profile disables both; verify in T4 |
| herdr Windows limitations bite | Read herdr's documented Windows limitations before T1 |

## Open questions to verify

- herdr: the CLI flag for a timeout on `agent wait` (the socket API has `timeout_ms`); whether `pane split` prints the new pane id; a JSON option for `agent list` (`herdr api snapshot` exists).
- herdr: whether its server survives Wave closing when it was first started from a Wave tab (T2).
- Claude Code: whether `--safe-mode` keeps the permission allowlist from settings, and whether `--mcp-config` works alongside it (mockup rows use the Obsidian API for markdown).
- Claude Code: what `claude agents` shows per background session, and whether a script can wait on one.
- Billing: whether separate `claude` processes on your plan cost the same as in-session subagents.
- Your hooks: what `rationalization-watch` and `context-watch` do.

## Sources

- herdr: [home](https://herdr.dev/) · [install](https://herdr.dev/docs/install/) · [concepts](https://herdr.dev/docs/concepts/) · [agents](https://herdr.dev/docs/agents/) · [session state](https://herdr.dev/docs/session-state/) · [socket API](https://herdr.dev/docs/socket-api/) · [agent guide](https://herdr.dev/agent-guide.md) — fetched 2026-09-13.
- `claude --help` on Claude Code 2.1.270, run 2026-09-13.
- This machine, 2026-09-13: environment variables and process chain (Wave 0.14.5); `~/.claude/settings.json` hooks and plugins; sizes of CLAUDE.md, MEMORY.md, `agents/foreman-worker.md`; `scripts/claude-done.ps1`, `scripts/claude-waiting.ps1`.
- Row records `C:\devops\repos\speedmerchants\.loop\rows\*.json`; memory notes project_myfable_foreman, reference_loop_does_not_wake_on_subagent_completion, reference_claude_account_switching, reference_backslash_escapes_become_control_bytes.
