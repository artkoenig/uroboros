# Researcher — the planner classifies each increment's chain depth

## Implementation plan

The change adds one value to an increment — its chain depth, `full` or
`direct` — and one branch to the loop that reads it. Five files change in
production, three in the test tree.

### The field, and where it lives

Call the field `depth`, with the two values `full` and `direct`. One word, one
meaning, in all five places it appears: the increment object in `backlog.json`,
the index projection, the two schemas in the workflow, and the run result's
entry for a worked increment. Do not introduce a second spelling
(`chainDepth`, `path`, `mode`) anywhere.

`full` is the default, and it is enforced in code rather than asked for in
prose: every place that reads the field normalises with
`raw.depth === 'direct' ? 'direct' : 'full'`, so a missing field, an older
state file and a value nobody recognises all come out `full`.

### 1. `skills/agent-brief/assets/backlog.mjs` — the field is stored and projected

- In `shapeIncrement` (line 123), add `depth: raw.depth === 'direct' ? 'direct' : 'full',`
  between `criteria` and `status`. The depth belongs to the cut, which is what
  the payload owns; `status` and `note` are what the run does to it.
- In `index` (line 402), add the same normalised `depth` to the per-increment
  projection, in the same position. Reading it from `increment.depth` rather
  than assuming `shapeIncrement` ran is what makes a state file written before
  this change index as `full` instead of `undefined`.
- The payload owns the depth on every `init`, exactly as it owns `title`,
  `goal`, `criteria` and `status`. Do **not** carry a prior depth across a
  re-cut the way `branch` and `attempts` are carried: an increment the planner
  re-cuts without a depth goes back to `full`, which is the mechanical half of
  the criterion that says the planner classifies again on every re-cut.
- Add one sentence to the comment above `init` (or above `shapeIncrement`) in
  the file's own voice, saying that the depth is normalised here so `full` is
  the default in code rather than in prose.

### 2. `workflows/agile-loop.js` — the loop reads it and skips round 0's planning

- **`STATE`** (line 134), `increments.items`: add
  `depth: { type: 'string', enum: ['full', 'direct'] }` and add `'depth'` to
  that item's `required` list. The state loader returns the index verbatim, so
  no prompt text changes; the index always carries the field after change 1.
- **`BACKLOG`** (line 182), `increments.items`: add
  `depth: { type: 'string', enum: ['full', 'direct'], description: 'The chain depth you recorded for this increment. Your page states the bar.' }`
  and add `'depth'` to `required`. This is the channel that matters on a fresh
  run: the loop steers on the planner's returned `increments` when there is no
  state yet, so without this every fresh increment would read as `full`.
  Keep the description to one line that points at the page — the bar itself
  belongs to the planner's page alone.
- **The head comment** (lines 44–51) lists what the script carries as steering:
  "the cut, whether tests are needed, the closed list of commands the reviewer
  runs, how many findings a review filed, and the questions that end a run".
  Add the chain depth to that list.
- **`codemapBlock()`** (line 699): change the trailing words `before you
  research.` to `before you begin.` The block is now sent to the implementer as
  well as to the researcher, and it is the one copy of that instruction.
- **`lastChecks`**: declare `let lastChecks = []` beside `const worked = []`
  (line 712), before the increment loop. It holds the `checks` of the most
  recent researcher step the run has walked. Set it immediately after every
  researcher return, dispatched or replayed:
  `lastChecks = Array.isArray(plan.checks) ? plan.checks : []`, placed right
  after `planLabel = researchLabel` and before the `asksTheHuman` check.
  Then replace **both** remaining uses of `checkList(plan.checks)` — the
  implementer's (line 888) and the reviewer's (line 917) — with
  `checkList(lastChecks)`. In a planned round the two are identical, so this
  changes nothing there; in a round nobody planned it is what stops `plan`
  being dereferenced when it is `null`.
- **The restore loop** (lines 722–733): add
  `depth: t.depth === 'direct' ? 'direct' : 'full',` to the object pushed for
  an increment an earlier session already closed, so every entry of the result
  carries a depth.
- **Per attempt**, right after `attempt` is computed (line 745), settle the
  depth once:
  ```js
  const depth = task.depth === 'direct' && attempt === 1 ? 'direct' : 'full'
  ```
  with a comment saying this is the one place the loop overrides the planner: a
  second attempt is `full` whatever the re-cut classified it as, so a
  misclassification cannot be repeated.
- **Per round** (line 784), replace the single `directFix` with three lines:
  ```js
  const directFix = round > 0 && isDirectFixRound(verdict)
  const directRound = round === 0 && depth === 'direct'
  ```
  and gate the research-and-tests block on `directFix || directRound`. Keep the
  existing `if (directFix)` log line exactly as it is; add an `else if
  (directRound)` log line that names the path, contains the word `direct`, and
  is prefixed like every other round line (`Increment ${n} round ${round}: `).
  Both branches still set `testsLabel = ''`.
