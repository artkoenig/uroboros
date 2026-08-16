# The skills

One skill is one directory holding a `SKILL.md`. Discovery finds it by that
file alone: a directory here without one is in the tree and unreachable from a
session, and nothing announces it — the session simply never sees the skill.

A skill only one subagent ever runs does not live here. It belongs to that
agent, under `agents/<agent>/skills/<skill>/SKILL.md`, and reaches it through
the agent's `skills:` frontmatter, which injects the whole page at startup
instead of costing a `Skill` call mid-run. Never leave a location in use out of
`plugin.json`'s `skills` field — not "discovery will find it": for this
marketplace entry a declared path replaces the default scan, so an undeclared
path is a skill in the tree that no session ever reaches. `./skills/` has to
stay listed, and the first agent-owned skill adds its path alongside.
This directory is for the skills a session itself reaches, and for the shared
brief every agent preloads — that one belongs to no single agent, so it cannot
sit under any of them.

## What a page has to carry

- **Frontmatter**: `name`, `description`, and `user-invocable` where the human
  may call it directly. The `description` decides whether the skill is ever
  loaded, so it leads with the words a request would actually contain; the
  body is only read once it has won.
- **The body** is the procedure, not an essay: every slot filled — how to run
  it; what it produces; a closing "what it is not" that fences it off from the
  neighbouring skill it will otherwise be confused with.

## Interface and inside

A skill page is a contract. What a caller hands it — content and the name of
an operation — is the interface; where that content lands is behind it. Say
which is which on the page. Never put a path, a filename or a heading on the
interface side — not "the caller needs to know where it lands": a caller that
learned one is a caller that breaks the day the page moves it, and the inside
stops being free to change.

Describe each thing once, and point at the owner where another page owns a
rule. Never restate a rule another page owns — not "one sentence here saves the
reader a jump": the two copies drift apart, and whoever meets both follows the
one that is wrong.

## Where a rule belongs

A rule that binds more than one skill or more than one agent has one home:
`agent-brief`, the shared brief every uroboros agent preloads. Write it there,
and let every other page point at it rather than say it again — the section
above is why.

Nothing else reaches every agent. The rulebook the session reads is the
session's alone: a subagent starts no session and inherits none of it, so a
cross-cutting rule written anywhere but the brief binds only the page it sits
on, and the agents it was meant for never see it.

What decides is who the rule binds, not what it is about. An instruction only
one skill can carry out stays on that skill's page even when it reads like
policy; an instruction every agent has to follow belongs in the brief even
when it reads like a detail.

This section decides where a rule lives; `.claude/rules/authoring.md` decides
what form it takes.

## Assets

Commands and templates live in `assets/`, next to the page that owns them, and
are referenced relative to the page. A skill runs from a plugin cache, from
`~/.claude/skills` or from a checkout. Never hard-code a path inside this
repository — not "it resolves here": the path that resolves in this checkout
resolves nowhere else, and the skill breaks for everyone who installed the
plugin. An executable in `assets/` ships the suite that guards it beside it,
and that suite is listed in `test.sh`.
