# Researcher — the reviewer proves a suspicion with a probe

## Implementation plan

This is a prose change to the rules an agent works by. It lifts one
prohibition on the reviewer's page — "You never write a test to prove a
finding, not even a throwaway" — and replaces it with a bounded licence: a
throwaway probe, written and run inside the sandbox worktree the reviewer
already builds outside the checkout. Nothing in the workflow script, the
recorder, the hooks or any schema changes; the licence is a role rule, and a
role rule lives on that role's page.

Four files change: `agents/reviewer.md` (the whole of the rule),
`agents/test-author.md` (one clause that would otherwise contradict it),
`README.md` (one sentence, so the public account of the closed list stays
true), and `test-repo.sh` (the cases below).

### 1. `agents/reviewer.md` — the licence and its bounds

Five edits. Write every sentence in the imperative, state each rule once, and
do not restate a rule that already stands elsewhere on the page.

**a. Frontmatter `description` (line 3).** After "…separating what this change
broke from what was already red." insert one sentence:

> Inside the sandbox worktree it builds outside the checkout it may also write
> and run a throwaway probe to prove a doubt it has stated, and that probe
> never reaches the checkout or the diff.

The rest of the description stays exactly as it is.

**b. "What you check", check 1 (line 46).** Delete the sentence

> That is the one run your list does not have to name.

and nothing else in that paragraph. It is the old, narrow spelling of the
sandbox exception — one run, named as the only one — and the new section (e)
states that exception generally. Two wordings of one rule drift on the first
edit; the general one is the one criterion 5 asks for, so the narrow one goes.
The paragraph then reads "…run the same listed command at the merge base in a
sandbox. Report a pre-existing red in one line and move on; …".

**c. "The reproduction rule", last paragraph (lines 88–92).** Replace it whole
with:

> A reproduction is a spec, not a file you wrote. State it in words and hand it
> over; the test-author turns the ones that need a test into one. Reading, `git
> show`, running what already exists and probing in the sandbox get you to the
> concrete form, and a finding you cannot reach even with a probe is one round
> of test-authoring away.

The first two sentences are unchanged on purpose — criterion 3 keeps the
reproduction-is-a-spec rule standing. What goes is "You never write a test to
prove a finding, not even a throwaway", and the closing "not one file away",
which was that prohibition's tail.

**d. "You touch no code", first sentence (line 105).** Replace

> You do not write or fix production code or tests, and nothing you run may
> change the checkout.

with

> You write nothing in the checkout — no production code, no test, no fix — and
> nothing you run may change it.

The rest of that section — `git show`, `git diff`, building the sandbox with
`git worktree add` on a temporary path and removing it afterwards, and the
closing "that is a fact for your report, not a licence" — stays exactly as it
is. The scope moves from "no writing at all" to "no writing in the checkout";
what may be written in the sandbox is the next section's, said once.

**e. A new section `## The probe`,** placed between `## You touch no code` and
`## What you record`, because it builds on the sandbox that section describes.
Five paragraphs, in this order:

> ## The probe
>
> A doubt a reading cannot settle you settle with a probe: a script, a request,
> a test-shaped file, written inside the sandbox worktree, run there, and gone
> when you remove it. What it returns is the reproduction of the finding you
> file.
>
> Probe from a stated doubt, never to explore. Name the criterion and what you
> doubt about it in one sentence before you write anything, and carry that
> sentence into your report. A reviewer that goes looking is a second
> researcher, and the run pays for it twice.
>
> A probe exists in the sandbox alone: never write one into the checkout, never
> commit one, and never let one reach the diff under review.
>
> The closed list of commands does not bind inside the sandbox: running a probe
> there is not running a command the list failed to name. Outside it the list is
> closed, and what you report as green or red rests on the listed commands
> alone.
>
> A probe is evidence for a finding, never the test that pins the behaviour
> afterwards — that test is the test-author's — and a finding a probe produced
> is classified like any other.

Each paragraph is one criterion: 1, 6, 2, 5, 3. Keep the words `probe`,
`sandbox`, `checkout`, `commit`, `diff`, `list`, `doubt` and `test-author`
inside the sentences shown — the cases below match on those pairings within a
sentence, not on the sentences verbatim, so a rewording that keeps the rule
still passes and a deletion does not.

**f. "What you record".** Two field edits, and no others.

- The `findings` bullet: add one sentence as its own paragraph inside the
  bullet, after the paragraph that ends "…which is why you never make it
  yourself." and before the one that begins "That list is the whole triage":

  > Where a probe produced the finding, its `reproduction` carries the doubt you
  > stated, what the probe ran and what it returned.

  Do not put it earlier in the bullet: the sentence "That last one says how much
  of the machinery the correction needs" has to keep following "and its `fix`."
  directly, or its referent breaks.

