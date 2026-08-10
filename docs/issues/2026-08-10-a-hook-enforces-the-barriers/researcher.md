# Researcher handoff — a hook enforces the barriers the pages only ask for

## Implementation plan

### What gets built

A new `PreToolUse` hook, `hooks/read-barrier.mjs`, wired in `hooks/hooks.json`
on the matcher `Read|Bash|Grep`. It decides from the event payload alone — the
`agent_type` and the `tool_input` — and never touches the filesystem, opens no
connection and reads no environment variable. It exits 0 on every path. When
it can positively identify a forbidden read it prints the deny decision on
stdout; otherwise it prints nothing at all.

The refusal envelope is the documented `PreToolUse` decision object, printed on
stdout with exit 0:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<the reason the agent reads>"
  }
}
```

Exit 0 with empty stdout lets the call proceed through the normal permission
flow. That is the fail-open path, and every path that is not a positive
identification takes it: an unparseable payload, an unknown agent, an ungated
tool, a command the hook cannot classify, and the single `try/catch` around the
whole of `main`.

### The rule table

Three roles are gated, keyed on the exact `agent_type` strings the workflow
dispatches with (`workflows/agile-loop.js` passes `uroboros:researcher`,
`uroboros:test-author`, `uroboros:implementer`, `uroboros:reviewer`,
`uroboros:planner`, and `general-purpose` for the state loader):

| `agent_type` | forbidden file | forbidden fields | page cited in the reason |
| --- | --- | --- | --- |
| `uroboros:implementer` | `issue.md` | `testPlan` | `agents/implementer.md` |
| `uroboros:reviewer` | `backlog.json` | — | `agents/reviewer.md` |
| `uroboros:test-author` | — | `plan` | `agents/test-author.md` |

Every other `agent_type`, and an event that carries none, returns immediately
and silently. This is the first gate, before the tool name, because it rejects
the most for the least: every call of the main conversation, of the planner, of
the researcher and of the state loader ends there.

Each entry is grounded in a page and cites it, so the hook is the mechanically
visible shadow of a rule that keeps its owner rather than a second statement of
it (non-goal 2). Where the ground is:

- `agents/implementer.md`, "How you work" step 1: "You do not read `issue.md`".
- `agents/reviewer.md`, "You never read `backlog.json`": "the helper's reading
  subcommands are not yours".
- `agents/test-author.md`, "How you work" step 1: "take no other field of it —
  the implementation plan is not yours".
- `agents/researcher.md`, on `testPlan`: "the implementer never sees it".

Put that citation in a comment beside each table entry.

### What counts as a read

A `Read` call: `tool_input.file_path`.

A `Grep` call: `tool_input.path` when it names a file. A `path` that is a
directory, or absent, is not a positive identification and passes.

A `Bash` call: split `tool_input.command` on `&&`, `||`, `;`, `|` and newlines,
and classify each segment on its own, skipping leading `VAR=value` assignments
and a leading `sudo`, `command` or `time`. A segment is a read when one of
these holds, and nothing else is:

1. **The helper.** The head is `node` (by basename) and some token's basename
   is `backlog.mjs`. The token after it is the subcommand and the one after
   that is the state path.
   - Reading subcommands: `index`, `steps`, `codemap`, `read`. The state path
     is a read.
   - Writing subcommands: `init`, `start`, `record`, `branch`, `close`. The
     segment is not a read at all — the reviewer records its own step through
     `start` and `record` and must keep doing so.
   - For `steps`, additionally take the value of `--fields` as the fields being
     read, and the absence of `--fields` as "every field of the step".
2. **A reader command.** The head's basename is one of `cat`, `head`, `tail`,
   `less`, `more`, `bat`, `nl`, `tac`, `od`, `xxd`, `hexdump`, `strings`, `wc`,
   `grep`, `egrep`, `fgrep`, `rg`, `ag`, `sed`, `awk`, `jq`, `cut`, `sort`,
   `uniq`, `diff`, `column`; or the head is `git` and the next token is `show`
   or `cat-file`. Then every token that does not start with `-` is a candidate
   path. Strip surrounding quotes; for a `<ref>:<path>` token (what `git show`
   takes) use the part after the last `:`.
3. **A redirect.** A `< path` in the segment: the token after `<`.

Anything else passes. `git add`, `git commit`, `git diff`, `bash test.sh`,
`node --test …`, `node -e '…readFileSync…'` are all unclassified and go
through. That is the fail-open bargain of criterion 4, and `node -e` is the
deliberate hole in it: closing it means guessing at the content of arbitrary
code.

### What counts as the file

A candidate path is resolved with `path.resolve(event.cwd || process.cwd(),
candidate)` — the event's `cwd`, not this process's, exactly as
`hooks/backlog-changed.mjs` does. It names a gated file when its basename is
`issue.md` or `backlog.json` **and** the resolved path contains a `docs/issues/`
segment. Both halves are required: the basename alone would refuse an
installing project's own unrelated `issue.md`, and a wrong refusal is the
expensive mistake. The consequence is that `cd <issue dir> && cat issue.md`
resolves against the session cwd, misses, and passes — a known, accepted gap.

`backlog.json.tmp` fails the basename test and is not the state file, the same
way `hooks/backlog-changed.mjs` treats it.

### What counts as a forbidden field

Only for the helper's `steps` subcommand, and only against the role's own
field list, which comes from its page and never from the prompt: which steps
and which fields a prompt named is not in the payload, so the hook never asks
(criterion 6). Two shapes are refused:

- `--fields a,b,c` where any name is on the role's list.
- no `--fields` at all, for a role that has a list — the whole step comes back,
  the forbidden field with it. The reason tells the agent to name its fields
  with `--fields`, which is a route it can take on the next call.

A label is never looked at. `steps … research:i1.0 --fields plan,moduleMap,environment`
by the implementer passes, and so does `steps … review:i1.0 --fields findings`,
because the payload cannot tell which steps the prompt named.

### The reason

One sentence, built from the rule that fired. It names three things and the
tests assert on two of them as substrings:

- what may not be read: the path as it appeared in the tool input, or the field
  name;
- the page that says so, by path (`agents/implementer.md`,
  `agents/reviewer.md`, `agents/test-author.md`);
- the route to take instead, in a clause, not a restatement of the rule.

Shape to follow, wording the implementer may adjust as long as the path-or-field
and the page path are both in the string:

- `the implementer may not read /repo/docs/issues/x/issue.md — agents/implementer.md says so. Take what you need from the reads your prompt names.`
- `the reviewer may not read /repo/docs/issues/x/backlog.json — agents/reviewer.md says so. Your prompt is your whole brief; recording your own step with the helper's start and record still works.`
- `the test-author may not read the "plan" field of a step — agents/test-author.md says so. Ask for only the fields your prompt named with --fields.`
- `the implementer may not read a step whole — agents/implementer.md says so. Name the fields your prompt gave you with --fields.`

