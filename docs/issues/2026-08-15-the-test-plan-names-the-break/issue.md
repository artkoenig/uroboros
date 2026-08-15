# The test plan names the break for every criterion

## Problem

The reviewer holds a mutation standard — would each criterion have a test that
fails if the behaviour breaks? — that the researcher, who decides the test
plan, has never been given. So coverage gaps are planned in and found one role
and one correction round too late: in one measured run, eight of nine review
rejections were coverage gaps rather than defects, and correction rounds with
nothing to correct cost 12.3 % of the run's subagent spend
(`docs/issues/2026-08-07-second-timeline-run-fixes`). Criterion 1 of
`docs/issues/2026-08-07-agile-loop-optimizations` asked for this and was never
delivered.

obra/superpowers states the planning-side form of the standard in
`skills/test-driven-development/writing-good-tests.md`: before writing a test,
name the production change that should make it fail — "name the break".

## Acceptance criteria

- The researcher's page requires the test plan to name, for every acceptance
  criterion of the increment, at least one case that fails when that
  criterion's behaviour is broken or removed.
- The researcher's page requires each planned case to state the production
  change that would make it fail, as part of the case.
- The mutation standard has one owning page; every other page that needs it
  points at the owner instead of restating it.
- A test plan that leaves a criterion without such a case must say so and why,
  in the plan itself.
