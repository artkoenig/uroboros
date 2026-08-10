# Test-author

## Round 1

Wrote the one block the researcher's test plan asked for, in `test-repo.sh`,
inserted at the point the plan named — after the `=== every agent page is
declared` block's closing `fi` and before `echo "=== every test suite carries
its doc"` (the researcher's "line 1496" landed there once the file's own
line count was accounted for). Header: `echo "=== the reviewer proves a doubt
with a probe in the sandbox"`.

### R1 — the page carries every rule the probe needs

Became the first case in that block: a `declare -a reviewer_probe_patterns`
table of the eight patterns the plan specified verbatim (one per criterion,
two for criterion 2), matched case-insensitively with `grep -qiE` over
`agents/reviewer.md` collapsed with `tr '\n' ' ' | tr -s ' '`, exactly as the
`argus_view_patterns` loop the plan pointed at does it. `ok "agents/
reviewer.md carries every rule the probe licence needs"` / `no "these
patterns for the probe licence matched nothing in agents/reviewer.md:"` with
the miss list indented.

Ran `bash test-repo.sh`: this case fails now, printing all eight patterns as
misses — the page carries none of the probe licence yet:

```
FAIL — these patterns for the probe licence matched nothing in agents/reviewer.md:
       probe[^.]*sandbox|sandbox[^.]*probe
       probe[^.]*checkout|checkout[^.]*probe
       probe[^.]*commit|commit[^.]*probe
       probe[^.]*diff|diff[^.]*probe
       probe[^.]*doubt|doubt[^.]*probe
       probe[^.]*(list|closed)|(list|closed)[^.]*probe
       probe[^.]*test-author|test-author[^.]*probe
       probe[^.]*returned|returned[^.]*probe
```

### R2 — the old prohibition is gone

Became the second case: `grep -inE 'not even a throwaway|never write a test'`
against `agents/reviewer.md` (ungathered, so the offending line number is
visible), guarded with `|| true` per the file's convention for a grep whose
empty result is legitimate. `ok` on empty, `no` with the matched line
otherwise.

Ran `bash test-repo.sh`: fails now, correctly, because the prohibition is
still on the page as it stands:

```
FAIL — the old blanket prohibition is still on agents/reviewer.md:
       90:a test to prove a finding, not even a throwaway. Reading, `git show` and running
```

### R3 — the review's summary reports the probes

Became the third case: `grep -A3 -- '- \*\*`summary`\*\*' agents/reviewer.md`
(guarded with `|| true`), then `grep -qi 'probe'` on that slice, anchoring on
the `summary` bullet itself rather than the whole page — exactly as the plan
required, to keep this the one criterion R1's table does not already cover.

Ran `bash test-repo.sh`: fails now, correctly — the current bullet says
nothing about a probe:

```
FAIL — the summary bullet on agents/reviewer.md does not mention a probe:
       - **`summary`** — one sentence on the review, the run of the listed commands
         included.

       Your prompt names every field this step returns. Record the return into
```

### R4 — only the reviewer's page licenses a probe

Became the fourth case, a direct mirror of the existing `chain_depth_owners`
case: `grep -lie 'probe' agents/*.md skills/*/SKILL.md` must return exactly
`agents/reviewer.md`.

Ran `bash test-repo.sh`: fails now, correctly — no page mentions a probe yet,
so the owner list comes back empty instead of naming `agents/reviewer.md`:

```
FAIL — the word "probe" is owned by more (or fewer) pages than agents/reviewer.md alone:
       (none)
```

### Full run

`bash test-repo.sh`, from the repository root, exit 1, `FAIL: 4 of 75 cases`.
The four new cases above are exactly the ones red; every case that existed
before this change still passes — confirmed by reading the full output: all
71 pre-existing cases print `ok`, only the four new ones print `FAIL`, and
each failure is the missing-behaviour kind the plan predicted (a pattern
table with every entry missing, a still-present old sentence at its real line
number, a `summary` bullet without the word, an empty owner list) — none is
an import error, a syntax error, or a typo in the case itself. `git diff
--stat` confirms only `test-repo.sh` changed (77 insertions, 0 deletions).

### Left untested, as the plan directed

Per the plan's own "Left untested, and why": no case pins the wording of any
sentence, no case touches `agents/test-author.md`'s one clause, no case
checks for the leftover narrow merge-base sentence, and no case tests
criterion 2's runtime half (that a probe never reaches a real commit). All
four are the plan's explicit calls, not gaps I introduced.

### Gaps and conflicts found

None. The plan gave exact patterns, exact anchors, an exact insertion point
and an exact predicted failure for each case, and every one matched what
`bash test-repo.sh` actually produced on the pre-edit tree. No case was too
vague to pin, and no case contradicted the criterion it claims to cover.

