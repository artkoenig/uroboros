# Test-author handoff — a hook enforces the barriers the pages only ask for

## Round 1

Wrote the whole test plan from `researcher.md`: `hooks/read-barrier.test.mjs`
(26 cases), the `## Tests for read-barrier.mjs` section of `hooks/CLAUDE.md`,
and the `=== the read barrier is wired, and decides from the payload alone`
section of `test-repo.sh` (R1-R5). Never opened `hooks/backlog-changed.mjs`'s
sibling under-test file `read-barrier.mjs` — it does not exist yet — and read
no production code beyond what the researcher's plan itself quoted.

### `hooks/read-barrier.test.mjs`

Command: `node --test hooks/read-barrier.test.mjs`, run from the repository
root. Result: 26 tests, 0 pass, 26 fail, exit code 1. Every failure is the
same shape — the hook does not exist yet, so the spawn itself fails, not an
assertion inside the test:

```
error: 'spawn /home/user/uroboros/hooks/read-barrier.mjs ENOENT'
code: 'ENOENT'
```

That is the intended red: a missing file, not a typo in the test. Case by
case, each became the test named below, and every one is currently red with
the `ENOENT` above (I list the failure once per case rather than repeating the
identical stack trace 26 times):

1. `a Read of the issue file by the implementer is refused, and the reason names the file and the page` — `readOf('uroboros:implementer', ISSUE)` → `denies(result, ISSUE, 'agents/implementer.md')`.
2. `a cat of the issue file is refused like the Read, with the relative path resolved against the event cwd` — `bashOf('uroboros:implementer', 'cat docs/issues/2026-01-01-a-thing/issue.md')`, `cwd: '/repo'` is `event`'s default → denies, reason contains `issue.md`.
3. `the researcher reading the same issue file passes` — `readOf('uroboros:researcher', ISSUE)` → `allows`.
4. `the test-author reading the same issue file passes` — `readOf('uroboros:test-author', ISSUE)` → `allows`.
5. `the reviewer is refused every reading subcommand of the helper on the run state` — loops `index`, `steps … --fields findings`, `codemap`, `read`, each `bashOf('uroboros:reviewer', helper(...))` → denies with `backlog.json` and `agents/reviewer.md`; a failure in the loop is rethrown with the subcommand's name folded into the message.
6. `the reviewer's own start and record on the run state pass — the gate is on reads, not writes` — `helper('start …')` and `helper('record …')` → `allows` for both.
7. `a cat of the run state by the reviewer is refused` — `bashOf('uroboros:reviewer', 'cat ' + STATE)` → denies.
8. `a git show of the run state at a revision by the reviewer is refused` — `bashOf('uroboros:reviewer', 'git show origin/main:…/backlog.json')` → denies.
9. `staging and committing the run state by the reviewer passes` — `bashOf('uroboros:reviewer', 'git add … && git commit …')` → `allows`.
10. `a Grep whose path is the run state is refused for the reviewer, and one on a source file passes` — `grepOf('uroboros:reviewer', STATE)` denies; `grepOf('uroboros:reviewer', '/repo/hooks/read-barrier.mjs')` allows.
11. `the implementer running the helper's index on the run state passes — only the reviewer's page closes that file` — `bashOf('uroboros:implementer', helper('index ' + STATE))` → `allows`.
12. `the test-author asking for the researcher's plan field is refused, and the reason names the field and the page` — `--fields plan` → `denies(result, 'plan', 'agents/test-author.md')`.
13. `the test-author asking for the test plan alone passes` — `--fields testPlan` → `allows`.
14. `a forbidden field anywhere in the list is refused` — `--fields testPlan,plan` → denies.
15. `the implementer asking for the test plan is refused, and the three fields its page names pass` — `--fields testPlan` denies with `agents/implementer.md`; `--fields plan,moduleMap,environment` allows.
16. `a steps call with no --fields by a role with a closed field is refused, and the reason names --fields` — `steps … research:i1.0` with no `--fields`, test-author → `denies(result, '--fields', 'agents/test-author.md')`.
17. `a steps call with no --fields by the planner passes — no field is closed to it` — `bashOf('uroboros:planner', helper('steps ' + STATE + ' i1'))` → `allows`.
18. `which step a prompt named is not in the payload, so the label never decides` — implementer reading `research:i1.0 --fields plan,moduleMap,environment` and `review:i1.0 --fields findings`, both `allows`.
19. `a field on no page's list passes for every gated role` — `--fields cases` for the implementer, `--fields openQuestions` for the test-author → both `allows`.
20. `an event with no agent_type passes without a word` — a `Read` of `ISSUE` with `agent_type` deleted → `allows`, `stderr === ''`.
21. `the state loader's general-purpose read of the index passes without a word` — `bashOf('general-purpose', helper('index ' + STATE))` → `allows`, `stderr === ''`.
22. `an agent type that is not uroboros's passes without a word` — `readOf('Explore', ISSUE)` and `readOf('reviewer', STATE)` → both `allows`, both `stderr === ''`.
23. `a tool the hook does not gate passes` — implementer with `tool_name: 'Write'` then `'Edit'`, `tool_input: { file_path: ISSUE }` → both `allows`, `stderr === ''`.
24. `a Bash call the hook cannot positively identify as a read passes` — implementer running the `node -e` `readFileSync` one-liner, and separately `bash test.sh` → both `allows`.
25. `an input the hook cannot use passes and still exits 0` — the eight-entry table (`''`, `'not json at all'`, `'{}'`, `'[]'`, `tool_input` missing, `tool_input: null`, `tool_input: { command: 12345 }`, `tool_input: { file_path: ['a', 'b'] }`) → `allows` for every entry, a failing entry's name folded into the assertion message.
26. `a refusal is a PreToolUse deny decision on stdout and nothing else, and the process still exits 0` — re-runs case 1's exact call (`readOf('uroboros:implementer', ISSUE)`, deterministic, so this stands in for "take case 1's result" without depending on test execution order) → asserts `Object.keys` of the parsed envelope is exactly `['hookSpecificOutput']`, its three fields are `PreToolUse`, `deny`, and a non-empty string, and `code === 0`.

