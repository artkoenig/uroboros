# A decidable question gets a ruling, not a blocked run

## Problem

Any step return with a non-empty `questions` list ends the run, whatever the
question weighs. The rulebook already gives the session a finer rule — a
material question parks the work, anything else takes a recorded default — but
no subagent has that distinction, so a question a default would have settled
costs the whole round trip through the human: the run stops, the human answers,
the workflow restarts. A wrong default costs rework the human can see and
undo in review; a parked run costs their day and buys nothing.

The pattern is proven elsewhere: obra/superpowers ships it as "Rulings, not
stalls" (`skills/subagent-driven-development/SKILL.md`) — four stop conditions,
everything else decided and disclosed — after measuring a session that sat
blocked for nine hours on a question its controller could have decided.

## Acceptance criteria

- The shared brief distinguishes a material question from a decidable one, in
  the same terms the rulebook gives the session: user-visible behaviour, a
  public contract, the data model, the dependency footprint, or anything
  irreversible is material; everything else is decidable.
- A material question still goes into `questions` and still ends the run.
- A decidable question never goes into `questions`: the agent picks a default
  and records it in a step-return field `rulings`.
- Each ruling is one string naming the decision, the reason, and what it costs
  if the default is wrong, short enough to survive the steering projection.
- The workflow result carries every ruling of the run.
- The pull-request body lists the run's rulings under their own heading, so no
  decision taken on the human's behalf reaches them only through
  `backlog.json`.
