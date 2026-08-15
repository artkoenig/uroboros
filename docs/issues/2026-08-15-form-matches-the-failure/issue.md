# An authoring rule matches the form of a rule to the failure it prevents

## Problem

The repository's pages and skills choose their form — prohibition, recipe,
template slot, condition — by the author's taste. obra/superpowers measured
the choice (`skills/writing-skills/SKILL.md`, "Match the Form to the
Failure"): against output-shaping failures, a prohibition list performed worse
than no guidance at all while a positive recipe held; a single nuance clause
appended to a working rule degraded it from consistent to noisy; and a
description that summarises a workflow becomes a shortcut agents take instead
of reading the body. Nothing in this repository's authoring rules carries
those results, so every new page can repeat the measured mistakes.

## Acceptance criteria

- The authoring rules state the form table: a rule skipped under pressure gets
  a prohibition with its price; a wrong output shape gets a recipe stating
  what the output is; an omitted element gets a required slot in the template;
  behaviour that depends on a condition gets a rule keyed to an observable
  predicate.
- The authoring rules state that an exemption clause reopens the negotiation
  and is added only with a recorded reason.
- The authoring rules state that an agent or skill description names when to
  use it, never its workflow.
- One pass over the shipped agent pages and skills flags every description
  that summarises a workflow, and the flagged ones are rewritten.
