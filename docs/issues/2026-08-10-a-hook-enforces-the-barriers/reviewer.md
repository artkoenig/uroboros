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

## Round 1

Status: accepted. 0 findings requiring a correction.

Reviewed against `origin/main` (`03d6ba4`), not the local `main` ref, which is
33 commits stale at `57e5fd4`: `git diff main...HEAD` there carries eight
merged pull requests that have nothing to do with this issue. The change under
review is `origin/main..HEAD` — 13 files, of which four are handoff files
outside my judgement.

### The runs

The one command my prompt named, its exit code with it, in one call:

- `bash test-repo.sh` — 63 cases, every one `ok`, exit 0. Nothing skipped and
  nothing excluded. The five read-barrier checks it gained (the `hooks.json`
  wiring on `Read|Bash|Grep`, the file's existence and executable bit, `node
  --check`, no filesystem or network reference in the source, the suite listed
  in `test.sh`) are among them, as are the 19 workflow driver modes including
  the new `w19`.

No red run, so there is nothing to attribute to this change or to the merge
base.

One fact about coverage, not a finding: `test-repo.sh` does not execute
`hooks/read-barrier.test.mjs`. Only `test.sh` does, through the line this
change added to it, and `test.sh` was not on my list. So the hook's own 26
cases are pinned by this round as *listed and parsing*, never as *run*. The
judgements below on the hook's behaviour come from reading it, not from
executing its suite.

### The criteria, one by one

- **A `PreToolUse` hook refuses from `agent_type` and the tool input alone** —
  met. `hooks/read-barrier.mjs` imports only `node:path`, opens no file, no
  socket and no environment variable; `test-repo.sh:279-292` pins that by
  source inspection. The event's `cwd` is used to resolve a relative path,
  which is payload and not the state being guarded.
- **At least the three barriers** — met. Implementer/`issue.md`
  (`RULES['uroboros:implementer'].file`), reviewer/`backlog.json` across the
  helper's complete set of readers `index`, `steps`, `codemap`, `read`
  (`HELPER_READS`), and the field gate for `testPlan` and `plan`. The four
  page citations in the table are verbatim in the pages: `agents/implementer.md:24`
  ("You do not read `issue.md`"), `agents/reviewer.md:94,100` ("You never read
  `backlog.json`", "the helper's reading subcommands are not yours"),
  `agents/test-author.md:25-26` ("take no other field of it — the
  implementation plan is not yours") and `agents/researcher.md:54` ("the
  implementer never sees it").
- **Every route to the same file** — met. `Read.file_path`, `Grep.path`, a
  reader command's arguments, a `< path` redirect, `git show <ref>:<path>` and
  the helper's own reads all converge on `namesGatedFile`, which requires both
  the exact basename and a `docs/issues/` ancestor, so `git add` and
  `git commit` of the same path are not refused.
- **It fails open** — met. Only a positive identification refuses; an
  unparseable payload, a non-object, an unknown or absent `agent_type`, an
  ungated tool, a malformed `tool_input`, an unclassifiable command and the
  catch around `main` all fall through, and every path ends at
  `process.exit(0)`.
- **A refusal reaches the agent as its reason** — met. `denyReason` names the
  role, the file or field, the page, and the route to take instead, inside the
  documented deny envelope on stdout.
- **It gates nothing it cannot see** — met. No step label is ever looked at;
  the only question asked of a `steps` call is which fields it would hand back.
- **A non-uroboros event and an ungated tool pass without a word** — met. The
  `RULES[event.agent_type]` lookup is the first gate after parsing, before the
  tool name is read, and a pass prints nothing on either stream.

### The tests against the intent

Each criterion has a case that would fail if the behaviour broke:

- The two file barriers and the field barrier are each pinned from both sides —
  refused for the role whose page closes it, allowed for a role whose page does
  not — so widening or dropping a rule breaks a case either way.
- Criterion 3's routes are pinned one case per route, with `git add`/`git
  commit` of the same path pinned as a pass, which is the wrong refusal that
  rule would most easily cause.
- Criterion 4 is pinned by a table of every unusable payload shape plus the
  unknown-agent, ungated-tool and unclassifiable-command cases, all asserting
  exit 0 and empty stdout.
- Criterion 5 is pinned by every `denies` call requiring the file or field and
  the page path inside `permissionDecisionReason`, and by the envelope case
  that pins exactly the three documented fields.
- Criterion 6 is pinned by running identical fields against two different step
  labels and requiring both to pass, so a label can never decide.
- Criterion 7 is pinned by cases that assert empty stderr as well as empty
  stdout for a foreign `agent_type`, the bare unprefixed role name and
  `general-purpose`.
- The workflow correction is pinned outside the unit suite, in `test-repo.sh`:
  mode `w19` (a resumed implementer that asked, with the answer carried in its
  prompt and no `## Decisions` pointer), the `w9` no-answer branch, the state
  loader's prompt in `w1`, and a check in every mode that no `implement:`
  prompt contains a line ordering a read of `issue.md`.

Two gaps, neither correction-worthy, both unchanged from Round 0:

- The second half of criterion 4 — "so does every call if the hook itself
  errors" — has no case that would fail if the `try`/`catch` around `main` were
  deleted, because no payload reaches a throw: every field is type-checked
  before use and the suite already covers every malformed shape. A test for it
  would need fault injection the hook does not offer.
- The gate *order* of criterion 7 is not observable from outside — an early
  pass and a late pass look identical — so no test can pin it. The observable
  half (pass, silent, exit 0) is pinned.

### Scope

Nothing in the diff is unasked for. `hooks/read-barrier.mjs` and its suite are
the change; `hooks/hooks.json` wires it; `test.sh` lists the suite and
`README.md` moves "seven suites" to "eight" so that line stays true;
`hooks/CLAUDE.md` gains the hook's description and the suite doc the
repository's own rule requires and `test-repo.sh` enforces; `test-repo.sh`
gains the wiring checks and the `w19` mode.

`workflows/agile-loop.js` and the one sentence in `rulebook.md` are the repair
of the breakage Round 0 found, and I judge them in scope rather than as scope
creep: without them the hook refuses a read the workflow's own resume prompt
orders, which is precisely the price the fourth criterion names. The repair
holds. `answeredBlock` no longer names `issue.md` at all; the state loader — a
`general-purpose` agent the hook does not gate — lifts the `## Decisions` block
out of the file once and the answer travels in the prompt of every step that
asked. `decisions` is declared at `workflows/agile-loop.js:524` and first read
when a prompt is built at 673 and later, so the `const` is initialised before
any call reaches it; there is no temporal-dead-zone throw, and the driver modes
that build those prompts pass.

### Blast radius

Traced again, from the diff rather than from Round 0's list:

- **Every dispatched prompt of a gated role.** Each `readStep` the workflow
  builds for the implementer or the test-author names `--fields`
  (`workflows/agile-loop.js:809, 811, 841, 864, 870, 878`), so none of them
  walks into the whole-step refusal; the reviewer's prompt orders no read of
  `backlog.json` and says so explicitly at `workflows/agile-loop.js:922`.
- **The helper's invocation form.** Every page and prompt invokes it as `node
  "<base>/assets/backlog.mjs" …` (`skills/agent-brief/SKILL.md:118,137`,
  `workflows/agile-loop.js:478`), which is the form the hook classifies. The
  brief's fallback `find … | head -1` line tokenizes into segments whose heads
  are `find` and `head`, and neither yields a gated candidate.
- **The chosen `agent_type` keys.** `uroboros:implementer` is the value the
  pre-existing `hooks/backlog-changed.test.mjs:120` already uses as the shape a
  subagent event really has, so the prefixed keys are corroborated by something
  outside this change rather than assumed by it.
- **`plugin.json`** enumerates hooks nowhere, so the new `hooks.json` entry
  ships without touching it; `README.md` names no hook count that would go
  stale; no page outside `rulebook.md:49` still tells a resumed step to read
  `## Decisions` (`workflows/agile-loop.js:1028` is the message to the human,
  which is still correct).
- **The `PostToolUse` neighbour** is untouched and gates a different event.

Two things found and deliberately not filed, recorded so a later round does not
re-derive them:

- A `>>` append whose head is a reader command is treated as a read of its
  target. `cat extra >> docs/issues/x/backlog.json` run by the reviewer is
  refused, because `splitRedirects` consumes the second `>` as the first one's
  operand and the target then falls through into the argument list
  (`hooks/read-barrier.mjs:225-239`). It violates no criterion — the non-goal
  "it does not gate writes" is about which files an agent may change, and no
  reachable path has any agent appending to either gated file, the helper being
  the only writer of `backlog.json`. A non-reader head such as `echo` is
  unaffected, because the leaked target is only harvested once the head is a
  known reader.
- `answeredBlock`'s no-question branch still tells a resumed agent that "your
  own earlier attempt is in the run state under this step's label"
  (`workflows/agile-loop.js:418`), which for the reviewer names the file its
  own page closes. The imperative "Read both" that Round 0 saw is gone, the
  next line of the reviewer's own prompt forbids the read, and a reviewer that
  tried it anyway is refused with a reason rather than stranded — which is
  criterion 5 working. Prose worth tightening one day, not a defect of this
  change.