- **The implementer dispatch** (line 853):
  - branch block: pass `directRound && freshBranch` as the `create` flag
    instead of `false`. On the direct path the implementer is the attempt's
    first dispatch, so it is the one that records the branch name into the
    state and creates the branch; without this the increment is worked on the
    issue branch, the reviewer's `git diff <issueBranch>...HEAD` is empty and
    the closing planner is told to merge a branch that does not exist. The
    researcher's own create flag stays `freshBranch && round === 0` — it is
    never dispatched in a direct round 0.
  - brief: add a third case ahead of the two that exist. For `directRound` the
    prompt carries `scope(task, increments, n)` (the criteria), then
    `codemapBlock()` (the map), then one sentence saying no researcher and no
    test-author worked this increment, so what stands above is its whole brief.
    It reads no step at all — no `readBlock`, no `steps` call, and not the
    "No test was written for this round" line, which belongs to the planned
    case. `directFix` and the planned case keep their current text unchanged.
  - `effort`: leave as it is (`directFix ? { effort: 'low' } : {}`). A direct
    increment is still a whole change, unlike a one-word finding; lowering
    effort for it was considered and rejected.
- **`worked.push`** (line 947): add `depth,`.
- Nothing else changes. `runOutcome()`, the publish prompt, the reviewer
  dispatch beyond its `checkList` argument, `MAX_*`, `isDirectFixRound` and the
  correction-round machinery all stay exactly as they are.

### 3. `agents/planner.md` — the bar, and its only owner

Add a section between `## The codemap` and `## Your brief`, headed
`## How deep the chain goes`, stating, once each and in the imperative:

- Every increment carries a chain depth, `full` or `direct`; set it on every
  increment of every cut and of every re-cut, and it travels both in the `init`
  payload and in the `increments` you return.
- `full` is the default and the answer whenever you hesitate.
- An increment is `direct` only when its criteria and the codemap already name
  the file, the place and the right result, so nothing is left to decide, and
  when nothing in it could be verified by a test that does not already exist.
- What `direct` buys and costs: round 0 is worked by the implementer and judged
  by the reviewer alone, so an increment you classify wrongly costs one
  implementer and one reviewer and is worked again in full.

Two existing passages have to move with it, or the page states two rules that
disagree:

- `## What you may not do`, the bullet "You do not decide anything about
  testing. That is the researcher's, per increment." — reword so the boundary
  survives the new section: what is tested inside a `full` increment stays the
  researcher's call, and the depth says how deep the chain goes, never what it
  tests.
- `## What you write`, the sentence "Every increment carries its id, title,
  what it delivers, its own acceptance criteria and its status" — add the
  chain depth to that list.

Use the exact phrase **chain depth** on this page, and on no other agent page
and in no shipped skill: a test pins that this page is its only owner.

### 4. `agents/implementer.md` — the second work order

Add a section after `## Direct-fix rounds`, headed `## An increment nobody
planned`, stating:

- Where your prompt names no researcher step to read, no researcher and no
  test-author worked this increment: the acceptance criteria in your prompt and
  the codemap the prompt sends you to are your whole brief.
- Build exactly those criteria, and write no test — you are not the role that
  decides one is needed, and none was planned.
- Where the criteria and the codemap leave a real decision open, build what
  they do settle and report the rest as a `blockers` entry; an increment worked
  this way that turns out to need a plan is a misclassification, and the review
  is what catches it.

Amend the frontmatter `description` so it is still true — it currently says the
prompt names the steps it reads and that those are its whole brief. One added
clause naming the case where the prompt names no researcher step is enough.
Do not use the phrase "chain depth" on this page (see above), and do not write
a bare `planner.md`/`researcher.md` anywhere on it — a repository test greps
agent pages for those.

### 5. `README.md` — the account of a run stays true

Not asked for by a criterion, and required by the plan: the README is the
project's description of how a run works, and the shape of a run changes
visibly. Keep it to two edits inside `## The backlog: the planner says what,
the researcher says how`:

- One paragraph after the paragraph that ends "…and the researcher says how."
  (line 131): the planner also says how deep the chain has to go for each
  increment — `full` by default, `direct` when the criteria and the codemap
  already name the file, the place and the right result and no test could catch
  anything — and a `direct` increment's first round is the implementer and the
  reviewer alone, judged by the commands the run's last researcher closed. A
  correction round leaves that path, and a second attempt is always `full`.
- Two lines in the second mermaid diagram (lines 139–147), added after the
  `BACK -->|"the first increment…"| CHAIN` edge:
  ```
      BACK -->|"an increment cut direct:<br/>no plan, no test"| SHORT["implementer → reviewer"]
      SHORT --> REPLAN
  ```

Write `agents/planner.md` with its directory prefix if you link it; the bare
filename trips a repository test.

## Technical decisions, including the rejected ones

