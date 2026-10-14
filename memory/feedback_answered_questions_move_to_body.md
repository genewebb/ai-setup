---
name: feedback_answered_questions_move_to_body
description: "Gene 2026-09-13 18:46: in a review page/doc, once a question is answered fold the answer into the main body and DELETE the question; the questions section holds only OPEN questions, no history"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9eca9880-07a9-4ace-86c9-8f76baf009ce
  modified: 2026-09-13T22:47:11.879Z
---

"Once I answer questions move them to the main body and remove them we dont need the history this should only include open questions."

**Why:** the review page is a working document, not a transcript; a reader should see the current design and what is still undecided, nothing else. History lives in the markdown addenda / memory, not on the page.

**How to apply:** on every review artifact (HTML page, plan doc): answered Q → its effect lands in the relevant capability row / decision line (cite "Gene <time>" not "Qn"), the Q box is removed, remaining Q numbers keep their IDs (no renumbering), the section is titled "Open questions". Related: [[project_dial_workload_builder_design_2026-09-13]], [[feedback_vnext_schedule_format]].