## Round 1

The reviewer's reproduction spec (Round 1 of `researcher.md`) is a single
case, `R1'`, replacing the old `reviewer_probe_patterns` case in the block
`=== the reviewer proves a doubt with a probe in the sandbox` of
`test-repo.sh`. It became one case and nothing else — the plan directed that
the other three cases in that block (the old-prohibition case, the
`summary`-bullet case, the owners case) stay untouched, and I left them
exactly as they were.

### R1' — every rule the probe licence needs stands in its own paragraph

Replaced lines 1500–1535 — the comment and the `reviewer_probe_patterns`
table, from `# docs/issues/2026-08-10-reviewer-probes-in-the-sandbox lifts
the reviewer's` down to the `fi` that closed it — with the three-mechanism
case the plan specified: a `declare -a reviewer_probe_rules` array of seven
colon-separated entries (heading pattern, label, then one or more terms), an
`awk -v RS='' -v want="$want"` extraction in paragraph mode scoping to the
section whose heading matches `want`, and a per-rule filter that pipes the
section's paragraphs through one `grep -iE -- "$term" || true` per term,
verbatim as the plan's table gave it. Kept `reviewer_probe_page="$root/
agents/reviewer.md"` — the plan's replacement range technically starts before
it, but the three cases below it in the same block (`R2`, `R3`, `R4`) all
read `$reviewer_probe_page`, so dropping its definition would break them; I
kept it defined once, where it already was, and only removed
`reviewer_probe_collapsed`, which nothing after the old table used. `ok
"every rule the probe licence needs stands in its own paragraph of
agents/reviewer.md"` / `no "these rules of the probe licence stand in no
paragraph of agents/reviewer.md:"` with the miss list indented, matching the
plan's suggested strings.

The seven rules, exactly the plan's table: heading patterns `^## .*probe`
(five rules: criteria 1, 6, 2, 5, 3-evidence), `^## .*reproduction`
(criterion 3-spec) and `^## what you record` (criterion 4), each with the
terms the plan listed. I wrote the criterion-3-evidence label as "a probe is
evidence and the pinning test stays with the test-author" rather than the
plan's "…stays the test-author's" — the possessive apostrophe inside a
single-quoted array-literal entry would have needed a `'"'"'` escape, and the
plan states the label is what a failure prints, not a rule the case matches
on (the matching is by term, not by label text), so the rewording changes
nothing the case pins.

### Round 1 — no red-first phase, as the plan predicted

Ran `bash test-repo.sh` from the repository root after making this one edit:
`PASS: 75 cases`, exit 0 — every case passes, including the new `R1'`,
printing `ok — every rule the probe licence needs stands in its own
paragraph of agents/reviewer.md`. This matches the plan exactly: "This round
has no red-first phase, and that is deliberate: the page already carries
every rule, so the replacement case passes from its first run… Implementer:
there is nothing to implement this round." The plan's own "What is already
red" for this round said the run must still print "75 cases and exit 0
afterwards" — it does. `git diff --stat` confirms only `test-repo.sh`
changed: 36 insertions, 26 deletions, no other file touched.

I did not verify red-on-regression myself by editing `agents/reviewer.md`
and reverting it — that file is production text I do not touch, edit or
open beyond the plan's own description of its headings and paragraphs, and
the plan already carries that verification ("I ran a prototype of the
proposed case… against fourteen copies of agents/reviewer.md" — deletions of
each probe paragraph, the whole `## The probe` section, the `findings` probe
paragraph, the reproduction-rule sentences, and rewordings/heading renames —
"the matching rule misses each time" / "no misses"). That offline
verification is the plan's, not mine to repeat inside the checkout.

### Left untested, as the plan directed

Unchanged from Round 0 and restated in this round's plan: no case pins the
wording of any sentence; `agents/test-author.md`'s clause and the
`README.md` sentence stay untested (prose the review reads, and a grep over
them would fail on any correction the reviewer asks for); criterion 2's
runtime half (that no probe ever reaches a real commit) is untestable here,
a property of a future run and not of this repository.

### Gaps and conflicts found

None. The plan gave the exact heading patterns, the exact terms per rule,
the exact `awk` extraction (which I used verbatim), the exact replacement
line range, and an exact predicted outcome (75 cases, exit 0, no red-first
phase) — and every part of it matched what `bash test-repo.sh` produced. The
one place I departed from the plan's literal text was the label string for
the criterion-3-evidence rule (dropping a possessive apostrophe that would
have forced an escape inside a single-quoted bash literal); the plan itself
says a rule's terms are what a rewording must keep, not the label, so this
is not a conflict with the plan, only a note for whoever reads the diff next
to why that one string differs from the table verbatim.
