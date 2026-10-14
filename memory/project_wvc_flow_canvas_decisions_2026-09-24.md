---
name: project-wvc-flow-canvas-decisions
description: Gene's 9/24 first-round decisions for a visual Canvas view of workload flows beside the Steps view (engine spike, scope, gate)
metadata:
  type: project
---
Canvas view = SECOND view of a workload flow; the sequential Steps view stays as shipped (Gene 2026-09-24).
Mockup v1: https://claude.ai/artifact/TGnSdLCyA1szKKJtahnFZA (scratch only, not yet in speedy\ui).

Decisions: Elsa and paid libraries (Syncfusion) OUT. Engine = SPIKE plain Blazor components vs Z.Blazor.Diagrams
(~2 days, same case: parallel for-each holding an if, drag to slot, round trip to flow data, drag latency measured
under InteractiveServer); output a measured study note in the WVC corpus, Gene picks. Full editing; automatic layout
only (no saved positions, flow hash unaffected); Steps|Canvas toggle remembered per user, selection in query string;
requirements = new FEAT-WVC-CANVAS-001 in Workflow-vs-Code, depends on FEAT-WVC-FLOW-001 (FLOW-001 untouched);
full keyboard parity; big flows = collapse + map, no cap, render-time criterion at the size limit; desktop only (no
touch); run overlay = later feature; v1 has undo/redo, copy/paste subtree, multi-select, collapse/expand all;
save-check problems on node + linked list, check runs live on every edit, Save disabled while problems exist;
one shared draft across both views; gate = mockups (states set) in speedy\ui + spike note approved, THEN write FEAT.

**Why:** the flow is a tree (one parent, no cycles), so a free-form graph engine is mostly switched off; Speedy
pages are InteractiveServer, which makes per-mousemove drag a lag risk (unmeasured).
**How to apply:** don't reopen Elsa for the canvas; don't write FEAT-WVC-CANVAS-001 before the gate. Related:
[[project-workflow-vs-code-corpus]].

**Review-loop fix (Gene 9/24):** ONE combined clean Claude review of FLOW-001 + both ADRs + CANVAS-001; the fixes
after it are checked by GENE from review/FIX-DIFF-FINAL.md (Gene is a valid independent reviewer, RequirementDesign
§9), not by another Claude round. Before that review: an executable fixture harness, no self-invented decisions (every
choice goes to the picker), an author pre-flight subagent recorded in SELF-REVIEW. Goal file:
Workflow-vs-Code/GOAL-CANVAS-READY.md (gates G1-G4).

**G1 answers 9/24 (all 16 in review/TRIAGE-ROUND4-2026-09-24.md):** lone bool condition allowed (unset=false); NEW `fail` node;
bound exhaustion (1,048,576-char intermediate strings in evaluator, 64 MiB retained per VU); composite outside-call time
stated unrecorded + pass-record gains start/end; ordinal StartsWith/EndsWith/IndexOf; allow ?: ??, refuse ?.; decimal keeps
scale; {{row}} refused; poll timeout fails at once; MET-002 = 1.2 us signed; export obligation NOW (flow rides inside the
workload bundle, same-hash import reuses existing); shared draft model owned by FEAT-WVC-CANVAS-001; ASCII names; no
Random/Pick in poll-until; nested JSON keeps number spelling; SQL NULL/no rows = absent.

## Item-4 drafting answers (Gene 2026-09-24, picker)
- 18 fail node reason = literal text (no tokens); pass fails at fail node's path, reason = that text.
- 19 64 MiB retained = 2 bytes per text char (strings, list items, row names+values); numbers/bools/datetimes not counted.
- 20 bundle import: carried hash != computed hash -> refuse whole import naming flow, write nothing.
- 21 sql-rows with zero rows = EMPTY LIST (only scalar "no rows" = absent).
- 22 run param read by flow but not supplied -> refused at workload save + run start, naming param + node-path; flow save treats unknown token root / expression name as run parameter.
- Import naming reuses speedmerchants ImportName.Mint (c7890cb): name, name-imported, name-imported-2..., case-insensitive.
- 23 string literal escapes: only what DynamicExpresso 2.19.5 parses (\' \" \\ \0 \a \b \f \n \r \t \v); other chars written as themselves; save refuses \u \U \x (verified by probe).
- G2 2026-09-24: Gene APPROVED the eight canvas mockup states (canvas.proposed.css as a design-system addition) and PICKED PLAIN BLAZOR over Z.Blazor.Diagrams (spike: collapse/expand ~2x faster, 145 vs 260 LOC, 0 vs 89 idle frames; minimap must be built).
- Canvas FEAT answers 2026-09-24 (picker): C1 reference size 200 nodes; C2 thresholds FIXED NOW at 200 nodes loopback: drag feedback p95 <= 16 ms, collapse-all/expand-all median <= 50 ms, first full render <= 500 ms; C3 undo 100 steps, kept across save + view switch, cleared on leaving page or JSON reload; C4 copy/paste via SYSTEM clipboard as flow JSON; C5 multi-select siblings only; C6 map auto when flow overflows stage, hideable, remembered per user; C7 zoom 50%-200% in 25% steps (Fit button from mockup).
- Canvas self-review answers 2026-09-24: C8 clipboard/node JSON = REQ-WVC-FLOW-023 canonical node form (no new storage format); C9 paste with no focused node appends to end of root; C10 Duplicate puts copies right after the selection and selects them; C11 Fit = largest 25% step <= 100% that fits, else 50%. Removed my invented Ctrl+minus/plus zoom keys; Tab from last lane leaves the stage (no keyboard trap).
- Pre-flight answers 2026-09-24 (picker, 13): P1 node TITLE = optional FLOW node-shapes field on every kind, HASHED; P6 undo/redo raise own change event (live check, not history), dirty flag = draft hash != last saved hash; P7 inspector text commits on Enter/Apply, Escape reverts, pickers on pick, dialog save = 1 op; P18 import runs FLOW-012 save check, any failure refuses whole import; P13 node JSON keys pinned in FLOW REQ-023; P4 Enter on palette kind = keyboard placement (arrows walk slots depth-first, then before else), Ctrl+D duplicate, Space toggles sibling; P5 choice lanes in inspector list (add/remove, weight, last lane not removable), lane not a stage target; P17 check after collect + item binding too, 8 B per list item/row entry + 2 B/char; P19 remembered = per user account server-side, node= percent-encoded, focused node named, unknown node ignored; P10 emptying move allowed, live check flags; P20 list "run parameters read" beside problems (never blocks); P23 dup/paste off-sequence refused w/ message, Ctrl+click/Space toggles; P34 retrying status step = future step-type feature.
- P33 answers 2026-09-24: null row field / list item in a token = empty text; parallel-for-each failure = node's own path, reason 'branch item-index N failed at <inner path>: <reason>' (lowest N); captures store one by one in declared order.
- 9/24 later: P19 REVERSED to browser localStorage (standing rule [[feedback-speedy-view-memory-localstorage]] wins; address wins); JSON apply compared against last loaded/saved (no new baseline); move mode (M) starts on the gap just before the node.
