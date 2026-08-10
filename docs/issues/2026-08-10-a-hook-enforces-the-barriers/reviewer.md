# Reviewer

## Round 0

Status: 1 finding requiring a correction.

### The runs

The three commands my prompt named, each with its own exit code, in one call:

- `node --test hooks/read-barrier.test.mjs` — 26 cases, 26 pass, 0 fail, exit 0.
- `bash test-repo.sh` — 62 cases, all `ok`, exit 0. The five new read-barrier
  checks (wiring in `hooks.json`, the file's existence and executable bit,
  `node --check`, no filesystem or network reference, the suite listed in
  `test.sh`) are among them and pass.
- `bash -n test.sh` — exit 0. Note this is a syntax check only: `test.sh` was
  not executed in this review, so the new `hooks: the read barrier` line in it
  is verified as parsed and as present (by the `test-repo.sh` check), never as
  run through `test.sh` itself.

No red run, so nothing to attribute to this change or to the merge base.

### Finding 1 — a resumed run cannot deliver the human's answer to the implementer

Criterion violated: none directly. This is a breakage outside the criteria,
found by tracing what the change touches, and it collides with the price the
fourth criterion names — "a wrong refusal stops a run that may have been
working for hours".

Reproduction, from state that already exists in the repository:

1. An implementer step returns a question for the human. `workflows/agile-loop.js:872`
   (`asksTheHuman(buildLabel, build)`) ends the run with `blockedOnHuman`.
2. The human follows `rulebook.md:49`: records the answer under a `## Decisions`
   heading in `issue.md`, commits it, and starts the same workflow on the same
   directory again.
3. The resumed run dispatches the implementer with `questionBlock(buildLabel)`
   (`workflows/agile-loop.js:831`), whose text is `answeredBlock`
   (`workflows/agile-loop.js:405-418`): "The answer is under `## Decisions` in
   `<dir>/issue.md`. Read it there first, then work this step again."
4. The implementer issues that read — `Read` with
   `file_path: "<repo>/docs/issues/<dir>/issue.md"`, or `cat` of the same path.
5. `hooks/read-barrier.mjs:58-64` maps `uroboros:implementer` to
   `file: 'issue.md'`, so `main` emits the deny envelope with the reason "the
   implementer may not read <path> — agents/implementer.md says so. Take what
   you need from the reads your prompt names." The existing case at
   `hooks/read-barrier.test.mjs:92` already pins exactly this refusal for this
   payload.

Wrong result: the human's answer reaches the implementer through no other
route. It lives only in `issue.md`; the researcher's step was recorded before
the answer existed and is not re-run; the prompt names no read that carries it;
and the deny's own "instead" line sends the agent to "the reads your prompt
names", which is the dead end it just came from. The step that asked the
question is worked again without the answer it asked for — the exact resume
path `test-repo.sh` pins as "a run resumed after a question for the human works
that step again with the question in its prompt".

Before this change that read went through, and the resume worked. The fix is
not mine to choose: either the hook must let the implementer reach the human's
answer, or the workflow must stop routing the implementer to `issue.md` on
resume and carry the answer another way. Whichever is chosen, the two must
agree, because right now the prompt orders a call the hook refuses.

### Observations, no correction needed

These are recorded so a later round does not re-derive them. None of them is a
finding: each is either pre-existing, unreachable by any input, or a fail-open
gap the criteria explicitly permit.

- The reviewer meets a milder form of the same collision. `answeredBlock`'s
  second branch (`workflows/agile-loop.js:414`) tells the resumed agent "your
  own earlier attempt is in the run state under this step's label. Read both",
  and `questionBlock(reviewLabel)` is in the reviewer's dispatch
  (`workflows/agile-loop.js:878`). For the reviewer that instruction was
  already contradicted by its own page and by the very next line of its own
  prompt ("Read nothing out of `<dir>/backlog.json`"), so the hook enforces the
  side that was already binding, and the answer half of that branch —
  `issue.md` — stays open to the reviewer. Pre-existing prose contradiction,
  not a breakage this change introduces.
- The fourth criterion's second half — "so does every call if the hook itself
  errors" — has no test that would catch its removal: delete the `try`/`catch`
  at `hooks/read-barrier.mjs:408-413` and all 26 cases still pass. I am not
  filing it, because no payload reaches a throw. Every field the hook touches
  is type-checked before use, `path.resolve` only throws on a non-string, and
  the suite already covers every malformed shape (`''`, non-JSON, `[]`, `{}`,
  missing `tool_input`, `tool_input: null`, a numeric `command`, an array
  `file_path`). A test for the catch would need fault injection the hook does
  not offer, so there is no behaviour a test could break against.
