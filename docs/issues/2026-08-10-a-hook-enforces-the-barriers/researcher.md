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

## Round 1

The reviewer filed one finding. This section is the whole work order for it;
nothing from Round 0 carries over, the list of commands included.

### The finding, and what it costs

`hooks/read-barrier.mjs` refuses the implementer every read of `issue.md`, and
that refusal is correct by the implementer's own page. But `workflows/agile-loop.js`
orders exactly that read on one path: when a step ended the previous run with a
question for the human, the resumed run dispatches it again with
`answeredBlock(label)`, whose text is "The answer is under `## Decisions` in
`<dir>/issue.md`. Read it there first". For the implementer the prompt now
orders a call the hook denies, and the human's answer reaches it through no
other route — it lives only in `issue.md`, the researcher's step is recorded
and not re-run, and the deny's own "instead" line points back at the prompt it
came from. The step is worked again without the answer it asked for.

### What gets built

The workflow stops routing any agent to `issue.md` for the answer and carries
the answer itself. The state loader — a `general-purpose` agent, ungated by the
hook, already the one dispatch that opens the run state at startup — lifts the
text under the `## Decisions` heading out of `issue.md` once and returns it in
its structured return. The workflow keeps it in one binding and puts it in the
prompt of every step that ended the last run asking. The hook is not touched:
its refusal was right, and after this change its "Take what you need from the
reads your prompt names" is literally true, because the answer is in the
prompt.

Rejected alternatives, and why:

- **Carve an exception into the hook for `issue.md`.** The hook decides from
  the payload alone and cannot see that a run is resumed, so the exception
  would have to be unconditional — which is the barrier the issue exists to
  build, deleted.
- **Have the workflow read `issue.md` itself.** The workflow runtime gives the
  script `args`, `agent`, `log` and `phase` and no filesystem; the script's own
  header says so.
- **Re-run the researcher so it relays the answer.** The resume semantics are
  keyed on recorded labels; re-running a recorded step to launder one paragraph
  costs a dispatch and changes a mechanism that works.
- **A separate dispatch that fetches the answer.** A second general-purpose
  agent for one section of one file, when the one that already runs at startup
  can return it in the same call.

### The edits, one by one

All five are in `workflows/agile-loop.js` unless named otherwise.

**1. `STATE` gains a `decisions` field.** In the `STATE` schema, after the
`runSteps` property and before `summary`:

```js
    decisions: {
      type: 'string',
      description:
        'Everything under the `## Decisions` heading of the issue file, verbatim and without the heading itself. Empty string when the file has no such heading.',
    },
```

and `decisions` joins `required`, which becomes
`['exists', 'branch', 'increments', 'runSteps', 'decisions', 'summary']`.

**2. The state loader is asked for it.** In the `load-state` dispatch prompt,
insert this immediately before the closing `Read nothing else, change nothing,
…` sentence:

```js
    `The human's answers to whatever ended an earlier run are under a \`## Decisions\` heading ` +
    `in ${dir}/issue.md: return everything under that heading in decisions, verbatim and ` +
    `without the heading itself, up to the next \`## \` heading or the end of the file. Return ` +
    `an empty string when there is no such heading and when there is no such file, and read no ` +
    `other part of it into your return.\n` +
```

The trailing "Read nothing else … beyond the read-only ones named here" stays
as it is: this read is now one of the ones named here.

**3. One binding holds the answer.** After the `issueBranch` block (the
`if (!issueBranch) log(...)`) and before the `recorded`/`carriedQuestions`
block, add:

```js
// The human's answer to whatever ended the last run, lifted out of `issue.md`
// by the state loader — the one agent of the run that may open that file. It
// travels in the prompt of the step that asked, because that file is closed to
// the implementer by its own page and by `hooks/read-barrier.mjs`, so a prompt
// that sent it there would order a call the hook refuses and strand the step.
const decisions = state && typeof state.decisions === 'string' ? state.decisions.trim() : ''
```

**4. `answeredBlock` hands over the text instead of the path.** Replace the
function and its header comment with:

```js
// The question this step asked before the run stopped, and the human's answer
// to it. The answer is in the prompt and not behind a read, because `issue.md`
// is closed to some of the roles that ask.
function answeredBlock(label) {
  const asked = carriedQuestions.get(label)
  return (
    (asked && asked.length
      ? `This step ended the previous run with a question for the human:\n` +
        asked.map((q) => `  - ${q}`).join('\n') +
        '\n'
      : `This step ended the previous run with a question for the human, and your own earlier ` +
        `attempt is in the run state under this step's label.\n`) +
    (decisions
      ? `The human answered it, and the answer is here in full:\n${decisions}\n` +
        `Work this step again from it, and ask again only what it does not settle.\n`
      : `The human recorded no answer. Work this step again from what you have, and ask again ` +
        `only what you still cannot settle.\n`)
  )
}
```

Two things about that text are deliberate and must survive: it names neither
`issue.md` nor the `## Decisions` heading — where the human writes the answer is
the rulebook's rule and the run's closing log line, and the agent needs the
text, not its address — and the second branch states where the earlier attempt
is instead of ordering a read of it, which is the same sentence reworded and no
new instruction.

