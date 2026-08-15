---
paths: agents/**
---
# The subagents

This is `agents/`'s own page, and it sits here rather than in `agents/CLAUDE.md`
because plugin discovery reads every `agents/*.md` as an agent — a `CLAUDE.md`
there would register as a nameless one. Its `paths:` frontmatter is what keeps
it out of a startup context:
an unscoped rule loads at launch and is inherited by every subagent the session
dispatches, and this page exists only in this checkout, so an agent would hold
it here and nowhere else. Scoped, nobody is handed it uninvited — inheritance
passes on what the session loaded at launch, and a path-scoped rule is by
definition not that.

It still reaches whoever actually works here. A reader that opens a file under
`agents/` loads this page for itself, and a subagent does so on its own reads,
not only the session — measured with a probe agent that read
`agents/test-author.md` and held this page afterwards. So scoping costs an agent
nothing it needs; it only stops the page from arriving where it is irrelevant.
What an agent needs before it reads anything is a different matter, and that
belongs in the shared brief.

One agent is one flat `<name>.md` in that directory, and every one of them is
listed in `plugin.json`'s `agents` field. That list is not decoration: for a
plugin, agent discovery scans `agents/` *recursively*, and a subdirectory
becomes part of the name — `agents/review/security.md` registers as
`uroboros:review:security`. Without the list, every `.md` anywhere below loads
as an agent of its own — a skill an agent preloads, above all. Declaring the
files replaces that scan. Never add an agent without adding its line — not
"discovery scans the directory anyway": nothing compares the list with the
directory, so a missing line is an agent that is simply not there in any
session.

An agent may own a directory beside its page, `<name>/` next to `<name>.md`,
for what belongs to it alone — the skills it preloads, under
`<name>/skills/<skill>/SKILL.md`, declared in `plugin.json`'s `skills` field.
Anything else under `agents/` is in the tree and unreachable.

## What every agent shares

What holds for every agent at run time — what always binds it, how it takes its
brief, how it spends its tools, how it reports a run, how it records, commits
and pushes its step return, and the check mode — lives in
`skills/agent-brief/SKILL.md`, and
every agent page names it in `skills:` so it is injected at startup. That skill
ships with the plugin, so it is the only channel that reaches an agent in every
project alike. This page is for whoever writes the agents; the shared brief is
for the agents.

An agent holds exactly three things: its own page, the shared brief, and
whatever memory the host project itself provides. Nothing uroboros owns may
reach it by any other route, or the same agent behaves differently here than in
a project that installed the plugin. That is why the rulebook reaches the
session through the SessionStart hook and is named `rulebook.md` rather than
`CLAUDE.md` — the hook fires for a session and never for a subagent dispatched
inside one, while a `CLAUDE.md` here would load as project memory and be
inherited, which no installing project can reproduce — and why every page in
`.claude/rules/` carries `paths:`, which `test-repo.sh` checks.

So a page here may only carry what someone developing uroboros needs, and this
one — about writing the agents — is that. Never make a page here the only home
of a rule that binds a run — not "whoever works here will read it": an agent
dispatched in a project that installed the plugin holds nothing from this
directory, so the rule binds nobody in the one place it had to. `docs/` had
such a page, and its writing rules moved into the shared brief, where every
project gets them. Scoping keeps a rule from the
wrong reader; it cannot make one exist where this directory does not.

Three rules bind the session and the agents alike: English, the default branch
moving only through a merged pull request, and the test that decides whether a
question stops the work. They stand in the rulebook and in the
shared brief, because the two audiences have no channel in common. Never edit
one copy without editing the other — not "the other one can follow later": no
check compares them, and the copy left behind runs the session and the agents
on different rules until somebody notices.

So an agent page carries its role and the boundaries of that role alone. What
decides whether a sentence the shared brief also carries may stand on the page
is whether that sentence still has to work when the brief did not load. A
sentence that reaches the agent only once the brief has loaded stands in the
brief alone: a rule that stands in both drifts.

A sentence that has to work when the brief is missing stands on the page, and
one sentence meets that — the line that opens every page, telling the agent to
report the shared brief as missing and stop. A skill that failed to load cannot
announce its own absence, and Claude Code skips an unresolved `skills:` entry
with nothing but a line in the debug log — so without that opener an agent runs
on half its rules and nobody hears about it.

The form a rule on an agent page takes is decided by
`.claude/rules/authoring.md`.

## What a page has to carry

- **Frontmatter**: `name`, `description`, `tools`, `skills`, `color`. The
  `description` is what a caller reads while deciding — say what the agent
  does and what not to use it for. It is read far more often than the body.
  `skills` carries `agent-brief` and whatever else that agent alone preloads.
  `model` is left out, so the agent runs on the session's model. Where the work
  of an agent is mechanical enough that a smaller model cannot get it wrong,
  its page may name that tier in `model`, and a page that names one says why.
- **The body** is what the shared brief does not already cover, every slot
  filled: the role; how it works; the boundaries that belong to it alone; the
  shape of its report. Beyond the brief it has no context — a caller's
  reasoning never reaches it.

## The page is the interface

The rulebook binds every dispatch to what this page declares: whatever the
page says the agent does *not* get is not handed over, and whatever it says
the agent may not do is not asked of it. The boundaries slot carries both and
leaves neither empty: what the agent does not get; what it may not do — an
implementer that may not edit the tests, a test-author that has never seen an
implementation, a reviewer that sees only the diff and the intent. An omission
here becomes a leak in every run.

Give each agent the narrowest tool list that does its job. Never hand a role a
tool its work does not need, and never hand a read-only role a writing tool —
not "it may as well have it in case": the tool gets used, and the boundary the
page declared is gone from that run on.

Give it nothing about the project beyond the issue directory under
`docs/issues/`. Never hand it a path beyond that directory — not "one path
saves it a search": the agent reads what its role was never given, and the
independence the next role rests on is gone. The next agent finds what it needs
in the run state, `backlog.json`, through the reads its prompt names, and a
reviewer derives the intent from the issue file and git instead, its diff range
already bounding what it may see.