- `steps` with no `--fields` is refused for the two roles that have a closed
  field, whatever step it names (`hooks/read-barrier.mjs:376-382`). That
  refuses some calls that are not forbidden — the implementer reading a review
  step whole, which carries no `testPlan`. I am not filing it: without it, the
  second criterion's field barrier is bypassed by omitting one flag, the hook
  cannot tell which fields a step holds without opening the file the first
  criterion forbids it to open, and the deny hands back the correction that
  fixes it ("Name the fields your prompt gave you with `--fields`"). Every
  `readStep` the workflow builds for a gated role already names `--fields`
  (`workflows/agile-loop.js:783, 815, 838, 844, 852`), so no dispatched prompt
  walks into it.
- Invoking the helper without `node` — `.../backlog.mjs read <state>` — is not
  classified as a helper call (`hooks/read-barrier.mjs:284` requires
  `head === 'node'`) and passes. Theoretical only:
  `skills/agent-brief/assets/backlog.mjs` is mode `100644`, so it cannot be
  executed directly, and every prompt names the `node` form.

### The criteria, one by one

- A `PreToolUse` hook refuses from `agent_type` and the tool input alone —
  met. `hooks/read-barrier.mjs` opens no file, no socket and no environment
  variable; `test-repo.sh` pins that by source inspection and the suite pins
  the decisions. It also uses the event's `cwd`, which is the payload and not
  the state it guards, and it is what makes a relative path mean what the
  agent meant.
- At least the three barriers — met. Implementer/`issue.md`
  (`read-barrier.test.mjs:92, 97`), reviewer/`backlog.json` through all four
  reading subcommands `index`, `steps`, `codemap`, `read`
  (`read-barrier.test.mjs:112`, which is the helper's complete set of readers
  per `skills/agent-brief/assets/CLAUDE.md`), and the field gate both ways —
  the test-author refused `plan` and the implementer refused `testPlan`, each
  with its own page named (`read-barrier.test.mjs:164, 174, 179`). The three
  page quotes the hook's table cites are verbatim in
  `agents/implementer.md:25`, `agents/reviewer.md:94-100`,
  `agents/test-author.md:22-30` and `agents/researcher.md:53-54`.
- Every route to the same file — met. `Read` by path, `cat`, `git show
  <ref>:<path>` and `Grep` are all refused
  (`read-barrier.test.mjs:92, 97, 137, 142, 152`), and `git add`/`git commit`
  of the same path is not (`read-barrier.test.mjs:147`), which is the wrong
  refusal that rule could easily have caused.
- It fails open — met for everything reachable. No `agent_type`, a foreign
  one, the bare unprefixed role name, `general-purpose`, `Write`/`Edit`,
  `node -e`, `bash test.sh` and every malformed stdin all exit 0 with empty
  stdout (`read-barrier.test.mjs:210-282`). See the observation above on the
  untested catch-all, and Finding 1 on the one refusal that is correct by the
  page and still costs a run.
- A refusal reaches the agent as its reason — met. Every `denies` assertion
  requires the file or field and the page path inside
  `permissionDecisionReason`, and `read-barrier.test.mjs:284` pins the whole
  envelope: exactly `hookSpecificOutput` with exactly the three documented
  fields, a non-empty reason, exit 0.
- It gates nothing it cannot see — met. `read-barrier.test.mjs:196` runs the
  same fields against two different step labels and requires both to pass, so
  a label can never decide.
- Non-uroboros events and ungated tools pass without a word or a cost — met.
  The `agent_type` lookup is the first gate after parsing
  (`hooks/read-barrier.mjs:353-357`), and the cases that pass also assert
  `stderr === ''`.

### Scope

Nothing in the diff is unasked for. `hooks/hooks.json` wires the hook,
`test.sh` lists the suite, `README.md` moves "seven suites" to "eight" because
that line would otherwise be false, `hooks/CLAUDE.md` gains the hook's
description and the suite doc the repository's own rule requires (and
`test-repo.sh` enforces), and `test-repo.sh` gains five checks that the hook is
wired and stays payload-only. The three handoff files are outside my judgement.

### Blast radius

Traced: the workflow's dispatches for all five roles and the two
`general-purpose` ones, the resume-after-question path, the helper's
subcommands, the recorder's own `start`/`record`/`branch` writes, `plugin.json`
(it enumerates no hooks, so `hooks/hooks.json` shipping the new entry is
enough), and the neighbouring `PostToolUse` hook (untouched, and the two gate
on different events). One breakage found, above; everything else the change
touches passes as it did before.