### Gate order

1. Read stdin to the end before anything else, so the writer on the other end
   is never left on a full pipe.
2. Parse it. Not JSON, or not an object: return.
3. `agent_type` is not one of the three keys of the rule table: return. This is
   the gate that keeps the hook off everything.
4. `tool_name` is not `Read`, `Bash` or `Grep`: return. The matcher already
   narrows this; this is the guarantee.
5. Collect the reads out of the tool input, check them against the role's rule,
   print the first refusal, and return.

All of it inside one `try/catch` that swallows and exits 0, and a `process.exit(0)`
at the end.

### Decisions taken, and what was rejected

- **`PreToolUse` decision JSON over exit 2.** Exit 2 also blocks, but it feeds
  stderr to the agent as an error and discards stdout; the JSON route lets the
  refusal arrive as a reason with a named page (criterion 5) and keeps the
  process's exit code constant at 0, which is what makes "if the hook itself
  errors, every call goes through" checkable.
- **No filesystem access at all.** Criterion 1 says the decision comes from
  `agent_type` and the tool input alone. It also makes the hook fast enough to
  sit on every `Read`, and makes the whole suite pure.
- **Exact `uroboros:` agent types, not bare role names.** A project that
  installs the plugin may have its own agent called `reviewer`; gating it would
  be a wrong refusal in someone else's run, which criterion 4 prices as the
  expensive mistake. The workflow always dispatches with the `uroboros:` prefix.
- **A reader-command list rather than "any command that mentions the path".**
  The blunt rule would refuse the reviewer's own `git add <dir>/backlog.json`
  before its commit. The list is the positive identification criterion 4 asks
  for; commands outside it pass.
- **`Grep` is gated, `Glob` and `Write`/`Edit` are not.** The reviewer is the
  only gated role that holds `Grep`, and a grep of `backlog.json` is a plain
  read of it. `Glob` returns paths, not content. Writes are explicitly a
  non-goal.