- **The checks a direct increment is judged by are the run's last researcher
  step as the loop walks it**, held in `lastChecks` and updated on every
  researcher return, replayed returns included. Rejected: seeding `lastChecks`
  from the state index at startup. It buys no reachable behaviour — every
  research step the index still holds belongs to an open increment whose round
  replays it before any later increment runs — and a closed increment's steps
  are archived into `attempts`, which the index does not project and the STATE
  schema does not carry. So a run resumed behind a closed increment starts a
  direct increment with an empty list, which is exactly the case the criterion
  names: where the run holds none, the list is empty and the review is a
  reading. This mirrors what the direct-fix round already does with
  `plan.checks`.
- **The planner's `direct` governs round 0 only.** A correction round of a
  direct increment is an ordinary round: the full chain, unless the reviewer's
  own verdict says `allDirect`, which is the pre-existing mechanism the issue's
  problem statement praises and the non-goals leave untouched. Rejected:
  forcing a correction round of a direct increment to be full even when every
  finding is a direct fix — that would change the reviewer-driven path the
  issue explicitly keeps.
- **The loop, not the planner, forces `full` on a second attempt.** The planner
  is told to classify again on every re-cut, but the loop does not trust that
  for an increment it has already worked once: `attempt === 1` is part of the
  condition. Rejected: relying on the page alone, which would make the rule
  honour-system in exactly the case it exists for.
- **The direct implementer creates the increment branch.** Rejected: leaving
  the branch to the reviewer or to the planner, which would leave the diff the
  reviewer judges empty.
- **No new field in the publish prompt.** The criterion asks the run to say
  which path an increment took while it works and after it ends; the log line
  and the result's entry are both, and `runOutcome()` is neither.
- **No change to `hooks/read-barrier.mjs`.** The implementer's rule there gates
  `issue.md` and the `testPlan` field; the helper's `codemap` subcommand is
  neither a gated path nor a `steps` call, so the direct implementer's read of
  the codemap already passes. Do not "fix" the hook.

## Module map

| Path | What it holds | Entry points for this change |
| --- | --- | --- |
| `workflows/agile-loop.js` | The whole orchestration: schemas, prompt builders, the resume machinery, the increment loop. 1138 lines, no imports, run by the harness as an async function body with `args`, `agent`, `log`, `phase`. | head comment l.44–51; `STATE` l.134; `BACKLOG` l.182; `checkList` l.351; `codemapBlock` l.699; `worked`/restore loop l.712–733; increment loop l.736; round loop l.779–941; `directFix` l.784; implementer dispatch l.853–897; reviewer dispatch l.900–926; `worked.push` l.947 |
| `skills/agent-brief/assets/backlog.mjs` | The only writer and reader of `backlog.json`; a zero-dependency CLI with the subcommands `init`, `start`, `record`, `branch`, `close`, `index`, `steps`, `codemap`, `read`. | `shapeIncrement` l.123; `init` l.147; `index` l.402 |
| `agents/planner.md` | The planner's page: what an increment is, the codemap, its brief, what it may not do, what it writes, what it returns. | new section after `## The codemap` (l.68); `## What you may not do` l.106; `## What you write` l.122 |
| `agents/implementer.md` | The implementer's page: frontmatter, how it works, direct-fix rounds, boundaries, what it records. | frontmatter `description` l.3; after `## Direct-fix rounds` (ends l.58) |
| `README.md` | The public account of the loop, with two mermaid diagrams. | `## The backlog…` l.116–147 |
| `test-repo.sh` | The repository's own suite: bash cases plus an embedded `driver.js` heredoc (l.461–1124) that runs a workflow script with a stubbed `agent()` under a mode name, and a loop of `run_driver` calls (l.1136–1161). | driver fixtures l.509–728; mode assertions l.800–1112; `run_driver` list l.1138–1161 |
| `skills/agent-brief/assets/backlog.test.mjs` | The recorder's suite: helpers first, then flat `test(...)` calls grouped by CLI command. | `incrementPayload` l.120; init block l.130–252; index block l.689–777 |
| `skills/agent-brief/assets/CLAUDE.md` | That suite's doc — what it covers, its helpers, where a new case belongs. | "What the suite covers" paragraph |

Not touched, and deliberately: `agents/reviewer.md`, `agents/researcher.md`,
`agents/test-author.md`, `skills/agent-brief/SKILL.md`, `hooks/*`,
`rulebook.md`, `.claude-plugin/plugin.json`, `tools/*`.

## Environment

- **Shell:** `bash`. Both commands below are run from the repository root.
- **Runtime:** Node.js, with `node --test`. Every suite in the repository is
  zero-dependency; there is no `package.json` at the repository root and no
  install step is needed for either command below.
- **Linter, formatter, type checker:** there are none in this repository.
- `./test.sh` is the aggregate of every suite. It is not in the closed list
  below because this change touches nothing under `tools/`, `hooks/` or the
  worktree machinery those extra suites cover.
- `test-repo.sh` is run as `bash test-repo.sh`; it is not marked executable.
  It prints one `ok`/`FAIL` line per case and exits non-zero when any fails.

## Test plan

