# A correction round judges the fix, not the increment again

## Problem

A correction round's reviewer is dispatched exactly like the first round's: it
judges the whole increment diff afresh. Nothing ties its verdict to the
findings the round was run to fix, so a round can raise findings no earlier
round named, and the loop has no reason to converge inside
`MAX_CORRECTIONS` — each round re-litigates the increment instead of closing
it.

obra/superpowers bounds this with a scoped re-review
(`skills/subagent-driven-development/re-review-prompt.md`): the re-reviewer
verdicts each prior finding as addressed or not, judges only the fix diff, and
parks everything else as observations that neither block nor extend the loop.

## Acceptance criteria

- A correction round's review prompt names the previous verdict's findings and
  the fix's diff range.
- The reviewer verdicts each named finding as addressed or not addressed,
  where addressed means the defect no longer exists, not that a fix was
  attempted.
- New breakage inside the fix diff is a finding.
- A remark outside the named findings and outside the fix diff is an
  observation in the summary; it does not block the increment and does not
  start another round.
- The verdict's `findingCount` counts only not-addressed findings and new
  fix-diff findings.
- The reviewer still reads nothing out of `backlog.json`; whatever it needs
  travels in its prompt.
- The first round of an increment is unchanged.
