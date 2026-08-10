# Reviewer — the planner classifies each increment's chain depth

## Round 0

**Status: 2 findings.** Both suites are green and every acceptance criterion is
met on the paths the tests walk. Two criteria — 6 and 7 — are unmet on a path
the tests do not walk, and each is reachable from a state the run itself
produces.

### What I ran

- `bash test-repo.sh` — 69 cases, exit 0. Nothing skipped, nothing excluded.
- `node --test skills/agent-brief/assets/backlog.test.mjs` — 52 cases, exit 0.

No red, so no merge-base run was needed.

### What I reviewed, and against what

Local `main` is stale: it points at `57e5fd4`, twenty-odd merged pull requests
behind. `origin/main` is `03d6ba4`, and that is the merge base with `HEAD`. The
range `03d6ba4..HEAD` still contains the previous issue's read-barrier hook,
which was accepted in its own review round. So I judged `8968dbf..HEAD` — the
three commits of this issue (`21350fa`, `93f5353`, `6932100`) — against
`issue.md`. That is a fact about the checkout, not a finding.

Files judged: `workflows/agile-loop.js`, `skills/agent-brief/assets/backlog.mjs`,
`skills/agent-brief/assets/CLAUDE.md`, `agents/planner.md`,
`agents/implementer.md`, `README.md`, `test-repo.sh`. The other agents' handoff
files in this issue directory are excluded, as my page says.

### Finding 1 — a `direct` increment does not leave the direct path when the review's findings are all direct fixes

Criterion 6: "A `direct` increment whose review files a finding leaves the
direct path for the rest of its attempt: the correction round runs the full
chain, so a misclassification costs one implementer and one reviewer, and no
unplanned change reaches the pull request."

Reproduction. The planner cuts increment `i1` with `depth: "direct"`. Round 0
runs `implement:i1.0` and `review:i1.0`, as it should. The reviewer returns
`findingCount: 1` with `allDirect: true` — the shape `verdictReturnWithDirectFinding`
already models in `test-repo.sh`. Then at `workflows/agile-loop.js:802`,
`directFix = round > 0 && isDirectFixRound(verdict)` is true, and at
`workflows/agile-loop.js:806` `directRound` is false, so the round dispatches
`implement:i1.1` and `review:i1.1` and skips the researcher and the
test-author. The labels of the attempt are `implement:i1.0`, `review:i1.0`,
`implement:i1.1`, `review:i1.1` — no `research:i1.1`, no `tests:i1.1`. Repeat
at round 2 and the whole attempt closes with a plan never written for it, which
is what "no unplanned change reaches the pull request" forbids. The criterion
says the correction round runs the full chain; on this verdict it runs neither
the researcher nor the test-author.

