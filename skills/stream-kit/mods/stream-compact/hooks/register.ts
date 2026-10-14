// stream-compact: keeps a long-running stream-kit session (Planner, Integrator, Kit, Coordinator, Status) small.
//
// Those five roles run as one interactive session per tab under /loop, so the owner can work with them, instead of a
// fresh session per tick. Without a limit each tick re-reads an ever larger context. This mod compacts the session
// after a turn once the context fill reaches STREAM_COMPACT_PCT percent (the profile's addStreams sets it; owner ruling
// 2026-10-04: 35). With STREAM_COMPACT_PCT unset (a person's own session) the mod does nothing.
//
// The compaction runs after the turn has completed, not awaited inside the hook: $.session.compact rejects while a turn
// runs. A rejected or vetoed compaction is retried after the next turn.
import type { Register } from 'claude-code'

const INSTRUCTIONS = [
  'This is a long-running stream-kit session under /loop. Keep: the /loop command and its interval, the repo path,',
  'this session id and role, the inbox items and tasks being worked and their state, decisions made and why,',
  'and everything the owner asked or said. Drop tool output that can be re-read from .streams\\.',
].join(' ')

export const register: Register = (on) => {
  let compacting = false

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    // A subagent's turn (a verifier, a scout) is not the session's.
    if (e.agentId || compacting) return r
    const raw = await $.env.get('STREAM_COMPACT_PCT')
    const limit = raw ? Number(raw) : NaN
    if (!(limit > 0 && limit <= 100)) return r
    const { context } = await $.session.usage()
    const percent = context.percent ?? 0
    if (percent < limit) return r
    compacting = true
    void (async () => {
      try {
        $.ui.toast(`stream-compact: context ${percent}% >= ${limit}%, compacting`)
        const res = await $.session.compact({ instructions: INSTRUCTIONS })
        if (res && 'skip' in res && res.skip) $.ui.toast(`stream-compact: compaction skipped (${res.skip}); retrying after the next turn`)
        else $.ui.toast('stream-compact: compacted')
      } catch (err) {
        // A turn started first (or the engine refused); the next turn.complete tries again.
        $.ui.toast(`stream-compact: compaction did not run (${err instanceof Error ? err.message : String(err)}); retrying after the next turn`)
      } finally {
        compacting = false
      }
    })()
    return r
  })
}
