# Direct Mode is keyed to a predicate, not to a judgement call

## Problem

`rulebook.md` opens Direct Mode with "Small or obvious work: you do it." That
sentence was written when the chain was fixed: every issue paid for a
researcher, a test-author, an implementer and a reviewer, so anything genuinely
small was cheaper in the session than in the loop.

The chain is not fixed any more. The planner cuts every increment `full` or
`direct`, and round 0 of a `direct` one is worked by the implementer and judged
by the reviewer alone
(`docs/issues/2026-08-10-planner-classifies-chain-depth`). A correction round
whose findings are all direct fixes skips research and tests. And an increment
cut `direct` names no break for any of its criteria, so the run reports every
one of them as accepted without an executable check
(`docs/issues/2026-08-16-the-break-decides-the-chain`).

So "small or obvious" now names exactly the band the loop works cheaper and
with a reviewer in front of it — including the rule-text and documentation
changes that used to be the clearest case for Direct Mode.

The form is the second half of the problem. `.claude/rules/authoring.md` puts
behaviour that depends on a condition in the row whose working form is a rule
keyed to an observable predicate, and names the judgement call as the form that
decides neither branch. "Small or obvious" is a judgement call, and it decides
against the loop every time: the session weighs "small" against nothing, pulls
the work into the most expensive context in the run, and no reviewer ever sees
the diff.

Two cases are left that the loop cannot do more cheaply. In the first the issue
file is the expensive part — a typo, one line in a document — and the loop's
floor is the issue file, the planner opening and closing the state, the
implementer, the reviewer and the publish step. In the second the loop cannot
run at all: it is broken, or not installed. That already happened once, when
`workflows/agile-loop.js` would not load because its `meta` was not a pure
literal, and only the session could repair it.

Nothing about the loop's own chain composition is wrong, and this issue does
not touch it. Neither the `agent-brief` skill nor any agent page mentions the
modes, and none of them is in scope: a subagent never picks a mode.

## Acceptance criteria

- `rulebook.md` keys Direct Mode to two observable cases: writing the issue
  file costs more than the change itself, and the loop cannot be run.
- `rulebook.md` sends every task outside those two cases to Issue Mode.
- `rulebook.md` states what taking Direct Mode for a task outside those two
  cases costs: the loop would have cut it `direct` and put a reviewer on the
  diff, and the session gives it no reviewer and spends the run's most
  expensive context on it.
- `rulebook.md` quotes, verbatim, the rationalisation that price counters.
- `rulebook.md` offers "small or obvious" nowhere as the test for Direct Mode.
- `rulebook.md` keeps the rest of the Direct Mode section as it stands: read the
  code, change the code and the tests, run them, commit, push, open the pull
  request, and hand a broad search to a subagent.
- `rulebook.md` keeps the mode-picking rule as it stands, including that an
  unanswered mode question falls to Issue Mode.
- `GEMINI.md` is byte-identical to `rulebook.md`.
- `test-repo.sh` has a case that turns red when `GEMINI.md` and `rulebook.md`
  differ.
- Each rule this adds to `rulebook.md` gets a case in `test-repo.sh` that turns
  red when that rule is removed.
- The paragraph in `README.md` that names the two modes states the same
  predicate as `rulebook.md` and states no other test.
- `bash test.sh` exits 0.
