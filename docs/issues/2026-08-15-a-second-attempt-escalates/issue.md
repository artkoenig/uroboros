# A second attempt escalates, and the cap ends in adjudication

## Problem

A second attempt re-runs the same chain the same way: same steering, and no
word to any agent that a first attempt already failed — the new chain
rediscovers what the archived attempt already learned. And when the last
correction round is used up, the increment closes as blocked with "last round
used up": the human is handed a failure without being told which findings
still stand, which are contestable, or what the smallest unblocking change
would be.

obra/superpowers does both (`skills/subagent-driven-development/SKILL.md`): a
loop that survives its resumes gets fresh eyes told "a prior implementer
attempted this task; you own it now — read what was tried", and a tripped cap
ends in adjudication — every open finding is either parked with a recorded
ruling or answered with the smallest unblocking change — with the explicit
guard that adjudicating before the cap is pre-judging.

## Acceptance criteria

- Every dispatch of a second attempt says that a first attempt failed and
  points at the archived attempt in the run state, so the chain reads what was
  tried instead of rediscovering it.
- The workflow raises the implementer's dispatch effort one step on a second
  attempt.
- When an increment closes as blocked because its last round is used up, the
  planner's closing note adjudicates every finding still open: it stands and
  why, or the smallest change that would unblock it.
- The run result carries that adjudication where the rulebook's per-increment
  reason line can quote it.
- No round before the cap ends by adjudicating findings away.
