# `test.sh` runs the suite you name

## Problem

`test.sh` is the one command behind "the suite is green", and it has exactly
one mode: it runs all eight suites, one after another, every time. A run that
only needs `test-repo.sh` still pays for two shell suites, three `node --test`
suites and three `npm test` invocations.

The bill has been measured on the run that shipped
`docs/issues/2026-08-16-the-break-decides-the-chain`. That run invoked the full
`test.sh` 78 times and `test-repo.sh` 141 times, across 28 subagents in 2 h
54 min of strictly sequential wall clock. Most of those invocations were
mutation probes: delete one paragraph from an agent page, run the suite, expect
red, restore. Such a probe can only ever turn `test-repo.sh` red — every other
suite in the list is untouched by an edit to a markdown page and runs purely as
overhead, and it runs on the critical path, because no two agents in the chain
run at the same time.

The reviewer's probing is not the only caller. A test-author iterating on one
grep pattern re-runs the same eight suites until the pattern sits, and so does
an implementer fixing one case.

What makes this more than a speed problem is the answer a filtered run gives.
Today the closing line of a green run is `PASS: all 8 suites`, and every agent
reports it as the fact that the suite is green. A filter that keeps that line
hands every agent a way to call a change green having run an eighth of the
evidence — and the mutation standard the repository runs on rests on exactly
that fact being true. So the filter has to be visibly a filter, in its own
output and in the rules the agents follow, or it buys latency by weakening the
one measurement the chain trusts.

Selecting a suite also needs something to select it by. The list carries prose
labels — "the repository itself", "parallel runs: worktrees",
"skills/agent-brief/assets: the backlog recorder" — which are written to be read
in output, not typed on a command line.

Speeding up the mutation probe itself — the delete, run, expect-red, restore
loop three agents hand-rolled separately in that run — is a separate issue and
stays out of this one.

## Acceptance criteria

- `bash test.sh` with no arguments runs every suite and prints what it prints
  today.
- Every suite carries a short stable name that a caller can type, and no two
  suites share one.
- `bash test.sh --only <name>` runs that suite alone and no other.
- `--only` given more than once runs each named suite and no other, in the
  order the suite list declares them.
- `bash test.sh --list` prints every suite's name and exits 0 without running a
  suite.
- A name that matches no suite makes the run exit non-zero, print the unmatched
  name and print the names that do exist, and run no suite at all.
- A filtered run never prints the wording an unfiltered green run ends with, and
  its closing line names how many of the repository's suites it ran and that it
  was filtered.
- A filtered run whose suites all pass exits 0, and a filtered run with a
  failing suite exits non-zero.
- Adding a suite to `test.sh` requires giving it a name, and a suite without one
  makes a case turn red.
- The rules the agents follow state that a filtered run is not the fact that the
  suite is green, and that the run an agent commits, reports or takes a verdict
  from is the unfiltered one.
- Every rule this adds to a page gets a case in `test-repo.sh` that turns red
  when that rule is removed, and each such case matches only the passage
  carrying its rule.
- The behaviour of every criterion above is covered by cases that turn red when
  that behaviour is removed.
- `bash test.sh` exits 0.
