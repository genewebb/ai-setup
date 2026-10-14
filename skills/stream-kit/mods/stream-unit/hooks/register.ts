// stream-unit: ends one stream-kit runner unit (EnhanceStream option G).
//
// Start-StreamRunner.ps1 -Live starts an interactive Claude session per unit of work and sets three variables:
//   STREAM_UNIT_OUT      absolute path of the unit's result file (.streams\logs\runner\<runner>\<stamp>-<session>.json)
//   STREAM_UNIT_SESSION  the stream session id the skill uses (build-..., integ-..., ...)
//   STREAM_UNIT_ROLE     author | build | integrate | plan | status | kit | coordinator
// With STREAM_UNIT_OUT unset (a person's own session) the mod registers nothing and changes nothing.
//
// The role skill ends its cycle by calling unit_done. The hook writes the result file in the fields the -p runner logs
// (result, is_error, num_turns, total_cost_usd) plus the outcome. When that turn completes, the mod runs /exit, so the
// process ends and the runner starts the next unit in a fresh process. /exit cannot run from the tool.call hook itself:
// the call holds the turn, and the host refuses a command run that would wait on it.
//
// Waiting on the owner: when a tool call (the session's or a subagent's) will show a permission prompt (tool.check's
// verdict is ask), the mod writes <STREAM_UNIT_OUT>.waiting.json { waiting: true, since, tool, reason } and puts a line
// under the dialog. The runner polls that file: it pauses the unit timeout, retitles the tab NEEDS YOU, rings the bell
// and files an owner-queue line. When every prompted call has resolved, the file reads { waiting: false }. On
// 2026-10-04 a builder sat 90 minutes on a prompt nobody knew about until its timeout killed it.
// The dialog itself is drawn by the engine alone; a mod cannot move or redraw it.
import type { Register } from 'claude-code'

type Asking = Map<string, { tool: string; reason: string }>

// Writes <out>.waiting.json from the open prompts: waiting while any is open, cleared when none is.
async function writeWaiting($: any, out: string, asking: Asking) {
  const first = asking.values().next()
  const record = asking.size
    ? { waiting: true, since: await $.clock.now(), count: asking.size, tool: first.value!.tool, reason: first.value!.reason }
    : { waiting: false, at: await $.clock.now() }
  await $.fs.write(`${out}.waiting.json`, JSON.stringify(record))
}

