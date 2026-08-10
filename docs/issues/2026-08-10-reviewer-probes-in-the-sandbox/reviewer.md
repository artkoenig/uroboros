# Reviewer

## Round 0

**Status: 2 findings, both `needs-plan`.** The change reads right — every one of
the seven acceptance criteria is stated on `agents/reviewer.md` — but four of
them are pinned by nothing: delete the rule from the page and `bash test-repo.sh`
still exits 0.

### The listed command

`bash test-repo.sh`, 75 cases, exit 0. Nothing skipped, nothing excluded. The
four new cases under `=== the reviewer proves a doubt with a probe in the
sandbox` are all green. No pre-existing red anywhere in the suite.

### Sandbox runs

Nine further runs of that same command against mutated copies of HEAD in a
`git worktree` outside the checkout, each one deleting a single sentence or
paragraph from `agents/reviewer.md` to see whether the suite notices. No file
in the checkout was touched and the worktree is removed. This is the
merge-base-style run the reviewer's page already allows and the issue's
non-goals already name ("breaking a line on purpose to see whether anything goes
red — is already allowed and already practised"); no probe in the new sense was
written.

### The diff against the intent

The change is `README.md`, `agents/reviewer.md`, `agents/test-author.md` and
`test-repo.sh` (commits 6ad7058, 1d7d599, 624bae5). Criterion by criterion:

- **C1 — the licence to write a probe in the sandbox.** Met.
  `agents/reviewer.md:112-116`, the `## The probe` section: "a script, a
  request, a test-shaped file, written inside the sandbox worktree, run there,
  and gone when you remove it. What it returns is the reproduction of the
  finding you file."
- **C2 — sandbox only, never the checkout, never committed, never in the
  diff.** Met. `agents/reviewer.md:123-124`. The sandbox's removal still stands
  at `agents/reviewer.md:107-109`.
- **C3 — a reproduction is still a spec; a probe is evidence, not the pinning
  test; classification unchanged.** Met in the text:
  `agents/reviewer.md:87` keeps "A reproduction is a spec, not a file you
  wrote."; `agents/reviewer.md:130-132` says a probe is "never the test that
  pins the behaviour afterwards — that test is the test-author's — and a
  finding a probe produced is classified like any other".
  `agents/test-author.md:62-63` was narrowed to match, correctly: the old "The
  reviewer never writes tests" would now be false.
- **C4 — the `reproduction` carries what the probe ran and returned.** Met,
  `agents/reviewer.md:149-150`.
- **C5 — the closed list does not bind inside the sandbox, and binds outside
  exactly as before.** Met, `agents/reviewer.md:126-128`, and `README.md:84-87`
  keeps the README's account of the closed list true beside it.
- **C6 — probe from a stated doubt, one sentence, into the report.** Met,
  `agents/reviewer.md:118-121`.
- **C7 — the `summary` says how many probes ran and what they showed.** Met,
  `agents/reviewer.md:168-169`.

Nothing in the diff goes beyond the criteria. The two consequential edits
outside `agents/reviewer.md` — the README paragraph and the test-author
sentence — each repair a statement the licence would otherwise have made false,
and neither adds a rule. The deletion of "That is the one run your list does not
have to name." (old `agents/reviewer.md:46`) does not lose the merge-base run:
check 1 still says in the imperative "run the same listed command at the merge
base in a sandbox", and "The closed list of commands does not bind inside the
sandbox" covers it in general.

### Findings

#### 1. Criteria 1, 5 and 6 have no test that fails when the rule leaves the page

`fix: needs-plan` — `criterion: 1, 5, 6`

The four new cases in `test-repo.sh:1498-1571` grep the whole of
`agents/reviewer.md`, frontmatter included, and the `description` on line 3
already pairs "probe" with "sandbox", "checkout", "diff" and "doubt" in its own
sentences. So a pattern meant to pin a rule in the body stays green when that
rule is deleted, because the description alone satisfies it.

Reproduction, each step run in a `git worktree` of HEAD outside the checkout,
with `bash test-repo.sh` afterwards:

- Delete the paragraph `agents/reviewer.md:114-116` ("A doubt a reading cannot
  settle you settle with a probe: … the reproduction of the finding you file.")
  — the whole of criterion 1. Result: `PASS: 75 cases`, exit 0; all four probe
  cases report `ok`.
- Delete the paragraph `agents/reviewer.md:126-128` ("The closed list of
  commands does not bind inside the sandbox: … rests on the listed commands
  alone.") — the whole of criterion 5. Result: `PASS: 75 cases`, exit 0.
- Delete the paragraph `agents/reviewer.md:118-121` ("Probe from a stated doubt,
  never to explore. … the run pays for it twice.") — the whole of criterion 6.
  Result: `PASS: 75 cases`, exit 0.
- As the limit case, delete the entire `## The probe` section, lines 112-132.
  Result: `FAIL: 1 of 75 cases`, exit 1 — and the one case that fails is a
  single pattern, `probe[^.]*commit|commit[^.]*probe`. Every other pattern is
  still matched by the frontmatter description.

So the suite's whole grip on criteria 1, 5 and 6 is one word, "commit", in a
sentence that belongs to criterion 2.

#### 2. Criterion 3 is pinned by nothing

`fix: needs-plan` — `criterion: 3`

Criterion 3 has two halves the suite does not reach: that the
reproduction-is-a-spec rule still stands, and that a finding a probe produced is
classified like any other. The paragraph carrying the first is one the change
itself rewrote, which is exactly where a later edit would drop it.

Reproduction, each in a `git worktree` of HEAD outside the checkout, then
`bash test-repo.sh`:

- Delete "A reproduction is a spec, not a file you wrote. " from
  `agents/reviewer.md:87`. Result: `PASS: 75 cases`, exit 0.
- Delete " — and a finding a probe produced is classified like any other" from
  `agents/reviewer.md:130-132`. Result: `PASS: 75 cases`, exit 0.

The `probe[^.]*test-author` pattern survives both deletions, so it pins the
sentence's middle clause and neither of the two the criterion asks for.

### Beyond the criteria

Traced, nothing found that breaks:

- `workflows/agile-loop.js` builds the reviewer's prompt with `checkList()`
  (line 359), which says "The commands that count for this increment:" and
  claims no exclusivity, so it does not contradict the sandbox exception. The
  `VERDICT` schema (line 277) leaves `summary` a free string, so criterion 7
  needs nothing there.
- `skills/agent-brief/SKILL.md` and `rulebook.md` carry no rule about writing,
  sandboxes or probes, so the licence stays on the reviewer's page alone — the
  fourth new case checks that and passes.
- `.claude/rules/agents.md:18` uses the word "probe" in an unrelated sense
  ("measured with a probe agent"), and the owners case scans only `agents/*.md`
  and `skills/*/SKILL.md`, so it is unaffected.
- No other page still says the reviewer writes nothing at all: the only
  remaining "never write" lines are `agents/implementer.md:77` and
  `agents/researcher.md:29`, both about their own roles.
- The reviewer's `tools:` list already carried `Write` and `Edit`, so the
  licence is executable as written.

### Observations, no correction needed

- `agents/reviewer.md:106` is 96 characters — the rewrite of "You touch no code"
  left the sentence unwrapped while the rest of the file sits at about 80.
- The owners case compares `grep -l` output to one exact path, so any future
  page using "probe" in an unrelated sense turns it red. It is right today.
