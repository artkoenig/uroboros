# Implementer handoff — a hook enforces the barriers the pages only ask for

## Round 1

Built the plan in `researcher.md`: the new `PreToolUse` hook, its wiring, its
entry in the suite runner, and the prose the module map assigns to me. Wrote no
test and edited none — `hooks/read-barrier.test.mjs`, the
`## Tests for read-barrier.mjs` section of `hooks/CLAUDE.md` and the
`=== the read barrier is wired…` section of `test-repo.sh` are the
test-author's and are untouched.

### The red I started from

Ran all three commands before changing anything.

- `node --test hooks/read-barrier.test.mjs` — 26 tests, 0 pass, 26 fail, exit
  1. Every failure is `spawn /home/user/uroboros/hooks/read-barrier.mjs
  ENOENT`: the file did not exist. The intended red, and the same one the
  test-author recorded.
- `bash test-repo.sh` — 62 cases, `FAIL: 4 of 62 cases`, exit 1. The four are
  exactly R1, R2, R3 and R5 of the new section: `hooks.json` did not subscribe
  the hook, the file was missing and so not executable, it did not parse, and
  `test.sh` did not list its suite. R4 already reported `ok`, for the reason the
  test-author flagged — a `grep` against a file that does not exist finds
  nothing.
- `bash -n test.sh` — exit 0.

### What I changed

**`hooks/read-barrier.mjs` — new, the whole hook.** `#!/usr/bin/env node`, ESM,
executable bit set, `import path from 'node:path'` its only import. Structure
follows the plan's gate order: read stdin to the end, parse it, look the
`agent_type` up in the rule table and return if it is absent, check the tool
name, then collect the reads out of the tool input and print the first refusal.
One `try/catch` around the whole of `main`, `process.exit(0)` at the end, and no
write to stderr on any path.

- The rule table is one object keyed on the three `uroboros:`-prefixed agent
  types, each entry carrying its role name, its page, its forbidden file, its
  forbidden fields and the route-to-take-instead clause of its reason. Each has
  the plan's citation as a comment beside it.
- `tokenize` walks the command tracking single and double quotes and a
  backslash escape, dropping the quotes that only bound a word and emitting
  `;`, `&&`, `||`, `|`, `&`, `<` and `>` as their own tokens. `segmentsOf`
  splits on the separators; `splitRedirects` takes the operand of a `<` as a
  read and drops the operand of a `>` entirely; `stripPrefixes` drops leading
  `VAR=value` assignments and a leading `sudo`, `command` or `time`.
- `readsOfSegment` classifies one segment: the helper (head basename `node`,
  some token's basename `backlog.mjs`), then a reader command from the plan's
  list or `git show`/`git cat-file`. Anything else returns no paths, which is
  the passing side. For `git`, a `<ref>:<path>` token is cut at its last colon;
  for other readers the token is used as it stands, so a path that happens to
  contain a colon is not silently rewritten.
- `namesGatedFile` resolves against `event.cwd` (falling back to
  `process.cwd()`), and requires both the exact basename the role's rule names
  and a `docs`/`issues` pair among the resolved path's segments.
- Fields are read only off the helper's `steps` subcommand, in both
  `--fields a,b` and `--fields=a,b` shapes; absent `--fields` for a role with a
  field list is the "whole step" refusal. No label is ever looked at.

**`hooks/hooks.json`** — gained a `PreToolUse` array before the existing
`PostToolUse` one, matcher `Read|Bash|Grep`, command
`"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/read-barrier.mjs"`, in the shape the two
existing entries use.

**`test.sh`** — a `run "hooks: the read barrier" node --test
"$root/hooks/read-barrier.test.mjs"` entry after the run-state hook's and
before the three `npm` suites, with a one-line comment in the style of its
neighbours.

**`hooks/CLAUDE.md`** — the opening line now says three hooks and names the new
one, and four paragraphs after the collector prose explain the barrier hook:
why it exists and that the pages keep the rules, why `PreToolUse` on those
three tools, that it decides from the payload alone, why it fails open and
which holes are deliberate, and why a refusal is a deny decision rather than a
non-zero exit. The `## Tests for read-barrier.mjs` section below it is the
test-author's and I did not touch it.

**`README.md` line 305** — "seven suites" became "eight suites" with the read
barrier named in the list.

Nothing else was changed. `workflows/agile-loop.js`, `agents/*.md`,
`skills/agent-brief/SKILL.md` and `skills/agent-brief/assets/backlog.mjs` are
untouched, as the module map says.

### What I ran, and what it says now

The closed list from the plan, run from the repository root. Nothing else — the
plan leaves `bash test.sh` off deliberately, and this repository has no linter
and no formatter.

- `node --test hooks/read-barrier.test.mjs` — 26 tests, 26 pass, 0 fail, 0
  skipped, exit 0.
- `bash test-repo.sh` — `PASS: 62 cases`, exit 0. The four that were red (R1,
  R2, R3, R5) are green; no other section regressed.
- `bash -n test.sh` — exit 0.

Nothing is red. Nothing was skipped or excluded.

### Notes for the reviewer

- **I departed from the plan's letter in one place, to protect its intent.**
  The plan says the hook ends in `process.exit(0)`, and it does — but
  `process.exit` can truncate a pending `process.stdout.write` on a pipe, and
  the refusal *is* that write, so a truncated deny would be a flaky, silently
  wrong pass. The hook therefore awaits the write's completion callback (the
  `emit` helper) before falling through to `process.exit(0)`. The exit code is
  still constant at 0 on every path, which is the property the plan wanted from
  that line.
- **R4 cannot go red on a missing file**, as the test-author flagged. It is
  green now for the right reason — the hook imports only `node:path` and
  contains none of the forbidden strings anywhere, comments included — but it
  was green before the hook existed too, so it never contributed to the red
  signal. Not something I could fix without editing a test.
- **The plan's reason wording is followed almost verbatim**, with one
  generalisation: the test-author's page has no file barrier, so its `instead`
  clause for a file refusal is never reachable and I gave it the implementer's
  wording as a placeholder. If that ever becomes reachable it should be
  rewritten.
- **Scope I noticed and left alone.** The `Grep` gate cannot tell a directory
  path from a file path without opening it, so a `Grep` whose `path` is the
  *issue directory* reaches the same content and passes. That is the same class
  of accepted gap as `cd`-then-`cat`, and the plan does not ask for it.
- No blocking question.