Tests are needed. The change is mechanical in three files and provable there:
the field survives a write and a read, and the loop dispatches a different set
of agents. The four criteria that live in prose — the planner's bar, the
implementer's second work order, and the README — get one structural case each
where a grep can catch a deletion, and are otherwise left to the review, which
is what reads prose.

### Cases, per acceptance criterion

**Criterion 1 — the planner returns a depth per increment, recorded beside it,
`full` the default.**

- *A1* `init` records an increment's depth and defaults everything that is not
  `direct` to `full`. Input: one `init` payload with three increments — one
  `depth: 'direct'`, one with no `depth` key, one `depth: 'shallow'`. Expected:
  the written file's increments carry `'direct'`, `'full'`, `'full'`.
- *A2* `index` carries each increment's depth, and reads a state written before
  the field existed as `full`. State: a `backlog.json` written directly with
  `fs.writeFileSync` holding two increments, one `depth: 'direct'`, one with no
  `depth` key at all. Expected: the index's increments project `'direct'` and
  `'full'`.
- Edge (empty/repeat): an increment list with no depth anywhere is A1's middle
  increment; the unknown value is A1's third. Covered.
- The schema half of this criterion — `BACKLOG` requiring `depth` back from the
  planner — is not unit-testable: the driver stubs `agent()` and never
  validates a schema. It is left to the review, which reads the diff.

**Criterion 8 — the planner classifies again on every re-cut.**

- *A3* A re-cut re-classifies: `init` a payload with an increment at
  `depth: 'direct'`, record a step against it, then `init` again with the same
  increment id and no `depth` key. Expected: the increment is still there with
  its recorded step, and its depth is `'full'` — the payload owns the depth,
  unlike `branch` and `attempts`, which the same case can assert survive.
- The other half of this criterion is the planner's page, covered by *P1*.

**Criteria 3 and 5 — round 0 of a `direct` increment, and the commands it is
judged by.**

- *W20* One increment, `depth: 'direct'`, review clean, no state. Expected
  labels, exactly:
  `['load-state','decompose','implement:i1.0','review:i1.0','replan:i1','publish']`.
  And on `implement:i1.0`: it carries `increment 1 is yours` and the criterion
  text `does i1`; it carries the codemap read
  (`codemap docs/issues/x/backlog.json`); it carries
  `git checkout -b issue-branch--i1` and the branch record
  (`branch docs/issues/x/backlog.json i1 issue-branch--i1`); it contains no
  `steps docs/issues/x/backlog.json` at all; it says
  `No command counts for this increment` and does not carry `CHECK-MARKER`.
  On `review:i1.0`: it also says `No command counts for this increment` and
  still names `git diff issue-branch...HEAD`. This is the empty-list edge of
  criterion 5.
- *W21* Two increments, `i1` `full` and `i2` `direct`, both reviews clean.
  Expected labels, exactly:
  `['load-state','decompose','research:i1.0','tests:i1.0','implement:i1.0','review:i1.0','replan:i1','implement:i2.0','review:i2.0','replan:i2','publish']`.
  And `implement:i2.0` and `review:i2.0` both carry `CHECK-MARKER` — the checks
  of the run's last researcher step, carried across an increment boundary.
- Not tested, and why: the resumed-run seeding of `lastChecks` from the state
  index, because there is no such seeding — see the decision above; and a
  direct increment whose researcher-less round asks the human, because
  `asksTheHuman` is untouched code on a path the existing w7 already pins.

**Criterion 6 — a finding leaves the direct path for the rest of the attempt.**

- *W22* One increment, `depth: 'direct'`, `review:i1.0` returns one finding
  with `allDirect: false`, later reviews clean. Expected labels, exactly:
  `['load-state','decompose','implement:i1.0','review:i1.0','research:i1.1','tests:i1.1','implement:i1.1','review:i1.1','replan:i1','publish']`.

**Criterion 7 — a handed-back increment is `full` on its next attempt.**

