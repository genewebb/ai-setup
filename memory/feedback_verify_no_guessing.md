---
name: feedback_verify_no_guessing
description: "User demands verified facts, never guesses/inferences presented as conclusions"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ebe29a62-6f20-48b6-81f5-77ccc9168897
  modified: 2026-07-27T14:02:16.754Z
---

When diagnosing, every statement must be verified against ground truth before being presented. Do not present inferences ("likely redundant", "looks misplaced", "should be") as facts or recommendations. If something is unverified, either verify it or label it explicitly as unverified.

**Why:** User caught repeated guessing — e.g. assuming the test server's Profisee model was uniquely stale, when pulling local vs remote showed them byte-identical; and presenting metric-column "redundant/misplaced" verdicts without checking the actual model attributes. Guessing wastes their time and erodes trust.

**How to apply:** For metric/model work, query the actual model (e.g. [[reference_scenariomgt_db]], speedMcpLocal/Remote `get_attributes_by_entity`) and cross-check EVERY declared `[MetricColumn]` against the entity's real attribute list before claiming a gap or a fix. Compare environments with real queries, not assumptions. Present a fact matrix, not a narrative. Links: [[project_perfdashboard]].

**Extension — the gate applies to MY OWN subagent instructions (learned 2026-07-27, skill-audit apply pass):** when dispatching apply/fix agents, the claims written INTO the prompt are themselves unverified and must be gated. In that session I told an agent `ConnectRestClient` "builds paths via the shared PathAndQueryBuilder", extrapolating from the house rule in [[feedback_rest_reuse_path_query_utility]]; live code says the opposite in a header comment (*"No shared mutable PathAndQueryBuilder — paths are built per-call"*). The agent inverted it because its prompt said to verify everything. Always instruct subagents: "line numbers in this prompt are STALE HINTS, re-derive them; drop any claim of mine that fails verification and report it." Two of that sweep's 71 backlog findings were also outright false — an unverified finding is a hypothesis, not a work item.

**Defect classes that specifically require name-based grep** (all found 2026-07-27): **zero-hit identifiers** (a doc naming a symbol that does not exist repo-wide is worse than a stale line number — a reader greps, finds nothing, and concludes the feature is absent); **fabricated surface** (invented API/grammar that looks plausible); **rotting numbers** (tallies and versions — describe the mechanism and tell the reader to re-read the file instead of quoting a count); **stale comments outliving code** (XML docs and `//` comments are unverified prose — trust the implementation).
