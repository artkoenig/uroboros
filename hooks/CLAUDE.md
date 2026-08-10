# hooks/

The plugin's three hooks, declared in `hooks.json` and shipped by `plugin.json`.

`session-start.sh` puts the rulebook in front of a starting session and warns a
cloud session running an outdated plugin. `backlog-changed.mjs` follows
`backlog.json` and pushes a run's state to the telemetry collector as the run
writes it. `read-barrier.mjs` refuses a read an agent's own page forbids it.

That second one is the only place in uroboros that talks to a collector. The
recorder every agent writes its step through used to do the send itself, which
put a network call and a pair of environment variables inside every step of
every run and gave the workflow's agents a reference to something they must
know nothing about. The hook is what replaced it: the writers write, and this
watches from outside.

It hangs off `PostToolUse` on `Bash` rather than the `FileChanged` event that
describes exactly what it does, because `FileChanged` is not in every Claude
Code that runs this plugin yet and a hook that silently never fires is worse
than one that fires often. The recorder is always run as a Bash call, and tool
events fire inside a subagent the same as in the main conversation — which
matters, because every write of a run state is made by a subagent.

Firing often is paid for by the order of the gates: no collector in the
environment first, then the tool, then a command that never mentions a run
state, then a document identical to the one already sent. A run reads its state
several times for every write, and that last gate — a digest of the last
accepted document, kept per file in the temp directory — is what keeps the
reads off the wire.

The third one is the only place in uroboros that stops an agent doing
something. Three of the rules the agent pages carry are barriers between roles
— the implementer does not read `issue.md`, the reviewer does not read
`backlog.json`, no agent reads a field of a step its page does not grant it —
and until this hook they were honour-system. A role that reads the document
written for another role is a role whose fresh context was not fresh, and that
is the one failure a run cannot see in its own result. The pages still own
those rules; this is their shadow, and every entry in its table cites the page
it comes from, so a rule that moves moves in one place.

It hangs off `PreToolUse` on `Read`, `Bash` and `Grep`, because a file has more
than one route into a context: a `Read` by path, a `cat`, a `git show
<ref>:<path>`, a `Grep` and the backlog helper's own reading subcommands are
all the same read. It decides from the event's `agent_type` and tool input
alone — it opens no file, opens no connection and reads no environment
variable, which is what makes it cheap enough to sit in front of every one of
those calls, and the only honest position for a guard that would otherwise be
opening the state it guards.

It fails open everywhere, and that asymmetry is the whole design. A wrong
refusal blocks an agent mid-run over a call its page allows and costs a human
the run; a wrong pass costs nothing that was not already being paid before the
file existed. So only a positive identification refuses — a known reader
command naming a `docs/issues/` path with a gated basename — and everything
else is silent: an unknown agent, an ungated tool, an unparseable payload, a
command it cannot classify, and its own crash. `node -e`, `python -c` and a
`cd` before a `cat` are known holes, left open on purpose, because closing them
means guessing.

A refusal is the documented `PreToolUse` deny decision on stdout, not a
non-zero exit: the exit code stays 0 on every path, and the reason that reaches
the agent names the file or field, the page that closes it, and the route to
take instead.

## Tests for `backlog-changed.mjs`

`backlog-changed.test.mjs` spawns the real hook as a child process — the event
as JSON on stdin, exactly as Claude Code delivers it — against real files and a
real HTTP server.

### What the suite covers

The environment gate (no collector named means nothing sent and not a word
said); the send itself (`POST /api/runs`, a JSON content-type, the whole
document, and the run identified by the `issue` the state names); the fallback
id for a state that names none; a relative path resolved against the event's
`cwd` and not this process's; the unchanged-document gate, with the three reads
a run makes between two writes sending nothing and the next real write sending
again; a refused send retried by the next call rather than remembered as
delivered; a Bash call that never mentions a run state dropped without a word;
`backlog.json.tmp` not mistaken for `backlog.json`; a tool that is not Bash
refused however the matcher was read; an input that is not JSON; a state that
is not there and one that does not parse, with the write that follows sending
it whole; both environment name pairs
(`OTEL_EXPORTER_OTLP_ENDPOINT`/`OTEL_EXPORTER_OTLP_HEADERS` and
`UROBOROS_OBS_URL`/`UROBOROS_OBS_TOKEN`) configuring the address and the bearer
header; a collector that answers 500, one that refuses the connection and one
that never answers, all three exiting 0; and stdout staying empty on every
path.

The line the whole suite defends is that this hook cannot cost a run anything.
`PostToolUse` cannot block — the tool already ran — and a non-zero exit only
puts stderr in front of the agent as feedback, which would turn a collector's
bad day into something an agent has to reason about. So every failure exits 0
and says why on stderr, which on a zero exit goes to the debug log.

### Helpers and fixtures

All defined at the top of the file; every case reuses them.

- `hook` — absolute path to `backlog-changed.mjs`, resolved relative to the
  test file.
- `cleanEnv(extra)` — a copy of `process.env` with the four collector variables
  removed, then `extra` merged over it. Every child gets one, so a developer
  whose shell already exports to a real collector cannot have this suite
  talking to it.
- `tmpDir()` — fresh `mkdtemp` directory under the OS tmpdir; one per case,
  never cleaned up.
- `stateOf(extra)` — a minimal valid run state; spread `extra` to override
  fields.
- `writeState(dir, state)` — writes it the way the recorder does, through a
  temp file and a rename, and returns the path.