- *W23* One increment, `depth: 'direct'`; the closing planner hands it back as
  `todo` still carrying `depth: 'direct'` on the first replan and returns it
  `done` on the second — the same shape as the existing w12 fixture. Expected
  labels, exactly:
  `['load-state','decompose','implement:i1.0','review:i1.0','replan:i1','research:i1.0','tests:i1.0','implement:i1.0','review:i1.0','replan:i1','publish']`.
  Plus: the first attempt's `implement:i1.0` carries
  ``git checkout -b issue-branch--i1` `` (with the closing backtick, so it
  cannot match the take2 name — the trick w12 already uses) and the second
  attempt's `research:i1.0` carries `git checkout -b issue-branch--i1-take2`.
  The assertion that matters is that the depth in the fixture is still
  `direct` on the second pass, so a green case proves the loop overrode it.

**Criterion 9 — the run says which path each increment took.**

- Folded into *W20* and *W21*: in W20, `logs` holds a line matching
  `/Increment 1 round 0/` that contains the word `direct`; and
  `result.increments[0].depth === 'direct'`. In W21,
  `result.increments.map((w) => w.depth)` is `['full','direct']`.
- Not tested: the restored entry of an increment an earlier session closed
  carrying a depth. The existing w15 covers the restore path; adding a depth
  assertion to it is welcome but not required.

**Criteria 2 and 4 — the two pages.**

- *P1* `agents/planner.md` is the only owner of the phrase `chain depth`: a
  case-insensitive `grep -rl` over `agents/*.md` and `skills/*/SKILL.md`
  returns `agents/planner.md` and nothing else.
- *P2* `agents/implementer.md` names the `codemap` — the brief it works from
  when no researcher step is named. It names it nowhere today, so this case is
  red until the page is written.
- The wording of both sections beyond those two greps is prose, judged by the
  review. Say so rather than adding greps for sentences: a grep for a sentence
  fossilises the sentence.

**The default, unchanged behaviour.** Every existing driver mode (w1–w19) has
fixtures with no `depth` at all, so they are the standing proof that an
unclassified increment runs the full chain. They must all stay green
unmodified, apart from the two fixture helpers below.

### How each case runs

**W20–W23 — `test-repo.sh`, the embedded driver.**

- Level: integration against the real workflow script. `driver.js` reads
  `workflows/agile-loop.js`, strips the `export` from `meta`, compiles the body
  with `new AsyncFunction('args','agent','log','phase', src)` and runs it with a
  stubbed `agent()` that records `{label, agentType, prompt}` and returns a
  fixture per label. Nothing else is faked; nothing touches the filesystem.
- Framework: none. Plain Node, `assertTrue`/`assertEqualArrays` defined at the
  top of the heredoc, failures collected into `failures` and printed on exit 1.
- Where each piece goes:
  - `contextFor(mode)` (l.674–728) gains a `case 'w20':` … `case 'w23':` entry
    returning `{ stateReturn: noState, decomposeReturn: …, researchReturn: planReturn }`,
    plus `verdictFor` for w22 and `closeFor` for w23, modelled on w10 and w12.
  - `increment(id)` (l.539) gains an optional second argument for the depth and
    defaults to `'full'`, so every existing call site is unchanged.
  - `idxIncrement` (l.564) gains `depth: 'full'` in its defaults, overridable
    through `extra`.
  - The mode's assertions go in the `else if (mode === 'wNN')` chain
    (l.800–1112), in mode order, after the `w19` block.
  - One `run_driver "$wf" wNN "$wf_name: <sentence>"` line per mode goes in the
    `for wf in …` loop at l.1138–1155 — all four modes are agile-loop's alone,
    but so is every mode in that loop today; keep them there rather than beside
    w12/w15 unless a mode needs the `agile-loop.js`-only placement.
- Naming: the third argument of `run_driver` is a lowercase declarative
  sentence, prefixed by the script name — e.g.
  `"$wf_name: an increment the planner cut direct is worked by the implementer and the reviewer alone"`.
  Every assertion message states what went wrong, not what was expected.
- Markers: use the existing `CHECK_MARKER`. If a new marker string is needed,
  add it to `DISJOINT_MARKERS` (l.484) — a standing case asserts no marker
  contains another.
- Command that runs just these: `bash test-repo.sh` (there is no way to run a
  single case; it is a few seconds).

**P1, P2 — `test-repo.sh`, a bash block.**

- Add one `echo` heading block near the existing
  `=== the run state is the channel…` group, holding the two `ok`/`no` cases.
  Follow the surrounding style: a comment saying why the case exists, then an
  `if … then ok … else no … fi`. P1 mirrors the existing `rulebook_readers`
  case at l.185 — collect the matching files into a variable and require it to
  hold exactly `agents/planner.md`.
- Command: `bash test-repo.sh`.

**A1, A2, A3 — `skills/agent-brief/assets/backlog.test.mjs`.**

- Level: unit, but nothing is mocked — every case spawns the real CLI with
  `run([...])` (`execFileSync`, `cleanEnv()`) against real files in a fresh
  `tmpDir()`, and asserts on the file bytes or on parsed stdout.
- Framework: `node:test` with `node:assert/strict`.
- Placement: A1 and A3 go inside the init block (after the case at l.161 that
  covers the merge rules, before the codemap cases at l.194); A2 goes inside
  the index block (after l.689's projection case). That is the file's rule —
  a new case sits in the block for the command it exercises.
- Helpers to reuse: `tmpDir()`, `writeJson(dir, name, value)`,
  `backlogTemplate(increments)`, `incrementPayload(id, title, extra)` — spread
  `{ depth: 'direct' }` through `extra` — `run(args)`. A2 writes its state file
  with `fs.writeFileSync(path.join(dir,'backlog.json'), JSON.stringify(state))`
  directly, because the point of the case is a file `init` never shaped.
- Naming: lowercase declarative sentences leading with the command name, no
  "should", no numbering — e.g.
  `'init records an increment's chain depth and defaults anything that is not "direct" to full'`.
  Assertion messages carry the why.
