# A hook enforces the barriers the pages only ask for

## Problem

Every information barrier in a run is a sentence on a page. The implementer
"does not read `issue.md`", the reviewer "never reads `backlog.json`", an agent
"takes no other field" of a step its prompt did not name. Nothing enforces any
of it. The implementer's tools are `Read, Write, Edit, Bash`, the issue file
sits at a path it can infer in one guess, and the run state is a file any agent
can read with the helper it already runs. The barriers hold because the agents
follow their pages, and they hold exactly as well as that.

That is thin for the thing the whole design rests on. The reviewer's worth is
that it saw no plan; the test-author's is that it saw no implementation. If one
of them reads what it should not — not out of malice, but because a page is
long and a path is one line away — nothing in the run notices, and the review
that follows is worthless in a way no one can see from its output.

The enforcement is available and unused. Tool events fire inside a subagent the
same as in the main conversation, and the payload carries `agent_type`, so a
hook can tell which role is calling — `backlog-changed.mjs` already meets that
shape and its suite already builds payloads with it. And unlike `PostToolUse`,
which cannot block because the tool has already run, a `PreToolUse` hook can
refuse the call before it happens.

## Acceptance criteria

- [ ] A `PreToolUse` hook refuses a read that the calling agent's page forbids,
      deciding from the event's `agent_type` and the tool input alone.
- [ ] It enforces at least these three, each of which is visible in the payload:
      the implementer reading `issue.md`; the reviewer reading `backlog.json`
      through any of the helper's reading subcommands; an agent reading a field
      of a step through the helper that its role is not given.
- [ ] It covers the routes to the same file, not only the obvious one: a `Read`
      by path and a `Bash` command that reads the same path are the same
      violation and are refused alike.
- [ ] It fails open. A call it cannot positively identify as forbidden goes
      through, and so does every call if the hook itself errors: a wrong refusal
      stops a run that may have been working for hours, a wrong pass costs a
      barrier that was honour-system until now. The two are not the same price.
- [ ] A refusal reaches the agent as its reason, naming what it may not read and
      which page says so, so the agent corrects its route instead of retrying
      the same call.
- [ ] It gates nothing it cannot see. Which steps and fields a prompt named is
      not in the payload, so that rule stays with the pages and the shared
      brief, and the hook never guesses at it.
- [ ] An event that is not a uroboros agent's, and a tool the hook does not
      gate, pass without a word and without a cost — the gate order that keeps
      `backlog-changed.mjs` off the wire applies here too.

## Non-goals

- This is not a security boundary. The agents are forgetful, not adversarial;
  the hook catches the route a forgetful one takes and is no proof against one
  that is trying. Claiming more of it would be worse than not having it.
- It does not replace the pages. Every rule keeps the owner it has, and the
  hook enforces the part of it that is mechanically visible — never a second
  statement of the rule that drifts from the first.
- It does not gate writes. Which files an agent may change stays its page's,
  and the commit it makes is judged by the reviewer like everything else.