- `collectorStub(options)` — a real `node:http` server on `127.0.0.1:0`
  resolving to `{ url, requests, close() }`. `requests` collects every request
  as `{ method, url, headers, body }`; `options.status` answers something other
  than 200 and `options.hang: true` never answers at all.
- `runHook(input, env)` — spawns the hook with `input` on stdin (verbatim when
  it is a string, so a case can hand it something that is not JSON) and
  resolves to `{ code, stdout, stderr }`.
- `event(command, extra)` — a well-formed `PostToolUse` payload for a Bash call
  running `command`, common fields included. It carries `agent_id` and
  `agent_type` because every write of a run state is made by a subagent, and
  that is the shape the hook actually meets; spread `extra` to change the tool,
  the `cwd` or the input.
- `recordCall(file)` — the command line the recorder is actually invoked with,
  so a case exercises the string the hook has to find a path in rather than a
  convenient one.

### Where a new case belongs

Flat top-level `test(...)` calls after the helpers, in the order the hook's own
gates run: the environment, the send, the ids, the unchanged-document gate and
its retry, the calls it drops, the inputs it refuses, the file states it
tolerates, the two environment name pairs, the collector answers it tolerates,
and the stdout guarantee last.

A case about something *not* being sent asserts on `stub.requests.length`
against a stub that is genuinely listening — a stub that was never started
would pass the same assertion for the wrong reason.

A case about the unchanged-document gate needs its own temp directory: the
digest is remembered per absolute path across processes, so two cases sharing a
directory would share a memo.

### Faked vs real

Nothing is mocked. Every case spawns the actual hook against real files in a
fresh temp directory, and the collector is a real `node:http` server on a real
port in the test process. No dependencies beyond `node:test`,
`node:assert/strict`, `node:child_process`, `node:http`, `node:fs`, `node:os`
and `node:path`.

### Running it

From the repository root:

    node --test hooks/backlog-changed.test.mjs

## Tests for `read-barrier.mjs`

`read-barrier.test.mjs` spawns the real hook as a child process — the event as
JSON on stdin, exactly as Claude Code delivers it.

### What the suite covers

The three gated barriers, each pinned from both directions: the implementer's
`Read` of `issue.md` refused, the researcher's and the test-author's `Read` of
the same file passing; the reviewer refused on every one of the helper's
reading subcommands against `backlog.json` (`index`, `steps`, `codemap`,
`read`), its own `start` and `record` on the same file passing because the
gate is on reads and not writes, and its staging and committing that file
passing too; a field a role's page closes refused whether it is named in
`--fields` or the whole step comes back with no `--fields` at all, and the
three fields a page does grant passing; that no label ever decides, because
the payload never carries which step or field a prompt named. The routes to
the same file: a `Read` by path, a `cat`, a `git show <ref>:<path>` and a
`Grep` all refused alike, a `Grep` of an unrelated file passing. The fail-open
side: no `agent_type`, an `agent_type` that is not one of the three gated
keys — including the bare role name, which is deliberately not the same
string as the `uroboros:`-prefixed one the workflow dispatches with — a tool
the hook does not gate (`Write`, `Edit`), a `Bash` call the hook cannot
positively classify (`node -e`, a script it does not open), and every shape of
stdin the hook cannot use (not JSON, an array, a missing or malformed
`tool_input`) — all exiting 0 with empty stdout, several of them pinned on
empty stderr too. Last, the shape of a refusal itself: the documented
`PreToolUse` deny envelope on stdout, nothing besides it, and the process
still exiting 0.

The line the whole suite defends is that a wrong refusal is the expensive
mistake and a wrong pass is not: every case that is not a positive
identification of a forbidden read allows the call, and the suite never
asserts a deny for a route the plan did not name explicitly.

### Helpers and fixtures

All defined at the top of the file; every case reuses them.

- `hook` — absolute path to `read-barrier.mjs`, resolved relative to the test
  file, so the suite runs the same way from a checkout and from a plugin
  cache.
- `ISSUE`, `STATE` — a fixed issue directory's `issue.md` and `backlog.json`,
  absolute under `/repo`, which is the `cwd` every event below carries.
- `runHook(input)` — spawns the hook with `input` on stdin (verbatim when it
  is a string, so a case can hand it something that is not JSON) and resolves
  to `{ code, stdout, stderr }`. No `env` argument: the hook reads no
  environment.
- `event(extra)` — a well-formed `PreToolUse` payload, common fields included,
  defaulting to the implementer running an empty `Bash` call; spread `extra`
  to override any field.
- `readOf(agentType, filePath)`, `bashOf(agentType, command)`,
  `grepOf(agentType, targetPath)` — thin wrappers over `event` for the three
  gated tools.
- `helper(args)` — the command line the backlog helper is really invoked
  with, plugin-cache path and all — the string the hook has to find a
  subcommand and a path in, not a convenient one.
- `allows(result, context)` — asserts `code === 0` and `stdout === ''`;
  `context` is folded into the assertion message so a case built from a loop
  or a table says which entry failed.
- `denies(result, ...substrings)` — asserts `code === 0`, that `stdout` parses
  as the documented deny envelope, and that `permissionDecisionReason`
  contains every one of `substrings`.

### Where a new case belongs

Flat top-level `test(...)` calls after the helpers, in the order the hook's
own gates run: the roles and their files, then the fields, then everything
that passes, then the shape of the refusal and the exit code.

### Faked vs real

Nothing is mocked and nothing is stubbed. Every case spawns the actual hook
against a JSON payload built in the test; unlike the neighbouring suite, no
temp directory and no server are needed at all, because the hook decides from
the payload and never opens a file.

### Running it

From the repository root:

    node --test hooks/read-barrier.test.mjs
