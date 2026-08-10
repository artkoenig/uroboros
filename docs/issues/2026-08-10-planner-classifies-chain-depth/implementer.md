# Implementer — the planner classifies each increment's chain depth

I built the plan in `researcher.md` in full: five production files, no test
touched, nothing outside the plan. Both commands the plan names are green.

## What I ran, and when

**Before changing anything**, to confirm the planned tests were red for the
reason the test-author recorded:

- `bash test-repo.sh` — 69 cases, 63 ok, 6 FAIL, exit 1. The six were exactly
  W20, W21, W22, W23, P1 and P2. Every failure message named missing
  `direct`-path behaviour or a missing page section, never a fixture mistake:
  W20's label array came back with `research:i1.0`/`tests:i1.0` still in it,
  P1's grep returned `(none)`, P2 reported `agents/implementer.md never names
  the codemap`.
- `node --test skills/agent-brief/assets/backlog.test.mjs` — 52 cases, 49 pass,
  3 fail, exit 1. The three were A1, A2 and A3, each failing on `expected
  'direct'/'full' got undefined`.

**After the change**, the two commands the plan lists as what counts as done,
both from the repository root:

- `bash test-repo.sh` — 69 cases, 69 ok, 0 FAIL, exit 0. Nothing skipped or
  excluded.
- `node --test skills/agent-brief/assets/backlog.test.mjs` — 52 cases, 52 pass,
  0 fail, 0 skipped, 0 todo, exit 0.

Nothing else was run: no `./test.sh`, no `tools/` suite, no `test-worktree.sh`,
no linter or formatter — the plan's list is closed and the repository has no
linter, formatter or type checker.

## What I changed

### `skills/agent-brief/assets/backlog.mjs`

- `shapeIncrement`: added `depth: raw.depth === 'direct' ? 'direct' : 'full',`
  between `criteria` and `status`.
- `index`: added the same normalised expression, reading `increment.depth`, in
  the same position of the per-increment projection.
- Extended the comment above `init` with one sentence saying the depth is
  normalised where it is shaped and where it is projected, so `full` is the
  default in code rather than in prose.
- No prior depth is carried across a re-cut: the payload owns it, unlike
  `branch` and `attempts`.

### `workflows/agile-loop.js`

- Head comment: the list of what the script carries as steering now names how
  deep the chain goes for each increment.
- `STATE`, `increments.items`: added `depth: { type: 'string', enum: ['full',
  'direct'] }` and `'depth'` to `required`.
- `BACKLOG`, `increments.items`: added the same property with the one-line
  description pointing at the planner's page, and `'depth'` to `required`.
- `codemapBlock()`: trailing words changed from `before you research.` to
  `before you begin.`
- Declared `let lastChecks = []` beside `worked`/`attempts`/`stopped`, with a
  comment on what it holds. It is set to `Array.isArray(plan.checks) ?
  plan.checks : []` immediately after `planLabel = researchLabel` and before the
  `asksTheHuman` check, so a replayed researcher return updates it too. Both
  remaining `checkList(plan.checks)` calls — the implementer's and the
  reviewer's — now read `checkList(lastChecks)`; the log line that prints the
  checks still reads `plan.checks`, since it sits inside the branch that just
  produced them.
- Restore loop: the entry pushed for an increment an earlier session closed
  carries `depth: t.depth === 'direct' ? 'direct' : 'full',`.
- Per attempt, right after `attempt` is computed: `const depth = task.depth ===
  'direct' && attempt === 1 ? 'direct' : 'full'`, with a comment saying this is
  the one place the loop overrides the planner.
- Per round: added `const directRound = round === 0 && depth === 'direct'`
  beside the untouched `directFix`, gated the research-and-tests block on
  `directFix || directRound`, kept the existing `directFix` log line verbatim
  and added an `else if (directRound)` line reading `Increment ${n} round
  ${round}: the planner cut this increment direct — the implementer and the
  reviewer alone, no research and no tests.` Both branches still clear
  `testsLabel`.
- Implementer dispatch: `branchBlock(..., directRound && freshBranch)` in place
  of the literal `false`, with a comment on why the direct implementer is the
  step that creates the branch. The brief gained a third case ahead of the two
  that existed — for `directRound` the prompt is `scope(...)`, then
  `codemapBlock()`, then one sentence saying no researcher and no test-author
  worked this increment so what stands above is its whole brief. It reads no
  step, and the "No test was written for this round" line stays bound to the
  planned case alone. `effort` is unchanged.
- `worked.push`: added `depth,`.
- Nothing else: `runOutcome()`, the publish prompt, `MAX_*`, `isDirectFixRound`
  and the correction-round machinery are untouched.

### `agents/planner.md`

- New `## How deep the chain goes` between `## The codemap` and `## Your brief`,
  stating once each: every increment carries a chain depth, set on every cut and
  re-cut and given in both the `init` payload and the returned `increments`;
  `full` is the default and the answer whenever you hesitate; `direct` only when
  criteria and codemap already name the file, the place and the right result and
  nothing could be verified by a test that does not already exist; what `direct`
  buys and costs.
- `## What you may not do`: the testing bullet now says what gets tested inside
  a `full` increment is the researcher's call per increment, and that the chain
  depth says how deep the chain goes, never what it tests.
- `## What you write`: the increment field list now includes the chain depth.

### `agents/implementer.md`

- New `## An increment nobody planned` after `## Direct-fix rounds`, with the
  three statements the plan names.
- Frontmatter `description` gained one clause: where the prompt names no
  researcher step, nobody planned the increment and the criteria in the prompt
  plus the codemap it points at are the whole brief instead.
