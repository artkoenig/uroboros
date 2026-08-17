# The root shell suites

`test.sh`, `test-repo.sh` and `test-worktree.sh` — bash, no framework. This
file is not inherited by an agent (nothing loads it as project memory outside
this reading), and there is no `test/` directory to hold it next to; it lives
at the repository root beside the three scripts it documents.

## What each file is

- `test.sh` — the runner. Declares every suite by a short, unique, typeable
  name inside `declare_suites()`, then runs them (all, or the ones `--only`
  names) and reports the closing line the whole repository trusts as "the
  suite is green" (`PASS: all N suites` unfiltered, `FILTERED: ran K of N
  suites …` filtered — a filtered run is never reported as that green line).
  `--list` prints the names and exits before running anything.
- `test-repo.sh` — facts about the repository itself that no other suite
  owns: licence claims, rule-page scoping, the rulebook's reach, the
  collector's one route in, the workflow's registration, agent pages,
  suite-doc coverage, and (this section) `test.sh`'s own filtering behaviour.
- `test-worktree.sh` — what a parallel run (`claude --worktree`) needs from
  this repository's configuration; it never creates a worktree itself.

Each file is `ok`/`no` counters that never abort (`set -u`, no `set -e`) and a
closing `PASS: N cases` / `FAIL: N of M cases; exit 1`.

## Conventions every case follows

- A comment directly above a case names the criterion it covers and the break
  that turns it red.
- `ok "<what holds>"` / `no "<what is wrong>"` — one call per case, stated as
  the fact, not as an assertion of it.
- Scratch state through `mktemp -d`, always removed with `rm -rf` before the
  case ends (including on its failing path).
- A generated file is written with a heredoc quoted `<<'EOF'`, never
  unquoted, so nothing in it is expanded by this shell.
- No `set -e`: a failing case increments `failed` and the suite keeps going,
  so one broken case does not hide the rest.

## Where a new case goes

Each file is sectioned by `echo; echo "=== <what this section is about>"`.
Add a case to the section it belongs to; open a new section the same way if
none fits. `test-repo.sh`'s section on `test.sh --only` filtering
(`=== test.sh runs only the suites you name`) is the one place that tests
`test.sh` itself — anything about the runner's own behaviour belongs there,
not in `test.sh` or scattered elsewhere in `test-repo.sh`.

## Testing `test.sh` from `test-repo.sh`

`test-repo.sh` runs as one of `test.sh`'s own suites. That means a case
testing `test.sh` must never invoke the real `$root/test.sh` with anything
that could run a suite — doing so re-enters `test-repo.sh` and recurses.
`--list` is the one real-script call this suite makes (it must not run a
suite), and it goes through `run_with_hard_timeout`: today, before `--list`
exists, an unrecognized flag still falls through into running everything, so
that call is capped by a hard, process-tree kill rather than a plain
`timeout`, because a killed direct child can still leave a re-entered
`test-repo.sh` running as an orphan.

Every other case in that section runs a **temp copy** of `test.sh`, built and
torn down by `run_stub_test_sh` (and its two one-off variants,
`run_nameless_stub_test_sh` and `run_dup_stub_test_sh`): copy `$root/test.sh`,
replace the body of its `declare_suites() {…}` with two or three synthetic
suites (`alpha`/`beta`/`gamma`, or a deliberately broken declaration), each
suite a two-line stub script that echoes a marker (`ALPHA-RAN`, …) and exits
with a chosen code, then run the copy with the arguments the case wants and
capture combined stdout/stderr and the exit code into `$stub_output` /
`$stub_status`. If the substitution finds no `declare_suites() {…}` to
replace — true today, since `test.sh` does not have that structure yet — the
helper reports a setup failure instead of ever running the untouched copy,
which is what keeps a broken substitution from recursing too.

## Naming and style

Case descriptions are lowercase sentences stating what holds or what broke —
`"bash test.sh --list exits 0 and lists a typeable, unique name per suite"`,
not a test title. Section headers (`=== …`) are similarly stated as what the
section is about, not as a file or function name.

## Running

```bash
bash test-repo.sh
bash test-worktree.sh
bash test.sh          # runs both of the above, and everything else
```
