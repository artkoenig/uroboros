# The reviewer proves a suspicion with a probe instead of a reading

## Problem

The reviewer is the one role that reads nothing any agent produced, and that
independence is the point of it. But what it may do with that independence is
narrow: it reads the diff, it reads the issue file, it runs the closed list of
commands, and where it must see another state it builds a sandbox worktree
outside the checkout and works there. What it may not do is write anything —
"You never write a test to prove a finding, not even a throwaway."

So a suspicion that a reading cannot settle has nowhere to go. The reviewer
sees `if (name === "")` against a criterion that says empty names are rejected,
doubts that three spaces are handled, and cannot find out: no test covers it,
`git show` does not answer it, and running the listed suite tells it only what
the suite already tests. The rule sends it away — such a finding is "one round
of test-authoring away" — so the doubt is either dropped, or filed without a
reproduction and dismissed by the caller's triage, or it becomes a finding that
costs a full correction round to answer a question a single request would have
answered.

That is the wrong price. A finding at review time costs a round of agents; the
question behind it costs one command. The run pays the expensive one because
the cheap one is forbidden.

The containment the rule protects is already provided elsewhere. The reviewer
may not touch the checkout and already builds a sandbox outside it for exactly
this kind of work — a probe written there, run there and removed with the
sandbox never reaches the diff, the commit or the pull request, which is what
the prohibition was defending.

## Acceptance criteria

- [ ] The reviewer may write a throwaway probe — a script, a request, a
      test-shaped file — inside the sandbox worktree it already builds, run it
      there, and use what it returns as the reproduction of a finding.
- [ ] A probe exists in the sandbox only. It is never written into the
      checkout, never committed, and never appears in the diff under review;
      the sandbox is removed when the review ends, as it already is today.
- [ ] The rule that a reproduction is a spec still stands: a probe is evidence
      for a finding, never the test that pins the behaviour afterwards. Writing
      that test stays the test-author's, and whether a probe produced a finding
      does not change how that finding is classified.
- [ ] A finding a probe produced carries, inside its `reproduction`, what the
      probe ran and what it returned.
- [ ] The closed list of commands does not bind inside the sandbox: running a
      probe there is not running a command the list failed to name. Outside the
      sandbox the list is closed exactly as before, and what the review reports
      as green or red still rests on the listed commands alone.
- [ ] The reviewer probes from a stated doubt, never to explore: before it
      writes one it can name, in one sentence, the criterion and the doubt, and
      that sentence reaches its report. A reviewer that goes looking is a
      second researcher, and the run pays for it twice.
- [ ] The review's `summary` says how many probes ran and what they showed, so
      a review that found nothing still shows whether it looked.

## Non-goals

- The reviewer fixes nothing. It edits no production code and no test in the
  checkout, and it never makes the correction a finding asks for.
- Running the listed commands against another state in a sandbox — including
  breaking a line on purpose to see whether anything goes red — is already
  allowed and already practised. This issue adds the written probe and nothing
  else.
- Planning the edge cases of a change stays the researcher's work, and its
  standard is settled in `docs/issues/2026-08-07-agile-loop-optimizations`.
  This issue is for what that plan could not anticipate, not a licence to plan
  less.
- Holding acceptance criteria back from the implementer so the reviewer alone
  sees them was considered and dropped: it reaches the same class of defect,
  but costs a full correction round whenever the implementer simply did not
  build what nobody told it about, and it makes an agent's brief deliberately
  incomplete. The probe costs a round only when it finds something.
