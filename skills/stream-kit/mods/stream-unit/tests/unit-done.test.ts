import { test, expect, mock } from 'claude-code/testing'

const OUT = 'repo\\.streams\\logs\\runner\\runner-build-1\\20261004T170000Z-build-1.json'

// Answers every call the mod makes beneath it, recording what it wrote and which commands it ran.
const world = (on: any, vars: Record<string, string>) => {
  const seen = { writes: [] as { path: string; text: string }[], commands: [] as string[], registered: [] as string[] }
  mock.env(on, vars)
  on('tool.register', ($: any, e: any) => { seen.registered.push(e.name); return { value: { tool: `mcp__stream-unit__${e.name}` } } })
  on('session.usage', () => ({ value: { startedAt: 1000, context: { percent: 12 }, rateLimits: [], cost: { usd: 0.42 } } }))
  on('session.id', () => ({ value: 'sess-uuid-1' }))
  on('clock.now', () => ({ value: 5000 }))
  on('fs.write', ($: any, e: any) => { seen.writes.push({ path: e.path, text: e.text }); return { value: undefined } })
  on('command.run', ($: any, e: any) => { seen.commands.push(e.command); return { text: '' } })
  on('session.start', ($: any, e: any) => e)
  on('turn.complete', ($: any, e: any) => ({ text: e.answer }))
  return seen
}

const turn = (answer: string, agentId?: string) => ({ reason: 'answer', answer, durationMs: 1, isAborted: false, turnId: 't-' + answer, ...(agentId ? { agentId } : {}) }) as any

const UNIT = { STREAM_UNIT_OUT: OUT, STREAM_UNIT_SESSION: 'build-1', STREAM_UNIT_ROLE: 'build' }

test('inside a runner unit, session.start registers unit_done', async ($, on) => {
  const seen = world(on, UNIT)
  await $.session.start({ cwd: 'repo' } as any)
  expect(seen.registered).toEqual(['unit_done'])
})

test('outside a runner unit, the mod registers nothing', async ($, on) => {
  const seen = world(on, {})
  await $.session.start({ cwd: 'repo' } as any)
  expect(seen.registered).toEqual([])
})

test('unit_done writes the result file with the -p runner fields, then queues /exit', async ($, on) => {
  const seen = world(on, UNIT)
  await $.session.start({ cwd: 'repo' } as any)
  const r: any = await $.tool.call({ tool: 'mcp__stream-unit__unit_done', outcome: 'built', note: 'G3.T137 built' } as any)
  expect(r.deny).toBeUndefined()
  expect(seen.writes.length).toBe(1)
  // The test harness resolves a relative path against the mod folder, so compare the tail.
  expect(seen.writes[0]!.path.endsWith(OUT)).toBe(true)
  const rec = JSON.parse(seen.writes[0]!.text)
  expect(rec.outcome).toBe('built')
  expect(rec.result).toBe('G3.T137 built')
  expect(rec.is_error).toBe(false)
  expect(rec.total_cost_usd).toBe(0.42)
  expect(rec.session).toBe('build-1')
  expect(rec.role).toBe('build')
  expect(rec.num_turns).toBe(1)
  expect(seen.commands).toEqual([])
  await $.turn.complete(turn('verifier', 'agent-1'))
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(seen.commands).toEqual([])
  await $.turn.complete(turn('done'))
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(seen.commands).toEqual(['exit'])
  await $.turn.complete(turn('again'))
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(seen.commands).toEqual(['exit'])
})

test('a failed outcome is an error result', async ($, on) => {
  const seen = world(on, UNIT)
  await $.session.start({ cwd: 'repo' } as any)
  await $.tool.call({ tool: 'mcp__stream-unit__unit_done', outcome: 'failed', note: 'grader lock' } as any)
  expect(JSON.parse(seen.writes[0]!.text).is_error).toBe(true)
})

test('an unknown outcome is refused and nothing is written', async ($, on) => {
  const seen = world(on, UNIT)
  await $.session.start({ cwd: 'repo' } as any)
  const r: any = await $.tool.call({ tool: 'mcp__stream-unit__unit_done', outcome: 'finished' } as any)
  expect(String(r.deny ?? r.text)).toMatch(/outcome must be one of/)
  expect(seen.writes.length).toBe(0)
  await $.turn.complete(turn('x'))
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(seen.commands).toEqual([])
})

test('a second unit_done is refused', async ($, on) => {
  const seen = world(on, UNIT)
  await $.session.start({ cwd: 'repo' } as any)
  await $.tool.call({ tool: 'mcp__stream-unit__unit_done', outcome: 'idle' } as any)
  const r: any = await $.tool.call({ tool: 'mcp__stream-unit__unit_done', outcome: 'idle' } as any)
  expect(String(r.deny ?? r.text)).toMatch(/already called/)
  expect(seen.writes.length).toBe(1)
})