`workflows/agile-loop.js:803-805` documents the opposite decision in a comment
("a correction round of a direct increment is an ordinary round unless the
reviewer's verdict makes it a direct-fix one"), so this is a deliberate choice,
not an oversight — but it is not the choice criterion 6 states, and the issue
names no exception for an `allDirect` verdict.

The existing case `w22` in `test-repo.sh` pins criterion 6 with
`verdictReturnWithFinding`, whose `allDirect` is not set. The `allDirect` edge
of the same criterion has no case at all, which is why the suite is green over
this.

### Finding 2 — after a restart, a handed-back `direct` increment is worked `direct` again

Criterion 7: "An increment the planner hands back after a failed attempt is
`full` on its next attempt, whatever it was classified as before."

The mechanism chosen is the session-local attempt counter:
`workflows/agile-loop.js:758-763`, `const depth = task.depth === 'direct' &&
attempt === 1 ? 'direct' : 'full'`. `attempts` is `new Map()` at
`workflows/agile-loop.js:720` and is never seeded from the run state — and
`workflows/agile-loop.js:65-69` records that this is on purpose for
`MAX_ATTEMPTS`. Criterion 7 inherits that reset, and is not written with an
exception for it.

Reproduction. `backlog.json` holds one increment: `{ id: "i1", depth:
"direct", status: "todo", branch: "issue-branch--i1", steps: [] }` — the shape
`close` leaves behind after the planner hands back a failed attempt, its steps
moved into `attempts`. Start the workflow on that directory. The state loader
returns that increment; `recorded` holds no step for `i1`, so
`incrementHasHistory("i1")` is false; `branches` holds `issue-branch--i1` from
the state. The loop then, in one and the same iteration:

- names the branch `issue-branch--i1-take2` (`nextBranchName`,
  `workflows/agile-loop.js:593-599`) — proof that it knows this is a later
  attempt, and a signal that survives the restart; and
- computes `attempt === 1`, therefore `depth === "direct"`, therefore
  `directRound` true, and dispatches `implement:i1.0` and `review:i1.0` with no
  researcher and no test-author.

So the second attempt at an increment whose first attempt already failed is
worked direct, which criterion 7 forbids unconditionally. `w23` covers the
live-session hand-back only; no case covers the hand-back seen across a
restart.

### Observations — no correction needed

- Criterion 5 degrades on the same restart path, but it degrades safely.
  `lastChecks` (`workflows/agile-loop.js:727`) is session-local, and `close`
  archives an increment's steps out of the index, so a run resumed behind a
  closed `full` increment has no researcher step in reach and hands a `direct`
  increment an empty list. That is the "where the run holds none, the list is
  empty, and an empty list means the review is a reading" branch the criterion
  itself sanctions, and recovering the archived checks would need the index
  projection widened. Recording it so it is a known property, not a surprise.
- `README.md` restates the bar for `direct` ("when the criteria and the codemap
  already name the file, the place and the right result and no test could catch
  anything"). Criterion 2 gives that bar to the planner's page "alone", and
  `test-repo.sh` enforces that ownership over agent pages and shipped skills
  only. The README copy is a human-facing summary and is a second wording that
  can drift, but the README would otherwise go stale about a path the run now
  takes, so this is a judgement call rather than a defect.
- No test pins that a *re-cut* that changes an open increment's depth is
  honoured by the loop — `w23`'s re-cut keeps `direct` and is overridden by the
  attempt rule, so the only depths any case reads come from the opening cut.
  Criterion 8's other half (the planner classifies again, `init` re-classifies)
  is covered by `backlog.test.mjs` case 4 and by `agents/planner.md`. The loop
  reads `task.depth` off `increments = recut.increments`
  (`workflows/agile-loop.js:1035`), the same path `status` and `title` take and
  which other cases exercise, so the gap is narrow.
- `agents/implementer.md`'s new section "An increment nobody planned" triggers
  on "your prompt names no researcher step to read", which is also true of a
  direct-fix correction round, where there is no codemap and no criteria in the
  prompt. The wording is the criterion's own, so the page states what it was
  asked to state; the overlap with the "Direct-fix rounds" section above it is
  worth knowing about.

### Beyond the criteria

- The read barrier does not block the new read: `hooks/read-barrier.mjs` gates
  the implementer on `issue.md` and on the `testPlan` field only, so the direct
  implementer's `backlog.mjs codemap <dir>/backlog.json` passes.
- `argus-ui` renders a run state as a generic tree (`tools/argus-ui/public/run.js`),
  so the new `depth` field appears without a schema to break.
- `codemapBlock()` changed "before you research" to "before you begin", which
  reaches the researcher's prompt too; nothing in `agents/researcher.md`
  depends on the old wording.
- The state loader's `STATE` schema now requires `depth` per increment
  (`workflows/agile-loop.js:151-160`) while its dispatch prompt still only says
  to return "the index's `increments`". A state file written before the field
  existed is projected as `full` by `backlog.mjs index`, so the loader always
  has a value to hand over. Nothing found.
- Non-goals hold: `agents/reviewer.md`, `agents/researcher.md` and
  `agents/test-author.md` are untouched in this range, and `MAX_INCREMENTS`,
  `MAX_ATTEMPTS`, `MAX_BLOCKED` and `MAX_CORRECTIONS` keep their values.
