import { test, expect, mock } from 'claude-code/testing'

// Answers every call the mod makes beneath it, recording each compaction it asked for.
const world = (on: any, vars: Record<string, string>, percent: number | undefined, compactThrows = false) => {
  const seen = { compacts: [] as any[] }
  mock.env(on, vars)
  on('session.usage', () => ({ value: { startedAt: 1, context: { window: 1000000, ...(percent === undefined ? {} : { percent }) }, rateLimits: [], cost: { usd: 0 } } }))
  on('session.compact', ($: any, e: any) => {
    seen.compacts.push(e)
    if (compactThrows) throw new Error('a turn is running')
    return { messages: [] }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('turn.complete', ($: any, e: any) => ({ text: e.answer }))
  return seen
}

const turn = (answer: string, agentId?: string) => ({ reason: 'answer', answer, durationMs: 1, isAborted: false, turnId: 't-' + answer, ...(agentId ? { agentId } : {}) }) as any
const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

test('at or above the threshold, a completed turn compacts with the stream instructions', async ($, on) => {
  const seen = world(on, { STREAM_COMPACT_PCT: '35' }, 35)
  await $.turn.complete(turn('tick'))
  await settle()
  expect(seen.compacts.length).toBe(1)
  expect(String(seen.compacts[0].instructions)).toMatch(/\/loop command/)
})

test('below the threshold nothing is compacted', async ($, on) => {
  const seen = world(on, { STREAM_COMPACT_PCT: '35' }, 34)
  await $.turn.complete(turn('tick'))
  await settle()
  expect(seen.compacts.length).toBe(0)
})

test('without STREAM_COMPACT_PCT (a person\'s own session) the mod does nothing', async ($, on) => {
  const seen = world(on, {}, 90)
  await $.turn.complete(turn('tick'))
  await settle()
  expect(seen.compacts.length).toBe(0)
})

test('a subagent turn never compacts', async ($, on) => {
  const seen = world(on, { STREAM_COMPACT_PCT: '35' }, 80)
  await $.turn.complete(turn('verifier', 'agent-1'))
  await settle()
  expect(seen.compacts.length).toBe(0)
})

test('no figure yet (fresh or just compacted) does not compact', async ($, on) => {
  const seen = world(on, { STREAM_COMPACT_PCT: '35' }, undefined)
  await $.turn.complete(turn('tick'))
  await settle()
  expect(seen.compacts.length).toBe(0)
})

test('a rejected compaction is retried after the next turn', async ($, on) => {
  const seen = world(on, { STREAM_COMPACT_PCT: '35' }, 60, true)
  await $.turn.complete(turn('one'))
  await settle()
  await $.turn.complete(turn('two'))
  await settle()
  expect(seen.compacts.length).toBe(2)
})