- Command that runs just this file:
  `node --test skills/agent-brief/assets/backlog.test.mjs`.
- The suite doc `skills/agent-brief/assets/CLAUDE.md` is part of this work: add
  the depth to its "What the suite covers" paragraph, in the init and index
  clauses where the rest of the shape is enumerated.

### What counts as done

Run exactly these two, from the repository root:

```
bash test-repo.sh
node --test skills/agent-brief/assets/backlog.test.mjs
```

Nothing else. Not `./test.sh`, not the `tools/` suites, not
`test-worktree.sh` — this change touches none of the code they cover.

### What is already red

I ran no command, not once and not as a baseline. From reading, both commands
above pass on the current tree, and after the test-author's work and before the
implementer's, exactly the new cases are red: A1, A2, A3 in the recorder suite,
and W20–W23, P1 and P2 in `test-repo.sh`. Every pre-existing case in both files
must still pass at the end — in particular the driver's standing assertions that
no prompt reads a step without `--fields`, that no implementer prompt is told to
read `issue.md`, and w5's assertion that a *planned* implementer round is not
sent to the codemap.

## Round 1

Two findings, both in `workflows/agile-loop.js`, both fixed by changing when the
loop treats a round as direct. No page, no README, no `backlog.mjs`, no schema
of the recorder changes. This section is the whole work order for this round:
the sections above are how the change got here, not something to do again.

### Implementation plan

#### Finding 1 — a correction round of a `direct` increment always runs the full chain

Criterion 6 gives no exception for a verdict whose findings are all direct
fixes, so the attempt-level depth has to beat the verdict. At
`workflows/agile-loop.js:802`, replace

```js
const directFix = round > 0 && isDirectFixRound(verdict)
```

with

```js
const directFix = round > 0 && depth !== 'direct' && isDirectFixRound(verdict)
```

`depth` is the attempt's depth, settled at line 763, so this reads: an increment
this attempt is working direct leaves the direct path the moment a review files
anything, whatever the verdict says about the findings.

Rewrite the two comments that sit around those lines, because one of them
states the decision this finding reverses:

- The comment above `directFix` (l.799–801) keeps its point that the round
  before's verdict is what decides, and gains the new clause: an increment the
  planner cut direct is never a direct-fix round, because a review that files
  anything against it has already shown the classification was wrong.
- The comment above `directRound` (l.803–805) currently says "a correction round
  of a direct increment is an ordinary round unless the reviewer's verdict makes
  it a direct-fix one". Replace that clause: the planner's classification governs
  round 0, and every later round of that attempt is a full round — the
  reviewer-driven fast path stays open to increments the planner cut `full`.

Nothing else in the round moves. `isDirectFixRound` keeps its meaning and its
callers, the direct-fix implementer brief and its `{ effort: 'low' }` stay as
they are, and w16 — a `full` increment whose review returns `allDirect` — must
stay green, because that is the path the issue's non-goals keep.

#### Finding 2 — a hand-back the state remembers forces `full` across a restart

The session-local attempt counter cannot see an attempt an earlier session
closed, so the depth override needs a signal that survives the restart. The
recorder already computes one: `index` projects `attempts:
(increment.attempts || []).length` per increment
(`skills/agent-brief/assets/backlog.mjs:423`), which is how many attempts
`close` has archived for that increment. A `todo` increment with a non-zero
count is exactly an increment handed back after a failed attempt. Three edits,
all in `workflows/agile-loop.js`:

1. **`STATE`, `increments.items` (l.148–162).** Add `attempts: { type:
   'integer' },` after `steps` in `properties`, and `'attempts'` at the end of
   `required`. Give it no description — its neighbours in this schema, `depth`
   included, carry none, and the array's own description already says the items
   are the index's increments verbatim.
2. **A map beside `branches` (after l.573).** Seed, from the same loop or a
   second one over `savedIndex.increments`, a `const closedAttempts = new Map()`
   holding the count for every increment whose `attempts` is a positive number.
   Comment it in the file's voice: what it holds is how many attempts the state
   says this increment has already closed, and it exists for one decision only —
   an increment that has closed an attempt is never worked direct again, however
   the re-cut classified it.
3. **The depth line (l.758–763).** Extend the condition:
   ```js
   const depth =
     task.depth === 'direct' && attempt === 1 && !closedAttempts.get(task.id) ? 'direct' : 'full'
   ```
   and extend its comment: the session counter catches a hand-back inside one
   session, the archived count catches one across a restart, and between them a
   second attempt is never direct.

Then correct the head comment at l.64–69, which now contradicts the code. Its
clause "closing an increment ends its attempt in the state, so nothing there
counts attempts" is false once the loop reads that count: keep `MAX_ATTEMPTS`
session-local and keep the sentence that a restart granting one more attempt is
cheaper than a budget kept in the file, but say that the count the index does
carry is read for one thing only — never working an increment direct twice.

### Technical decisions, including the rejected ones

