#!/bin/bash
# Runs the test suites of this repository and exits 0 only when all of them
# pass. This is the one command behind "the suite is green" — a new suite must
# be added to declare_suites() below, and every suite needs a short typeable
# name so a single one can be asked for.
#
# usage: test.sh [--only <name>]... [--list]
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
ran=0
total=0
suite_mode=collect
suite_names=()
suite_labels=()
declare -A selected=()
filtering=0

# Called twice: once in the collect pass, which validates every name and
# records it without running anything, and once in the run pass, which runs
# the suites the filter selects.
suite() {
  if [ "$suite_mode" = collect ]; then
    if [[ ! "$1" =~ ^[a-z][a-z0-9-]*$ ]]; then
      echo "test.sh: suite \"$1\" was declared without a name — every suite needs a short typeable name" >&2
      exit 2
    fi
    local existing
    for existing in ${suite_names[@]+"${suite_names[@]}"}; do
      if [ "$existing" = "$1" ]; then
        echo "test.sh: two suites share the name \"$1\"" >&2
        exit 2
      fi
    done
    suite_names+=("$1")
    suite_labels+=("$2")
    return 0
  fi

  if [ "$filtering" -eq 1 ] && [ -z "${selected[$1]:-}" ]; then
    return 0
  fi
  ran=$((ran + 1))
  echo "=== $2"
  "${@:3}" || failed=$((failed + 1))
  echo
}

declare_suites() {
suite repo "the repository itself" bash "$root/test-repo.sh"
suite worktree "parallel runs: worktrees" bash "$root/test-worktree.sh"
# The backlog recorder, the only writer of a run's `backlog.json`. Named as a
# file rather than as the `skills/agent-brief/assets` directory because
# `node --test <dir>` resolves the bare directory as a module in this Node
# build instead of scanning it for `*.test.mjs`.
suite backlog "skills/agent-brief/assets: the backlog recorder" node --test "$root/skills/agent-brief/assets/backlog.test.mjs"
# The hook that pushes a run's state to the collector — the one place in the
# plugin that talks to one, and the reason the recorder above no longer does.
suite run-state "hooks: the run-state hook" node --test "$root/hooks/backlog-changed.test.mjs"
# The hook that refuses a read an agent's own page forbids — the barriers the
# pages used to only ask for.
suite read-barrier "hooks: the read barrier" node --test "$root/hooks/read-barrier.test.mjs"
# Through the package's own `test` script rather than a `node --test` line
# repeated here, so the suite this runs stays the suite the tool declares.
# Zero-dependency, so no install step is needed first.
suite argus "tools/argus" npm --prefix "$root/tools/argus" test --silent
suite argus-ui "tools/argus-ui" npm --prefix "$root/tools/argus-ui" test --silent
suite log-parser "tools/log-parser" npm --prefix "$root/tools/log-parser" test --silent
}

usage="usage: test.sh [--only <name>]... [--list]"
wanted=()
list_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      if [ $# -lt 2 ]; then
        echo "test.sh: --only needs a suite name" >&2
        exit 2
      fi
      wanted+=("$2")
      shift 2
      ;;
    --list)
      list_only=1
      shift
      ;;
    --help | -h)
      echo "$usage"
      exit 0
      ;;
    *)
      echo "test.sh: unknown argument \"$1\"" >&2
      echo "$usage" >&2
      exit 2
      ;;
  esac
done

# Collect pass: every name is known, and validated, before any suite runs.
declare_suites
total=${#suite_names[@]}

if [ "$list_only" -eq 1 ]; then
  for i in "${!suite_names[@]}"; do
    printf '%-14s %s\n' "${suite_names[$i]}" "${suite_labels[$i]}"
  done
  exit 0
fi

if [ "${#wanted[@]}" -gt 0 ]; then
  filtering=1
  for name in "${wanted[@]}"; do
    found=0
    for existing in "${suite_names[@]}"; do
      [ "$existing" = "$name" ] && found=1
    done
    if [ "$found" -eq 0 ]; then
      echo "test.sh: no suite named \"$name\"" >&2
      echo "the suites this repository has: ${suite_names[*]}" >&2
      exit 2
    fi
  done
  for name in "${wanted[@]}"; do
    selected[$name]=1
  done
fi

suite_mode=run
declare_suites

if [ "$filtering" -eq 1 ]; then
  if [ "$failed" -eq 0 ]; then
    echo "FILTERED: ran $ran of $total suites — a filtered run is not a green suite"
  else
    echo "FILTERED: ran $ran of $total suites, $failed failed — a filtered run is not a green suite"
    exit 1
  fi
elif [ "$failed" -eq 0 ]; then
  echo "PASS: all $ran suites"
else
  echo "FAIL: $failed of $ran suite(s)"
  exit 1
fi