- **Rejected: gating the helper's `read` subcommand for every role.** The
  shared brief says no agent of a run reads the state whole, and that rule is
  mechanically visible — but no acceptance criterion asks for it, and scope
  nobody asked for is a finding. Left to the pages.
- **Rejected: resolving a `cd` inside the command.** Tracking a shell's working
  directory across segments is guesswork; the miss fails open.
- **Rejected: reading `backlog.json` to learn which fields a step holds.** It
  would make the hook's decision depend on state it has no business opening,
  and criterion 6 forbids guessing at what the prompt named.

### A note for whoever lands this

This checkout enables the plugin from `.` (`.claude/settings.json`), so once
`hooks.json` names the new hook, uroboros's own later runs in this repository
are gated by it. That is the intent. Nothing in this change's own brief needs
`issue.md` or `backlog.json` read by a gated role.

## Module map

- `hooks/read-barrier.mjs` — **new**, the whole hook. `#!/usr/bin/env node`,
  ESM, zero dependencies, executable bit set (`hooks.json` invokes it
  directly). Top-of-file comment block in the register of
  `hooks/backlog-changed.mjs`: why a `PreToolUse` hook, why it fails open, why
  it never reads a file, and what it deliberately does not catch. Entry point
  is `main()` reading the event off stdin, under one `try/catch`, then
  `process.exit(0)`.
- `hooks/hooks.json` — the plugin's hook wiring. Holds `SessionStart` and
  `PostToolUse` today; gains a `PreToolUse` array with matcher `Read|Bash|Grep`
  and the command `"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/read-barrier.mjs"`, in the
  shape the two existing entries use.
- `hooks/CLAUDE.md` — the directory's page and the suite doc for both hook
  suites. Its opening line says "The plugin's two hooks"; it becomes three, and
  the intro gains a short paragraph on what the barrier hook does and why it
  fails open. **The implementer owns that prose.** The `## Tests for …` section
  for the new suite is the test-author's (see the test plan).
- `hooks/read-barrier.test.mjs` — **new**, the test-author's file.
- `test.sh` — the one command behind "the suite is green"; a new suite must be
  added to its list. Gains a `run "hooks: the read barrier" node --test
  "$root/hooks/read-barrier.test.mjs"` entry beside the run-state hook's, with
  a one-line comment in the style of the ones already there.
- `test-repo.sh` — the repository's own facts, `ok`/`no` helpers, sections
  opened with `echo "=== …"`. Gains a section for the new hook (test-author).
- `README.md` lines 305-307 — "seven suites, one command: … the backlog
  recorder, the run-state hook, and the three tools" becomes eight suites with
  the read barrier named in the list. **Implementer.**
- `workflows/agile-loop.js` — **not changed.** Read for the `agentType` strings
  and the reads each role is given; the prompts already say what the hook now
  enforces.
- `agents/*.md`, `skills/agent-brief/SKILL.md` — **not changed.** Every rule
  keeps its owner (non-goal 2).
- `skills/agent-brief/assets/backlog.mjs` — **not changed.** Read for the
  subcommand names: writers `init`, `start`, `record`, `branch`, `close`;
  readers `index`, `steps`, `codemap`, `read`; `steps` takes
  `<backlogPath> <incrementId|-> [label …] [--fields a,b,c]`.

## Environment

- `node` v22.22.2 is on the `PATH`. Every suite here is `node --test` on a
  `*.test.mjs`; zero dependencies, no install step, no build step.
- `bash` 5.2 is on the `PATH`. `test.sh` and `test-repo.sh` are bash scripts
  run from the repository root.
- There is no linter and no formatter in this repository, and no lint command
  to run.
- `test-repo.sh` shells out to `git`, `find`, `grep`, `sed` and `node`; all are
  present.
- Nothing needs network access: the new hook opens no connection, and the new
  suite starts no server.
- The commands the test plan asks for, in full:
  - `node --test hooks/read-barrier.test.mjs`
  - `bash test-repo.sh`
  - `bash -n test.sh`

## Test plan

### Whether

Tests, yes. Every acceptance criterion is a behaviour of a script that takes
JSON on stdin and answers on stdout.

### What — per acceptance criterion

**C1 — a `PreToolUse` hook refuses a read the page forbids, from `agent_type`
and the tool input alone.** Cases 1, 2, 5, 12, 29; the "decides from the
payload alone" half is pinned structurally by case R4, which fails if the hook
imports `node:fs`.