Small things the plan left to me, decided in its own style:
- `allows(result, context)` takes an optional second parameter folded into
  its assertion messages, so the loops in cases 5, 22, 23, 24 and 25 can name
  which sub-call failed without a second helper. `denies` stayed exactly the
  fixed `(result, ...substrings)` signature the plan gives it; case 5's loop
  gets its subcommand into the message by catching and rethrowing rather than
  changing that signature.
- Case 26 re-issues case 1's call rather than sharing a variable across two
  `test()` blocks — `node:test` cases are independent and the call is
  deterministic, so this is the same result the literal wording asks for.

### `hooks/CLAUDE.md`

Added `## Tests for read-barrier.mjs` immediately after the existing
`## Tests for backlog-changed.mjs` section, with the same five subsections
that one uses (what the suite covers, helpers and fixtures, where a new case
belongs, faked vs real, running it). Left the file's opening paragraphs
("The plugin's two hooks…") untouched — that prose is the implementer's, per
the module map.

### `test-repo.sh`

Added the `=== the read barrier is wired, and decides from the payload alone`
section, placed after `=== the collector is reached from the hook and from
nowhere else` and before `=== the run state is the channel …`, five numbered
cases in the file's `ok`/`no` style. Ran `bash test-repo.sh` from the
repository root: exit 1, `FAIL: 4 of 62 cases`, and the four failures are
exactly the new section's R1, R2, R3 and R5:

```
FAIL — hooks.json does not subscribe read-barrier.mjs to PreToolUse on Read, Bash and Grep — the barriers would be honour-system again
FAIL — hooks/read-barrier.mjs is missing or not executable, and hooks.json invokes it directly
FAIL — the read barrier does not parse (or does not exist)
FAIL — test.sh does not list the read barrier suite
```

