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

## Round 1

The reviewer filed two findings, both `needs-plan`, both about the suite and
neither about the prose: every acceptance criterion is stated on
`agents/reviewer.md`, but four of them are pinned by nothing, because the four
cases in `test-repo.sh` grep the whole page — frontmatter included — and the
`description` on line 3 already pairs "probe" with "sandbox", "checkout",
"diff" and "doubt" inside its own sentences. Delete the rule from the body and
the suite stays green.

So this round changes **`test-repo.sh` and no other file.** No production edit,
no page edit. The one case that gives false confidence — the flat
`reviewer_probe_patterns` table — is replaced by a table that matches each rule
inside the *paragraph of the section that owns it*, which is what makes a
deleted paragraph turn the case red. The other three cases in the block stay
exactly as they are.

### The fix, concretely

In `test-repo.sh`, inside the existing block `=== the reviewer proves a doubt
with a probe in the sandbox`, replace the first case — its comment and the
`reviewer_probe_patterns` table, currently lines 1500–1535, everything from
`# docs/issues/2026-08-10-reviewer-probes-in-the-sandbox lifts the reviewer's`
down to the `fi` that closes it — with one case built on three mechanisms:

1. **Section scoping.** A rule is looked for only inside the section that owns
   it, so the frontmatter description cannot satisfy anything: it is not under
   a `##` heading and is never read.
2. **Paragraph scoping.** Inside that section each paragraph is collapsed to a
   single line, and a rule must be satisfied by *one* paragraph — not by words
   scattered across the section.
3. **A conjunction of terms per rule**, chosen so that only the paragraph
   carrying that rule can satisfy all of them. Each term is still a word or a
   short alternation, never a sentence, so a rewording that keeps the rule
   passes and a deletion does not.

The extraction, which I verified (see "What I ran"), is one `awk` in paragraph
mode. `want` is the lowercased heading pattern of the section:

```
awk -v RS='' -v want="$want" '
  /^## / { inside = tolower($0) ~ want; next }
  inside { gsub(/\n/, " "); print }
' "$reviewer_probe_page"
```

Each rule is one entry of a `declare -a` array, colon-separated: the heading
pattern, then the label printed on failure, then one field per term. Split it
with `IFS=':' read -ra`, then filter the paragraph list through one
`grep -iE -- "$term" || true` per term; a rule whose filtered list is empty is
a miss. No label and no heading pattern may contain a colon.

The table, verbatim — the terms are ERE, matched case-insensitively:

| Heading pattern | Label (criterion) | Terms |
| --- | --- | --- |
| `^## .*probe` | criterion 1, a probe is written and run in the sandbox and what it returns is the reproduction | `probe`, `sandbox`, `reproduc\|return` |
| `^## .*probe` | criterion 6, a probe follows a stated doubt that reaches the report | `probe`, `doubt`, `report` |
| `^## .*probe` | criterion 2, a probe never reaches the checkout, a commit or the diff | `probe`, `checkout`, `commit`, `diff` |
| `^## .*probe` | criterion 5, the closed list does not bind inside the sandbox | `probe`, `closed`, `list` |
| `^## .*probe` | criterion 3, a probe is evidence and the pinning test stays the test-author's | `probe`, `test-author`, `classif\|triag` |
| `^## .*reproduction` | criterion 3, a reproduction is still a spec | `reproduc`, `spec` |
| `^## what you record` | criterion 4, the reproduction carries what the probe ran and returned | `probe`, `return` |

Why each conjunction is the one that pins its paragraph, against the page as it
stands:

- **Criterion 1.** `reproduc|return` is what separates the licence paragraph
  from the two other probe paragraphs that also pair "probe" with "sandbox".
  Section scoping is what keeps the `## The reproduction rule` paragraph — which
  says "probing in the sandbox" and "reproduction" in one breath — from
  standing in for it.
- **Criterion 6.** `report` is what separates the stated-doubt paragraph from
  the licence paragraph, which also carries "doubt".
- **Criterion 2.** All four terms meet in one sentence and nowhere else.
- **Criterion 5.** `closed` plus `list` appear in the probe section only in the
  closed-list paragraph.
