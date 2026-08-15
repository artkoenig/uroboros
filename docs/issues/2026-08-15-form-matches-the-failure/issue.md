# The authoring rules pick a rule's form by the failure it prevents

## Problem

This repository's production code is largely prose: agent pages and skills
steer what the agents do, and when a page fails — an agent skips a rule under
pressure, returns the wrong shape, omits a required element — the wording of
the correction is chosen by taste. obra/superpowers measured that choice in
head-to-head wording tests (`skills/writing-skills/SKILL.md`, "Match the Form
to the Failure"): against wrong-shaped output a prohibition list performed
worse than no guidance at all while a positive recipe held; a single exemption
clause appended to a working rule degraded it from consistent to noisy; and a
description that summarises a workflow becomes a shortcut agents take instead
of reading the body — their measured case ran one review where the body
ordered two, because the description said "review between tasks". Nothing in
this repository's authoring rules carries those results, so every page edit
re-learns form through failed runs, and a failed run costs a full agent chain.

## Acceptance criteria

- The authoring rules contain a four-row form table; each row names a failure
  class, the form that works, the form that fails, and the reason in one
  sentence.
- The four rows are: a rule skipped under pressure gets a prohibition carrying
  its price and the verbatim rationalisation it counters; a wrong output shape
  gets a recipe stating what the output is; an omitted required element gets a
  required slot in the schema or template; behaviour that depends on a
  condition gets a rule keyed to an observable predicate.
- The authoring rules forbid patching an existing rule with an exemption
  clause and require re-cutting the rule on an observable predicate instead.
- The authoring rules require a description to name the occasion for using the
  thing, never its steps.
- Every shipped skill description is checked against that rule, and each one
  that summarises steps is rewritten.
- The agent descriptions are checked too, but rewritten only where a
  description contradicts the page it fronts: the workflow dispatches agents
  by name, so their descriptions serve the human reading them.
