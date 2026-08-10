# Implementer

## Round 1

Made the four-file prose change the plan specified: the reviewer's page gains a
bounded probe licence, the test-author's page loses the clause that would
contradict it, and the README's account of the closed list says where that list
binds. No test file was touched.

### Tests first

Ran `bash test-repo.sh` before editing anything: 75 cases, exit 1, `FAIL: 4 of
75 cases`. The four red ones were exactly the block
`=== the reviewer proves a doubt with a probe in the sandbox` the test-author
wrote, and each failed for the missing-behaviour reason the plan predicted:

- the pattern table printed all eight patterns as misses,
- the old prohibition was still on `agents/reviewer.md` line 90,
- the `summary` bullet did not mention a probe,
- the owner list came back `(none)` instead of `agents/reviewer.md`.

Every other case printed `ok`.

### What changed

**`agents/reviewer.md`** — five edits plus the two field edits, as planned.

- Frontmatter `description` (line 3): inserted the sentence "Inside the sandbox
  worktree it builds outside the checkout it may also write and run a throwaway
  probe to prove a doubt it has stated, and that probe never reaches the
  checkout or the diff." after "…separating what this change broke from what was
  already red." The rest of the description is untouched.
- Check 1: deleted "That is the one run your list does not have to name." and
  rewrapped the two lines the deletion left short. Nothing else in that
  paragraph changed.
- `## The reproduction rule`, last paragraph: replaced whole with the planned
  text. The first two sentences are unchanged; "You never write a test to prove
  a finding, not even a throwaway" and the closing "not one file away" are gone.
- `## You touch no code`, first sentence: now "You write nothing in the
  checkout — no production code, no test, no fix — and nothing you run may
  change it." The rest of the section is untouched.
- New `## The probe` section, five paragraphs verbatim from the plan, placed
  between `## You touch no code` and `## What you record`.
- `findings` bullet: added "Where a probe produced the finding, its
  `reproduction` carries the doubt you stated, what the probe ran and what it
  returned." as its own paragraph, after the paragraph ending "…which is why you
  never make it yourself." and before "That list is the whole triage".
- `summary` bullet: now "one sentence on the review: the run of the listed
  commands, and how many probes you ran and what they showed."

Nothing else on the page changed — not `## You never read backlog.json`, not
`reason`, `questions`, `findingCount` or `allDirect`, not the closing sentence.

**`agents/test-author.md`** — the one clause: "The reviewer never writes tests;
you do." became "The reviewer never writes the test that pins a behaviour; you
do." The surrounding two lines were rewrapped because the replacement is longer;
no other word on that page changed.

**`README.md`** — one sentence added to the closed-list paragraph, after "…
instead of four agents each reaching for `test.sh` to be safe.": "That list
binds outside the sandbox the reviewer builds for another state: inside it the
reviewer may write and run a throwaway probe to prove a doubt it has already
stated, and what the review reports as green or red still rests on the listed
commands alone." Neither mermaid diagram and neither neighbouring paragraph was
touched.

**Not touched:** `test-repo.sh` (the test-author's), `workflows/agile-loop.js`,
`skills/agent-brief/SKILL.md`, `hooks/read-barrier.mjs`, `rulebook.md`,
`.claude-plugin/plugin.json`, every other agent page.

`git diff --stat`: `README.md` +5/-1, `agents/reviewer.md` +50/-13,
`agents/test-author.md` +4/-2 — three files, 43 insertions, 16 deletions.

### What counts as done

`bash test-repo.sh`, from the repository root, the only command the plan lists:
75 cases, exit 0, `PASS: 75 cases`. Nothing skipped, nothing excluded. All four
new cases are green and every case that passed before still passes. I ran
nothing else — not `./test.sh`, not any `node --test` suite — because the plan
names nothing else.

### Notes for the reviewer

- The plan's placement instruction for the README sentence names the sentence
  "Nobody runs a suite or a linter it leaves out, and an empty list means the
  review is a reading." as the one to follow, but in the file that sentence runs
  on past an em dash into "…so the cost of checking is a decision made once,
  with the codebase in view, instead of four agents each reaching for `test.sh`
  to be safe." I put the new sentence after the full stop that ends the whole
  sentence, so it does not interrupt the em-dash clause. That is the only place
  the plan's literal wording and the file's punctuation could diverge.
- `.claude/rules/agents.md` contains the phrase "probe agent" in its prose about
  how a scoped rule reaches a subagent. R4's file set (`agents/*.md` and
  `skills/*/SKILL.md`) deliberately excludes it, so the case stays green, and I
  left that file alone. Flagging it only because a future widening of that case's
  file set would trip on it.
- No question, nothing blocking.