- **Criterion 3, both halves.** `classif|triag` pins the clause the reviewer
  showed was droppable ("a finding a probe produced is classified like any
  other"); the separate `## The reproduction rule` entry pins "A reproduction is
  a spec", the sentence this change rewrote and the one a later edit would drop.
- **Criterion 4.** `return` inside `## What you record` is carried by the
  probe paragraph of the `findings` bullet alone; the `summary` bullet says
  "showed", not "returned".

Keep the file's conventions: `"$root/agents/reviewer.md"` for the path, `|| true`
after every grep whose empty result is legitimate, one `ok`/`no` at the end of
the loop, misses printed with `sed 's/^/       /'`. Suggested strings —
`ok "every rule the probe licence needs stands in its own paragraph of
agents/reviewer.md"` and `no "these rules of the probe licence stand in no
paragraph of agents/reviewer.md:"`.

The comment above the case says why it exists, as every case in that file does:
the earlier table matched the frontmatter `description`, so deleting the rule
for criterion 1, 5 or 6 from the body left the suite green, and the whole grip
on three criteria was the word "commit" in a sentence belonging to a fourth.

### Technical decisions, including the rejected ones

- **No page changes this round.** The reviewer checked every criterion against
  `agents/reviewer.md` and found all seven stated; both findings are that the
  suite does not hold them. Editing the page would add a diff the next review
  has to judge and fix nothing.
- **Rejected: keeping the flat whole-page table and merely stripping the
  frontmatter.** I checked it: it still leaves criterion 1 unpinned, because the
  `## The reproduction rule` paragraph pairs "probing", "sandbox" and
  "reproduction" in the body. Section scoping is not optional.
- **Rejected: matching each rule against the collapsed section rather than a
  paragraph.** Then criterion 6's `report` and criterion 1's `reproduc` would be
  satisfied by each other's paragraphs, which is the same failure one level up.
- **Rejected: exact heading strings.** `^## .*probe` and `^## .*reproduction`
  let the section be renamed without turning the suite red for a wording choice
  that is the reviewer's to make. A heading that no longer names a probe at all
  makes every probe rule miss — that is the intended failure, and the printed
  miss list says which rules were not found.
- **Rejected: one case per rule, seven cases instead of one.** The file's
  precedent for a table of required patterns (`argus_view_patterns`,
  `reviewer_probe_patterns`) is a single case with a printed miss list, and a
  miss list names the criterion just as precisely as seven case names would.
- **Rejected: acting on the reviewer's two observations.** The 96-character line
  at `agents/reviewer.md:106` and the strictness of the owners case are marked
  "no correction needed" in the review; rewrapping the line would put a second,
  cosmetic file in a diff that otherwise touches `test-repo.sh` alone.
- **Rejected: a case that pins criterion 2's runtime half.** Unchanged from
  Round 0: that no probe ever reaches a commit is a property of a future run,
  not of this repository.

### Module map

| Path | What it holds | Entry points for this round |
| --- | --- | --- |
| `test-repo.sh` | The repository's own suite: bash `ok`/`no` cases in `echo "=== …"` blocks. `ok()`/`no()` at l.11–12, `root` at l.6. 1638 lines, exits non-zero when any case fails. | the block `=== the reviewer proves a doubt with a probe in the sandbox`, l.1497–1572; **replace** the comment and first case, l.1500–1535; **leave** the old-prohibition case (l.1537–1547), the `summary`-bullet case (l.1549–1560) and the owners case (l.1562–1572) untouched; the `argus_view_patterns` loop at l.1365–1389 is the table-and-miss-list precedent |
| `agents/reviewer.md` | The reviewer's page. Read-only this round. Paragraph anchors the new table matches: `## The reproduction rule` l.87–91, `## The probe` l.112–132 (licence l.114–116, stated doubt l.118–121, the bounds l.123–124, the closed list l.126–128, evidence-not-the-test l.130–132), `## What you record` l.134–169 (probe paragraph l.149–150, `summary` bullet l.168–169) | none — do not edit |

Unchanged and not to be touched: `README.md`, `agents/test-author.md`,
`workflows/agile-loop.js`, `skills/agent-brief/SKILL.md`, `hooks/`, `tools/`,
`rulebook.md`.

### Environment

- **Shell:** `bash`, every command run from the repository root.
- **`awk`** is on the path and is used by the new case; nothing else in
  `test-repo.sh` uses it today, and POSIX paragraph mode (`RS=''`), `tolower`
  and `gsub` are all it needs. `node` is on the path for other blocks and is
  not needed by this one.
- **Linter, formatter, type checker: there are none in this repository.**
- `test-repo.sh` is not executable; run it as `bash test-repo.sh`. It prints one
  `ok —` or `FAIL —` line per case and exits non-zero if any case failed.
- `./test.sh` is the aggregate of every suite and is deliberately **not** in the
  closed list: this round touches nothing any other suite covers.

### Test plan

Tests are needed, and they are the whole of the change: both findings say the
existing cases do not fail when the rule leaves the page, and the correction is
a case that does.

**What, per criterion.** One case, `R1'`, replacing the old `R1`. It carries
seven rules, listed in the table above, covering criteria 1, 2, 3 (both halves),
4, 5 and 6.

- Input/state: `agents/reviewer.md` as it stands in the tree.
- Expected: no rule misses; the case prints `ok` and the miss list is empty.
- Edges: a rule matched by two paragraphs is as good as one, so a repeat needs
  no handling; a section heading that matches nothing yields an empty paragraph
  list and every rule of that section misses, which is the intended red.
- Untested, deliberately: the wording of any sentence; `agents/test-author.md`'s
  one clause and the `README.md` sentence (prose the review reads, and a grep
  over them would fail on any correction the reviewer asks for); criterion 2's
  runtime half.

Criterion 7 keeps the case it already has — the `summary` bullet with its
continuation lines must mention a probe — and criteria 1 and 5's containment
property keeps the owners case. Neither was faulted; do not rewrite them.

**How.** Level: structural, over the repository's own files, no framework and no
fixtures. File: `test-repo.sh`, inside the existing block at l.1497. Conventions
of that file, which the case follows: a comment above each case saying why it
exists, `if … then ok "<lowercase declarative sentence>" else no "<what is
wrong>" fi`, `"$root/…"` paths, `|| true` on a grep whose empty result is
legitimate, offending lines printed with `sed 's/^/       /'`, and a table of
requirements as a `declare -a` array plus a loop collecting misses into one
string. Nothing is faked; nothing is written; no temporary directory is used.

**Command that runs just this file:** `bash test-repo.sh`. There is no way to
run one case; the file takes a few seconds.

**What counts as done.** Run exactly this, from the repository root:

```
bash test-repo.sh
```

Nothing else. Not `./test.sh`, not `node --test` on any suite, not
`test-worktree.sh`.

**What is already red.** Nothing. I did not run the suite, not once and not as a
baseline: the reviewer reported `bash test-repo.sh`, 75 cases, exit 0 on this
tree, and this round adds no case and removes none, so 75 cases and exit 0 is
what the run must still print afterwards.

This round has no red-first phase, and that is deliberate: the page already
carries every rule, so the replacement case passes from its first run — I
verified exactly that (below). **Implementer: there is nothing to implement this
round.** Run `bash test-repo.sh`, confirm 75 cases and exit 0, and change no
file. If a new rule comes back as a miss, the case is wrong and the page is not;
record it as a `deviations` entry and still do not edit `agents/reviewer.md`.

### What I ran

Not the suite. I ran a prototype of the proposed case — the `awk` extraction and
the seven rules above, in a scratch script outside the checkout — against
fourteen copies of `agents/reviewer.md`, to settle the one question the plan
turns on: whether these conjunctions go red on exactly the reviewer's
reproductions and stay green on a faithful rewording. No file in the checkout
was read for it other than `agents/reviewer.md`, and none was written.

Results, one line per copy:

- the page as it stands: no misses.
- each of the five probe paragraphs deleted in turn, and the whole `## The
  probe` section deleted: the matching rule misses each time, all five miss for
  the whole-section deletion.
- the `findings` probe paragraph deleted: criterion 4 misses.
- the last paragraph of `## The reproduction rule` deleted, and — the reviewer's
  own two clause-level reproductions — "A reproduction is a spec, not a file you
  wrote. " deleted, and " — and a finding a probe produced is classified like any
  other" deleted: the matching rule misses each time.
- the clause "and carry that sentence into your report" deleted: criterion 6
  misses.
- the whole `## The probe` section rewritten in different words, keeping every
  rule: no misses.
- the heading renamed to `## Probes in the sandbox`: no misses.
