# Inbox: {{skill}}

Handles: {{handles}}.
Anyone may write here: the owner, any stream session, or this conversation. Only {{skill}} acts on it.

## Contract (append-only; never edit or delete a line)

One line per event. A new item:
`- <id> | <utc> | <from> | open | request|bug | <task id or -> | <ask, one sentence> | <evidence path or ->`
Every later event on it, by any session:
`- <id> | <utc> | <by> | taken|done|declined|forwarded | <note: result, reason, or the inbox it went to>`

- Use the kit scripts (stream-kit\scripts), which lock the file, so two sessions can never take the same item:
  `Send-InboxItem.ps1` to file, `Get-InboxItems.ps1 -Open` to list, `Set-InboxItem.ps1` for taken, done, declined
  and forwarded. `Set-InboxItem -Status taken` refuses an item whose latest line is not `open` (or a `taken` past
  the role's limit) and exits 8.
- id = `IN-<yyyyMMddHHmmss>-<4 hex>`, made by the sender. Longer detail goes in an evidence file under
  `.streams\inbox\evidence\`, never in a session scratchpad (it vanishes with the session).
- The item's status is its last line. `open` needs an owner. `taken` older than the role's limit counts as open again.
  `forwarded` is owned by the target inbox, where the same id appears as a new `open` line.
- The receiving skill reads this file at the start of every cycle, takes the oldest open item it can act on within its
  own write rules, appends `taken`, does it, then appends `done` or `declined` with the reason. An item outside its
  rules is `forwarded` to the right inbox.
- **Guidance for the future holder of a named row goes in THAT ROW, never here.** The inbox delivers one way: a role
  takes an open item. `Claim-Task.ps1` picks by group and chain order, so no author or builder can choose to work a
  named task. An item that says "for whoever authors G6.T109", or that waits on a condition only that row's holder can
  meet, has no reachable taker: it stays open forever and flags on every status tick. Put it where it travels with the
  work instead - `Update-Task.ps1 -Task <id> -Note '<the guidance>'` - and it reaches whoever claims the row.
  `Send-InboxItem.ps1` REFUSES such an item to `stream-author` or `stream-build` (exit 9) and prints the `-Note`
  command to use; `-Force` files it anyway. Reserve this inbox for work a role can take now.

## Items