R4 (`hooks/read-barrier.mjs opens no file and no connection`) reports `ok`
even now, before the hook exists — worth flagging as a gap in the plan, not
fixed by me: the case is `grep -qE "…" "$root/hooks/read-barrier.mjs" ` must
find nothing, and a `grep` against a file that does not exist at all also
finds nothing, so this specific check cannot be red on a missing file the way
R1, R2, R3 and R5 are. It is written exactly as the plan specifies and will
correctly catch a real violation once the file exists; it just is not part of
today's red signal. No other section of `test-repo.sh` regressed — the other
58 cases still pass.

`bash -n test.sh`: exit 0, syntax is clean. `test.sh` itself is not yet
edited to add the `hooks/read-barrier.test.mjs` run entry — that is the
implementer's module-map item, and R5 above is what currently catches its
absence.

### Gaps and conflicts found in the plan

- The R4 grep-on-a-missing-file behaviour above: not a defect in what I wrote,
  but the researcher's "the R1-R5 cases … will fail until the hook and the
  wiring exist" undersells R4 specifically. No change needed on my end; flagging
  for the record.
- No other gap or conflict. Every case in the test plan had a concrete,
  checkable expected outcome, and none contradicted the criterion it claimed
  to cover.

### What is NOT covered here (by the plan's own design)

The "Left untested, deliberately" paragraph of the plan — hook cheapness, that
Claude Code actually applies the deny, and `node -e`/`python -c`/`cd`-then-`cat`
as accepted fail-open holes — is honoured by omission: no case in the file
above tests any of those, and case 24 is exactly the plan's "pins one of them
as passing rather than pretending it is caught."

## Round 1