// Kill by name: a unit stops only processes it started, by the PID it recorded. A kill that picks processes by name or
// command-line pattern on the shared stream host also takes every other unit's graders and the integrator's suites. On
// 2026-10-09 one builder asked for `pkill -f Invoke-Grader.ps1` and another for `pkill -f python`; both sat on the
// owner's prompt with their timeouts paused. Inside a unit such a command is refused outright, never put to the owner.
// Returns why the command kills by name, or '' when it does not.
function killByName(command: string): string {
  const c = command
  if (/(^|[;&|(`'"]\s*|\b(sudo|xargs|exec)\s+)pkill\s+\S/im.test(c)) return 'pkill picks processes by name or pattern'
  if (/(^|[;&|(`'"]\s*|\b(sudo|xargs|exec)\s+)killall\s+\S/im.test(c)) return 'killall picks processes by name'
  if (/\bpgrep\b[^;&]*\|\s*xargs\s+kill\b/i.test(c) || /\bkill\b[^;&|]*\$\(\s*pgrep\b/i.test(c)) return 'pgrep feeds kill a set of processes chosen by name'
  if (/\btaskkill(\.exe)?\b[^;&|]*\s\/(im|fi)\b/i.test(c)) return 'taskkill /IM or /FI picks processes by image name or filter'
  if (/\b(Stop-Process|spps|kill)\b[^;&|]*\s-(Name|ProcessName)\b/i.test(c)) return 'Stop-Process -Name picks processes by name'
  for (const m of c.matchAll(/\b(Get-Process|gps|ps)\b([^|;&]*)(\|[^;&]*?)?\|\s*(Stop-Process|spps|kill)\b/gi)) {
    if (!/\s-Id\b/i.test(m[2] ?? '')) return 'Get-Process piped to Stop-Process picks processes by name'
  }
  if (/\bwmic\b[^;&|]*\bprocess\b[^;&|]*\b(delete|terminate)\b/i.test(c)) return 'wmic process ... terminate picks processes by a query'
  if (/Win32_Process[\s\S]*\b(Terminate)\b/i.test(c)) return 'Win32_Process Terminate picks processes by a query'
  return ''
}

const COMMAND_TOOLS = new Set(['Bash', 'PowerShell'])

const OUTCOMES =['built', 'ticketed', 'planned', 'integrated', 'done', 'idle', 'blocked', 'failed'] as const

const DESCRIPTION = [
  'Ends this stream runner unit. Call it exactly once, as the last action of the cycle,',
  'after every result of the unit is written under .streams\\ (task state, inbox items, history).',
  'outcome: built | ticketed | planned | integrated | done (the unit moved its task that far), idle (nothing to take),',
  'blocked (the task is blocked or handed back), failed (the cycle could not finish).',
  'note: one line saying what happened. The session exits after this call; do not call anything after it.',
].join(' ')

const SCHEMA = {
  type: 'object',
  properties: {
    outcome: { type: 'string', enum: [...OUTCOMES] },
    note: { type: 'string' },
  },
  required: ['outcome'],
}

export const register: Register = (on) => {
  let turns = 0
  let done = false
  let exiting = false

  // Prompted calls not yet resolved, by tool_use_id.
  const asking: Asking = new Map()

  on('tool.check', async ($, e, next) => {
    if (COMMAND_TOOLS.has(e.tool) && (await $.env.get('STREAM_UNIT_OUT'))) {
      const command = String((e.input as { command?: unknown } | null)?.command ?? '')
      const why = killByName(command)
      if (why) {
        return {
          decision: 'deny',
          reason: `Refused by the stream runner: ${why}. On the shared stream host it would also stop other units' graders and the integrator's suites. Stop only a process this unit started, by the PID you recorded (Start-Process -PassThru then Stop-Process -Id <pid>; taskkill /PID <pid> /T). A hung process you did not start is not yours: let the unit limit end it, or name it in an inbox item.`,
        }
      }
    }
    const r = await next(e)
    if (r?.decision !== 'ask' || !e.tool_use_id) return r
    const out = await $.env.get('STREAM_UNIT_OUT')
    if (!out) return r
    asking.set(e.tool_use_id, { tool: e.tool, reason: r.reason ?? '' })
    await writeWaiting($, out, asking)
    const tab = (await $.env.get('STREAM_UNIT_TAB')) || (await $.env.get('STREAM_UNIT_SESSION')) || 'this unit'
    try { $.ui.notice(e.tool_use_id, `Stream runner (${tab}) is waiting on you: its unit timeout is paused until you answer.`) } catch { }
    return r
  })

  // Any call that was prompted resolves here, answered or refused; the last one clears the waiting file.
  on('tool.call', async ($, e, next) => {
    const id = (e as { tool_use_id?: string }).tool_use_id
    try { return await next(e) }
    finally {
      if (id && asking.delete(id)) {
        const out = await $.env.get('STREAM_UNIT_OUT')
        if (out) await writeWaiting($, out, asking)
      }
    }
  })

  on('session.start', async ($, e, next) => {
    const out = await $.env.get('STREAM_UNIT_OUT')
    if (out) await $.tool.register({ name: 'unit_done', description: DESCRIPTION, inputSchema: SCHEMA })
    return next(e)
  })

  // A subagent's turn (a verifier, a scout) carries agentId: it neither counts nor ends the unit.
  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId) return r
    turns++
    if (done && !exiting) {
      exiting = true
      void $.command.run({ command: 'exit' })
    }
    return r
  })

  on('tool.call', { tool: 'mcp__stream-unit__unit_done' }, async ($, e) => {
    const out = await $.env.get('STREAM_UNIT_OUT')
    if (!out) return { deny: 'unit_done works only inside a stream runner unit: STREAM_UNIT_OUT is not set.' }
    if (done) return { deny: 'unit_done was already called for this unit; the session is exiting.' }
    const input = e as unknown as { outcome?: unknown; note?: unknown }
    const outcome = typeof input.outcome === 'string' ? input.outcome : ''
    if (!(OUTCOMES as readonly string[]).includes(outcome)) {
      return { deny: `outcome must be one of: ${OUTCOMES.join(', ')}.` }
    }
    const note = typeof input.note === 'string' ? input.note : ''
    const usage = await $.session.usage()
    const record = {
      type: 'result',
      runner: 'stream-unit',
      session: (await $.env.get('STREAM_UNIT_SESSION')) ?? null,
      role: (await $.env.get('STREAM_UNIT_ROLE')) ?? null,
      session_id: await $.session.id(),
      outcome,
      result: note,
      is_error: outcome === 'failed',
      // main-session turns ended before this one, plus the turn that calls unit_done
      num_turns: turns + 1,
      total_cost_usd: usage.cost?.usd ?? null,
      started_at_ms: usage.startedAt,
      ended_at_ms: await $.clock.now(),
      context: usage.context,
    }
    await $.fs.write(out, JSON.stringify(record, null, 2))
    done = true
    return { result: `recorded ${outcome}. End your turn now with one short line; the session exits when this turn completes.` }
  })
}