// Waiting on the owner: a prompted call writes <out>.waiting.json { waiting: true }, its resolution { waiting: false }.
const waitWorld = (on: any, vars: Record<string, string>, decision: string) => {
  const seen = world(on, vars)
  const notices: string[] = []
  on('tool.check', () => ({ decision, reason: 'destructive-path-guard: confirm' }))
  on('tool.call', () => ({ result: 'ran' }))
  on('ui.notice', ($: any, e: any) => { notices.push(String(e.text ?? e[1] ?? '')); return { value: undefined } })
  return { seen, notices }
}
const waiting = (seen: any) => seen.writes.filter((w: any) => w.path.endsWith('.waiting.json')).map((w: any) => JSON.parse(w.text))

test('an ask verdict marks the unit waiting, and its resolution clears it', async ($, on) => {
  const { seen } = waitWorld(on, { ...UNIT, STREAM_UNIT_TAB: 'Builder 3' }, 'ask')
  await $.session.start({ cwd: 'repo' } as any)
  const r: any = await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf x' }, tool_use_id: 'tu-1' } as any)
  expect(r.decision).toBe('ask')
  let w = waiting(seen)
  expect(w.length).toBe(1)
  expect(w[0].waiting).toBe(true)
  expect(w[0].tool).toBe('Bash')
  expect(seen.writes[0].path.endsWith(OUT + '.waiting.json')).toBe(true)
  await $.tool.call({ tool: 'Bash', command: 'rm -rf x', tool_use_id: 'tu-1' } as any)
  w = waiting(seen)
  expect(w.length).toBe(2)
  expect(w[1].waiting).toBe(false)
})

test('an allow verdict writes nothing', async ($, on) => {
  const { seen } = waitWorld(on, UNIT, 'allow')
  await $.session.start({ cwd: 'repo' } as any)
  await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'tu-2' } as any)
  await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 'tu-2' } as any)
  expect(waiting(seen).length).toBe(0)
})

test('outside a runner unit an ask writes nothing', async ($, on) => {
  const { seen } = waitWorld(on, {}, 'ask')
  await $.session.start({ cwd: 'repo' } as any)
  await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf x' }, tool_use_id: 'tu-3' } as any)
  expect(waiting(seen).length).toBe(0)
})

test('two open prompts stay waiting until both resolve', async ($, on) => {
  const { seen } = waitWorld(on, UNIT, 'ask')
  await $.session.start({ cwd: 'repo' } as any)
  await $.tool.check({ tool: 'Bash', input: {}, tool_use_id: 'a' } as any)
  await $.tool.check({ tool: 'Bash', input: {}, tool_use_id: 'b' } as any)
  await $.tool.call({ tool: 'Bash', command: 'x', tool_use_id: 'a' } as any)
  expect(waiting(seen).at(-1).waiting).toBe(true)
  await $.tool.call({ tool: 'Bash', command: 'x', tool_use_id: 'b' } as any)
  expect(waiting(seen).at(-1).waiting).toBe(false)
})

// Kill by name: inside a unit the mod refuses it before core is asked, so it never reaches the owner as a prompt.
const KILLS = [
  'pkill -f Invoke-Grader.ps1',
  'pkill -f python',
  'sudo killall dotnet',
  'pgrep -f vstest | xargs kill -9',
  'kill $(pgrep node)',
  'taskkill /F /IM dotnet.exe',
  'taskkill /FI "IMAGENAME eq testhost.exe" /F',
  'Stop-Process -Name dotnet -Force',
  'Get-Process testhost | Stop-Process -Force',
  "Get-Process | Where-Object { $_.CommandLine -match 'Invoke-Grader' } | Stop-Process",
  'wmic process where name="python.exe" delete',
  "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Invoke-CimMethod -MethodName Terminate",
]
const PID_KILLS = [
  'Stop-Process -Id 4242 -Force',
  'taskkill /PID 4242 /T /F',
  'kill -9 4242',
  'Get-Process -Id $p.Id | Stop-Process',
  'rg "pkill" skills',
  'dotnet test --filter Kill',
]

test('inside a unit, a kill by name is refused without asking, on Bash and PowerShell', async ($, on) => {
  const { seen } = waitWorld(on, UNIT, 'ask')
  await $.session.start({ cwd: 'repo' } as any)
  for (const command of KILLS) {
    for (const tool of ['Bash', 'PowerShell']) {
      const r: any = await $.tool.check({ tool, input: { command }, tool_use_id: `k-${tool}-${command}` } as any)
      expect([command, r.decision]).toEqual([command, 'deny'])
      expect(String(r.reason)).toMatch(/by the PID you recorded/)
    }
  }
  expect(waiting(seen).length).toBe(0)
})

test('inside a unit, a kill by PID and an ordinary command are left to core', async ($, on) => {
  waitWorld(on, UNIT, 'allow')
  await $.session.start({ cwd: 'repo' } as any)
  for (const command of PID_KILLS) {
    const r: any = await $.tool.check({ tool: 'PowerShell', input: { command }, tool_use_id: `p-${command}` } as any)
    expect([command, r.decision]).toEqual([command, 'allow'])
  }
})

test('outside a runner unit, a kill by name is left to core', async ($, on) => {
  waitWorld(on, {}, 'ask')
  await $.session.start({ cwd: 'repo' } as any)
  const r: any = await $.tool.check({ tool: 'Bash', input: { command: 'pkill -f python' }, tool_use_id: 'o-1' } as any)
  expect(r.decision).toBe('ask')
})