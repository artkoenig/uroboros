# The named break decides the chain, and the reviewer executes it

## Problem

`agents/researcher.md` already asks the test plan for the fact this issue needs.
Every acceptance criterion gets at least one case that fails when that
criterion's behaviour is broken or removed, each case states the break — the
production change that would make it fail — and a criterion left without such a
case is declared in the plan, with the reason.

That declaration is written and then read by nobody. The workflow triages on
`needsTests` and `checks` alone, so an increment whose criteria no tool can
reach runs exactly the chain of one whose criteria a test catches. Two costs
follow from that, and both have been measured on this repository.

The first is the coverage finding nobody can act on. The reviewer holds every
criterion to the mutation standard and files the ones no test would catch,
without being told which of them the researcher already determined no test
*can* catch. In one measured run eight of nine review rejections were coverage
gaps rather than defects, and correction rounds with nothing to correct cost
12.3 % of the run's subagent spend
(`docs/issues/2026-08-07-second-timeline-run-fixes`). Naming the break in the
plan closed the half of that which was a planning gap. The half that is left is
a reviewer that cannot tell a gap from a criterion no tool reaches, and it pays
for the difference in full correction rounds.

The second cost is that the declaration is trusted in both directions. A named
break is a sentence, and nothing makes it red: a plan that names a break for a
case which would pass anyway earns the same credit as one that names a real
break, and naming one is always the cheaper direction, because declaring a
criterion unbreakable is what routes it out of the ordinary path. A break that
is executed is a measurement. A break that is only written down is a claim by
the role with an interest in the answer.

Two channels bound the shape of the fix. The reviewer reads no run state, so
everything it is told about the criteria reaches it through its prompt. The
workflow reads no file, so everything it steers on reaches it through the
researcher's structured return, beside `needsTests` and `checks` — and that
return is projected into later prompts, so what it carries stays small.

What routing an unbreakable criterion *to* — an adjudicated design decision,
independent attempts compared for variance — is a separate issue and stays out
of this one. This one determines the fact, carries it to the role that acts on
it, and stops the two wrong answers the run gives today: a coverage finding
against a criterion no test can reach, and a break nobody ran.

## Acceptance criteria

- The researcher's structured return names, for every acceptance criterion of
  the increment, whether the test plan named a break for it, and carries that
  break where it named one.
- The workflow carries those criteria and their breaks into the prompt of the
  reviewer that judges the increment as a whole.
- The reviewer does not file the absence of a test for a criterion the
  researcher declared unbreakable.
- The reviewer judges each unbreakable criterion by reading the diff against it,
  and says in its `summary` what it judged and on what.
- The reviewer applies each named break in its sandbox worktree, runs the
  commands its prompt already names, and reports the criterion as verified only
  where that run fails.
- A named break that leaves every one of those commands green is a finding
  against the criterion it was named for.
- An applied break never reaches the checkout and never reaches the diff.
- The run result carries, per increment, every criterion accepted without an
  executable check.
- An increment worked `direct` names no break for any of its criteria, and the
  run result carries all of them as accepted without an executable check.
- `rulebook.md` requires the session to give the human one line naming those
  criteria, for every increment that has any.
- Each rule this adds to a page gets a case in `test-repo.sh` that turns red
  when that rule is removed.
- `bash test.sh` exits 0.