**5. Two comments and one log line follow the new route.** The comment above
`const recorded = new Map()` opens "A step that ended the run with a question
for the human is not replayed from its recorded return: the human answered in
`issue.md`, so the step is worked again with the question in front of it" —
change that clause to say the state loader lifted the human's answer out of
`issue.md` and the step is worked again with the question and the answer in
front of it. And after the existing `if (carriedQuestions.size) log(...)`
block, add:

```js
if (carriedQuestions.size && !decisions) {
  log('No answer came back from the issue file, so the steps that asked are worked again without one.')
}
```

**6. The rulebook's sentence.** `rulebook.md` and `GEMINI.md` are byte-for-byte
identical files and both must get the same edit. In the paragraph beginning "A
result carrying `blockedOnHuman`", replace "with the question in its prompt and
your answer in `issue.md`" with "with the question and your answer both in its
prompt". Nothing else in either file changes: the human still records the
answer under a `## Decisions` heading in `issue.md`, which is what the rest of
that paragraph says.

### Module map

- `workflows/agile-loop.js` — the one workflow. Entry points for this change,
  in file order: the `STATE` schema (edit 1), the `load-state` dispatch that
  opens every run (edit 2), `answeredBlock`/`questionBlock` around the middle
  of the file (edit 4), the `issueBranch` block that the new `decisions`
  binding follows (edit 3), and the `recorded`/`carriedQuestions` block just
  below it (edit 5). `questionBlock` is called in all five role dispatches, so
  every step that asked gets the answer, not only the implementer's.
- `test-repo.sh` — the repository's own checks. The workflow driver is a
  `node` script in a heredoc (`cat >"$driver_tmp/driver.js" <<'JS'` … `JS`): it
  compiles `agile-loop.js` with `new AsyncFunction('args', 'agent', 'log',
  'phase', src)`, runs it with a stub `agent` that records every
  `{label, agentType, prompt}` and returns a fixture per label, then asserts
  per mode. The modes are dispatched at the bottom by `run_driver "$wf" wN
  "<description>"`.
- `hooks/read-barrier.mjs` — not edited. Named here so nobody goes looking:
  the refusal it makes is the correct one.
- `rulebook.md`, `GEMINI.md` — the session's page, identical twins.

### Environment

- Node and bash are on the PATH; no install step, no build step, zero
  dependencies. Run everything from the repository root.
- `bash test-repo.sh` is the only command this round's work is judged by. It
  runs the repository's own checks, including every workflow driver mode, and
  prints one `ok`/`no` line per case with a `PASS`/`FAIL` summary and a
  non-zero exit on any `no`.
- There is no linter and no formatter in this repository, and nothing to
  install before the command above.

### Test plan

Tests are needed. The finding is a prompt that orders a call the hook denies,
and a driver mode reproduces it from the payload the script builds.

Everything below lives in `test-repo.sh`, in the driver heredoc. There is no
test framework: `assertTrue(cond, msg)` and `assertEqualArrays(actual,
expected, msg)` push into `failures`, a non-empty `failures` exits 1, and the
bash wrapper `run_driver` turns that into one `ok`/`no` line. A case is named
by the description string passed to `run_driver`, which reads
`agile-loop.js: <what the run does>`. Nothing is mocked: the real workflow
source is compiled and run, with `agent`, `log` and `phase` stubbed, which is
also what proves the script uses no other runtime.

**Fixture changes first.**

- `stateOf` takes the answer: `const stateOf = (increments, runSteps, decisions) => ({ exists: true, branch: 'issue-branch', increments, runSteps, decisions: decisions || '', summary: '' })`.
  `noState` gains `decisions: ''`.
- `DISJOINT_MARKERS` gains `'MARKER-BUILD-QUESTION'` and
  `'MARKER-HUMAN-ANSWER'`. Neither contains nor is contained by an existing
  marker, and the standing containment loop at the top of `main` checks that.
- A new fixture beside `questionState`, with the comment saying why the
  implementer is the role this case is built on — its page and the read barrier
  close `issue.md` to it, so it is the role whose resume the old prompt broke:

