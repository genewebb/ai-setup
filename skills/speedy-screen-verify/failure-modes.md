# Failure-mode log: speedy-screen-verify

Framework block B7a item 2. One line per observed agent failure: date, what happened, evidence, and the skill line or
check that answers it. Scenarios for the skill's evaluation (B7a item 4) are drawn from here.

Created 2026-11-23 (owner decision, chat, "3. Need to add and update this"). The seed rows below are the framework's
own example failures; they are not yet observed on Speedy and say so. Replace or confirm them with observed rows.

| Date | Failure | Evidence | Answered by |
|---|---|---|---|
| seed | Declared a screen change done without looking at the screen | framework B7a item 2 example, not yet observed here | Skill rule "not done until you have opened the screen"; report block "saw" |
| seed | Did not run the test or the command | framework B7a item 2 example, not yet observed here | Skill step 3 and the stdout line in the report |
| seed | Guessed a feature or selector instead of reading the map or code | framework B7a item 2 example, not yet observed here | Skill step 2 "prefer feature"; the command refuses an unknown feature |
| seed | Reported a harness fault (exit 3) as a pass or as a page defect | NFR-SCREENDRIVE-001 local decision five-exit-codes rationale, not yet observed here | Skill step 4 table |