**C2 — it enforces the three named barriers.** The implementer reading
`issue.md`: cases 1-4. The reviewer reading `backlog.json` through any reading
subcommand: cases 5, 6, 11. A field the role is not given: cases 12-17.

**C3 — the routes to the same file, not only the obvious one.** Cases 2, 7, 8,
10 — a `Read` by path, a `cat`, a `git show <ref>:<path>` and a `Grep` of the
same file are refused alike; cases 6 and 9 pin what must still pass on the
same path.

**C4 — it fails open.** Cases 18-25: an unknown route, an unknown agent, an
ungated tool, an unparseable input, a tool input of the wrong type. Case 25
pins that no path exits non-zero.

**C5 — a refusal reaches the agent as its reason.** Case 29 pins the envelope;
every deny assertion pins that the reason names both the file-or-field and the
page.

**C6 — it gates nothing it cannot see.** Cases 17, 18, 19 — a label is never
part of the decision, a field on no page's list passes, and a role with no
field list may read a step whole.

**C7 — a foreign event and an ungated tool pass without a word.** Cases 20-23,
each asserting empty stdout *and* empty stderr.

**Left untested, deliberately.** That the hook is cheap: a wall-clock assertion
on a node start is flaky and buys nothing. That Claude Code actually applies the
deny — that is the CLI's contract, not this repository's code, and no test here
can exercise it. `node -e`, `python -c` and a `cd` before a `cat`: fail-open
routes by design, and case 24 pins one of them as passing rather than
pretending it is caught.

### How

One new file, `hooks/read-barrier.test.mjs`, `node:test` and
`node:assert/strict`, plus `node:child_process`, `node:path`, `node:url`.
Nothing else. It follows `hooks/backlog-changed.test.mjs`: helpers first, then
flat top-level `test(...)` calls; every case spawns the real hook as a child
process with the event as JSON on stdin, exactly as Claude Code delivers it.
Nothing is mocked and nothing is stubbed — and unlike the neighbouring suite,
no temp directory and no server are needed at all, because the hook decides
from the payload and never opens a file.

Case names: lowercase declarative sentences stating the guaranteed behaviour,
no "should", no numbering — the register of `'with no collector in the
environment nothing is sent, and nothing is said'`. Assertion messages carry
the why.

Helpers to define at the top:

- `hook` — absolute path to `read-barrier.mjs`, resolved with
  `fileURLToPath(new URL('./read-barrier.mjs', import.meta.url))` so the suite
  runs from a checkout and from a plugin cache alike.
- `runHook(input)` — spawns the hook, writes `input` on stdin verbatim when it
  is a string and as JSON otherwise, resolves to `{ code, stdout, stderr }`.
  Copy it from `backlog-changed.test.mjs`; it needs no `env` argument here,
  since the hook reads no environment.
- `event(extra)` — a well-formed `PreToolUse` payload:
  `session_id`, `transcript_path: '/dev/null'`, `cwd: '/repo'`,
  `permission_mode: 'default'`, `agent_id: 'agent-7'`,
  `agent_type: 'uroboros:implementer'`, `hook_event_name: 'PreToolUse'`,
  `tool_name: 'Bash'`, `tool_input: {}`, `tool_use_id: 'toolu_1'`, then
  `...extra`.
- `readOf(agentType, filePath)`, `bashOf(agentType, command)`,
  `grepOf(agentType, targetPath)` — three thin wrappers over `event`.
- `ISSUE = '/repo/docs/issues/2026-01-01-a-thing/issue.md'` and
  `STATE = '/repo/docs/issues/2026-01-01-a-thing/backlog.json'`, with `'/repo'`
  as the event `cwd`, so a case can hand either the absolute path or the
  relative one and mean the same file.
- `helper(args)` — the command line the helper is really invoked with:
  `` `node "/plugins/uroboros/skills/agent-brief/assets/backlog.mjs" ${args}` ``.
  The plugin cache path varies in reality, which is exactly why the hook must
  find the helper by basename.
- `allows(result)` — asserts `code === 0` and `stdout === ''`.
- `denies(result, ...substrings)` — asserts `code === 0`, parses `stdout`,
  asserts `hookSpecificOutput.hookEventName === 'PreToolUse'`,
  `permissionDecision === 'deny'`, and that `permissionDecisionReason` contains
  each substring.

The cases, in the order of the hook's own gates — the roles and their files
first, then the fields, then everything that passes, then the shape and the
exit code:

1. `a Read of the issue file by the implementer is refused, and the reason
   names the file and the page` — `readOf('uroboros:implementer', ISSUE)` →
   `denies(result, ISSUE, 'agents/implementer.md')`.
2. `a cat of the issue file is refused like the Read, with the relative path
   resolved against the event cwd` —
   `bashOf('uroboros:implementer', 'cat docs/issues/2026-01-01-a-thing/issue.md')`
   with `cwd: '/repo'` → denies, reason contains `issue.md`.
3. `the researcher reading the same issue file passes` —
   `readOf('uroboros:researcher', ISSUE)` → `allows`.
4. `the test-author reading the same issue file passes` —
   `readOf('uroboros:test-author', ISSUE)` → `allows`. Its page sends it there.
5. `the reviewer is refused every reading subcommand of the helper on the run
   state` — loop over `index ${STATE}`, `steps ${STATE} i1 research:i1.0
   --fields findings`, `codemap ${STATE}`, `read ${STATE}`, each as
   `bashOf('uroboros:reviewer', helper(...))` → denies with `backlog.json` and
   `agents/reviewer.md`; the assertion message names the subcommand.
6. `the reviewer's own start and record on the run state pass — the gate is on
   reads, not writes` — `helper('start ' + STATE + ' i1 review:i1.0 /tmp/p.txt')`
   and `helper('record ' + STATE + ' i1 review:i1.0 /tmp/r.json /tmp/p.txt')` →
   `allows` for both.
7. `a cat of the run state by the reviewer is refused` —
   `bashOf('uroboros:reviewer', 'cat ' + STATE)` → denies.
8. `a git show of the run state at a revision by the reviewer is refused` —
   `bashOf('uroboros:reviewer', 'git show origin/main:docs/issues/2026-01-01-a-thing/backlog.json')`
   → denies.
9. `staging and committing the run state by the reviewer passes` —
   `bashOf('uroboros:reviewer', 'git add ' + STATE + ' && git commit -m "record the review"')`
   → `allows`.
10. `a Grep whose path is the run state is refused for the reviewer, and one
    on a source file passes` — `grepOf('uroboros:reviewer', STATE)` → denies;
    `grepOf('uroboros:reviewer', '/repo/hooks/read-barrier.mjs')` → `allows`.
11. `the implementer running the helper's index on the run state passes — only
    the reviewer's page closes that file` —
    `bashOf('uroboros:implementer', helper('index ' + STATE))` → `allows`.
12. `the test-author asking for the researcher's plan field is refused, and the
    reason names the field and the page` —
    `bashOf('uroboros:test-author', helper('steps ' + STATE + ' i1 research:i1.0 --fields plan'))`
    → `denies(result, 'plan', 'agents/test-author.md')`.
13. `the test-author asking for the test plan alone passes` — same call with
    `--fields testPlan` → `allows`.
14. `a forbidden field anywhere in the list is refused` — `--fields testPlan,plan`
    for the test-author → denies.
15. `the implementer asking for the test plan is refused, and the three fields
    its page names pass` — `--fields testPlan` → denies with
    `agents/implementer.md`; `--fields plan,moduleMap,environment` → `allows`.
16. `a steps call with no --fields by a role with a closed field is refused,
    and the reason names --fields` —
    `bashOf('uroboros:test-author', helper('steps ' + STATE + ' i1 research:i1.0'))`
    → `denies(result, '--fields', 'agents/test-author.md')`.
17. `a steps call with no --fields by the planner passes — no field is closed
    to it` — `bashOf('uroboros:planner', helper('steps ' + STATE + ' i1'))` →
    `allows`.
18. `which step a prompt named is not in the payload, so the label never
    decides` — the implementer reading `research:i1.0 --fields
    plan,moduleMap,environment` and `review:i1.0 --fields findings`, both
    `allows`.
19. `a field on no page's list passes for every gated role` — `--fields cases`
    for the implementer, `--fields openQuestions` for the test-author → both
    `allows`.
20. `an event with no agent_type passes without a word` — a `Read` of `ISSUE`
    with `agent_type` deleted → `allows` and `stderr === ''`.
21. `the state loader's general-purpose read of the index passes without a
    word` — `bashOf('general-purpose', helper('index ' + STATE))` → `allows`
    and `stderr === ''`.
