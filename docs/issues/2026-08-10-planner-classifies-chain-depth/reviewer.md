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

## Round 1

**Status: 0 findings. Accepted.** Every acceptance criterion is met, each on a
path a case in `test-repo.sh` walks, and the suite is green. Nothing in the diff
is outside the criteria.

### What I ran

- `bash test-repo.sh` — 71 cases, exit 0. Nothing skipped, nothing excluded.

That was the whole list I was given, so nothing else was run. No red, so no
merge-base run was needed. Note for the record: the chain-depth cases added to
`skills/agent-brief/assets/backlog.test.mjs` are not executed by `test-repo.sh`
— they run under `test.sh`, which was not on my list. `test-repo.sh` does
assert that `test.sh` lists that suite.

### What I reviewed, and against what

Local `main` is `57e5fd4` and stale by twenty-odd merged pull requests;
`origin/main` is `03d6ba4` and is the merge base with `HEAD`. The range
`03d6ba4..HEAD` still carries the previous issue's read-barrier hook, accepted
in its own review round at `8968dbf`. So the change under review is
`8968dbf..HEAD`, judged against `issue.md`. That is a fact about the checkout,
not a finding.

Files judged: `workflows/agile-loop.js`, `skills/agent-brief/assets/backlog.mjs`,
`skills/agent-brief/assets/backlog.test.mjs`,
`skills/agent-brief/assets/CLAUDE.md`, `agents/planner.md`,
`agents/implementer.md`, `README.md`, `test-repo.sh`. The other agents' handoff
files in this issue directory are excluded, as my page says.

### The criteria, one by one

1. **Depth returned and recorded.** The planner's return schema requires
   `depth` per increment (`workflows/agile-loop.js:201-208`), `agents/planner.md`
   tells the planner to give it in the `init` payload and in the `increments` it
   returns, and `shapeIncrement` records it with `full` as the code default
   (`skills/agent-brief/assets/backlog.mjs:129`). Met.
2. **The bar, owned by the planner's page.** `agents/planner.md`, "How deep the
   chain goes", states the bar and that `full` is the answer on any hesitation;
   `test-repo.sh` pins that no other agent page or shipped `SKILL.md` names
   "chain depth". Met.
3. **Round 0 of a `direct` increment.** `directRound = round === 0 && depth ===
   'direct'` (`workflows/agile-loop.js:818`) skips the researcher and the
   test-author and dispatches the implementer then the reviewer; `w20` pins the
   exact label sequence. Met.
4. **The implementer's second work order.** `agents/implementer.md`, "An
   increment nobody planned", states it in the criterion's own words, and the
   frontmatter description repeats it for the dispatch. Met.
5. **The checks carried over.** `lastChecks` is set from every researcher step
   the run walks (`workflows/agile-loop.js:866`) and is what the implementer and
   the reviewer are handed (`:939`, `:968`); `w21` pins the carry-over across an
   increment boundary and `w20` pins the empty-list edge. Met.
6. **Leaving the direct path on a finding.** `directFix = round > 0 && depth
   !== 'direct' && isDirectFixRound(verdict)` (`workflows/agile-loop.js:814`) —
   the round-0 finding 1 is fixed. `w22` covers an ordinary finding and `w24`
   covers the `allDirect` verdict that was the hole: both assert
   `research:i1.1` and `tests:i1.1` are dispatched, so removing the
   `depth !== 'direct'` guard fails the suite. Met.
7. **A second attempt is `full`.** `closedAttempts`, seeded from the index's
   per-increment `attempts` count (`workflows/agile-loop.js:570-578`), now joins
   the session counter in `depth = task.depth === 'direct' && attempt === 1 &&
   !closedAttempts.get(task.id) ? 'direct' : 'full'` (`:771`) — the round-0
   finding 2 is fixed. `backlog.mjs index` already projected `attempts` as a
   count (`:423`) and the `STATE` schema now carries and requires it, so the
   loader has the value to hand over. `w23` covers the in-session hand-back and
   `w25` the hand-back seen across a restart. Met.
8. **Re-classified on every re-cut.** `agents/planner.md` says to set it on
   every cut and every re-cut; `init` lets the payload own the field, so a
   re-cut that carries no depth resets it to `full`, pinned by
   `backlog.test.mjs`. The loop reads `task.depth` off `increments =
   recut.increments`. Met.
9. **The run says which path.** The `directRound` branch logs "the planner cut
   this increment direct — the implementer and the reviewer alone", pinned by
   `w20`; every `worked` entry carries `depth`, including the ones rebuilt from
   an earlier session, and it reaches the result as `increments`. `w20`, `w21`
   and `w25` assert it. Met.

### Nothing in the diff is unasked for

`README.md` gains the direct path in prose and in the diagram, `codemapBlock()`
says "before you begin" because the implementer now reads it too, and
`skills/agent-brief/assets/CLAUDE.md` gains the suite-doc sentence the repo's
own convention requires for the new `backlog.test.mjs` cases. Nothing else.

### Beyond the criteria

- The `directFix` fast path is unchanged for `full` increments: a full round
  always runs its researcher before the implementer, so `lastChecks` equals the
  `plan.checks` the old code passed, and the resume case that reads the checks
  back out of the index still passes.
- The `STATE` schema now requires `attempts`; `backlog.mjs index` has always
  emitted it, and a state file written before either field existed indexes as
  `attempts: 0` and `depth: "full"`, so no old state can be read as `direct`.
- `MAX_ATTEMPTS` is still session-local: `closedAttempts` is read for the depth
  decision alone and is never added to the attempt count, so the "no new
  backstop" non-goal holds.
- `tools/argus-ui/public/run.js` renders the run state as a generic document, so
  the new `depth` key appears without a schema to break.
- Nothing found beyond that.

### Observations — no correction needed

- `rulebook.md:45` still says the chain "runs once per increment" without
  naming the direct path. The pre-existing direct-fix correction round already
  skipped the researcher and the test-author without that sentence mentioning
  it, so the summary is no more of a simplification than it was before this
  change. Not newly stale.
- No case asserts on a dispatch schema, here or anywhere in `test-repo.sh`, so
  dropping `depth` from the planner's return schema would break criterion 1's
  "the planner returns a chain depth" without failing a case. The recording and
  the defaulting behind that criterion are pinned by `backlog.test.mjs`, and
  schema assertions would be a new convention for this suite.
- The implementer's page test greps for the word `codemap`, which now also
  appears in the frontmatter description; deleting the "An increment nobody
  planned" section alone would not fail it. The criterion is prose, and the
  grep still fails if the change to that page is reverted whole.
- `README.md` restates the bar for `direct` in a second wording ("no test could
  catch anything") that is already slightly tighter than the planner's page
  ("nothing in it could be verified by a test that does not already exist"). It
  is a human-facing summary of a path the README would otherwise be silent
  about, and criterion 2's ownership test scopes itself to agent pages and
  shipped skills. Worth knowing it can drift.
- Criterion 5 still degrades on one restart path: `lastChecks` is session-local
  and `close` archives an increment's steps out of the index, so a run resumed
  behind a closed `full` increment hands a `direct` increment an empty list.
  That is the branch the criterion itself sanctions, and the issue's Decisions
  section chose the session-local carry-over the direct-fix round already used.
- `agents/implementer.md`'s new section triggers on "your prompt names no
  researcher step to read", which is also true of a direct-fix correction round,
  where the prompt carries neither criteria nor a codemap. The wording is the
  criterion's own and the direct-fix prompt names itself explicitly, so the
  overlap resolves in the prompt.
