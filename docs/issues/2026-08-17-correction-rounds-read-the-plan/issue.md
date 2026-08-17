# A correction round's researcher reads the plan it already wrote

## Problem

A correction round dispatches a fresh researcher, and that researcher is handed
the review's findings, the questions the test-author left open, and a pointer to
the planner's codemap in the run state. It is not handed the plan its own
increment's previous round produced, although that plan sits in the same run
state under the step label `research:<increment>.<round-1>`. So it re-derives
the design it already wrote, from the codebase, at full price.

The measured cost, across the eleven runs recorded under `docs/issues/`: the
researcher is the most expensive role in the loop at 23,700 characters of
recorded return per step, three times the next role, and 66 % of all recorded
return volume. Eleven of the seventeen increments whose rounds are recorded went
past round 0, and rounds 1 and 2 together account for 25 % of all recorded
returns. The retrospective in
`docs/issues/2026-08-07-timeline-focus-and-context-filter/issue.md` names the
same waste in the run it measured: three of that run's seven researchers were
correction-round researchers re-deriving context their own round-0 researcher
already had.

The run state already solves this problem once, for the codemap: the planner
writes it to the state, no prompt copies it, and every researcher reads it there
with the backlog helper. The previous round's plan is the same kind of thing and
gets none of that treatment.

## Acceptance criteria

- A correction round's researcher prompt names the research step of the round
  before for the same increment, and instructs the researcher to read that
  step's plan out of the run state before it plans the fix.
- The prompt names that step and its field and copies no plan text into itself.
- The step the prompt names belongs to the increment being worked and never to
  another increment.
- Where the increment's previous round dispatched no researcher, the prompt
  names no such step and stays valid.
- Every page that describes what a correction round's researcher reads describes
  this too.
- A test turns red when the prompt no longer names the previous round's plan.
- `bash test.sh` exits 0.

## Out of scope

- A researcher that stays alive across rounds or increments. The run state is
  the shared memory and every agent stays disposable.
- What the researcher returns: no field is added to its schema and none changes
  its meaning.
- The codemap, and how the planner writes it.
- The prompts of the test-author, the implementer and the reviewer.
- Rounds that skip research: a direct-fix round and a direct increment dispatch
  no researcher and this issue changes neither.

## Decisions

Taken as defaults, from the conversation that filed this issue, without a
separate answer from the human:

- Read from the state, do not copy into the prompt. This mirrors what the
  codemap already does and keeps the largest thing an agent produced from being
  emitted a second time.
- The previous round's plan only, not every earlier round's. Each correction
  round's researcher overwrites the increment's plan, so the round before holds
  the current design.
- The plan only, not the previous round's other recorded fields. The findings
  and the open questions already reach this researcher.