The reviewer's finding, and the researcher's Round 1 test plan for it, is the
whole work order: the workflow's resumed-implementer prompt orders a read
`hooks/read-barrier.mjs` refuses, and the human's answer never reaches the
step that asked. `hooks/read-barrier.mjs` itself is not edited this round, so
`hooks/read-barrier.test.mjs` is untouched. Everything below lives in
`test-repo.sh`'s driver heredoc, in the `=== a run resumes from the state it
recorded` section, and nothing else was opened or changed in the file. Read no
production code beyond what the researcher's plan itself quoted.

Command: `bash test-repo.sh`, run from the repository root. Result: exit 1,
`FAIL: 3 of 63 cases`, and the three failures are exactly the plan's Case 1,
Case 2 and Case 3 below (none of the other 60 cases regressed).

**Fixture changes**, all in the driver heredoc:
- `stateOf` takes a third argument, `decisions`, folded into the returned
  object as `decisions: decisions || ''`; `noState` gained `decisions: ''`.
- `DISJOINT_MARKERS` gained `'MARKER-BUILD-QUESTION'` and
  `'MARKER-HUMAN-ANSWER'`, after `'MARKER-CUT-QUESTION'`. The standing
  containment loop at the top of `main` covers them for free.
- `buildQuestionState`, a new fixture beside `questionState`, with the
  comment the plan asked for on why the implementer is the role the case is
  built on. Exactly as specified: `research:i1.0` and `tests:i1.0` recorded
  clean, `implement:i1.0` recorded with `questions: ['MARKER-BUILD-QUESTION']`,
  the run-level `decompose` recorded, and `'MARKER-HUMAN-ANSWER'` as the third
  `stateOf` argument.
- `contextFor` gained `case 'w19': return { stateReturn: buildQuestionState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };`,
  placed right after the `w17`/`w18` case and before `default`.
- The `for wf in ...` loop gained
  `run_driver "$wf" w19 "$wf_name: a resumed run hands the step that asked the human the answer in its prompt"`
  immediately after the `w18` line, inside the loop, exactly as the plan
  named it.

**Case 1 — the finding, as a new `w19` branch.** Added
`} else if (mode === 'w19') { ... }` in the driver's `if`/`else if` chain,
right after the `w18` branch and before the final `else { throw ... }`, with
the five assertions in the order the plan gave:
1. `assertEqualArrays(labels, ['load-state', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'], ...)`.
2. `implement:i1.0`'s prompt includes `MARKER-BUILD-QUESTION`.
3. `implement:i1.0`'s prompt includes `MARKER-HUMAN-ANSWER` — **the assertion
   the plan calls out as red today**, and it is: failure output is
   `"the repeated step's prompt does not carry the human's answer"`.
4. `assertTrue(!/## Decisions/.test(buildCall.prompt), ...)` — also red today:
   `"the repeated step is pointed at the ## Decisions heading instead of
   handed the answer"`.
5. `assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 0, ...)`.

Assertions 1 and 2 pass on the unmodified tree (labels and the carried
question already work); 3 and 4 fail. The run's own new third loop (Case 4,
below) also fires on this mode and reports the same underlying defect from a
different angle — its failure line is quoted there.

**Case 2 — the empty edge, folded into the existing `w9` branch.** Kept w9's
first assertion (`researchCall.prompt` carries `MARKER-HUMAN-QUESTION`) and
its last (`blockedOnHuman.length === 0`) untouched. Replaced the middle
assertion — the one that asserted `/## Decisions/` and `/issue\.md/` in the
researcher's prompt — with exactly the line the plan gives:
`assertTrue(!!researchCall && /The human recorded no answer/.test(researchCall.prompt), "the repeated step is not told that no answer came back, so it cannot tell an empty answer from a missing one");`.
Red today, with that exact message.

**Case 3 — the loader is asked for the section, in the existing `w1` branch.**
Added, immediately beside the existing loader assertions:
`assertTrue(!!loader && /## Decisions/.test(loader.prompt) && loader.prompt.includes('docs/issues/x/issue.md'), "the state loader is not asked for the human's answer under ## Decisions in issue.md, so a resumed step would have no route to it");`.
Red today, with that exact message — `w1`'s `load-state` prompt does not yet
ask for `decisions`.

**Case 4 — the standing guard, checked in every mode.** Added the third loop
the plan specifies, after the two that already run over every call, word for
word:

```js
  // `hooks/read-barrier.mjs` refuses the implementer every read of `issue.md`,
  // so a prompt that ordered one would order a call the hook denies and strand
  // the step mid-run. Checked in every mode.
  for (const c of calls) {
    if (!c.label.startsWith('implement:')) continue;
    const ordered = c.prompt.split('\n').filter((line) => /issue\.md/.test(line) && /\bread\b/i.test(line));
    assertTrue(ordered.length === 0,
      c.label + ' is told to read the issue file its page closes: ' + JSON.stringify(ordered));
  }
```

Green in every mode except `w19`, where it fails with the exact forbidden line
quoted back:
```
implement:i1.0 is told to read the issue file its page closes: ["The answer is under `## Decisions` in docs/issues/x/issue.md. Read it there first, then work this step again; ask again only what it does not answer."]
```
That is `w19`'s `answeredBlock` output on the unmodified tree — the loop finds
the exact prompt line the finding describes, not a stand-in for it.

### Gaps and conflicts found in this round's plan

None. Every case had a concrete, checkable expected outcome and none
contradicted the criterion it claimed to cover; the reviewer's reproduction
spec and the researcher's plan for it agree throughout.

### What was left alone

`rulebook.md`/`GEMINI.md` and the five `agile-loop.js` edits are the
implementer's, per the module map. `hooks/read-barrier.mjs` and
`hooks/read-barrier.test.mjs` are untouched — the plan is explicit that this
round does not touch the hook and that its suite is off this round's "what
counts as done" list. `bash test.sh` and `bash -n test.sh` were not run —
`test.sh` is not edited this round and `test-repo.sh` is the only command this
round's work is judged by, per the plan's own closed list.