- **The archived attempt count, not the branch name, is the restart signal.**
  `nextBranchName` also knows a later attempt is starting, and the reviewer's
  finding names it. Rejected: the branch machinery only runs when the state
  loader named an issue branch (`workflows/agile-loop.js:521, 779`), so a run
  on a checkout with no issue branch would silently lose the rule; and it would
  make branch naming, which is about collisions on the remote, the carrier of a
  rule about chain depth.
- **A map keyed by id, seeded once at startup, not `task.attempts` read off the
  increment.** The increment object is replaced by the planner's returned
  `increments` on every re-cut (l.1035–1037), and that object cannot carry
  `attempts` — `BACKLOG` forbids it with `additionalProperties: false`. The map
  survives that, exactly as `branches` does.
- **`MAX_ATTEMPTS` stays session-local.** Seeding the `attempts` counter itself
  from the archived count was rejected: it would change the backstop's budget
  across a restart, which the head comment settles deliberately and which no
  criterion of this issue asks for.
- **An increment that closed an attempt is forced `full` whatever it closed
  as.** A `done` increment a later re-cut re-opens as `todo` is thereby full
  too. Rejected: keying on the status the attempt closed with, which would add a
  field to the index for a case worth nothing — `full` is the default the whole
  change leans on, and being conservative here costs at most one increment's
  chain.
- **Nothing outside the loop changes.** `README.md` already says "A correction
  round leaves that path, and a second attempt at an increment is always
  `full`", and `agents/planner.md`'s `## How deep the chain goes` already says
  a misclassified increment "is worked again in full afterwards". Both describe
  the behaviour after this round, so do not edit them. `agents/implementer.md`,
  `agents/reviewer.md`, `skills/agent-brief/assets/backlog.mjs` and its suite
  doc are untouched.

### Module map

| Path | What it holds | Entry points for this round |
| --- | --- | --- |
| `workflows/agile-loop.js` | The whole orchestration: schemas, prompt builders, the resume machinery, the increment loop. Run by the harness as an async function body with `args`, `agent`, `log`, `phase`. | head comment l.64–69; `STATE` increments items l.148–162; `branches` seed l.565–573; `incrementHasHistory` l.580; per-attempt depth l.758–763; `directFix`/`directRound` l.797–806 |
| `skills/agent-brief/assets/backlog.mjs` | The only writer and reader of `backlog.json`. Read-only for this round: `index` at l.406 already projects `attempts` as a count, and `close` at l.346–349 is what increments it. | nothing to change |
| `test-repo.sh` | The repository's suite: bash cases plus an embedded `driver.js` heredoc (l.485–1254) that compiles `workflows/agile-loop.js` with `new AsyncFunction` and runs it against a stubbed `agent()` under a mode name, then a list of `run_driver` calls (l.1266–1294). | `idxIncrement` l.593–608; state builders l.620–700; `contextFor` l.702–783; mode chain, after the `w23` block that ends l.1239; `run_driver` list l.1266–1289 |

### Environment

- **Shell:** `bash`, run from the repository root.
- **Runtime:** Node.js. The suite is zero-dependency; there is no `package.json`
  at the repository root and no install step.
- **Linter, formatter, type checker:** there are none in this repository.
- `test-repo.sh` is not executable; it is run as `bash test-repo.sh`. It prints
  one `ok`/`FAIL` line per case and exits non-zero when any case fails. There is
  no way to run a single driver mode through it; the whole file takes a few
  seconds.
- `node --test skills/agent-brief/assets/backlog.test.mjs` is not part of this
  round: no file that suite covers changes.

### Test plan

Tests are needed. Both findings are a behaviour of the loop on a path no case
walks, and both are provable by the driver that already models this loop.

#### What, per finding

**Finding 1 — criterion 6, the `allDirect` edge.**

- *W24* One increment, `depth: 'direct'`. `review:i1.0` returns the
  all-direct-findings verdict; every later review is clean. Expected: the
  correction round runs the full chain — researcher, test-author, implementer,
  reviewer — and the round-1 implementer works from the plan, not from the
  findings.
- Edges: the `allDirect` verdict is the only one criterion 6 has left untested
  (`allDirect: false` is w22, already in the tree). The
  round-2-and-beyond repeat is not tested separately: `depth !== 'direct'` is
  round-independent, and w17 already pins that an increment burns all its
  correction rounds.
- Untested by decision: that a `full` increment still takes the
  reviewer-driven direct-fix path. w16 pins it already and must stay green.

**Finding 2 — criterion 7, across a restart.**

- *W25* A resumed run whose state holds one open increment classified
  `direct`, with the abandoned branch of a failed attempt, one archived attempt
  and no current step — the shape `close` leaves after the planner hands an
  increment back. Expected: the increment is worked full from round 0, on a
  fresh `-take2` branch, and its entry in the result carries `full`.
- Edges: the count is read as "any non-zero", so a second restart needs no case
  of its own. The live-session hand-back is w23, already in the tree.
