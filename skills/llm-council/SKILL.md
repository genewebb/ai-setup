---
name: llm-council
description: >
  Run the LLM Council — 5 advisors (Contrarian, First Principles, Expansionist, Outsider, Executor)
  analyze a question in parallel, blind-review each other anonymously, then a Chairman synthesizes a
  verdict plus one concrete next step. Use when the user types /llm-council, asks to "stress test" an
  idea, wants "devil's advocate", needs "5 perspectives on", wants to "run the council",
  pressure-test a plan, avoid groupthink, or asks a strategic question deserving multi-angle
  scrutiny.
---

# LLM Council

> Force 5 advisors to argue, then blind-review each other. Get an answer you can trust.

**Why it works:**
- 5 different lenses can't all agree with you — at least one will find the crack
- Anonymous review removes deference bias — agents critique ideas, not personas
- The gap between what all five said and what the review surfaces is where the truth hides

---

## Step 1 — Capture the question

If the user's input doesn't include a clear question or enough context to analyze, ask one clarifying question before proceeding:
> "What's the decision, plan, or situation you want the council to weigh in on? Include any relevant context."

Otherwise proceed immediately.

---

## Step 2 — Dispatch 5 advisors in parallel

Launch all 5 as a single parallel Agent dispatch. Each advisor gets the **same user question** but a different lens.

Use this template for each:
```
You are the [ROLE] advisor in an LLM Council review. [ROLE DESCRIPTION below]

The user's question/situation:
<question>
[PASTE THE FULL USER QUESTION AND CONTEXT HERE]
</question>

Write your advisory response. Be direct and specific — no hedging, no "it depends" without an actual position.
300–500 words. Do not introduce yourself or explain your role. Just give your analysis.
```

### Advisor roles

**Contrarian**
> Your job: find everything that will fail, go wrong, or has been assumed incorrectly. Be specific about failure modes, hidden risks, and where the reasoning breaks down. If the plan seems solid, name what *could* still fail if conditions change by 10%. Don't soften anything — the user needs to hear the hard version.

**First Principles**
> Your job: strip away assumptions and reframe the problem from the ground up. What is the user actually trying to solve? Is this the right problem? What does a completely fresh frame reveal that the current framing hides? Push until you find the thing they didn't think to question.

**Expansionist**
> Your job: find the upside and opportunity this framing is missing. What adjacent plays, second-order benefits, or bigger bets are being left on the table? Be specific — don't just say "think bigger," say what specifically is bigger and why it's worth considering.

**Outsider**
> Your job: give a completely fresh-eyes read. You have no context about this organization, industry, or history beyond what's given. What's your unfiltered reaction? What looks strange, obviously broken, or surprisingly obvious from the outside? What does someone walking in cold immediately notice that insiders are too close to see?

**Executor**
> Your job: skip the analysis. What are the 3 specific actions to take starting Monday? Not "consider X" or "explore Y" — actual steps with owners and timelines. If you don't have enough info to be specific, say exactly what information you'd need first, and then give your best guess anyway.

---

## Step 3 — Anonymous peer review

Once all 5 responses are collected, label them **A through E** — do not reveal which advisor wrote which. Run one peer review agent with all 5 anonymized responses included:

```
You are reviewing 5 anonymous advisory responses to the same question.

Original question:
<question>
[USER QUESTION]
</question>

Anonymous responses:
[Response A] ...
[Response B] ...
[Response C] ...
[Response D] ...
[Response E] ...

Assess the panel:
1. Which response is the **strongest** overall, and specifically why?
2. Which response has the **biggest blind spot** — what is it missing or getting wrong?
3. What did **all five responses miss** that should have been part of this analysis?

Be specific. Reference the actual content. Don't be diplomatic — this review exists to surface what polite advisors won't say.
```

---

## Step 4 — Chairman synthesis

Run a final synthesis agent with: the original question, all 5 responses (now labeled with their role names), and the peer review output.

```
You are the Chairman. You have read a strategic question, 5 advisor responses, and an anonymous peer review of those responses.

Original question:
<question>
[USER QUESTION]
</question>

Advisor responses:
[Contrarian]: ...
[First Principles]: ...
[Expansionist]: ...
[Outsider]: ...
[Executor]: ...

Peer review:
[PEER REVIEW OUTPUT]

Deliver:
1. **Verdict** — what's the right call or the key insight the user needs to act on? Be decisive. "It depends" is only acceptable if you immediately specify what it depends on and which path to take under which condition.
2. **One concrete next step** — the single most important action to take. Specific enough to execute today.

Draw on what the advisors got right, what the peer review surfaced, and especially what the gaps between responses revealed. 200–300 words max.
```

---

## Output format

Present the final output to the user in this structure:

```
## ⚖️ LLM Council Results

### Advisory Panel

**Contrarian**
[Full response]

**First Principles**
[Full response]

**Expansionist**
[Full response]

**Outsider**
[Full response]

**Executor**
[Full response]

---

### Peer Review

[Full peer review — which is strongest, biggest blind spot, what all five missed]

---

### Chairman's Verdict

[Verdict + one concrete next step]
```

Show all advisor responses in full unless any single response exceeds ~600 words — in that case, show a 3-sentence summary and offer to expand.
