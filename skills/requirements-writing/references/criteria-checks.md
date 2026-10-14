# Criteria checks: run these before a criterion is handed to a planner

Each check exists because a criterion without it sent an implementation the wrong way, or could not fail. Run them
while drafting and again before hand-off. They are human checks; the validator covers none of them.

The rules themselves live in `RequirementDesign.md`: checks 1 to 7 in section 6 ("Checking a criterion against its fixture
and its requirement"), checks 8 to 10 in section 5 ("Values reused as identifiers, input shape, and carriers"). This
page is the working list; where the two differ, the standard governs.

## Against the fixture

1. **Fixture figures carry their source.** Every count or value taken from a fixture is either derived at run time
   by the test (count the attributes, do not hard-code the count) or written beside the command that produced it.
   A number typed from memory reads as measured and is wrong often enough to cost an implementation round.
2. **Absence searches are probed.** A criterion that asserts a string does NOT appear in some text needs a probe
   of the fixture first: list every place the fixture legitimately carries that string, and name each exclusion
   inside the criterion. "Entity name appears only inside its token" fails when 50 attributes share the entity's
   spelling.
3. **Name collisions are profiled.** While profiling a fixture, ask whether two kinds of thing share a spelling
   (entity and attribute, column and global, file and entity). A collision changes what a text search or a
   name lookup can prove.
4. **Criteria sharing a fixture are checked pairwise.** Two criteria over the same fixture must both be able to
   pass. Read each pair once for a direct contradiction (one demands a literal the other forbids).

## Against the requirement

5. **No wider net than the statement.** When the requirement enumerates sites, cases or fields, the criterion
   tests those plus named exclusions. "Anywhere in the output" is a wider obligation than the requirement made.
6. **Expected strings come from the producer.** A string a criterion expects (an error text, a token spelling, a
   status) is copied from the component that produces it, or the criterion states the obligation ("names the
   missing secret and nothing else") and leaves the spelling to the test. A friendly label is not what a tool
   reports.
7. **The rule is observable.** Ask how a test reaches the behaviour through the surface the design offers. If
   every path gives the same answer whatever the implementation does (all parts share one value, so "A wins on
   conflict" never shows), name the seam the test uses or drop the rule.

## Against the input and the sinks

8. **One value, several grammars.** When a value is reused as an identifier in more than one grammar (token key,
   dictionary key, URL segment, SQL identifier, file name), the requirement states the allowed grammar once:
   forbidden characters, reserved names, and whether letter case distinguishes two values.
9. **Input-shape assumptions live in the term.** An ordering or traversal rule that only works for a tree, a DAG
   or unique keys says so in the term that defines the input, and the requirement says what happens when the
   input breaks the assumption (refuse, and with what message). Cover every reference kind the input has, not
   only the first one noticed.
10. **Displayed and numeric values are pinned.** "As the tool displays it" names the culture or format. A numeric
    rule names the carrier and the precision of the sink (decimal to the target attribute's scale, not "a
    number"), and says whether an over-precise input is rounded or refused.

## What made criteria easy to implement (keep doing)

- A counterexample with disposition CAUGHT maps one-to-one onto a test; write the case so the test is obvious.
- Facts from a probe (accepted formats, what a rejected value leaves behind) go into the statement verbatim;
  they reach the code unchanged.
- A fixture stated per criterion lets every test provision itself; no shared set-up is argued about later.
