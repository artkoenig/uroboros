# Every rule this repository ships is written in the form its failure calls for

## Problem

`.claude/rules/authoring.md` now picks a rule's form from the failure class it
prevents, and bans patching a working rule with an exemption clause. Every page
it governs was written before it existed. The pass that landed the rule checked
the frontmatter descriptions and nothing else, so the bodies still carry
whatever form taste picked at the time: reminders that never name the price of
skipping them, prohibition lists where the failure is a wrong output shape and a
recipe is what measures better, required elements asked for in prose rather than
slotted into a template, and conditional behaviour left to a judgement call. A
rule in the losing form does not look broken — it reads fine and fails under
pressure, one agent run at a time, and each of those runs costs a full chain.

The pass covers the pages the authoring rules are scoped to and the two pages
that carry those rules: `agents/*.md`, `skills/*/SKILL.md`, `skills/CLAUDE.md`
and `.claude/rules/agents.md`. `rulebook.md`, `GEMINI.md` and `README.md` stay
out of it.

## Acceptance criteria

- Every rule on every page in scope is read against the four rows of the form
  table and against the ban on exemption clauses.
- A rule whose form loses against the failure it prevents is rewritten into the
  form that wins.
- A rewrite changes the form of a rule and never what the rule requires; where
  the winning form cannot be written without changing that, the rule is left as
  it stands and the conflict is recorded as a question for the human.
- An exemption clause bolted onto an existing rule is re-cut into a rule keyed
  to an observable predicate, with each branch stated on its own.
- Each rewritten rule gets a case in `test-repo.sh` that turns red when that
  rule is restored to the wording it replaced.
- The verdict is recorded page by page and rule by rule, and a rule left
  unchanged carries the reason it needs no rewrite.
- `bash test.sh` exits 0.
