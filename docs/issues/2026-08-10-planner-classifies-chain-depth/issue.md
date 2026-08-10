# The planner classifies each increment's chain depth

## Problem

Every increment costs four agents. The chain — researcher, test-author,
implementer, reviewer — runs once per increment whatever the increment is, so
an increment that is a stale reference in a document, a wrong number in prose
or a rename the codemap already names in full is researched, planned, tested
and built by the same machinery as one that has something to decide. The
research and the test-authoring produce nothing a reader of the criteria did
not already have, and the run pays two agents and their turns for it.

The workflow already knows the cheap path and already runs it. A correction
round whose findings are all `direct` skips the researcher and the test-author
and is worked by the implementer alone, off the findings and the checks the
round before closed (`workflows/agile-loop.js`, the `directFix` branch). What is
missing is the entry: that path opens only after a review has already filed
findings, so the first round of every increment is expensive by construction,
and an increment that was never going to need a plan pays for one anyway.

The role that could decide this earlier already exists and already has what it
needs. The planner cuts the increments, writes each one's criteria and builds
the codemap that names the files the issue changes — it is the one role that
holds the shape of an increment before any agent works it. It says what; how
deep the chain has to go to deliver that what is the same kind of call.

## Acceptance criteria

- [ ] The planner returns a chain depth for every increment it cuts, recorded
      in `backlog.json` beside that increment: `full` or `direct`. `full` is
      the default and the answer whenever the planner hesitates.
- [ ] The planner's page states the bar for `direct` and owns it alone: an
      increment is `direct` only when its criteria and the codemap already name
      the file, the place and the right result, so nothing is left to decide,
      and when nothing in it could be verified by a test that does not already
      exist. Anything the planner is unsure of is `full`.
- [ ] Round 0 of a `direct` increment runs without the researcher and without
      the test-author: the implementer is dispatched first, and the reviewer
      follows it as it does in every other round.
- [ ] The implementer's page states this second work order: where its prompt
      names no researcher step to read, the increment's criteria and the
      codemap are its whole brief, and it writes no tests.
- [ ] The commands a `direct` increment is judged by are the `checks` of the
      most recent researcher step recorded in the run; where the run holds
      none, the list is empty, and an empty list means the review is a reading
      — the rule that already holds everywhere else.
- [ ] A `direct` increment whose review files a finding leaves the direct path
      for the rest of its attempt: the correction round runs the full chain, so
      a misclassification costs one implementer and one reviewer, and no
      unplanned change reaches the pull request.
- [ ] An increment the planner hands back after a failed attempt is `full` on
      its next attempt, whatever it was classified as before.
- [ ] The planner classifies again on every re-cut, so an increment still open
      is reclassified against what the increment before it turned up.
- [ ] The run says which increments took which path while it works and after it
      ends: the line the loop logs when a `direct` round starts names the path,
      and the result's entry for a worked increment carries its depth.

## Non-goals

- Whether a `full` increment needs tests stays the researcher's call, returned
  as `needsTests`. The planner decides how deep the chain goes, never what is
  tested inside it.
- The reviewer is unchanged. It reads nothing any agent produced in either
  path, and a `direct` increment is reviewed exactly as any other.
- No new backstop. `MAX_INCREMENTS`, `MAX_ATTEMPTS`, `MAX_BLOCKED` and
  `MAX_CORRECTIONS` keep their meaning and their values.

## Decisions

- The commands a `direct` increment is judged by are carried over from the last
  researcher step of the run rather than named by the planner. The planner
  searches the codebase for the codemap but does not read it in depth, and
  naming a runner it has not seen is a guess; carrying the list over mirrors
  what the direct-fix correction round already does.