- Untested by decision: that the state loader actually returns `attempts` for
  each increment. The driver stubs `agent()` and validates no schema, so the
  `STATE` addition is unreachable from a test — the same gap the earlier round
  recorded for `BACKLOG`'s `depth`, and it is the review that reads it.

#### How, per case

Both cases are integration cases against the real workflow script, in the
`driver.js` heredoc inside `test-repo.sh`. Level: the whole script, compiled
from source and run with a stubbed `agent()` that records `{label, agentType,
prompt}` and answers per label. No framework: `assertTrue` and
`assertEqualArrays` are defined at the top of the heredoc, failures are
collected and printed on exit 1. Nothing touches the filesystem, and no fixture
carries a plan, a test plan or a finding — only the steering values a return
holds. Every assertion message says what went wrong, not what was expected.

**Shared fixture changes**, before either case:

- `idxIncrement` (l.593–608): add `attempts: 0` to the defaults, overridable
  through `extra`, in the position the index prints it — after `steps`. Every
  existing call site stays unchanged.
- Add nothing to `DISJOINT_MARKERS`: neither case needs a new marker.

**W24** — mode `w24`.

- `contextFor` gains, after `case 'w23'`:
  ```js
  case 'w24':
    return { stateReturn: noState, decomposeReturn: decomposeReturnDirect, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithDirectFinding : verdictReturnClean) };
  ```
  It is w22 with w16's verdict fixture. Add a comment above it saying the case
  is the `allDirect` edge of a direct increment: the verdict that would open the
  fast path for a `full` increment must not open it for this one.
- Assertions, in an `else if (mode === 'w24')` block after the `w23` block
  (l.1239), opened with a comment in the surrounding style stating why the case
  exists:
  - `assertEqualArrays(labels, ['load-state', 'decompose', 'implement:i1.0', 'review:i1.0', 'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'], …)`
    with a message along the lines of "a direct increment whose review filed
    findings that are all direct fixes did not run the full chain in its
    correction round".
  - `research:i1.1` exists and its prompt includes
    `readStep('i1', 'review:i1.0', 'findings')`.
  - `implement:i1.1` exists and its prompt includes
    `readStep('i1', 'research:i1.1', 'plan,moduleMap,environment')` — the
    planned brief, not the direct-fix one.
- `run_driver "$wf" w24 "$wf_name: a direct increment whose review files only direct fixes still runs the full chain in its correction round"`,
  added to the `for wf in` loop (l.1266–1289) after the `w23` line.

**W25** — mode `w25`.

- A new state builder beside the others (l.620–700), with a comment saying what
  it models: the state a hand-back leaves once the session that made it is
  gone — `close` archived the attempt's steps, so the increment is open with no
  current step, one closed attempt and the abandoned branch still recorded, and
  the session's own counter starts at zero again.
  ```js
  const handedBackState = () =>
    stateOf(
      [idxIncrement('i1', { depth: 'direct', branch: 'issue-branch--i1', attempts: 1 })],
      [idxStep('decompose', decomposeReturnDirect)],
    );
  ```
- `contextFor` gains
  ```js
  case 'w25':
    return { stateReturn: handedBackState(), decomposeReturn: decomposeReturnDirect, researchReturn: planReturn };
  ```
- Assertions, in an `else if (mode === 'w25')` block after `w24`:
  - `assertEqualArrays(labels, ['load-state', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'], …)`
    with a message along the lines of "an increment whose earlier attempt the
    state archived was worked direct again after the restart". `decompose` is
    absent because the state's `runSteps` hold it and it replays, as in w15.
  - `research:i1.0` exists and its prompt includes
    `git checkout -b issue-branch--i1-take2` — the second attempt's fresh
    branch, so the case shows the run knew it was a later attempt while it
    classified.
  - `result.increments[0].depth === 'full'`.
- `run_driver "$wf" w25 "$wf_name: an increment the state shows as having already closed an attempt is full again after a restart"`,
  added after the `w24` line.

Change no existing case, no existing fixture beyond `idxIncrement`'s new
default, and no bash block. w16, w20, w21, w22, w23, P1 and P2 stay exactly as
they are and stay green.

#### What counts as done

Run exactly this, from the repository root:

```
bash test-repo.sh
```

Nothing else. Not the recorder suite, not `./test.sh`, not the `tools/` suites,
not `test-worktree.sh` — this round changes one production file, and the driver
inside `test-repo.sh` is what covers it.

#### What is already red

I ran no command this round, not once and not as a baseline. From reading, the
tree is green as the reviewer left it (69 cases, exit 0), and after the
test-author's work and before the implementer's exactly W24 and W25 are red:
W24's label array comes back as
`['load-state','decompose','implement:i1.0','review:i1.0','implement:i1.1','review:i1.1','replan:i1','publish']`
because the correction round takes the direct-fix path, and W25's comes back as
`['load-state','implement:i1.0','review:i1.0','replan:i1','publish']` because
the restarted attempt is still classified direct. Every other case in
`test-repo.sh` must be green before the change and after it.