```js
const buildQuestionState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [
          idxStep('research:i1.0', planReturn),
          idxStep('tests:i1.0', testsReturn),
          idxStep('implement:i1.0', Object.assign({}, buildReturn, { questions: ['MARKER-BUILD-QUESTION'] })),
        ],
      }),
    ],
    [idxStep('decompose', decomposeReturnOne)],
    'MARKER-HUMAN-ANSWER',
  );
```

- `contextFor` gains
  `case 'w19': return { stateReturn: buildQuestionState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };`
- The modes list gains, inside the `for wf in ...` loop after the `w18` line:
  `run_driver "$wf" w19 "$wf_name: a resumed run hands the step that asked the human the answer in its prompt"`

**Case 1 — the finding, as a new `w19` branch** (criterion: a resumed run
delivers the human's answer to the implementer without ordering a read its page
forbids). Input: the state above, whose `implement:i1.0` asked
`MARKER-BUILD-QUESTION` and whose loader returned `MARKER-HUMAN-ANSWER`.
Assertions, in this order:

1. `assertEqualArrays(labels, ['load-state', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'], ...)` —
   the recorded researcher and test-author stay skipped and the step that asked
   is worked again.
2. The `implement:i1.0` prompt includes `MARKER-BUILD-QUESTION` — the question
   it asked is in front of it.
3. The `implement:i1.0` prompt includes `MARKER-HUMAN-ANSWER` — **this is the
   assertion that is red today.**
4. `assertTrue(!/## Decisions/.test(p), ...)` — it is handed the answer, not
   pointed at the heading it may not go and read.
5. `assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 0, ...)` —
   the resumed run carries on to a clean close.

**Case 2 — the empty edge, folded into the existing `w9` branch** (criterion:
the same route when the human recorded nothing). `questionState()` passes no
third argument, so `decisions` is `''`. Keep w9's first assertion (the
prompt carries `MARKER-HUMAN-QUESTION`) and its last (the run makes progress).
Replace the middle assertion — the one that today requires `/## Decisions/` and
`/issue\.md/` in the researcher's prompt — with:
`assertTrue(!!researchCall && /The human recorded no answer/.test(researchCall.prompt), "the repeated step is not told that no answer came back, so it cannot tell an empty answer from a missing one");`

**Case 3 — the loader is asked for the section, in the existing `w1` branch**
(criterion: the answer has a route into the script at all). Beside the existing
`loader` assertions: the `load-state` prompt matches `/## Decisions/` and
includes `docs/issues/x/issue.md`, with a message saying the human's answer
would reach no resumed step otherwise.

**Case 4 — a standing guard, checked in every mode.** Add a third loop beside
the two that already run over every call ("no prompt may read a step whole",
"the publish prompt reads nothing"), after them:

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

It is scoped to the implementer and to `issue.md` on purpose: the reviewer's
prompt legitimately contains a line with both "Read" and `backlog.json` — the
sentence forbidding it — so a generalised version would fire on correct text.

**Left untested, deliberately.** A resumed *researcher* with an answer
recorded: it is the same `answeredBlock` branch w19 exercises, and w9 already
holds the researcher's resume. A `decisions` string that is only whitespace:
`.trim()` puts it on the empty branch Case 2 covers. The state loader actually
finding the `## Decisions` heading in a real file: that is an agent following
its prompt, and no driver mode can dispatch a real one. `hooks/read-barrier.mjs`
itself: not edited, and its suite already pins the refusal.

### What counts as done

Closed list, run from the repository root:

    bash test-repo.sh

Nothing else. The hook is not touched this round, so
`node --test hooks/read-barrier.test.mjs` is deliberately off the list — its 26
cases judge a file this round does not edit, and `test-repo.sh` still checks
that the hook is wired, parses and opens nothing. `bash test.sh` is off it for
the same reason it was in Round 0: it would re-run three `npm` suites over
untouched code. `bash -n test.sh` is off it because `test.sh` is not edited
this round.

### What is already red

I ran nothing, not once and not as a baseline. From reading, and from the exit
codes the reviewer reported for the same tree: `bash test-repo.sh` passes as it
stands. The assertions above are the intended red — Case 1's third assertion
above all, which fails until the answer travels in the prompt, plus Case 3 and
the rewritten middle of w9. Case 4 is red in the new `w19` mode as well, and
green in every existing one: the old text puts "Read it there first" and
`issue.md` on one line, and only a mode whose implementer carried a question
renders that line at all. Anything else that comes back red
belongs to code this change never touched: report it with its exit code and
leave it alone.