- The phrase "chain depth" does not appear on this page, and no bare
  `planner.md`/`researcher.md` was written on it.

### `README.md`

- One paragraph inside `## The backlog: the planner says what, the researcher
  says how`, after the paragraph ending "…and the researcher says how."
- Two lines in the second mermaid diagram, after the `BACK -->|"the first
  increment…"| CHAIN` edge: the `SHORT` node and its edge to `REPLAN`.

`skills/agent-brief/assets/CLAUDE.md` already carried the depth in its init and
index clauses — the test-author landed that in the previous commit, so I left it
alone.

## Notes for the reviewer

- **No test was edited or added by me.** The test-author's fixture changes to
  the `test-repo.sh` heredoc (`increment(id, depth)`, `idxIncrement`'s
  `depth: 'full'` default, `decomposeReturnDirect`/`Mixed`, cases `w20`–`w23`)
  and the three new cases in `backlog.test.mjs` were already in the tree when I
  started, and I changed none of them.
- **Two things the plan marks as untestable here, so the review is what catches
  them.** The `BACKLOG` schema requiring `depth` back from the planner is not
  exercised by the driver, which stubs `agent()` and validates no schema; and
  the wording of both new page sections is prose beyond the reach of P1 and P2's
  greps.
- **The `plan.checks` log line was deliberately left as it is.** The plan says
  to replace "both remaining uses" — the implementer's and the reviewer's — and
  it names those two by line. The third reference, inside the research branch's
  own log line, prints what the researcher just returned and is never reached
  with `plan` null, so I did not touch it.
- **The mermaid `SHORT --> REPLAN` edge precedes `REPLAN`'s label definition**,
  because the plan places the two new lines directly after the `CHAIN` edge.
  Mermaid resolves the label from the later definition; the diagram renders. Say
  so if you would rather have the edge moved below `CHAIN --> REPLAN[...]`.
- **The test-author's accidental read of `backlog.mjs`** is recorded in
  `test-author.md`; it is a process note for the researcher, not something my
  work depends on.
- I am blocked on nothing.

## Round 1

Both findings of the Round 1 plan are implemented in `workflows/agile-loop.js`
alone. No page, no README, no `backlog.mjs`, no test file was touched.

### Finding 1 — a correction round of a `direct` increment always runs the full chain

- `workflows/agile-loop.js`, the round loop: `const directFix = round > 0 &&
  isDirectFixRound(verdict)` became `const directFix = round > 0 && depth !==
  'direct' && isDirectFixRound(verdict)`.
- Rewrote the comment above `directFix`: it keeps its point that only the round
  before's verdict decides, and gains the clause that an increment this attempt
  is working direct is never a direct-fix round, because a review that filed
  anything against it has already shown the classification was wrong.
- Rewrote the comment above `directRound`: the planner's classification governs
  round 0 alone, every later round of that attempt is a full round, and the
  reviewer-driven fast path stays open only to increments the planner cut
  `full`.
- Nothing else in the round moved: `isDirectFixRound`, the direct-fix
  implementer brief and its `{ effort: 'low' }` are untouched.

### Finding 2 — a hand-back the state remembers forces `full` across a restart

Three edits, all in `workflows/agile-loop.js`:

1. `STATE`, `increments.items`: added `attempts: { type: 'integer' },` after
   `steps` in `properties` and `'attempts'` at the end of `required`, with no
   description, matching its neighbours.
2. Beside the `branches` seed: added `const closedAttempts = new Map()`, filled
   from the same loop over `savedIndex.increments` with
   `if (Number(t.attempts) > 0) closedAttempts.set(t.id, Number(t.attempts))`,
   commented in the file's voice as holding how many attempts the state says the
   increment has already closed, for one decision only.
3. The per-attempt depth line became
   `const depth = task.depth === 'direct' && attempt === 1 &&
   !closedAttempts.get(task.id) ? 'direct' : 'full'`, and its comment gained the
   sentence that the session counter catches a hand-back inside one session, the
   archived count catches one across a restart, and between them a second
   attempt is never direct.

The head comment on the backstops was corrected: the false clause "closing an
increment ends its attempt in the state, so nothing there counts attempts" is
gone; `MAX_ATTEMPTS` is still stated as session-local with the restart-is-cheaper
sentence intact, plus the new sentence that the count the index does carry is
read for one thing only — never working an increment direct twice.

### Files changed

- `workflows/agile-loop.js` (the only production file this round).

### Tests

I ran `bash test-repo.sh` before changing anything: 71 cases, 69 ok, 2 FAIL,
exit 1. The two failures were W24 and W25, red for exactly the reasons the plan
recorded — W24's labels came back
`["load-state","decompose","implement:i1.0","review:i1.0","implement:i1.1","review:i1.1","replan:i1","publish"]`
(the correction round took the direct-fix path) and W25's came back
`["load-state","implement:i1.0","review:i1.0","replan:i1","publish"]` (the
restarted attempt was still classified direct). I wrote and edited no test.

### Commands run — what counts as done

```
bash test-repo.sh
```
71 cases, all ok, exit 0. Nothing skipped, nothing excluded. That is the whole
closed list for this round; `node --test skills/agent-brief/assets/backlog.test.mjs`
is excluded by the plan because no file that suite covers changed, and I did not
run it.

### Notes for the reviewer

- The `STATE` addition of `attempts` is unreachable from any test — the driver
  stubs `agent()` and validates no schema — exactly as the Round 1 test plan
  records. It is the review that reads it.
- `closedAttempts` is read with `!closedAttempts.get(task.id)`, so any non-zero
  archived count forces `full`; an absent id and a zero both leave the planner's
  classification standing, as the plan intends.
- I am blocked on nothing.
