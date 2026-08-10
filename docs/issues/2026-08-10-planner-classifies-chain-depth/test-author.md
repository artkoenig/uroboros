# Test author — the planner classifies each increment's chain depth

I wrote every case the researcher's test plan named, in the files and the
style it named, and no others. Production code was not opened; I read
`skills/agent-brief/assets/backlog.mjs` once by accident (a stray `Read` call
issued in parallel with an `Edit`, offset 380–420, `index()` and
`indexStep()`), caught it, and wrote A2 from the test plan's own description
and the existing test file's conventions rather than from anything that read
told me — worth flagging in case the researcher wants to know a slip happened,
even though nothing in A1–A3 depends on it.

## Cases, per acceptance criterion

**Criterion 1 — the planner returns a depth per increment, recorded beside
it, `full` the default.**

- *A1* → `skills/agent-brief/assets/backlog.test.mjs`, test
  `"init records an increment's chain depth and defaults anything that is not
  \"direct\" to full"` (inserted after the merge-rules case, before the
  codemap cases, per the plan's placement rule). Failure when run stand-alone:
  `a payload that names depth: "direct" is recorded as direct — expected
  'direct' got undefined` (assertion on `backlog.increments[0].depth`).
- *A2* → same file, test `"index projects each increment's chain depth, and
  reads a state written before the field existed as full"` (inserted after
  the projection case in the index block, per the plan's placement rule).
  State written directly with `fs.writeFileSync`, one increment `depth:
  'direct'`, one with no `depth` key. Failure: `the index projects a recorded
  direct depth — expected 'direct' got undefined`.
- *A3* → same file, test `"a re-cut re-classifies an increment's chain depth,
  unlike its branch and its attempts which the payload does not own"`.
  Failure: `the payload owns the depth: a re-cut that carries no depth key
  resets it to full, unlike branch and attempts — expected 'full' got
  undefined`.
- The schema half of criterion 1 (the `BACKLOG` schema requiring `depth`
  back from the planner) is not unit-testable, as the plan says — left to the
  review.

All three ran together via `node --test
skills/agent-brief/assets/backlog.test.mjs`: 52 cases, 49 pass, 3 fail (A1, A2,
A3), exit 1. Every pre-existing case in the file still passes.

**Criterion 8 — the planner classifies again on every re-cut.** Covered by
*A3* above. The page half of this criterion is *P1* below.

**Criteria 3 and 5 — round 0 of a `direct` increment, and the commands it is
judged by.**

- *W20* → `test-repo.sh`, driver mode `w20`, case line `"agile-loop.js: an
  increment the planner cut direct is worked by the implementer and the
  reviewer alone"`. Exact label array asserted, plus every sub-assertion the
  plan lists on `implement:i1.0` and `review:i1.0` (increment-is-yours text,
  criterion text, codemap read, branch creation and recording, no `steps`
  read at all, `No command counts for this increment` on both, no
  `CHECK-MARKER`), plus the criterion-9 folding (a log line matching
  `/Increment 1 round 0/` containing `direct`, and
  `result.increments[0].depth === 'direct'`).
- *W21* → driver mode `w21`, case line `"agile-loop.js: a full increment and
  a direct increment each take their own path, the direct one judged by the
  run's last researcher step"`. Exact label array for two increments (`i1`
  full, `i2` direct), plus `CHECK-MARKER` on `implement:i2.0` and
  `review:i2.0`, plus the criterion-9 folding
  (`result.increments.map(w => w.depth) === ['full','direct']`).
- Not tested, per the plan: resumed-run seeding of `lastChecks` from the state
  index (no such seeding exists by design) and a direct round's own
  `asksTheHuman` path (covered already by the untouched w7 mechanism). I wrote
  nothing for either, matching the plan's own "not tested, and why".

Failure output for W20 (representative — the full list of sub-failures is in
the run below):
```
an increment the planner cut direct did not skip exactly the researcher and the
test-author in round 0 — expected
["load-state","decompose","implement:i1.0","review:i1.0","replan:i1","publish"]
got
["load-state","decompose","research:i1.0","tests:i1.0","implement:i1.0","review:i1.0","replan:i1","publish"]
```
(plus ten more sub-assertions failing on the same run, all for the same
missing-behaviour reason — the direct path does not exist yet, so the loop
still dispatches the full chain.)

Failure output for W21:
```
a full increment followed by a direct increment did not each take their own
path — expected [...,"implement:i2.0","review:i2.0","replan:i2","publish"] got
[...,"research:i2.0","tests:i2.0","implement:i2.0","review:i2.0","replan:i2","publish"]
the run's result does not carry each worked increment's own chain depth —
expected ["full","direct"] got [null,null]
```

**Criterion 6 — a finding leaves the direct path for the rest of the
attempt.**

- *W22* → driver mode `w22`, case line `"agile-loop.js: a direct increment
  whose review files a finding leaves the direct path for the rest of its
  attempt"`. Exact label array only, as the plan specifies. Failure:
```
a direct increment whose review files a finding did not leave the direct path
for the rest of its attempt — expected
["load-state","decompose","implement:i1.0","review:i1.0","research:i1.1","tests:i1.1","implement:i1.1","review:i1.1","replan:i1","publish"]
got
["load-state","decompose","research:i1.0","tests:i1.0","implement:i1.0","review:i1.0","research:i1.1","tests:i1.1","implement:i1.1","review:i1.1","replan:i1","publish"]
```

**Criterion 7 — a handed-back increment is `full` on its next attempt.**

- *W23* → driver mode `w23`, case line `"agile-loop.js: an increment the
  planner cut direct and handed back after a failed attempt is full on its
  next attempt"`. Exact label array, plus the two branch-naming assertions the
  plan calls out (first attempt's `implement:i1.0` carries the
  base-named-branch checkout with the closing backtick, second attempt's
  `research:i1.0` carries the `-take2` branch). Failure:
```
an increment the planner cut direct and then handed back was not worked full on
its second attempt — expected
["load-state","decompose","implement:i1.0","review:i1.0","replan:i1","research:i1.0","tests:i1.0","implement:i1.0","review:i1.0","replan:i1","publish"]
got
["load-state","decompose","research:i1.0","tests:i1.0","implement:i1.0","review:i1.0","replan:i1","research:i1.0","tests:i1.0","implement:i1.0","review:i1.0","replan:i1","publish"]
the first attempt's direct implementer is not told to create the base-named
branch
the second attempt's researcher is not sent to a fresh take2 branch, so the
loop did not force the increment full despite the still-direct fixture
```

**Criterion 9 — the run says which path each increment took.** Folded into
*W20* and *W21* exactly as the plan directs; no separate case. The restore-path
depth on w15 was left untouched, as the plan marks optional and not required.

**Criteria 2 and 4 — the two pages.**

- *P1* → `test-repo.sh`, new bash section `=== the planner alone owns the
  chain depth it decides`, first block: `grep -lie 'chain depth'` over
  `agents/*.md` and `skills/*/SKILL.md`, asserting the result is exactly
  `agents/planner.md`. Failure today: the grep returns nothing (`(none)`),
  because the section does not exist yet on any page —
  `FAIL — the phrase "chain depth" is owned by more (or fewer) pages than
  agents/planner.md alone: (none)`.
- *P2* → same section, second block: `grep -qi 'codemap'
  agents/implementer.md`. Failure today: `FAIL — agents/implementer.md never
  names the codemap` — the page names it nowhere, as the plan predicted.
- The wording of both sections beyond these two greps is left to the review,
  as the plan directs; I added no further assertions.

## Fixture changes to the driver (test code, not production code)

Per the plan's instructions for W20–W23, I changed three driver helpers inside
the `test-repo.sh` heredoc (itself a test file, not production code):

- `increment(id, depth)` — optional second argument, defaults to `'full'`.
  Every existing call site (`increment('i1')`, `increment('i2')`) is
  unchanged and still produces `depth: 'full'`.
- `idxIncrement(id, extra)` — gained `depth: 'full'` in its defaults,
  overridable through `extra`, same as every other field.
- Added `decomposeReturnDirect` (one increment, `i1` direct) and
  `decomposeReturnMixed` (`i1` full, `i2` direct) beside the existing
  `decomposeReturnOne`/`Two`.
- Added `case 'w20'` through `case 'w23'` to `contextFor`, modelled on `w10`
  (a `verdictFor` that fires a finding on `review:i1.0` alone, for w22) and
  `w12` (a `closeFor` that hands the increment back once and closes it done
  the second time, for w23 — with the increment kept `depth: 'direct'` in
  both returns, since the point of the case is that the loop overrides it
  regardless of what the fixture still says).

## Command run

```
bash test-repo.sh
```
69 cases, 63 ok, 6 FAIL (the six new cases above), exit 1. Every case that
existed before this round — w1–w19, w12, w15, and every standing bash
check — still passes.

```
node --test skills/agent-brief/assets/backlog.test.mjs
```
52 cases, 49 pass, 3 fail (A1, A2, A3), exit 1. Every case that existed before
this round still passes.

## Gaps and conflicts found in the plan

None. The plan's expected label arrays, prompt substrings and placement rules
were all followed literally and matched the driver's actual behaviour on the
unmodified tree (every new case is red only on the missing `direct`-path
behaviour, never on a driver-fixture mistake — I confirmed this by running the
suite after each fixture change before writing the mode's own assertions).
The one thing worth the researcher's attention is the accidental read of
`backlog.mjs` noted above: it changed nothing about what I wrote, but it is a
process gap on my side rather than a plan gap, so I am recording it rather
than silently absorbing it.
