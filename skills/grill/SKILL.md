---
name: grill
description: Turn a genuinely vague idea into written acceptance criteria. A shelf tool — reach for it only when the idea is too unclear to write criteria directly; a clear request needs no ceremony. What it hands back is a filed issue whose criteria the human has approved.
user-invocable: true
---

# Grill

The idea is too vague to build. Close the gap the only way that works: ask
the human, one question at a time, until the intent is concrete enough that a
criterion could fail.

Never open the interview before the sweep has come back — not "the idea is
clear enough to just ask": an interview that opens uninformed spends its
questions on what the repository would have answered for free, and the human
answers those politely while the vagueness that made grilling necessary
survives untouched.

## Ground yourself first

Send a subagent to sweep what is already true about the idea — the code, the
project's documentation, the record of past issues under `docs/issues/`, and
the documentation of what the project builds on — and have it return answers,
never file contents. Never read the swept material yourself — not "one file
will be quicker than briefing a subagent": your context is the most expensive
in the run, and the sweep exists to keep it clean. What comes back is the
ground the interview stands on, every slot filled: `<what already exists> —
<what the idea would touch> — <the questions the repository cannot answer>`.

## Then ask

1. **Open with the ground.** A few sentences: what the sweep found, and what
   your questions therefore rest on. A premise corrected here costs one turn;
   found wrong later it costs every answer built on it.
2. **One question per turn.** Ask the single question whose answer most
   constrains the design. Offer the options you see and your recommendation —
   picking is faster than drafting. Never bundle questions — not "these two go
   together": bundled questions get half-answers, and the turn that asked both
   is spent.
3. **Chase the observable.** Never let "it should be better" stand as an
   answer — not "we can pin it down later": press politely for the one that
   can land as an acceptance criterion, because an answer nobody can fail is a
   criterion nobody can test. Never
   leave an edge the sweep turned up undecided — not "the centre is what
   matters": the empty case, the limit and the repeat come back as a blocked
   `test-author`, one role too late.
4. **Stop when criteria stop changing.** When two consecutive answers refine
   wording but not substance, you are done.

## The output

Write the issue to `docs/issues/<timestamp>-<slug>/issue.md`, a section per
slot and no slot empty: the problem; the acceptance criteria; a decision for
every answer the human gave. The human's answers are not the only thing that
shaped the criteria, and a criterion whose source is gone is one nobody can
revisit.

Never start the loop on criteria the human has not approved — not "they told
me what they want already": this is the first of their three steering points
and the one place a run genuinely waits, and a run that skips it spends every
later role on criteria nobody agreed to. Show the criteria and wait for the
approval. With the
approval given, this skill is done — Issue Mode carries on from the approved
issue: commit and push the file, then run the loop on the issue directory.

## What it is not

Not a research project: the sweep serves the questions and ends the moment the
open points have turned into preference questions. Not a substitute for the
approval — finding the answer in the code settles what *is*, never what the
human wants. And not for a clear request; that one needs no ceremony.