- The `summary` bullet (lines 144–145): replace it with

  > - **`summary`** — one sentence on the review: the run of the listed
  >   commands, and how many probes you ran and what they showed.

  A review that ran none says so; that is what makes a clean review show
  whether it looked.

Nothing else on the page changes — not the `## You never read backlog.json`
section, not `reason`, `questions`, `findingCount` or `allDirect`, not the
closing sentence about recording under the label the prompt names.

### 2. `agents/test-author.md` — one clause

Line 62–63 reads "The reviewer never writes tests; you do." A probe is
test-shaped, so that sentence and the reviewer's new licence contradict each
other on their face. Replace it with

> The reviewer never writes the test that pins a behaviour; you do.

and change nothing else on that page. This is criterion 3's other half, stated
where the boundary actually binds.

### 3. `README.md` — the account of the closed list stays true

In the paragraph at lines 80–84 ("The plan also closes the list of commands the
change is judged by…"), after the sentence "Nobody runs a suite or a linter it
leaves out, and an empty list means the review is a reading." add one sentence:

> That list binds outside the sandbox the reviewer builds for another state:
> inside it the reviewer may write and run a throwaway probe to prove a doubt it
> has already stated, and what the review reports as green or red still rests on
> the listed commands alone.

One sentence, no more. The README is the public account of how a run works and
it is the one document that describes the closed list to a human; left silent
it now reads as if the list bound everywhere. Do not add a probe to either
mermaid diagram and do not touch the paragraph about findings and correction
rounds.

### 4. `test-repo.sh` — the cases

See the test plan below. Four cases in one new heading block.

## Technical decisions, including the rejected ones

- **The licence lives on the reviewer's page alone.** The shared brief's "The
  commands that count" section says the list is closed and nothing else may be
  run; the brief itself states that where the two disagree about a role, the
  role's page wins. So the exception is written on the reviewer's page and the
  brief is not touched. **Rejected:** amending
  `skills/agent-brief/SKILL.md` — it would hand every agent a probe licence,
  and `skills/CLAUDE.md` and `.claude/rules/agents.md` both say a rule that
  binds one role belongs on that role's page.
- **No workflow change.** `workflows/agile-loop.js` carries only what varies
  with a dispatch: the increment, the branch, the labels and the list of
  commands (`checkList`, line 359). The reviewer's `VERDICT` schema gives
  `summary` no description on purpose — the field's meaning is the page's.
  Criteria 4, 5 and 7 are therefore page rules, not prompt rules. **Rejected:**
  adding a probe sentence to the reviewer's dispatch prompt or a description to
  the `summary` schema property; both would be a second copy of a rule that has
  an owner.
- **No hook change.** `hooks/read-barrier.mjs` gates reads only — its
  `GATED_TOOLS` is `Read`, `Bash`, `Grep`, and `Write`/`Edit` pass by design
  (the suite pins that). A probe is a write, outside `docs/issues/` and outside
  the checkout, so nothing in the barrier touches it and nothing in it needs to
  learn about it.
- **The narrow merge-base exception is deleted rather than kept beside the
  general one.** Keeping both would state one rule twice; the general sentence
  covers the merge-base run it used to license.
- **The probe is not given a place to live, a naming convention or a cleanup
  step of its own.** The sandbox already has all three — built outside the
  checkout with `git worktree add` on a temporary path, removed afterwards —
  and criterion 2 asks for exactly that and nothing more.
- **`rulebook.md` is not touched.** It is the session's page; it says nothing
  about how the reviewer works, and a rule there reaches no agent.

## Module map

| Path | What it holds | Entry points for this change |
| --- | --- | --- |
| `agents/reviewer.md` | The reviewer's whole page: frontmatter, what it checks (4 numbered checks), the reproduction rule, the `backlog.json` barrier, "You touch no code", and the fields it records. 149 lines. | `description` l.3; check 1 l.33–49 (sentence to delete, l.46); `## The reproduction rule` l.71–92 (paragraph to replace, l.88–92); `## You touch no code` l.104–111 (first sentence l.105–106); new section before `## What you record` l.113; `findings` bullet l.114–126; `summary` bullet l.144–145 |
| `agents/test-author.md` | The test-author's page: how it works, correction rounds, boundaries, what it records. | l.62–63, "The reviewer never writes tests; you do." |
| `README.md` | The public account of the loop, two mermaid diagrams included. | the closed-list paragraph, l.80–84 |
| `test-repo.sh` | The repository's own suite: bash `ok`/`no` cases in `echo "=== …"` blocks, plus an embedded `driver.js` heredoc (l.473–1348) that runs the workflow with a stubbed `agent()`. 1561 lines, exits non-zero when any case fails. | existing reviewer cases l.360–374; the single-owner precedent l.449–461; `=== every agent page is declared` block ends l.1495; insert the new block at l.1496, before `=== every test suite carries its doc` |

Read but deliberately **not** changed: `workflows/agile-loop.js` (the reviewer
dispatch l.949–976, `VERDICT` l.277–303, `checkList` l.359),
`skills/agent-brief/SKILL.md` ("The commands that count", l.76–86),
`hooks/read-barrier.mjs` and its suite, `agents/researcher.md`,
`agents/implementer.md`, `agents/planner.md`, `rulebook.md`,
`.claude-plugin/plugin.json`, everything under `tools/`.

## Environment

- **Shell:** `bash`. Every command below runs from the repository root.
- **Runtime:** Node.js is on the path (`test-repo.sh` shells out to `node -e`
  in four of its blocks). Every suite in this repository is zero-dependency;
  there is no `package.json` at the root and no install step.
- **Linter, formatter, type checker: there are none in this repository.**
- `test-repo.sh` is not executable, so it is run as `bash test-repo.sh`. It
  prints one `ok —` or `FAIL —` line per case and exits non-zero if any case
  failed.
- `./test.sh` is the aggregate of every suite in the repository. It is
  deliberately **not** in the closed list: this change touches no file under
  `tools/`, `hooks/`, `skills/agent-brief/assets/` or the worktree machinery
  the other suites cover.
- `test-repo.sh` needs no suite doc: the `CLAUDE.md` rule applies to
  directories holding a `*.test.mjs`, and this is bash.

## Test plan

Tests are needed. Every criterion here is a rule on a page, and the way this
repository pins a page rule is a grep case in `test-repo.sh` — the file already
carries two such cases for this very page ("the reviewer's page forbids reading
`backlog.json`", l.365) and a single-owner case for the planner's phrase
(l.455). What a grep can catch is a rule silently deleted or never written; the
wording itself is the reviewer's to judge, so every pattern below matches a
pairing of words inside one sentence, never a sentence verbatim.

### Cases, per acceptance criterion

**R1 — the page carries every rule the probe needs.** One case, a table of
required patterns over the whitespace-collapsed page, modelled on the
`argus_view_patterns` loop at l.1365. It covers criteria 1, 2, 3, 4, 5 and 6,
one pattern each (two for criterion 2):

| Pattern (case-insensitive, over the collapsed page) | Criterion | Satisfied by |
| --- | --- | --- |
| `probe[^.]*sandbox\|sandbox[^.]*probe` | 1 | "A probe exists in the sandbox alone: …" |
| `probe[^.]*checkout\|checkout[^.]*probe` | 2 | the same sentence |
| `probe[^.]*commit\|commit[^.]*probe` | 2 | the same sentence |
| `probe[^.]*diff\|diff[^.]*probe` | 2 | the same sentence |
| `probe[^.]*doubt\|doubt[^.]*probe` | 6 | "Probe from a stated doubt, never to explore." |
| `probe[^.]*\(list\|closed\)\|\(list\|closed\)[^.]*probe` | 5 | "The closed list of commands does not bind inside the sandbox: running a probe there …" |
| `probe[^.]*test-author\|test-author[^.]*probe` | 3 | "A probe is evidence for a finding, never the test that pins the behaviour afterwards — that test is the test-author's …" |
| `probe[^.]*returned\|returned[^.]*probe` | 4 | "Where a probe produced the finding, its `reproduction` carries the doubt you stated, what the probe ran and what it returned." |

`[^.]*` is what keeps a pairing inside one sentence: two words in two unrelated
paragraphs do not satisfy it. Collapse newlines to spaces first (`tr '\n' ' ' |
tr -s ' '`), exactly as the argus block does — every one of these sentences
wraps across lines in the source, and a per-line grep would miss all of them.
On failure, print the patterns that matched nothing.

- Input/state: the file `agents/reviewer.md` as it stands in the tree.
- Expected: every pattern matches; the miss list is empty.
- Edge (repeat): none applies — a pattern matching twice is as good as once.

**R2 — the old prohibition is gone.** Criterion 1 again, from the other
direction: a page that adds the probe section but leaves "You never write a
test to prove a finding, not even a throwaway" standing contradicts itself, and
R1 alone would pass it. Assert that the collapsed page matches **neither**
`not even a throwaway` **nor** `never write a test`. Expected: no hit. On
failure, print the offending line.

**R3 — the review's summary reports the probes.** Criterion 7. Take the
`summary` bullet with its continuation lines — `grep -A3 -- '- \*\*`summary`\*\*'
"$root/agents/reviewer.md"` — and require the result to match `probe`
case-insensitively. Expected: a hit. This is the one criterion R1's table does
not cover, because "summary" and "probe" could pair up anywhere on the page;
anchoring on the bullet is what makes the case mean what it says.

**R4 — only the reviewer's page licenses a probe.** Criteria 1 and 5 as a
containment property, and a direct mirror of the `chain_depth_owners` case at
l.455: `grep -lie 'probe' "$root"/agents/*.md "$root"/skills/*/SKILL.md` must
return exactly `$root/agents/reviewer.md`. It fails if the licence is copied
into the shared brief (where it would bind every agent) or into another agent's
page. `README.md` and `rulebook.md` are deliberately outside the file set — the
README's one sentence is an account of the rule for a human, not a rule an
agent is bound by, and the same set is what the existing single-owner case
uses.

**Left untested, and why.**

- The wording of every sentence, and the README sentence in full: prose is what
  the review reads, and a grep that pinned wording would fail on any correction
  the reviewer asks for.
- `agents/test-author.md`'s one clause: it is a single clause whose only failure
  mode is not being edited, and the reviewer reads the diff. Adding a fifth
  grep for it buys a line of coverage over a file the review already sees.
- The deletion of "That is the one run your list does not have to name.": same
  reason; R1's closed-list pattern already requires the general rule to exist,
  and a leftover narrow copy is a wording judgement.
- Criterion 2's runtime half — that no probe ever reaches a commit — cannot be
  tested here at all: it is a property of a future run, not of this repository,
  and the only thing this change can pin is that the page says so.

### How each case runs

All four cases live in **`test-repo.sh`**, in one new block inserted at line
1496 — after the `=== every agent page is declared` block ends and before
`echo "=== every test suite carries its doc"`.

- **Level:** structural, over the repository's own files. No framework: the
  file defines `ok()` and `no()` at l.11–12 and counts `passed`/`failed`.
- **Conventions of that file, which these cases follow:**
  - A block opens with `echo` (blank) then `echo "=== <lowercase sentence>"`.
    Use `echo "=== the reviewer proves a doubt with a probe in the sandbox"`.
  - Every case is preceded by a comment saying *why* the case exists — what
    went wrong or would go wrong without it — not what it asserts.
  - Every case is an `if … then ok "<lowercase declarative sentence>" else no
    "<what is wrong>" fi`. The `ok` string states the fact that holds; the `no`
    string states the fact that does not, and prints the offending lines
    indented with `sed 's/^/       /'` where there are any.
  - Paths are always `"$root/…"`; `$root` is set at l.6.
  - `|| true` after a `grep` whose empty result is a legitimate outcome, so
    `set -u` and a non-zero grep do not end the script.
  - A pattern table is a `declare -a name=( … )` array followed by a `for`
    loop collecting misses into one string, then a single `ok`/`no` on whether
    that string is empty (see l.1365–1389).
- **Fixtures/setup:** none. The cases read the files in the tree; nothing is
  faked, nothing is written, no temp directory is needed.
- **Command that runs just this file:** `bash test-repo.sh`. There is no way to
  run a single case; the whole file takes a few seconds.

### What counts as done

Run exactly this, from the repository root:

```
bash test-repo.sh
```

Nothing else. Not `./test.sh`, not `node --test` on any suite, not
`test-worktree.sh` — this change touches no file any of them covers.

### What is already red

I ran no command, not once and not as a baseline. From reading: `bash
test-repo.sh` passes on the tree as it stands, and none of its existing cases
turns red from the edits above — in particular the two greps at l.327 and l.343
that forbid an agent page from naming a prose handoff file or saying "handoff"
in any spelling still pass, because the new text says "the test-author's" and
never `test-author.md`, and contains no form of "handoff" (write "hand it over",
which does not match `hand-?off`). Keep it that way.

After the test-author's work and before the implementer's, exactly the four new
cases are red: R1 (no page mentions a probe), R2 ("not even a throwaway" is
still on l.90), R3 (the `summary` bullet does not mention a probe) and R4 (the
owner list comes back empty instead of `agents/reviewer.md`). Every existing
case in the file must still pass at the end.
