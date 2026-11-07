---
name: feedback-red-is-red-declared-inputs
description: "Gene rejects status that is red but \"fine\" (or green but can't run): fix the signal, not the explanation; CrewChief building blocks declare caller values in 'inputs'"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T00:21:57.194Z
---

Gene 2026-11-06, on 15 Connect building blocks showing red because they use values only their parent passes: "I dont
like that it is clugy and misleading, suggestions red is red". Explaining a red badge away as a "false alarm" is not
acceptable; green for something that cannot run alone is the same complaint.

**Why:** an operator scanning the Workloads page must be able to trust red = a run will fail.

**How to apply:** when a check reports a non-problem, change the model so the check is right (here: CrewChief
`inputs` on a workload, new `FromCaller` state, parent checked for supplying them), never add defaults that change run
behaviour (child globals beat parent globals) and never just document the noise. Pack lint now refuses undeclared
caller values (rule 9 in 60_PacksOverview). Details: [[crewchief-nested-workloads]], [[feedback-pack-own-source-database]].
