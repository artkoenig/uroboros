# Compress the rule texts to their minimum

## Problem

The human asked for the project's rules to be compressed to minimal size
without losing their key statements, in simple laconic wording. The rule
documents have grown long: they justify themselves, tell their history, and
restate the same rule in more than one place. A reader pays for every extra
sentence, and an agent pays for it in context on every run.

The scope is the project's rule texts: `rulebook.md` (with its byte-identical
copy `GEMINI.md`), the agent pages, the skill and workflow pages, and the
pages under `.claude/rules/`. Issue files under `docs/issues/` are records,
not rules, and stay untouched.

## Acceptance criteria

- Compress every rule document of the project: `rulebook.md`, each agent page,
  each skill page, each workflow page, and each page under `.claude/rules/`.
- Make every compressed document shorter than it was, measured in words.
- Keep every binding rule: everything the old text required is still required,
  and everything it forbade is still forbidden.
- State each rule once per document.
- Write short sentences in common words, one instruction per sentence, in the
  imperative.
- Drop history, anecdotes and self-justification; where a rule needs a reason,
  give it in at most one sentence.
- Keep every document's role, audience and file location unchanged.
- Keep every document in English.
- Keep `GEMINI.md` byte-identical to `rulebook.md`.
- Keep every case in `test-repo.sh` guarding a rule: where a case keys on
  wording the compression changed, re-key it to the new wording so it still
  turns red when its rule is removed; delete no case.
- Leave `docs/issues/` untouched except for this issue's own directory.
- `bash test.sh` exits 0.
