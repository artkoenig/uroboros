# backlog.mjs answers a help flag

## Problem

The backlog helper prints its usage only when a call is already wrong: there
is no way to ask for it, so whoever checks the calling convention has to
provoke an error first.

## Acceptance criteria

- `node skills/agent-brief/assets/backlog.mjs --help` prints the usage to stdout and exits 0.
- `node skills/agent-brief/assets/backlog.mjs -h` behaves exactly like `--help`.
- A call with an unknown command keeps exiting 2 with the usage on stderr.