22. `an agent type that is not uroboros's passes without a word` —
    `readOf('Explore', ISSUE)` and `readOf('reviewer', STATE)` → `allows` and
    `stderr === ''` for both. The second pins that the bare role name is not
    matched.
23. `a tool the hook does not gate passes` — the implementer with
    `tool_name: 'Write'` and `tool_input: { file_path: ISSUE }`, and again with
    `'Edit'` → `allows` and `stderr === ''`. Writes are not gated.
24. `a Bash call the hook cannot positively identify as a read passes` — the
    implementer running `node -e "console.log(require('fs').readFileSync('docs/issues/2026-01-01-a-thing/issue.md','utf8'))"`,
    and separately `bash test.sh` → `allows` for both.
25. `an input the hook cannot use passes and still exits 0` — a table:
    `''`, `'not json at all'`, `'{}'`, `'[]'`, an event with `tool_input`
    missing, one with `tool_input: null`, one with
    `tool_input: { command: 12345 }` and one with
    `tool_input: { file_path: ['a', 'b'] }`, the last four with
    `agent_type: 'uroboros:implementer'` → `allows` for every entry, with the
    entry named in the assertion message.
26. `a refusal is a PreToolUse deny decision on stdout and nothing else, and
    the process still exits 0` — take case 1's result, assert
    `JSON.parse(stdout)` has exactly the `hookSpecificOutput` key, that its
    three fields are `PreToolUse`, `deny` and a non-empty string, and that
    `code === 0`.

Command that runs just this file, from the repository root:

    node --test hooks/read-barrier.test.mjs

**The suite doc.** `hooks/CLAUDE.md` is the doc for this directory and for both
hook suites. Add a `## Tests for read-barrier.mjs` section after the existing
`## Tests for backlog-changed.mjs`, with the same subsections that one uses:
what the suite covers, helpers and fixtures, where a new case belongs, faked vs
real, running it. Say there that nothing is faked and nothing is written: the
hook decides from the payload alone, so the suite needs no temp directory and
no server. Do not touch the opening paragraphs of that file — the implementer
edits those in the same round.

**The repository's own facts.** `test-repo.sh` gains a section, placed after
`=== the collector is reached from the hook and from nowhere else` and before
`=== the run state is the channel …`, opened with

    echo
    echo "=== the read barrier is wired, and decides from the payload alone"

Four cases, in the file's `ok`/`no` style, each with the numbered comment block
the neighbouring section uses:

- **R1.** `hooks.json` subscribes the hook: parse it with `node -e`, assert
  there is a `PreToolUse` entry whose command ends in `read-barrier.mjs` and
  whose matcher names `Read`, `Bash` and `Grep`. `ok` message:
  `hooks.json subscribes read-barrier.mjs to PreToolUse on Read, Bash and Grep`.
  `no` message says the barriers would be honour-system again.
- **R2.** `[ -x "$root/hooks/read-barrier.mjs" ]` — `hooks.json` invokes it
  directly, so a lost executable bit is a hook that fails on every call.
- **R3.** `node --check "$root/hooks/read-barrier.mjs"` — it parses.
- **R4.** The hook opens no file and no connection:
  `grep -qE "node:fs|readFileSync|writeFileSync|\bfetch\(|node:https?" "$root/hooks/read-barrier.mjs"`
  must find nothing. It decides from `agent_type` and the tool input alone, and
  a hook that started reading the state it guards would be guarding it by
  opening it.
- **R5.** `grep -q 'hooks/read-barrier.test.mjs' "$root/test.sh"` — the suite is
  listed in the one command behind "the suite is green".

### What counts as done

Closed list, run from the repository root:

    node --test hooks/read-barrier.test.mjs
    bash test-repo.sh
    bash -n test.sh

Nothing else. `bash test.sh` is deliberately left off: the first command is the
only suite this change adds, `test-repo.sh` is the only other suite it touches,
and the whole runner would re-run three `npm` suites over untouched code.
`bash -n test.sh` is there because `test.sh` is edited and nothing else would
catch a syntax error in it — `test-repo.sh` only greps it for a filename.

### What is already red

I ran none of these, not once and not as a baseline. From reading: `bash
test-repo.sh` and `bash -n test.sh` are expected to pass on the current tree —
the R1-R5 cases the test-author adds will fail until the hook and the wiring
exist, and `node --test hooks/read-barrier.test.mjs` will fail on a missing
file until then. That is the intended red. Nothing else in either suite is
expected red; if something is, it belongs to code this change never touched and
gets reported with its exit code and left alone.
