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
