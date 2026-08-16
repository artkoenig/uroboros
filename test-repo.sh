#!/bin/bash
# Facts about the repository itself that no other suite owns. Exit 0 = all
# cases pass.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passed=0
failed=0

ok() { passed=$((passed + 1)); echo "  ok   — $1"; }
no() { failed=$((failed + 1)); echo "  FAIL — $1"; }

echo "=== the licence"

# Every place that names a licence names the one in LICENSE. Three of them
# said Apache 2.0 over a GPL-3 LICENSE file, each drifting on its own,
# because nothing compared them.
declare -a claims=(
  ".claude-plugin/plugin.json"
  "tools/argus/package.json"
  "README.md"
)

if head -2 "$root/LICENSE" | grep -q "GNU GENERAL PUBLIC LICENSE"; then
  if head -3 "$root/LICENSE" | grep -q "Version 3"; then
    ok "LICENSE is the GNU GPL version 3"
  else
    no "LICENSE is a GNU GPL, but not version 3"
  fi
else
  no "LICENSE is not the GNU GPL — the cases below assume it is"
fi

for file in "${claims[@]}"; do
  if grep -q "GPL-3.0-or-later" "$root/$file"; then
    ok "$file names GPL-3.0-or-later"
  else
    no "$file does not name GPL-3.0-or-later: $(grep -io 'apache[^",]*\|gpl[^",]*' "$root/$file" | head -1)"
  fi
done

# The other direction: no file anywhere claims a licence LICENSE is not.
# The record of past runs under docs/issues/ is out of scope, the way *.sh
# already is: those documents quote this suite — the sentence above about
# three files drifting is itself quoted in one of them — and a quotation is
# not a claim. Nothing there sets the project's licence anyway.
strays="$(grep -rln 'Apache' "$root" \
  --include='*.md' --include='*.json' --include='*.mjs' --include='*.yaml' \
  --exclude='package-lock.json' --exclude-dir=node_modules \
  --exclude-dir=issues 2>/dev/null || true)"
if [ -z "$strays" ]; then
  ok "no file claims the Apache licence"
else
  no "these files still claim the Apache licence:"
  echo "$strays" | sed 's/^/       /'
fi

echo
echo "=== no repository-local rule reaches an agent"

# `.claude/rules/` is not shipped with the plugin, so anything it delivers
# exists in this checkout and nowhere else. An unscoped page loads at launch
# and is inherited by every subagent the session dispatches, which would give
# an agent working here rules it never holds in a project that installed
# uroboros. `paths:` frontmatter is what stops that: inheritance passes on the
# launch context alone, and a scoped page is not in it.
rules_unscoped=""
for page in "$root"/.claude/rules/*.md; do
  [ -e "$page" ] || continue
  if ! head -1 "$page" | grep -q '^---$' || ! sed -n '2,/^---$/p' "$page" | grep -q '^paths:'; then
    rules_unscoped="${rules_unscoped} $(basename "$page")"
  fi
done
if [ -z "$rules_unscoped" ]; then
  ok "every page in .claude/rules/ is path-scoped, so no subagent inherits one"
else
  no "unscoped rule pages would reach every subagent in this checkout alone:$rules_unscoped"
fi

# Scoping is only half the bargain. The page still has to reach whoever opens
# the files it governs — a reader loads it on its own reads, subagents
# included — and a pattern that matches nothing loads for nobody while looking
# deliberate. `agent/**` for `agents/` would read as scoping and be a deleted
# rule. So every pattern has to name files that exist.
scope_tmp="$(mktemp -d)"
cat >"$scope_tmp/scope.js" <<'JS'
const fs = require("fs"), path = require("path");
const root = process.argv[2];
const tracked = fs.readFileSync(process.argv[3], "utf8").split("\n").filter(Boolean);
const dir = path.join(root, ".claude/rules");
const unquote = (s) => s.trim().replace(/^["']|["']$/g, "");
const problems = [];
for (const page of fs.readdirSync(dir).filter((f) => f.endsWith(".md"))) {
  const fm = (fs.readFileSync(path.join(dir, page), "utf8").match(/^---\n([\s\S]*?)\n---/) || [])[1] || "";
  const lines = fm.split("\n");
  const at = lines.findIndex((l) => /^paths:/.test(l));
  if (at < 0) { problems.push(page + ": no paths:"); continue; }
  const patterns = [];
  const inline = unquote(lines[at].replace(/^paths:/, ""));
  if (inline) patterns.push(inline);
  for (let i = at + 1; i < lines.length && /^\s*-\s/.test(lines[i]); i++) {
    patterns.push(unquote(lines[i].replace(/^\s*-\s*/, "")));
  }
  if (!patterns.length) { problems.push(page + ": paths: is empty"); continue; }
  for (const p of patterns) {
    const rx = new RegExp("^" + p
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*+/g, (m) => (m.length > 1 ? ".*" : "[^/]*")) + "$");
    if (!tracked.some((f) => rx.test(f))) problems.push(page + ": " + p + " matches no tracked file");
  }
}
if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
JS
git -C "$root" ls-files >"$scope_tmp/tracked.txt"
node "$scope_tmp/scope.js" "$root" "$scope_tmp/tracked.txt"
scope_status=$?
rm -rf "$scope_tmp"
if [ "$scope_status" -eq 0 ]; then
  ok "every paths: pattern in .claude/rules/ matches files that exist"
else
  no "a paths: pattern matches nothing, so its page loads for nobody"
fi

echo
echo "=== the rulebook reaches the session and stops there"

# The rulebook binds the session and nothing else. Two facts make that true and
# neither is visible from the tree, so both are pinned here: the hook delivers
# the page, and no other channel carries it.

# 1. Wired at all. A hook script nothing dispatches is a rulebook nobody gets,
#    and the session would run with no rules and no sign of it.
if [ -f "$root/hooks/hooks.json" ] &&
  grep -q 'SessionStart' "$root/hooks/hooks.json" &&
  grep -q 'session-start.sh' "$root/hooks/hooks.json"; then
  ok "hooks.json dispatches session-start.sh on SessionStart"
else
  no "hooks.json does not wire session-start.sh to SessionStart — the rulebook would never be delivered"
fi

# 2. Delivered, verbatim, as valid JSON. The script is run for real rather than
#    read, because everything that can break here breaks at run time: an unset
#    variable under `set -u`, a quote the encoder misses, a stray line on
#    stdout. The rulebook's own opening heading has to come back out the other
#    end, so a hook that emits well-formed JSON carrying nothing is caught too.
delivery_tmp="$(mktemp)"
if (cd "$root" && bash hooks/session-start.sh) >"$delivery_tmp" 2>/dev/null; then
  if node -e '
    const fs = require("fs");
    const answer = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const out = answer.hookSpecificOutput || {};
    if (out.hookEventName !== "SessionStart") throw new Error("wrong hookEventName: " + out.hookEventName);
    const context = out.additionalContext || "";
    const rulebook = fs.readFileSync(process.argv[2], "utf8");
    // Verbatim, not merely mentioned: a pointer to the file would leave the
    // session free to skip it, which is the whole reason the text is inlined.
    const body = rulebook.replace(/\r/g, "").trimEnd();
    if (!context.includes(body)) throw new Error("additionalContext does not carry rulebook.md verbatim");
  ' "$delivery_tmp" "$root/rulebook.md" 2>/dev/null; then
    ok "session-start.sh hands the session rulebook.md verbatim, as valid hook JSON"
  else
    no "session-start.sh runs, but its output does not carry rulebook.md verbatim as valid hook JSON"
  fi
else
  no "session-start.sh exits non-zero, so no session gets the rulebook"
fi
rm -f "$delivery_tmp"

# 3. And no second channel. `additionalContext` goes to the session that is
#    starting; a subagent is dispatched inside a running session and never
#    starts one, so the hook cannot reach it. The one way the rulebook could
#    still be inherited is a memory filename at the plugin root — a CLAUDE.md
#    there loads as project memory in this checkout and is passed to every
#    subagent, which no installing project reproduces.
if [ -e "$root/CLAUDE.md" ]; then
  no "CLAUDE.md at the repository root would load as project memory and be inherited by every subagent"
else
  ok "no CLAUDE.md at the repository root, so nothing here loads as inheritable project memory"
fi

# The other way in is an agent's own context: a page that reads the rulebook,
# or a shipped skill that carries it, would put session rules in front of an
# agent that is not the session. What binds an agent lives in the shared brief.
rulebook_readers="$(grep -ln 'rulebook' "$root"/agents/*.md "$root"/skills/*/SKILL.md 2>/dev/null || true)"
if [ -z "$rulebook_readers" ]; then
  ok "no agent page and no shipped skill names the rulebook"
else
  no "these reach an agent and name the rulebook:"
  echo "$rulebook_readers" | sed "s|^$root/|       |"
fi

echo
echo "=== the collector is reached from the hook and from nowhere else"

# The recorder every agent writes its step through used to push the document
# to the collector itself, which put a network call, a two-second timeout and
# a pair of environment variables inside every step of every run — and gave
# the workflow's agents a reference to something they are supposed to know
# nothing about. The FileChanged hook replaced that: the writers write, the
# session's file watcher notices. These cases pin both halves, because the
# tree shows neither.

# 1. Wired at all. A hook script nothing dispatches sends nothing, and a run
#    would look stuck to whoever is watching it with no sign why. PostToolUse
#    on Bash and not the FileChanged this describes: FileChanged is not in
#    every Claude Code that runs this plugin yet, and a hook that silently
#    never fires is worse than one that fires often. The recorder is always
#    run as a Bash call, and tool events fire inside a subagent too, which is
#    where every write of a run state is made.
if grep -q 'PostToolUse' "$root/hooks/hooks.json" &&
  grep -q 'backlog-changed.mjs' "$root/hooks/hooks.json" &&
  grep -q '"matcher": "Bash"' "$root/hooks/hooks.json"; then
  ok "hooks.json subscribes backlog-changed.mjs to PostToolUse on Bash"
else
  no "hooks.json does not wire backlog-changed.mjs to PostToolUse on Bash — no run state would reach a collector"
fi

# 2. The script itself has to exist, parse, and be runnable as the command
#    hooks.json names — it is invoked directly, so a lost executable bit is a
#    hook that fails on every change.
if [ -x "$root/hooks/backlog-changed.mjs" ]; then
  ok "hooks/backlog-changed.mjs exists and is executable"
else
  no "hooks/backlog-changed.mjs is missing or not executable, and hooks.json invokes it directly"
fi
if node --check "$root/hooks/backlog-changed.mjs" >/dev/null 2>&1; then
  ok "the run-state hook parses"
else
  no "the run-state hook does not parse (or does not exist)"
fi
if grep -q 'hooks/backlog-changed.test.mjs' "$root/test.sh"; then
  ok "test.sh lists the run-state hook suite"
else
  no "test.sh does not list the run-state hook suite"
fi

# 3. And nowhere else. The workflow, the agent pages, the shared brief and the
#    recorder are what a run is made of, and none of them may name a
#    collector, a telemetry variable or argus: an agent that knows it is being
#    measured is an agent whose run changed because someone watched it. The
#    argus skill is deliberately outside this file set — it is the session's
#    own page about measuring, and it reaches no agent.
telemetry_refs="$(grep -rniE 'argus|OTEL_|UROBOROS_OBS|collector' \
  "$root"/workflows/*.js "$root"/agents/*.md "$root/skills/agent-brief/SKILL.md" \
  "$root/skills/agent-brief/assets/backlog.mjs" 2>/dev/null || true)"
if [ -z "$telemetry_refs" ]; then
  ok "no workflow, agent page, shared brief or recorder names a collector"
else
  no "these reach a run and still name a collector:"
  echo "$telemetry_refs" | sed "s|^$root/|       |"
fi

# The same fact one level down: the recorder may not reach a network at all,
# whatever it calls the thing it reaches.
if grep -qE '\bfetch\(|node:https?|XMLHttpRequest' "$root/skills/agent-brief/assets/backlog.mjs"; then
  no "the recorder still opens a connection — writing the state must cost one write and nothing else"
else
  ok "the recorder opens no connection: it writes the file and stops there"
fi

echo
echo "=== the read barrier is wired, and decides from the payload alone"

# 1. Wired at all. A PreToolUse hook nothing dispatches refuses nothing, and
#    the barriers the pages only ask for stay honour-system. The matcher must
#    name all three gated tools — Read, Bash and Grep — or a route through one
#    of them would fire the hook never at all.
if node -e '
  const hooks = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const entries = (hooks.hooks && hooks.hooks.PreToolUse) || [];
  const match = entries.find(function (e) {
    return typeof e.matcher === "string" &&
      e.matcher.includes("Read") && e.matcher.includes("Bash") && e.matcher.includes("Grep") &&
      Array.isArray(e.hooks) &&
      e.hooks.some(function (h) { return typeof h.command === "string" && h.command.endsWith("read-barrier.mjs"); });
  });
  process.exit(match ? 0 : 1);
' "$root/hooks/hooks.json" >/dev/null 2>&1; then
  ok "hooks.json subscribes read-barrier.mjs to PreToolUse on Read, Bash and Grep"
else
  no "hooks.json does not subscribe read-barrier.mjs to PreToolUse on Read, Bash and Grep — the barriers would be honour-system again"
fi

# 2. The script itself has to exist, parse, and be runnable as the command
#    hooks.json names — it is invoked directly, so a lost executable bit is a
#    hook that fails on every call.
if [ -x "$root/hooks/read-barrier.mjs" ]; then
  ok "hooks/read-barrier.mjs exists and is executable"
else
  no "hooks/read-barrier.mjs is missing or not executable, and hooks.json invokes it directly"
fi

# 3. It parses.
if node --check "$root/hooks/read-barrier.mjs" >/dev/null 2>&1; then
  ok "the read barrier parses"
else
  no "the read barrier does not parse (or does not exist)"
fi

# 4. It decides from agent_type and the tool input alone — a hook that started
#    reading the state it guards would be guarding it by opening it.
if grep -qE "node:fs|readFileSync|writeFileSync|\bfetch\(|node:https?" "$root/hooks/read-barrier.mjs" 2>/dev/null; then
  no "hooks/read-barrier.mjs touches the filesystem or the network — it must decide from the payload alone"
else
  ok "hooks/read-barrier.mjs opens no file and no connection"
fi

# 5. The suite is listed in the one command behind "the suite is green".
if grep -q 'hooks/read-barrier.test.mjs' "$root/test.sh"; then
  ok "test.sh lists the read barrier suite"
else
  no "test.sh does not list the read barrier suite"
fi

echo
echo "=== the run state is the channel, and no prose handoff is left"

# The five handoff files used to be the channel between agents and the record
# of the run at once. A prompt or a page that still names one is a channel
# nobody deleted, so a grep across every prompt-bearing file catches a
# straggler before an agent goes looking for a file that no longer exists.
# The [^/] guard is load-bearing: README.md links agents/researcher.md as an
# agent page, which is not a handoff, and the regex must not flag it.
# .claude/rules/agents.md is deliberately outside the file set below — it
# names agent pages as examples for whoever writes them, not a channel.
handoff_refs="$(grep -nE '(^|[^/])(researcher|test-author|implementer|reviewer|planner)\.md|backlog\.md' \
  "$root"/workflows/*.js "$root"/agents/*.md "$root"/skills/*/SKILL.md "$root/rulebook.md" "$root/README.md" 2>/dev/null || true)"
if [ -z "$handoff_refs" ]; then
  ok "no prompt, agent page or skill still names a prose handoff file"
else
  no "these lines still name a prose handoff file:"
  echo "$handoff_refs" | sed 's/^/       /'
fi

# Finding 2 (round 1): a page can point at "your handoff" without naming any
# of the five files above, and the guard above matches file *names*, not the
# word — agents/planner.md line 55 said "Say in your handoff which criterion
# went where" and slipped through untouched. hand-?off, not a plain "hand":
# "hand over", which the shared brief and the agent pages say more than
# once, must not match. .claude/rules/agents.md stays outside this file set,
# same as above — it names agent pages as examples for whoever writes them.
handoff_word="$(grep -rniE 'hand-?off' \
  "$root"/workflows/*.js "$root"/agents/*.md "$root"/skills/*/SKILL.md "$root/rulebook.md" "$root/README.md" 2>/dev/null || true)"
if [ -z "$handoff_word" ]; then
  ok "no prompt, agent page or skill still says handoff, in any spelling"
else
  no "these lines still say handoff:"
  echo "$handoff_word" | sed 's/^/       /'
fi

# The workflow opens every run with the same cheap dispatch — the read that
# makes a restart resume instead of starting over.
if grep -q 'backlog.json' "$root/workflows/agile-loop.js" && grep -q 'load-state' "$root/workflows/agile-loop.js"; then
  ok "agile-loop.js carries the state loader and the file it loads"
else
  no "agile-loop.js is missing backlog.json or load-state"
fi

# The reviewer's independence is the one boundary a channel change could
# quietly erase: recording through the same file it must not read is only
# safe if its own page says so twice — once as a rule, once as a diff
# exclusion.
reviewer_page="$root/agents/reviewer.md"
if grep -i 'backlog.json' "$reviewer_page" | grep -Eiq 'not read|never read|without reading'; then
  ok "the reviewer's page forbids reading backlog.json"
else
  no "the reviewer's page does not forbid reading backlog.json"
fi
if grep -i 'backlog.json' "$reviewer_page" | grep -qi 'diff'; then
  ok "the reviewer's page excludes backlog.json from the diff it judges"
else
  no "the reviewer's page does not exclude backlog.json from its diff judgment"
fi

# The planner opens the run, closes every increment, and owns the codemap.
if grep -q 'uroboros:planner' "$root/workflows/agile-loop.js"; then
  ok "agile-loop.js dispatches the planner"
else
  no "agile-loop.js does not dispatch the planner"
fi
if grep -q 'codemap' "$root/workflows/agile-loop.js"; then
  ok "agile-loop.js carries the codemap channel"
else
  no "agile-loop.js never mentions the codemap"
fi

# Every agent records its own step now — the planner's exclusive backlog
# ownership is what this change ends.
missing_backlog_ref=""
for page in "$root"/agents/*.md; do
  grep -q 'backlog.json' "$page" || missing_backlog_ref="$missing_backlog_ref $(basename "$page")"
done
if [ -z "$missing_backlog_ref" ]; then
  ok "every agent page names backlog.json, the file it records its step into"
else
  no "these agent pages do not mention backlog.json:$missing_backlog_ref"
fi
if grep -q 'backlog.mjs' "$root/skills/agent-brief/SKILL.md"; then
  ok "the shared brief names the helper that records a step"
else
  no "the shared brief does not name backlog.mjs"
fi

# Finding 3 (round 1): step-level granularity is theater without a push per
# step, and a plain `grep -qi 'push'` over the two workflow scripts survives
# even if the per-step push instruction is deleted from noDispatch — both
# scripts also say "push" in their unrelated Publish prompt. That behavioural
# fact is now guarded by driver mode w8 above, per step, per workflow. What
# stays a grep is the shared brief's own sentence, tightened to its exact
# words so the frontmatter description ("pushes its step return") cannot
# satisfy it by accident.
if grep -q 'push the commit' "$root/skills/agent-brief/SKILL.md"; then
  ok "the shared brief instructs pushing the step's commit"
else
  no "the shared brief does not instruct pushing the step's commit"
fi

# Round 2, finding 3: a step worked a second time after a restart can find
# what its interrupted first run already committed — failing tests that
# exist, code that half-exists — and nothing said so, so a repeated step was
# free to write everything a second time instead of finishing or correcting
# it.
if grep -q 'already committed' "$root/skills/agent-brief/SKILL.md"; then
  ok "the shared brief tells a repeated step what its first run may have left behind"
else
  no "the shared brief does not tell a repeated step what its first run may have left behind"
fi

# The helper is the only writer of backlog.json, so it has to exist, parse,
# and be in the one command that proves the suite green.
if [ -f "$root/skills/agent-brief/assets/backlog.mjs" ]; then
  ok "skills/agent-brief/assets/backlog.mjs exists"
else
  no "skills/agent-brief/assets/backlog.mjs does not exist"
fi
if node --check "$root/skills/agent-brief/assets/backlog.mjs" >/dev/null 2>&1; then
  ok "the backlog helper parses"
else
  no "the backlog helper does not parse (or does not exist)"
fi
if grep -q 'skills/agent-brief/assets' "$root/test.sh"; then
  ok "test.sh lists the recorder suite"
else
  no "test.sh does not list the recorder suite"
fi

echo
echo "=== the planner alone owns the chain depth it decides"

# `chain depth` is the planner's phrase to define and to own; any other agent
# page or shipped skill naming it too would say the bar twice, and the two
# copies disagree the moment one drifts. Mirrors the rulebook_readers case
# above.
chain_depth_owners="$(grep -lie 'chain depth' "$root"/agents/*.md "$root"/skills/*/SKILL.md 2>/dev/null || true)"
if [ "$chain_depth_owners" = "$root/agents/planner.md" ]; then
  ok 'agents/planner.md is the only agent page or shipped skill naming "chain depth"'
else
  no "the phrase \"chain depth\" is owned by more (or fewer) pages than agents/planner.md alone:"
  echo "${chain_depth_owners:-       (none)}" | sed "s|^$root/|       |"
fi

# The implementer's second work order — where its prompt names no researcher
# step, the criteria and the codemap are its whole brief — has to name the
# codemap by name for that brief to mean anything.
if grep -qi 'codemap' "$root/agents/implementer.md"; then
  ok "agents/implementer.md names the codemap it works from when no researcher step is named"
else
  no "agents/implementer.md never names the codemap"
fi

echo
echo "=== the mutation standard has one owner"

# Criterion 1: the researcher's page requires a per-criterion go-red case —
# at least one case that fails when that criterion's behaviour is broken or
# removed. Break: delete from the '**What.**' bullet the sentence "Hold the
# plan to the shared brief's mutation standard: every acceptance criterion
# gets at least one case that fails when that criterion's behaviour is broken
# or removed."
if grep -qi 'at least one case' "$root/agents/researcher.md" && grep -qi 'broken or removed' "$root/agents/researcher.md"; then
  ok "agents/researcher.md requires a case that fails when a criterion's behaviour is broken or removed"
else
  no "agents/researcher.md does not require a per-criterion go-red case"
fi

# Criterion 2: each planned case states the production change that would make
# it fail. Break: remove the clause "the break — the production change that
# would make it fail" from that bullet.
if grep -qi 'production change' "$root/agents/researcher.md"; then
  ok "agents/researcher.md requires each planned case to state the production change that would make it fail"
else
  no "agents/researcher.md does not require a case to state the production change that would make it fail"
fi

# Criterion 3, part one: the mutation standard is defined on exactly one
# owning page, the shared brief. Break: delete the brief's section.
if grep -q '## The mutation standard' "$root/skills/agent-brief/SKILL.md"; then
  ok "skills/agent-brief/SKILL.md carries the '## The mutation standard' section"
else
  no "skills/agent-brief/SKILL.md does not carry a '## The mutation standard' section"
fi

# Criterion 3, part two: no other agent page or shipped skill restates the
# standard — mirrors the chain_depth_owners case above. Break, either
# direction: restate the defining sentence on any agent page or second skill
# (two paths match), or delete it from the brief (none match).
mutation_standard_owners="$(grep -lie 'counts as tested' "$root"/agents/*.md "$root"/skills/*/SKILL.md 2>/dev/null || true)"
if [ "$mutation_standard_owners" = "$root/skills/agent-brief/SKILL.md" ]; then
  ok "skills/agent-brief/SKILL.md is the only agent page or shipped skill naming what counts as tested"
else
  no "the phrase \"counts as tested\" is owned by more (or fewer) pages than skills/agent-brief/SKILL.md alone:"
  echo "${mutation_standard_owners:-       (none)}" | sed "s|^$root/|       |"
fi

# Criterion 3, part three: the researcher and the reviewer point at the
# owning page instead of restating it. Break: drop either page's pointer.
if grep -qi 'mutation standard' "$root/agents/researcher.md"; then
  ok "agents/researcher.md points at the mutation standard"
else
  no "agents/researcher.md does not point at the mutation standard"
fi
if grep -qi 'mutation standard' "$root/agents/reviewer.md"; then
  ok "agents/reviewer.md points at the mutation standard"
else
  no "agents/reviewer.md does not point at the mutation standard"
fi

# Criterion 3, part four: the reviewer's old free-standing restatement of the
# question is gone, replaced by the pointer above. Break: reinstate the old
# wording in check 3. Collapsed to a single line first — the phrase wraps
# across lines in the page's prose and a plain grep would miss it there.
reviewer_collapsed="$(tr '\n' ' ' <"$root/agents/reviewer.md" | tr -s ' ')"
if echo "$reviewer_collapsed" | grep -qi 'fails if the behaviour breaks'; then
  no "agents/reviewer.md still restates the mutation standard instead of pointing at its owner"
else
  ok "agents/reviewer.md no longer restates the mutation standard in its own words"
fi

# Criterion 4: a test plan that leaves a criterion without a go-red case must
# say so and why, in the plan itself. Break: delete "Where you leave a
# criterion without such a case, the plan itself says so and why" from the
# bullet.
if grep -Eqi 'says? so and why' "$root/agents/researcher.md"; then
  ok "agents/researcher.md requires a skipped criterion to say so and why, in the plan itself"
else
  no "agents/researcher.md does not require a skipped criterion to say so and why"
fi

echo
echo "=== the break the test plan named reaches the reviewer"

# These three cases are the whole of the page rules this increment adds — all
# on agents/researcher.md's '## What you record'. Collapsed first, the way the
# mutation-standard section above collapses agents/reviewer.md: the sentences
# below wrap across a line break in the page's prose, and a plain grep would
# miss them there.
break_researcher_collapsed="$(tr '\n' ' ' <"$root/agents/researcher.md" | tr -s ' ')"

# Criterion 1: `breaks` and `unbreakable` each get their own template on the
# page. Break: delete the new breaks/unbreakable bullet from '## What you
# record'.
if echo "$break_researcher_collapsed" | grep -q '<criterion> — <the production change that would make it fail>' &&
  echo "$break_researcher_collapsed" | grep -q '<criterion> — <why no test can catch it>'; then
  ok "agents/researcher.md gives both breaks and unbreakable their own template"
else
  no "agents/researcher.md does not give both breaks and unbreakable their own template"
fi

# Criterion 1: every criterion stands in exactly one of the two lists. Break:
# delete that sentence from the bullet.
if echo "$break_researcher_collapsed" | grep -qi 'every criterion stands in exactly one of the two lists'; then
  ok "agents/researcher.md requires every criterion to stand in exactly one of the two lists"
else
  no "agents/researcher.md does not require every criterion to stand in exactly one of the two lists"
fi

# Criterion 1: the needs-no-tests edge is decided on the page, not left to
# judgement. Break: delete that clause from the bullet.
if echo "$break_researcher_collapsed" | grep -qi 'a plan that needs no tests puts every criterion in unbreakable'; then
  ok "agents/researcher.md decides that a plan that needs no tests puts every criterion in unbreakable"
else
  no "agents/researcher.md does not decide where a plan that needs no tests puts its criteria"
fi

echo
echo "=== a decidable question gets a ruling, not a stall"

brief_collapsed="$(tr '\n' ' ' <"$root/skills/agent-brief/SKILL.md" | tr -s ' ')"

# Criterion 1.1: the five material terms the rulebook gives the session stand
# in the brief and in rulebook.md alike. Break: delete the sentence "A
# question is material when it turns on user-visible behaviour, a public
# contract, the data model, the dependency footprint, or anything
# irreversible." from the brief — four of the five terms vanish and the case
# fails. It fails in the other direction too if rulebook.md's own list drifts
# from the brief's.
declare -a material_terms=(
  "user-visible behaviour"
  "public contract"
  "data model"
  "dependency footprint"
  "irreversible"
)
for term in "${material_terms[@]}"; do
  if echo "$brief_collapsed" | grep -qi "$term"; then
    ok "the shared brief names \"$term\" as a material term"
  else
    no "the shared brief does not name \"$term\" as a material term"
  fi
  if grep -qi "$term" "$root/rulebook.md"; then
    ok "rulebook.md names \"$term\" as a material term"
  else
    no "rulebook.md does not name \"$term\" as a material term"
  fi
done

# Criterion 1.2: the brief names the other side of the test. Break: delete
# "Everything else is decidable." from the brief.
if echo "$brief_collapsed" | grep -qi 'decidable'; then
  ok "the shared brief names the decidable side of the material test"
else
  no "the shared brief does not name a decidable question"
fi

# Criterion 2.1: a material question stays in questions. Break: delete "A
# material question goes in `questions`" from the "Rulings, not stalls"
# section, or reword it to send a material question anywhere else.
if echo "$brief_collapsed" | grep -q 'A material question goes in `questions`'; then
  ok "the shared brief keeps a material question in \`questions\`"
else
  no "the shared brief no longer keeps a material question in \`questions\`"
fi

# Criterion 2.2: a non-empty questions list still ends the run. Break: delete
# that clause from the questions bullet of "Your step return".
if echo "$brief_collapsed" | grep -q 'A non-empty list ends the run'; then
  ok "the shared brief still ends the run on a non-empty \`questions\`"
else
  no "the shared brief no longer says a non-empty \`questions\` ends the run"
fi

# Criterion 3.1: a decidable question is forbidden in questions. Break:
# delete "A decidable one never does", or soften it to allow a decidable
# question into questions.
if echo "$brief_collapsed" | grep -q 'A decidable one never does'; then
  ok "the shared brief forbids a decidable question in \`questions\`"
else
  no "the shared brief no longer forbids a decidable question in \`questions\`"
fi

# Criterion 3.2: the agent picks a default and records it in rulings. Break:
# delete either half of "pick the default that costs least to undo, carry on,
# and record it in `rulings`".
if echo "$brief_collapsed" | grep -q 'record it in `rulings`' && echo "$brief_collapsed" | grep -q 'pick the default'; then
  ok "the shared brief requires a picked default recorded in \`rulings\`"
else
  no "the shared brief no longer requires a picked default recorded in \`rulings\`"
fi

# Criterion 3.3: rulings is one of the fields meaning the same in every role.
# Break: delete that bullet from the "Three of those fields mean the same in
# every role" list.
if echo "$brief_collapsed" | grep -q '\*\*`rulings`\*\*'; then
  ok "the shared brief lists \`rulings\` among the fields meaning the same in every role"
else
  no "the shared brief does not list \`rulings\` among the fields meaning the same in every role"
fi

# Criterion 4.1: the shape of one ruling. Break: delete or reword that
# sentence.
if echo "$brief_collapsed" | grep -q 'one string naming the decision, the reason, and what it costs if the default is wrong'; then
  ok "the shared brief states the shape of one ruling"
else
  no "the shared brief does not state the shape of one ruling"
fi

# Criterion 4.2: the length constraint. Break: drop the length constraint
# from that sentence.
if echo "$brief_collapsed" | grep -q 'steering projection'; then
  ok "the shared brief bounds a ruling's length to survive the steering projection"
else
  no "the shared brief does not bound a ruling's length to survive the steering projection"
fi

# Criterion 5.1: every agent page names the rulings field. Break: remove
# rulings from any one of them — the case fails and names it.
missing_rulings_ref=""
for page in "$root"/agents/*.md; do
  grep -q 'rulings' "$page" || missing_rulings_ref="$missing_rulings_ref $(basename "$page")"
done
if [ -z "$missing_rulings_ref" ]; then
  ok "every agent page names \`rulings\`, the step-return field a ruling is recorded in"
else
  no "these agent pages do not mention \`rulings\`:$missing_rulings_ref"
fi

# Criterion 5.2: the brief is the only page that defines the material test.
# Break, either direction: restate the material list on any agent page or
# second shipped skill (two paths match), or delete it from the brief (none
# match).
ruling_rule_owners="$(grep -lie 'dependency footprint' "$root"/agents/*.md "$root"/skills/*/SKILL.md 2>/dev/null || true)"
if [ "$ruling_rule_owners" = "$root/skills/agent-brief/SKILL.md" ]; then
  ok "skills/agent-brief/SKILL.md is the only agent page or shipped skill naming the material/decidable test"
else
  no "the phrase \"dependency footprint\" is owned by more (or fewer) pages than skills/agent-brief/SKILL.md alone:"
  echo "${ruling_rule_owners:-       (none)}" | sed "s|^$root/|       |"
fi

# Criterion 5.3: the implementer no longer parks every open decision. Break:
# revert either edit.
implementer_collapsed="$(tr '\n' ' ' <"$root/agents/implementer.md" | tr -s ' ')"
if echo "$implementer_collapsed" | grep -q 'need a material decision' && echo "$implementer_collapsed" | grep -q 'leave a material decision open'; then
  ok "agents/implementer.md only parks a material decision, not every open decision"
else
  no "agents/implementer.md does not say it only parks a material decision"
fi
if echo "$implementer_collapsed" | grep -q 'leave a real decision open'; then
  no "agents/implementer.md still says \"leave a real decision open\""
else
  ok "agents/implementer.md no longer says \"leave a real decision open\""
fi

echo
echo "=== a run resumes from the state it recorded"

# A workflow script is only ever compiled at dispatch, minutes into a real
# run — the same reason the compile check below exists. Here the same
# AsyncFunction trick runs the whole script with a stubbed agent(), so the
# resume mechanics (a recorded step is skipped, a finished backlog dispatches
# only the state loader and publish, each role's prompt carries only its own
# slice) are proven without ever paying for a live dispatch. `args`, `agent`,
# `log` and `phase` are the whole runtime the scripts may use, so running them
# this way also proves they use nothing else — no `require`, no ambient file
# access.
driver_tmp="$(mktemp -d)"
cat >"$driver_tmp/driver.js" <<'JS'
const fs = require('fs');

const file = process.argv[2];
const mode = process.argv[3];
const failures = [];

function fail(msg) { failures.push(msg); }
function assertTrue(cond, msg) { if (!cond) fail(msg); }
function assertEqualArrays(actual, expected, msg) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) fail(msg + ' — expected ' + e + ' got ' + a);
}

// Content no longer travels in prompts: every role reads its brief out of
// backlog.json, and a dispatch prompt carries the read that fetches it. So the
// markers below are the ones that legitimately remain in a prompt — a command
// to run, a question to re-ask, an increment title — and the reads themselves
// are asserted as text. DISJOINT_MARKERS is the standing guard that no two of
// them contain one another, which would let a slice assertion pass for the
// wrong reason.
const CHECK_MARKER = 'echo CHECK-MARKER';
const DISJOINT_MARKERS = [
  'CHECK-MARKER',
  'MARKER-HUMAN-QUESTION',
  'MARKER-VERDICT-REASON',
  'MARKER-CLOSE-QUESTION',
  'MARKER-STALE-CUT',
  'MARKER-FRESH-CUT',
  'MARKER-CUT-QUESTION',
  'MARKER-BUILD-QUESTION',
  'MARKER-HUMAN-ANSWER',
  'MARKER-FINDING-CLAIM',
  'MARKER-FINDING-REPRO',
  'MARKER-REVIEW-HEAD',
  'MARKER-RULING-CUT',
  'MARKER-RULING-PLAN',
  'MARKER-RULING-TESTS',
  'MARKER-RULING-BUILD',
  'MARKER-RULING-VERDICT',
  'MARKER-RULING-CLOSE',
  'MARKER-RULING-RESUMED',
  'MARKER-RULING-ARCHIVED',
  'MARKER-BREAK',
  'MARKER-UNBREAKABLE',
];

// The read a prompt has to carry for its role to have a brief at all. Written
// out here exactly as the workflow renders it, so a change to the calling
// convention fails these cases instead of silently leaving an agent with a
// pointer to nothing.
const STATE_PATH = 'docs/issues/x/backlog.json';
const READ_CODEMAP = 'codemap ' + STATE_PATH;
const READ_INDEX = 'index ' + STATE_PATH;
const readStep = (id, label, fields) =>
  'steps ' + STATE_PATH + ' ' + id + ' ' + label + (fields ? ' --fields ' + fields : '');

// What each role hands back to the script now: the values it steers on, and
// nothing else. A plan, a test plan, a case list and a finding are in the run
// state and reach no prompt, so no fixture below carries them.
const planReturn = {
  needsTests: true,
  checks: [CHECK_MARKER],
  breaks: ['does i1 — MARKER-BREAK'],
  unbreakable: [],
  questions: [],
  summary: 'plan summary',
};
const planReturnWithQuestion = Object.assign({}, planReturn, { questions: ['ask the human'] });
// w31's fixture for the criterion the plan named no break for: the break list
// is empty and the criterion sits in `unbreakable` instead, with the reason.
const planReturnUnbreakable = Object.assign({}, planReturn, {
  breaks: [],
  unbreakable: ['does i1 — MARKER-UNBREAKABLE'],
});
const testsReturn = { questions: [], summary: 'tests summary' };
const buildReturn = { questions: [], summary: 'build summary' };
const verdictReturnClean = {
  findingCount: 0,
  allDirect: false,
  reason: '',
  questions: [],
  summary: 'verdict summary',
};
const verdictReturnWithFinding = {
  findingCount: 1,
  allDirect: false,
  reason: 'MARKER-VERDICT-REASON',
  findings: [
    { claim: 'MARKER-FINDING-CLAIM', reproduction: 'MARKER-FINDING-REPRO', criterion: 'does i1' },
  ],
  head: 'MARKER-REVIEW-HEAD',
  questions: [],
  summary: 'verdict summary',
};
// w16's fixture: a review whose every finding is a direct fix. Such a round is
// worked without a researcher and without a test, so the implementer is
// dispatched straight off the review's recorded findings.
const verdictReturnWithDirectFinding = Object.assign({}, verdictReturnWithFinding, {
  allDirect: true,
});

function increment(id, depth) {
  return { id, title: 'Deliver ' + id, goal: 'Deliver ' + id + '.', criteria: ['does ' + id], status: 'todo', note: '', depth: depth || 'full' };
}
const decomposeReturnOne = { increments: [increment('i1')], questions: [], summary: 'backlog summary' };
const decomposeReturnTwo = { increments: [increment('i1'), increment('i2')], questions: [], summary: 'backlog summary' };
// The planner's chain depth on the cut: one increment classified direct alone,
// and a mix of a full increment followed by a direct one, so a run can prove
// each increment takes its own path.
const decomposeReturnDirect = { increments: [increment('i1', 'direct')], questions: [], summary: 'backlog summary' };
const decomposeReturnMixed = { increments: [increment('i1'), increment('i2', 'direct')], questions: [], summary: 'backlog summary' };

// The state loader returns the index of backlog.json, never the file: the cut,
// the recorded labels and the small steering values of each. These builders
// produce exactly what `backlog.mjs index` prints, flattened into the STATE
// schema the workflow asks for.
function idxStep(label, ret) {
  const r = ret || {};
  const questions = Array.isArray(r.questions) ? r.questions.filter(Boolean) : [];
  return {
    label,
    asked: questions.length > 0,
    questions,
    needsTests: r.needsTests === true,
    checks: Array.isArray(r.checks) ? r.checks : [],
    breaks: Array.isArray(r.breaks) ? r.breaks : [],
    unbreakable: Array.isArray(r.unbreakable) ? r.unbreakable : [],
    findingCount: r.findingCount || 0,
    allDirect: r.allDirect === true,
    reason: r.reason || '',
    rulings: Array.isArray(r.rulings) ? r.rulings : [],
  };
}

function idxIncrement(id, extra) {
  return Object.assign(
    {
      id,
      title: 'Deliver ' + id,
      goal: 'Deliver ' + id + '.',
      criteria: ['does ' + id],
      status: 'todo',
      note: '',
      branch: '',
      depth: 'full',
      steps: [],
      attempts: 0,
      attemptRulings: [],
      attemptBreaks: [],
    },
    extra || {},
  );
}

const noState = { exists: false, branch: 'issue-branch', increments: [], runSteps: [], decisions: '', summary: '' };
const stateOf = (increments, runSteps, decisions) => ({
  exists: true,
  branch: 'issue-branch',
  increments,
  runSteps,
  decisions: decisions || '',
  summary: '',
});

// A session that died mid-increment: research and tests are recorded, the
// implementer never ran. The steering the implementer's round needs — the
// checks the researcher closed — comes back out of the index, which is what
// makes the resume work without anyone re-emitting the plan.
const resumeState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [idxStep('research:i1.0', planReturn), idxStep('tests:i1.0', testsReturn)],
      }),
    ],
    [idxStep('decompose', decomposeReturnOne)],
  );

// A session that died right after round 0's review filed a finding, before the
// correction round it opens ran a step. `idxStep` drops `findings` and `head`
// off the recorded review — what a restart really leaves behind — so the
// resumed correction round has nothing but `round > 0` to go on.
const correctionResumeState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [
          idxStep('research:i1.0', planReturn),
          idxStep('tests:i1.0', testsReturn),
          idxStep('implement:i1.0', buildReturn),
          idxStep('review:i1.0', verdictReturnWithFinding),
        ],
      }),
    ],
    [idxStep('decompose', decomposeReturnOne)],
  );

// A session that died after the researcher and the test-author each recorded a
// ruling, with the implementer never run: a resumed run skips both steps, but
// the result it hands back must still carry what they decided.
const rulingResumeState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [
          idxStep('research:i1.0', Object.assign({}, planReturn, { rulings: ['MARKER-RULING-RESUMED'] })),
          idxStep('tests:i1.0', Object.assign({}, testsReturn, { rulings: ['MARKER-RULING-TESTS'] })),
        ],
      }),
    ],
    [idxStep('decompose', Object.assign({}, decomposeReturnOne, { rulings: ['MARKER-RULING-CUT'] }))],
  );

// A run resumed behind an increment an earlier session already closed: the
// closed increment's rulings live only in its archived attempt now, so the
// result of this run has to recover them from there — the resumed half of
// criterion 3, on a cut boundary rather than a mid-increment crash.
const closedRulingState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        status: 'done',
        note: 'accepted',
        branch: 'issue-branch--i1',
        attempts: 1,
        attemptRulings: [
          { label: 'research:i1.0', rulings: ['MARKER-RULING-ARCHIVED'] },
          { label: 'replan:i1', rulings: ['MARKER-RULING-CLOSE'] },
        ],
      }),
      idxIncrement('i2'),
    ],
    [idxStep('decompose', decomposeReturnTwo)],
  );

// A run resumed behind an increment an earlier session closed, whose plan
// named a break for none of its criteria: the run's result has to carry the
// same `unchecked` list a run that never restarted would, recovered from the
// closed increment's archived attempt rather than from a step this session
// works.
const closedBreakState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        status: 'done',
        note: 'accepted',
        branch: 'issue-branch--i1',
        attempts: 1,
        attemptBreaks: [
          { label: 'research:i1.0', breaks: [], unbreakable: ['does i1 — MARKER-UNBREAKABLE'] },
        ],
      }),
      idxIncrement('i2'),
    ],
    [idxStep('decompose', decomposeReturnTwo)],
  );

// A run whose research:i1.0 ended with a question for the human. A resumed run
// must not treat it as recorded: it works that step again, with the question in
// front of it.
const questionState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [idxStep('research:i1.0', Object.assign({}, planReturn, { questions: ['MARKER-HUMAN-QUESTION'] }))],
      }),
    ],
    [idxStep('decompose', decomposeReturnOne)],
  );

// The implementer is the role this case is built on: its own page and
// `hooks/read-barrier.mjs` close `issue.md` to it, so it is the role whose
// resume the old prompt broke by pointing it there for the human's answer.
const buildQuestionState = () =>
  stateOf(
    [
      idxIncrement('i1', {
        branch: 'issue-branch--i1',
        steps: [
          idxStep('research:i1.0', planReturn),
          idxStep('tests:i1.0', testsReturn),
          idxStep('implement:i1.0', Object.assign({}, buildReturn, { questions: ['MARKER-BUILD-QUESTION'] })),
        ],
      }),
    ],
    [idxStep('decompose', decomposeReturnOne)],
    'MARKER-HUMAN-ANSWER',
  );

// A finished run. `close` archived the increment's steps and the run-level
// `replan:i1` with them, so the index shows an increment with no current step
// and a run that still carries only its opening cut.
const doneState = () =>
  stateOf([idxIncrement('i1', { status: 'done', note: 'accepted' })], [idxStep('decompose', decomposeReturnOne)]);

// A state file that holds increments while its decompose step is not
// replayable, which is the only case in which Decompose is dispatched again
// with a populated backlog behind it. `carried` true is the run whose opening
// cut ended with a question; `carried` false is the session that died between
// the planner's `init` and its `record`.
const recutState = (carried) =>
  stateOf(
    [idxIncrement('i1', { title: 'MARKER-STALE-CUT' }), idxIncrement('i2')],
    carried ? [idxStep('decompose', { questions: ['MARKER-CUT-QUESTION'] })] : [],
  );

// The cut the human's answer bought: one increment under an id the stale file
// does not hold, so a run that works the superseded cut instead shows it in the
// labels it dispatches as well as in the prompts it sends.
const decomposeReturnRecut = {
  increments: [{ id: 'i3', title: 'MARKER-FRESH-CUT', goal: 'Deliver i3.', criteria: ['does i3'], status: 'todo', note: '' }],
  questions: [],
  summary: 'backlog summary',
};

// A closed increment beside an open one — the state a session leaves when it
// dies after `replan:i1` closed the first increment and re-cut.
const laterIncrementState = () =>
  stateOf(
    [idxIncrement('i1', { status: 'done', note: 'accepted' }), idxIncrement('i2')],
    [idxStep('decompose', decomposeReturnOne)],
  );

// The state a hand-back leaves once the session that made it is gone: `close`
// archived the failed attempt's steps, so the increment is open with no
// current step, one closed attempt on record and the abandoned branch still
// carried — and the new session's own attempt counter starts at zero again.
const handedBackState = () =>
  stateOf(
    [idxIncrement('i1', { depth: 'direct', branch: 'issue-branch--i1', attempts: 1 })],
    [idxStep('decompose', decomposeReturnDirect)],
  );

function contextFor(m) {
  switch (m) {
    case 'w1':
      return { stateReturn: noState, decomposeReturn: decomposeReturnTwo, researchReturn: planReturn };
    case 'w2':
      return { stateReturn: resumeState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w3':
      return { stateReturn: doneState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w4':
    case 'w5':
    case 'w6':
    case 'w8':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w7':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturnWithQuestion };
    case 'w9':
      return { stateReturn: questionState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w10':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithFinding : verdictReturnClean) };
    case 'w11':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn, closeFor: () => ({ questions: ['MARKER-CLOSE-QUESTION'], summary: 'closed' }) };
    case 'w12': {
      // The planner closes the increment and hands it straight back as todo —
      // the second chance MAX_ATTEMPTS exists for — and settles it on the
      // second pass.
      let replans = 0;
      return {
        stateReturn: noState,
        decomposeReturn: decomposeReturnOne,
        researchReturn: planReturn,
        closeFor: () => {
          replans += 1;
          return replans === 1
            ? { increments: [increment('i1')], questions: [], summary: 'handed back' }
            : { increments: [Object.assign(increment('i1'), { status: 'done' })], questions: [], summary: 'closed' };
        },
      };
    }
    case 'w13':
      return { stateReturn: recutState(true), decomposeReturn: decomposeReturnRecut, researchReturn: planReturn };
    case 'w14':
      return { stateReturn: recutState(false), decomposeReturn: decomposeReturnRecut, researchReturn: planReturn };
    case 'w15':
      return { stateReturn: laterIncrementState(), decomposeReturn: decomposeReturnTwo, researchReturn: planReturn };
    case 'w16':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithDirectFinding : verdictReturnClean) };
    case 'w17':
    case 'w18':
      // Every review round finds the same needs-plan defect, so the increment
      // burns its correction rounds and closes blocked.
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn, verdictFor: () => verdictReturnWithFinding };
    case 'w19':
      return { stateReturn: buildQuestionState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w20':
      return { stateReturn: noState, decomposeReturn: decomposeReturnDirect, researchReturn: planReturn };
    case 'w21':
      return { stateReturn: noState, decomposeReturn: decomposeReturnMixed, researchReturn: planReturn };
    case 'w22':
      return { stateReturn: noState, decomposeReturn: decomposeReturnDirect, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithFinding : verdictReturnClean) };
    case 'w23': {
      // Modelled on w12: the closing planner hands the direct increment back
      // as todo, still classified direct, and settles it done on the second
      // pass. The depth surviving in the fixture is the point of the case —
      // the loop, not the planner's re-cut, is what forces the second attempt
      // full.
      let replans = 0;
      return {
        stateReturn: noState,
        decomposeReturn: decomposeReturnDirect,
        researchReturn: planReturn,
        closeFor: () => {
          replans += 1;
          return replans === 1
            ? { increments: [increment('i1', 'direct')], questions: [], summary: 'handed back' }
            : { increments: [Object.assign(increment('i1', 'direct'), { status: 'done' })], questions: [], summary: 'closed' };
        },
      };
    }
    case 'w24':
      // w22 with w16's verdict fixture: the review that would open the
      // reviewer-driven fast path for a full increment must not open it for
      // one the planner already cut direct — the allDirect edge of criterion
      // 6.
      return { stateReturn: noState, decomposeReturn: decomposeReturnDirect, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithDirectFinding : verdictReturnClean) };
    case 'w25':
      return { stateReturn: handedBackState(), decomposeReturn: decomposeReturnDirect, researchReturn: planReturn };
    case 'w26':
      // Every step of a plain one-increment fresh run records a ruling, so the
      // labels stay the w1-shaped sequence for one increment and the point of
      // the case is what the result and the publish prompt do with them.
      return {
        stateReturn: noState,
        decomposeReturn: Object.assign({}, decomposeReturnOne, { rulings: ['MARKER-RULING-CUT'] }),
        researchReturn: Object.assign({}, planReturn, { rulings: ['MARKER-RULING-PLAN'] }),
        testsReturn: Object.assign({}, testsReturn, { rulings: ['MARKER-RULING-TESTS'] }),
        buildReturn: Object.assign({}, buildReturn, { rulings: ['MARKER-RULING-BUILD'] }),
        verdictFor: () => Object.assign({}, verdictReturnClean, { rulings: ['MARKER-RULING-VERDICT'] }),
        closeFor: () => ({ summary: 'closed', rulings: ['MARKER-RULING-CLOSE'] }),
      };
    case 'w27':
      // A session that died after the researcher and the test-author each
      // recorded a ruling: the resume skips both, and the run still has to
      // close on one increment, so decompose and research return their plain
      // fixtures.
      return { stateReturn: rulingResumeState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w28':
      return { stateReturn: closedRulingState(), decomposeReturn: decomposeReturnTwo, researchReturn: planReturn };
    case 'w29':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn, verdictFor: (label) => (label === 'review:i1.0' ? verdictReturnWithFinding : verdictReturnClean) };
    case 'w30':
      return { stateReturn: correctionResumeState(), decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w31':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturnUnbreakable };
    case 'w32':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturnUnbreakable };
    case 'w33':
      return { stateReturn: noState, decomposeReturn: decomposeReturnOne, researchReturn: planReturn };
    case 'w34':
      return { stateReturn: noState, decomposeReturn: decomposeReturnDirect, researchReturn: planReturn };
    case 'w35':
      return { stateReturn: closedBreakState(), decomposeReturn: decomposeReturnTwo, researchReturn: planReturn };
    default:
      throw new Error('unknown mode ' + m);
  }
}

const ctx = contextFor(mode);

function returnFor(label) {
  if (label === 'load-state') return ctx.stateReturn;
  if (label === 'decompose') return ctx.decomposeReturn;
  if (label.startsWith('research:')) return ctx.researchReturn;
  if (label.startsWith('tests:')) return ctx.testsReturn || testsReturn;
  if (label.startsWith('implement:')) return ctx.buildReturn || buildReturn;
  if (label.startsWith('review:')) return ctx.verdictFor ? ctx.verdictFor(label) : verdictReturnClean;
  if (label.startsWith('replan:')) {
    return ctx.closeFor ? ctx.closeFor(label) : { summary: 'closed' };
  }
  if (label === 'publish') return { summary: 'published' };
  throw new Error('unexpected label ' + label);
}

async function main() {
  for (const a of DISJOINT_MARKERS) {
    for (const b of DISJOINT_MARKERS) {
      if (a === b) continue;
      assertTrue(!a.includes(b), 'marker "' + a + '" contains marker "' + b + '" as a substring, so a slice assertion built on them cannot be trusted');
    }
  }

  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const src = fs.readFileSync(file, 'utf8').replace(/^export const meta =/m, 'const meta =');
  const fn = new AsyncFunction('args', 'agent', 'log', 'phase', src);
  const calls = [];
  const stub = async (prompt, opts) => {
    calls.push({ label: opts.label, agentType: opts.agentType, prompt, schema: opts.schema });
    return returnFor(opts.label);
  };
  const logs = [];
  const result = await fn({ issueDir: 'docs/issues/x' }, stub, (m) => logs.push(String(m)), () => {});
  const labels = calls.map((c) => c.label);
  const byLabel = (l) => calls.find((c) => c.label === l);

  // The rule the whole channel rests on: the script has no content to leak into
  // a prompt, so no prompt may read a step whole except the closing planner's,
  // which is the one role that re-cuts against everything the increment
  // produced. Every other read names its fields. Checked in every mode.
  for (const c of calls) {
    if (c.label.startsWith('replan:')) continue;
    const unfiltered = c.prompt
      .split('\n')
      .filter((line) => line.includes('steps ' + STATE_PATH) && !line.includes('--fields'));
    assertTrue(unfiltered.length === 0,
      c.label + ' reads a step without naming the fields it may see: ' + JSON.stringify(unfiltered));
  }

  // The publishing agent is handed the run in its prompt and reads no part of
  // the state. It carries no shared brief, so every read it is sent on it pays
  // for twice — once finding the helper, once asking a closed increment for the
  // steps `close` has already moved into its attempts. Checked in every mode.
  const publishing = calls.find((c) => c.label === 'publish');
  if (publishing) {
    assertTrue(!/\b(index|steps|codemap|read) docs\/issues\/x\/backlog\.json/.test(publishing.prompt),
      'the publish prompt sends the agent to read the run state instead of handing it the run');
  }

  // `hooks/read-barrier.mjs` refuses the implementer every read of `issue.md`,
  // so a prompt that ordered one would order a call the hook denies and strand
  // the step mid-run. Checked in every mode.
  for (const c of calls) {
    if (!c.label.startsWith('implement:')) continue;
    const ordered = c.prompt.split('\n').filter((line) => /issue\.md/.test(line) && /\bread\b/i.test(line));
    assertTrue(ordered.length === 0,
      c.label + ' is told to read the issue file its page closes: ' + JSON.stringify(ordered));
  }

  if (mode === 'w1') {
    const expected = ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1',
      'research:i2.0', 'tests:i2.0', 'implement:i2.0', 'review:i2.0', 'replan:i2', 'publish'];
    assertEqualArrays(labels, expected, 'the labels dispatched are not the expected fresh-run sequence');
    assertTrue(!!byLabel('decompose') && byLabel('decompose').agentType === 'uroboros:planner', 'decompose is not dispatched as uroboros:planner');
    assertTrue(!!byLabel('replan:i1') && byLabel('replan:i1').agentType === 'uroboros:planner', 'replan:i1 is not dispatched as uroboros:planner');
    assertTrue(!!byLabel('load-state') && byLabel('load-state').agentType === 'general-purpose', 'load-state is not dispatched as general-purpose');
    assertTrue(!!byLabel('publish') && byLabel('publish').agentType === 'general-purpose', 'publish is not dispatched as general-purpose');
    assertTrue(!!byLabel('replan:i2') && byLabel('replan:i2').agentType === 'uroboros:planner', 'replan:i2 is not dispatched as uroboros:planner');
    // The state loader asks for the index and never for the file: the one read
    // the script makes must not grow with the run.
    const loader = byLabel('load-state');
    assertTrue(!!loader && loader.prompt.includes(READ_INDEX), 'the state loader is not told to read the index');
    assertTrue(!!loader && !/\bread docs\/issues\/x\/backlog\.json/.test(loader.prompt),
      'the state loader is told to read the whole state file, which is what the index exists to avoid');
    assertTrue(!!loader && /## Decisions/.test(loader.prompt) && loader.prompt.includes('docs/issues/x/issue.md'),
      "the state loader is not asked for the human's answer under ## Decisions in issue.md, so a resumed step would have no route to it");
    // The planner said what files the issue changes; every researcher reads
    // that map out of the state, and the prompt asking for the cut asks for
    // the map too.
    assertTrue(!!byLabel('decompose') && /codemap/i.test(byLabel('decompose').prompt), 'the decompose prompt never asks the planner for the codemap');
    assertTrue(!!byLabel('replan:i1') && /codemap/i.test(byLabel('replan:i1').prompt), 'the replan prompt never asks the planner to update the codemap');
    for (const l of ['research:i1.0', 'research:i2.0']) {
      assertTrue(!!byLabel(l) && byLabel(l).prompt.includes(READ_CODEMAP), "the researcher's prompt " + l + ' is not sent to the codemap in the run state');
    }
    // The branch machinery: the attempt's first dispatch records and creates
    // the increment branch, the accepted replan lands it on the issue branch,
    // and the next increment starts its own.
    assertTrue(!!byLabel('research:i1.0') && byLabel('research:i1.0').prompt.includes('git checkout -b issue-branch--i1'),
      "increment i1's first dispatch is not told to create its branch");
    assertTrue(!!byLabel('research:i2.0') && byLabel('research:i2.0').prompt.includes('git checkout -b issue-branch--i2'),
      "increment i2's first dispatch is not told to create its branch");
    assertTrue(!!byLabel('research:i1.0') && /\bbranch\b.*backlog\.json i1 issue-branch--i1/.test(byLabel('research:i1.0').prompt),
      "increment i1's first dispatch is not told to record the branch in the run state");
    assertTrue(!!byLabel('replan:i1') && byLabel('replan:i1').prompt.includes('merge') && byLabel('replan:i1').prompt.includes('issue-branch--i1'),
      'the accepted replan is not told to merge the increment branch into the issue branch');
  } else if (mode === 'w2') {
    assertTrue(!labels.some((l) => l.startsWith('research:')), 'the researcher was dispatched even though its step was already recorded');
    assertTrue(!labels.some((l) => l.startsWith('tests:')), 'the test-author was dispatched even though its step was already recorded');
    const afterLoadState = calls[1];
    assertTrue(!!afterLoadState && afterLoadState.label.startsWith('implement:'), 'the first dispatch after load-state is not the implementer');
    // The resumed implementer gets its brief the same way a live one does: a
    // read of the steps the dead session recorded. Nothing was replayed into
    // its prompt, because nothing of the plan was ever in the script.
    assertTrue(!!afterLoadState && afterLoadState.prompt.includes(readStep('i1', 'research:i1.0', 'plan,moduleMap,environment')),
      "the resumed implementer is not sent to the recorded researcher step");
    assertTrue(!!afterLoadState && afterLoadState.prompt.includes(readStep('i1', 'tests:i1.0', 'cases')),
      'the resumed implementer is not sent to the recorded test-author step');
    // The steering the round needs survived the crash in the state, not in a
    // return anyone re-emitted: the checks reach the implementer's prompt out
    // of the index.
    assertTrue(!!afterLoadState && afterLoadState.prompt.includes('CHECK-MARKER'),
      "the resumed implementer's prompt does not carry the checks the state recorded");
    // The resume finds the recorded branch: the mid-flight increment continues
    // on it instead of starting a fresh one.
    assertTrue(!!afterLoadState && afterLoadState.prompt.includes('issue-branch--i1'),
      "the resumed implementer's prompt does not carry the recorded increment branch");
    assertTrue(!!afterLoadState && !afterLoadState.prompt.includes('git checkout -b issue-branch--i1'),
      'the resumed increment is told to create its branch instead of continuing on it');
    const reviewCall = calls.find((c) => c.label === 'review:i1.0');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('CHECK-MARKER'),
      'the resumed reviewer was handed no checks, so the recorded plan never reached the one role that cannot read it');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('MARKER-BREAK'),
      'the resumed reviewer was handed no break, so the recorded plan never reached the one role that cannot read it');
  } else if (mode === 'w3') {
    assertEqualArrays(labels, ['load-state', 'publish'], 'a fully-closed backlog dispatches more than the state loader and publish');
    // Criterion 5, the closed-increment edge: this fixture's one increment is
    // closed and its archive ruled nothing (idxIncrement's default
    // attemptRulings: []), so the result and the publish prompt must add no
    // noise about rulings — a seeding loop over archived steps must not push
    // an entry regardless of whether the step it archives carries one.
    assertTrue(!!result && Array.isArray(result.rulings) && result.rulings.length === 0,
      'the result of a run whose one closed increment ruled nothing carries a ruling');
    const publishCall = calls.find((c) => c.label === 'publish');
    assertTrue(!!publishCall && !/ruling/i.test(publishCall.prompt),
      'the publish prompt talks about rulings though the closed increment it replays recorded none');
  } else if (mode === 'w4') {
    const testsCall = calls.find((c) => c.label.startsWith('tests:'));
    assertTrue(!!testsCall, 'the test-author was never dispatched');
    assertTrue(!!testsCall && testsCall.prompt.includes(readStep('i1', 'research:i1.0', 'testPlan')),
      "the test-author is not sent to the researcher's test plan");
    // Its independence is now enforced by the read, not by what the script
    // pasted: the helper hands it `testPlan` and the implementation plan
    // beside it never reaches it.
    assertTrue(!!testsCall && !/--fields [^\n]*\bplan\b/.test(testsCall.prompt.replace(/--fields testPlan/g, '')),
      "the test-author's read would hand it the implementation plan");
    assertTrue(!!testsCall && !testsCall.prompt.includes(READ_CODEMAP), "the test-author is sent to the codemap");
    assertTrue(!!testsCall && !testsCall.prompt.includes('review:'), "the test-author is sent to a review step");
  } else if (mode === 'w5') {
    const implCall = calls.find((c) => c.label.startsWith('implement:'));
    assertTrue(!!implCall, 'the implementer was never dispatched');
    assertTrue(!!implCall && implCall.prompt.includes(readStep('i1', 'research:i1.0', 'plan,moduleMap,environment')),
      "the implementer is not sent to the researcher's plan");
    assertTrue(!!implCall && implCall.prompt.includes(readStep('i1', 'tests:i1.0', 'cases')),
      'the implementer is not sent to the tests that already exist');
    assertTrue(!!implCall && implCall.prompt.includes('CHECK-MARKER'), "the implementer's prompt does not carry the checks");
    assertTrue(!!implCall && !implCall.prompt.includes('--fields testPlan'), "the implementer's read would hand it the test plan");
    assertTrue(!!implCall && !implCall.prompt.includes(READ_CODEMAP), 'the implementer is sent to the codemap');
  } else if (mode === 'w6') {
    const reviewCall = calls.find((c) => c.label.startsWith('review:'));
    assertTrue(!!reviewCall, 'the reviewer was never dispatched');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('CHECK-MARKER'), "the reviewer's prompt does not carry the checks");
    // The one role that reads nothing. Every other brief is a read now, so the
    // reviewer's independence is exactly the absence of one.
    assertTrue(!!reviewCall && !/\bsteps docs\/issues\/x\/backlog\.json/.test(reviewCall.prompt),
      'the reviewer is sent to read a step of the run state');
    assertTrue(!!reviewCall && !reviewCall.prompt.includes(READ_CODEMAP), 'the reviewer is sent to the codemap');
    assertTrue(!!reviewCall && !reviewCall.prompt.includes(READ_INDEX), 'the reviewer is sent to the index');
    assertTrue(!!reviewCall && /read nothing out of/i.test(reviewCall.prompt),
      'the reviewer is not told that the run state is closed to it');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('git diff issue-branch...HEAD'),
      "the reviewer's prompt does not name the increment's diff range against the issue branch");
    // Criterion 2: the break the plan named for a criterion reaches the
    // reviewer's prompt, labelled as itself and tied to the criterion it was
    // named for.
    assertTrue(!!reviewCall && reviewCall.prompt.includes('MARKER-BREAK'),
      "the reviewer's prompt does not carry the break the plan named");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('does i1'),
      "the reviewer's prompt does not carry the criterion the break was named for");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('The break the plan named for each criterion it named one for:'),
      "the reviewer's prompt does not carry the breaks heading");
  } else if (mode === 'w7') {
    assertEqualArrays(labels, ['load-state', 'decompose', 'research:i1.0', 'publish'], 'a question from the researcher does not stop the run at publish');
    assertTrue(!!result && !!result.blockedOnHuman, 'the returned result does not carry blockedOnHuman');
    assertTrue(!!result && JSON.stringify(result.blockedOnHuman).includes('ask the human'), 'blockedOnHuman does not carry the question');
  } else if (mode === 'w8') {
    // A plain grep for the word "push" over the whole script survives even if
    // the per-step push instruction is deleted, because the unrelated Publish
    // prompt also says "push". This asserts on every recorded step's own
    // prompt instead — and on the two things that make the state the single
    // source of truth: the return goes in, and the prompt goes in beside it.
    for (const c of calls) {
      if (c.label === 'load-state' || c.label === 'publish') continue;
      assertTrue(/backlog\.json/.test(c.prompt) && /\brecord\b/i.test(c.prompt),
        c.label + ' is not told to record its return into backlog.json');
      assertTrue(/\bpush\b/i.test(c.prompt),
        c.label + " is not told to push its step's commit");
      assertTrue(/verbatim/i.test(c.prompt) && /prompt/i.test(c.prompt),
        c.label + ' is not told to record the prompt it was dispatched with, verbatim');
      assertTrue(/<the return file> <the prompt file>/.test(c.prompt),
        c.label + ' is not given the record call that stores both');
      // R.1: every recording step's payload list carries `rulings`, matched
      // as the rendered bullet so a stray mention elsewhere in the prompt
      // cannot satisfy it.
      assertTrue(c.prompt.includes('- `rulings`'), c.label + ' is not told that its step return carries `rulings`');
      // Criterion 1: the structured return the schema demands carries
      // `rulings` as a required array, not merely as a bullet the prompt's
      // prose names. Every role but load-state and publish is dispatched in
      // this fixture (decompose and replan on BACKLOG, research on PLAN,
      // tests on TESTS, implement on BUILD, review on VERDICT).
      assertTrue(!!c.schema && !!c.schema.properties && !!c.schema.properties.rulings && c.schema.properties.rulings.type === 'array',
        c.label + "'s schema does not declare `rulings` as an array property");
      assertTrue(!!c.schema && Array.isArray(c.schema.required) && c.schema.required.includes('rulings'),
        c.label + "'s schema does not require `rulings`");
    }
    // Criterion 3's mechanism: the state loader is asked for the rulings it
    // reads, on both the run-level steps and the increments' own steps, and
    // its prompt names the field — checked here because the driver's stub
    // returns its fixture whatever the schema says, so no run-level case can
    // catch a schema that stopped asking for the field.
    const loaderCall = byLabel('load-state');
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties &&
      !!loaderCall.schema.properties.runSteps && !!loaderCall.schema.properties.runSteps.items &&
      !!loaderCall.schema.properties.runSteps.items.properties &&
      !!loaderCall.schema.properties.runSteps.items.properties.rulings,
      "the state loader's schema does not ask runSteps for `rulings`");
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties.runSteps &&
      Array.isArray(loaderCall.schema.properties.runSteps.items.required) &&
      loaderCall.schema.properties.runSteps.items.required.includes('rulings'),
      "the state loader's schema does not require `rulings` on runSteps");
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties.increments &&
      !!loaderCall.schema.properties.increments.items && !!loaderCall.schema.properties.increments.items.properties &&
      !!loaderCall.schema.properties.increments.items.properties.steps &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items.properties &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items.properties.rulings,
      "the state loader's schema does not ask an increment's steps for `rulings`");
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties.increments &&
      Array.isArray(loaderCall.schema.properties.increments.items.properties.steps.items.required) &&
      loaderCall.schema.properties.increments.items.properties.steps.items.required.includes('rulings'),
      "the state loader's schema does not require `rulings` on an increment's steps");
    assertTrue(!!loaderCall && /\brulings\b/.test(loaderCall.prompt),
      "the state loader's prompt does not name `rulings` among the fields it fills");
    // Criterion 3, the resumed-run guarantee: the loader's schema asks each
    // increment for the rulings its archived attempts carry, not only the
    // rulings of its current steps — otherwise a resumed run behind a closed
    // increment could never recover what that increment's own steps ruled.
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties.increments &&
      !!loaderCall.schema.properties.increments.items && !!loaderCall.schema.properties.increments.items.properties &&
      loaderCall.schema.properties.increments.items.properties.attemptRulings &&
      loaderCall.schema.properties.increments.items.properties.attemptRulings.type === 'array',
      "the state loader's schema does not declare `attemptRulings` as an array property on each increment");
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties.increments &&
      Array.isArray(loaderCall.schema.properties.increments.items.required) &&
      loaderCall.schema.properties.increments.items.required.includes('attemptRulings'),
      "the state loader's schema does not require `attemptRulings` on each increment");
    assertTrue(!!loaderCall && /\battemptRulings\b/.test(loaderCall.prompt),
      "the state loader's prompt does not name `attemptRulings` among the fields it fills");
  } else if (mode === 'w9') {
    // A recorded step whose return carried a question used to be replayed
    // as-is, so a resumed run dispatched only load-state and publish, forever.
    // This pins the fix: the step that asked is worked again, with the
    // question and the answer's location in its prompt, and the run makes it
    // all the way to a clean close.
    assertEqualArrays(labels,
      ['load-state', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'the resumed run did not work the step that asked the human again, or did not carry on past it');
    const researchCall = calls.find((c) => c.label === 'research:i1.0');
    assertTrue(!!researchCall && researchCall.prompt.includes('MARKER-HUMAN-QUESTION'),
      "the repeated step's prompt does not carry the question it asked");
    assertTrue(!!researchCall && /The human recorded no answer/.test(researchCall.prompt),
      "the repeated step is not told that no answer came back, so it cannot tell an empty answer from a missing one");
    assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 0,
      'the resumed run ended on the stale recorded question instead of making progress');
  } else if (mode === 'w10') {
    // The correction round: the findings channel (researcher <- reviewer) and
    // the reason sentence (human <- reviewer). The findings are in the state
    // now, so what the prompt has to carry is the read that fetches them.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0',
       'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a review with findings does not open exactly one correction round');
    const round1 = calls.find((c) => c.label === 'research:i1.1');
    assertTrue(!!round1 && round1.prompt.includes(readStep('i1', 'review:i1.0', 'findings')),
      "the correction round's researcher is not sent to the review's findings");
    assertTrue(!!round1 && round1.prompt.includes(readStep('i1', 'tests:i1.0', 'openQuestions')),
      "the correction round's researcher is not sent to what the test-author left open");
    const round0 = calls.find((c) => c.label === 'research:i1.0');
    assertTrue(!!round0 && !round0.prompt.includes('review:i1'),
      "the first round's researcher is sent to a review that does not exist yet");
    assertTrue(logs.some((l) => l.includes('MARKER-VERDICT-REASON')),
      "the reviewer's reason sentence never reached the human in the chat");
    const round1Review = calls.find((c) => c.label === 'review:i1.1');
    assertTrue(!!round1Review && round1Review.prompt.includes('MARKER-BREAK'),
      "the correction round's reviewer prompt does not carry the break the plan named — the block is round-0 only");
  } else if (mode === 'w11') {
    // A question the closing planner asks has to reach the human: no
    // blockedOnHuman, no log line, and the run reports itself finished.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'a question from the closing planner does not stop the run at publish');
    assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 1,
      "the closing planner's question did not end the run as blocked on the human");
    const blocked = JSON.stringify((result && result.blockedOnHuman) || []);
    assertTrue(blocked.includes('MARKER-CLOSE-QUESTION'),
      'blockedOnHuman does not carry the question the closing planner asked');
    assertTrue(blocked.includes('replan:i1'),
      'blockedOnHuman does not name replan:i1 as the step that asked');
    assertTrue(logs.some((l) => l.includes('MARKER-CLOSE-QUESTION')),
      "the closing planner's question never reached the human in the chat");
  } else if (mode === 'w12') {
    // Labels are keyed on the increment id, so the second attempt at an
    // increment the planner handed back re-used the first attempt's labels,
    // found them all in the in-session recorded map, dispatched nobody and
    // re-read the first attempt's verdict and re-cut.
    assertEqualArrays(labels,
      ['load-state', 'decompose',
       'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1',
       'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1',
       'publish'],
      'an increment the planner handed back as todo was not worked a second time');
    assertTrue(calls.filter((c) => c.label === 'research:i1.0').length === 2,
      'the researcher was not dispatched again for the second attempt');
    // The hand-back starts a fresh branch: the first attempt worked
    // issue-branch--i1, the second must not resume onto that abandoned work.
    const attemptCalls = calls.filter((c) => c.label === 'research:i1.0');
    assertTrue(attemptCalls.length === 2 && attemptCalls[0].prompt.includes('git checkout -b issue-branch--i1\`'),
      "the first attempt's researcher is not told to create the base-named branch");
    assertTrue(attemptCalls.length === 2 && attemptCalls[1].prompt.includes('git checkout -b issue-branch--i1-take2'),
      "the second attempt's researcher is not sent to a fresh take2 branch");
    assertTrue(!!result && result.stopped === '',
      'the run stopped on the attempt backstop instead of working the increment again');
    assertTrue(!!result && result.delivered === 1 && Array.isArray(result.increments) && result.increments.length === 2,
      'the second attempt did not deliver the increment');
  } else if (mode === 'w13' || mode === 'w14') {
    // Both scripts preferred the increments of the state snapshot they read at
    // startup over the ones Decompose returned, unconditionally — including
    // when Decompose was dispatched in this session rather than replayed. So a
    // planner that read the human's answer, re-cut and rewrote backlog.json had
    // its new cut thrown away.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i3.0', 'tests:i3.0', 'implement:i3.0', 'review:i3.0', 'replan:i3', 'publish'],
      'the run worked the stale cut from the state file instead of the cut the re-dispatched Decompose returned');
    assertTrue(!calls.some((c) => c.prompt.includes('MARKER-STALE-CUT')),
      'a prompt of this run carries the superseded increment the state file still held');
    const closeCall = calls.find((c) => c.label === 'replan:i3');
    assertTrue(!!closeCall && closeCall.prompt.includes('MARKER-FRESH-CUT'),
      'the closing planner was not told about the increment of the fresh cut');
    assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 0,
      'the run ended blocked on the human instead of working the fresh cut to a close');
    if (mode === 'w13') {
      const decomposeCall = calls.find((c) => c.label === 'decompose');
      assertTrue(!!decomposeCall && decomposeCall.prompt.includes('MARKER-CUT-QUESTION'),
        'the Decompose worked again does not carry the question that ended the last run');
    }
  } else if (mode === 'w15') {
    // A resumed run counted its increments from scratch, so the first
    // increment it picked up was treated as increment 1, and the human's
    // result lost the closed increment's line.
    assertEqualArrays(labels,
      ['load-state', 'research:i2.0', 'tests:i2.0', 'implement:i2.0', 'review:i2.0', 'replan:i2', 'publish'],
      'the resumed run did not pick up the open increment behind the closed one');
    const resumedResearch = calls.find((c) => c.label === 'research:i2.0');
    assertTrue(!!resumedResearch && resumedResearch.prompt.includes(READ_CODEMAP),
      "the resumed researcher's prompt does not send it to the codemap the state file holds");
    assertTrue(!!resumedResearch && resumedResearch.prompt.includes('git checkout -b issue-branch--i2'),
      'the resumed fresh increment is not told to start its own branch');
    const reviewCall = calls.find((c) => c.label === 'review:i2.0');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('git diff issue-branch...HEAD'),
      "the resumed reviewer's prompt does not name the increment's diff range");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('increment 2 is yours'),
      'the resumed run does not count the open increment as the second');
    assertTrue(!!result && result.delivered === 2,
      'the resumed run did not close both increments as delivered');
    assertTrue(!!result && Array.isArray(result.increments) && result.increments.length === 2
      && JSON.stringify(result.increments).includes('"i1"'),
      'the increment the earlier session closed has no line in result.increments');
  } else if (mode === 'w16') {
    // The direct-fix round: a review whose findings all need no plan is worked
    // by the implementer alone, off the findings it recorded, and is reviewed
    // afterwards like any other.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0',
       'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a review whose findings are all direct fixes did not skip exactly the researcher and the test-author');
    const fixCall = calls.find((c) => c.label === 'implement:i1.1');
    assertTrue(!!fixCall && fixCall.prompt.includes(readStep('i1', 'review:i1.0', 'findings')),
      "the direct-fix round's implementer is not sent to the findings it corrects");
    assertTrue(!!fixCall && fixCall.prompt.includes('CHECK-MARKER'),
      "the direct-fix round's implementer prompt does not carry the checks the round before closed");
    assertTrue(!!fixCall && !fixCall.prompt.includes('--fields testPlan'),
      "the direct-fix round's implementer is sent to a test plan");
    const reviewCall = calls.find((c) => c.label === 'review:i1.1');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('CHECK-MARKER'),
      'the review after a direct-fix round was handed no checks');
    assertTrue(!!reviewCall && !/\bsteps docs\/issues\/x\/backlog\.json/.test(reviewCall.prompt),
      'the review after a direct-fix round is sent to read the finding it wrote, and is no longer independent');
  } else if (mode === 'w17') {
    // A blocked increment's work stays off the issue branch: the replan that
    // closes it is told not to merge and to name the unmerged branch in the
    // note.
    assertEqualArrays(labels,
      ['load-state', 'decompose',
       'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0',
       'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1',
       'research:i1.2', 'tests:i1.2', 'implement:i1.2', 'review:i1.2',
       'replan:i1', 'publish'],
      'an increment that never passes review does not use up exactly its correction rounds');
    const closeCall = calls.find((c) => c.label === 'replan:i1');
    assertTrue(!!closeCall && /do not merge/i.test(closeCall.prompt) && closeCall.prompt.includes('issue-branch--i1'),
      'the blocked replan is not told to keep the increment branch unmerged');
    assertTrue(!!closeCall && !/Land it first/.test(closeCall.prompt),
      'the blocked replan carries the accepted-merge instruction');
  } else if (mode === 'w18') {
    // Everything the pull request body is made of reaches the publishing agent
    // in its prompt. Same run as w17 — one increment, blocked with a finding
    // open on an unmerged branch — because that is the run whose body needs the
    // most: what the review said, what is still open, and where the work that
    // is not in the diff lives.
    const publishCall = calls.find((c) => c.label === 'publish');
    assertTrue(!!publishCall, 'publish was never dispatched');
    assertTrue(!!publishCall && publishCall.prompt.includes('MARKER-VERDICT-REASON'),
      "the publish prompt does not carry the review's reason, so the body cannot say why the increment is open");
    assertTrue(!!publishCall && /Deliver i1[^\n]*\[blocked\]/.test(publishCall.prompt),
      'the publish prompt does not carry the increment and the status it closed with');
    assertTrue(!!publishCall && publishCall.prompt.includes('issue-branch--i1'),
      'the publish prompt does not name the blocked increment\'s branch, so its unmerged work is unfindable');
    assertTrue(!!publishCall && /NOT accepted/.test(publishCall.prompt),
      'the publish prompt does not say the increment was not accepted');
    assertTrue(!!publishCall && /Do NOT open docs\/issues\/x\/backlog\.json/.test(publishCall.prompt),
      'the publish prompt does not forbid reading the run state it was just handed');
    assertTrue(!!publishCall && /[Ff]etch the default branch before you compare/.test(publishCall.prompt),
      'the publish prompt does not tell the agent to fetch the default branch before diffing against it');
    // Criterion 5: this fixture's returns carry no `rulings` anywhere, so the
    // publish prompt, the result and the chat must add no noise about them.
    assertTrue(!!publishCall && !/ruling/i.test(publishCall.prompt),
      'the publish prompt talks about rulings though this run recorded none');
    assertTrue(!!result && Array.isArray(result.rulings) && result.rulings.length === 0,
      'the result of a run that recorded no ruling carries one');
    assertTrue(!logs.some((l) => /ruling/i.test(l)),
      'a run with no rulings still logs about rulings');
  } else if (mode === 'w19') {
    // The finding: the old answeredBlock pointed the resumed implementer at
    // `## Decisions` in `issue.md`, a read `hooks/read-barrier.mjs` refuses it.
    // The human's answer now travels in the prompt itself, lifted out of
    // `issue.md` once by the state loader — the one role the hook does not gate.
    assertEqualArrays(labels,
      ['load-state', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'the recorded researcher and test-author were not skipped, or the step that asked was not worked again');
    const buildCall = calls.find((c) => c.label === 'implement:i1.0');
    assertTrue(!!buildCall && buildCall.prompt.includes('MARKER-BUILD-QUESTION'),
      "the repeated step's prompt does not carry the question it asked");
    assertTrue(!!buildCall && buildCall.prompt.includes('MARKER-HUMAN-ANSWER'),
      "the repeated step's prompt does not carry the human's answer");
    assertTrue(!!buildCall && !/## Decisions/.test(buildCall.prompt),
      'the repeated step is pointed at the ## Decisions heading instead of handed the answer');
    assertTrue(!!result && Array.isArray(result.blockedOnHuman) && result.blockedOnHuman.length === 0,
      'the resumed run did not carry on to a clean close');
  } else if (mode === 'w20') {
    // An increment the planner cut direct: round 0 is worked by the
    // implementer and the reviewer alone, with no researcher and no
    // test-author dispatched at all — the run holds no researcher step yet,
    // so the commands the round is judged by are empty, the criterion 5
    // empty-list edge.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'an increment the planner cut direct did not skip exactly the researcher and the test-author in round 0');
    const implCall = calls.find((c) => c.label === 'implement:i1.0');
    assertTrue(!!implCall && implCall.prompt.includes('increment 1 is yours'),
      "the direct round's implementer prompt does not name the increment as its own");
    assertTrue(!!implCall && implCall.prompt.includes('does i1'),
      "the direct round's implementer prompt does not carry the increment's criteria");
    assertTrue(!!implCall && implCall.prompt.includes(READ_CODEMAP),
      "the direct round's implementer is not sent to the codemap");
    assertTrue(!!implCall && implCall.prompt.includes('git checkout -b issue-branch--i1'),
      "the direct round's implementer is not told to create the increment branch");
    assertTrue(!!implCall && /\bbranch\b.*backlog\.json i1 issue-branch--i1/.test(implCall.prompt),
      "the direct round's implementer is not told to record the branch in the run state");
    assertTrue(!!implCall && !/\bsteps docs\/issues\/x\/backlog\.json/.test(implCall.prompt),
      "the direct round's implementer is sent to read a step, though no researcher or test-author worked this increment");
    assertTrue(!!implCall && implCall.prompt.includes('No command counts for this increment'),
      "the direct round's implementer prompt does not say no command counts for this increment — the empty-checks edge of a run with no researcher step yet");
    assertTrue(!!implCall && !implCall.prompt.includes('CHECK-MARKER'),
      "the direct round's implementer prompt carries checks though the run holds no researcher step");
    const reviewCall = calls.find((c) => c.label === 'review:i1.0');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('No command counts for this increment'),
      "the direct round's reviewer prompt does not say no command counts for this increment");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('git diff issue-branch...HEAD'),
      "the direct round's reviewer prompt does not name the increment's diff range against the issue branch");
    // Criterion 2, the empty-list edge: a run with no researcher step yet has
    // no break to carry, and says so instead of an empty heading or nothing.
    assertTrue(!!reviewCall && reviewCall.prompt.includes('No plan named a break for any criterion of this increment.'),
      "the direct round's reviewer prompt does not say no plan named a break for any criterion of this increment");
    assertTrue(!!result && Array.isArray(result.increments) && !!result.increments[0] && result.increments[0].depth === 'direct',
      "the run's result does not carry increment 1's chain depth as direct");
    assertTrue(logs.some((l) => /Increment 1 round 0/.test(l) && /direct/i.test(l)),
      'no log line names the direct path for increment 1 round 0');
  } else if (mode === 'w21') {
    // A full increment and a direct increment in the same run: each takes its
    // own path, and the direct one is judged by the checks the run's last
    // researcher step closed, carried across the increment boundary.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1',
       'implement:i2.0', 'review:i2.0', 'replan:i2', 'publish'],
      'a full increment followed by a direct increment did not each take their own path');
    const implCall = calls.find((c) => c.label === 'implement:i2.0');
    assertTrue(!!implCall && implCall.prompt.includes('CHECK-MARKER'),
      "increment 2's direct implementer prompt does not carry the checks the run's last researcher step closed");
    const reviewCall = calls.find((c) => c.label === 'review:i2.0');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('CHECK-MARKER'),
      "increment 2's direct reviewer prompt does not carry the checks the run's last researcher step closed");
    // The lists reset at the increment boundary: increment 2's own plan named
    // no break, and increment 1's break must not carry over.
    assertTrue(!!reviewCall && !reviewCall.prompt.includes('MARKER-BREAK'),
      "increment 2's direct reviewer prompt carries increment 1's break, though the lists should reset at the increment boundary");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('No plan named a break for any criterion of this increment.'),
      "increment 2's direct reviewer prompt does not say no plan named a break for any criterion of this increment");
    assertTrue(!!result && Array.isArray(result.increments),
      'the run result does not carry an increments list');
    assertEqualArrays((result && result.increments || []).map((w) => w.depth), ['full', 'direct'],
      "the run's result does not carry each worked increment's own chain depth");
  } else if (mode === 'w22') {
    // A direct increment whose round 0 review files a finding leaves the
    // direct path for the rest of the attempt: the correction round runs the
    // full chain.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'implement:i1.0', 'review:i1.0',
       'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a direct increment whose review files a finding did not leave the direct path for the rest of its attempt');
  } else if (mode === 'w23') {
    // An increment the planner cut direct, handed back after a failed
    // attempt, and still classified direct in the fixture on the second pass
    // — the loop, not the planner, is what forces it full.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'implement:i1.0', 'review:i1.0', 'replan:i1',
       'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'an increment the planner cut direct and then handed back was not worked full on its second attempt');
    const firstAttempt = calls.filter((c) => c.label === 'implement:i1.0')[0];
    assertTrue(!!firstAttempt && firstAttempt.prompt.includes('git checkout -b issue-branch--i1\`'),
      "the first attempt's direct implementer is not told to create the base-named branch");
    const secondAttempt = calls.find((c) => c.label === 'research:i1.0');
    assertTrue(!!secondAttempt && secondAttempt.prompt.includes('git checkout -b issue-branch--i1-take2'),
      "the second attempt's researcher is not sent to a fresh take2 branch, so the loop did not force the increment full despite the still-direct fixture");
  } else if (mode === 'w24') {
    // A direct increment whose round-0 review files a finding that is entirely
    // a direct fix: the reviewer-driven fast path that skips the researcher and
    // the test-author for a full increment must not open for one the planner
    // already cut direct, because a review that files anything against it has
    // already shown the classification was wrong. The correction round runs
    // the full chain, and the round-1 implementer works from the plan, not
    // from the findings.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'implement:i1.0', 'review:i1.0',
       'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a direct increment whose review files only direct fixes did not run the full chain in its correction round');
    const researchCall = calls.find((c) => c.label === 'research:i1.1');
    assertTrue(!!researchCall && researchCall.prompt.includes(readStep('i1', 'review:i1.0', 'findings')),
      "round 1's researcher is not sent to the findings the round-0 review filed");
    const implCall = calls.find((c) => c.label === 'implement:i1.1');
    assertTrue(!!implCall && implCall.prompt.includes(readStep('i1', 'research:i1.1', 'plan,moduleMap,environment')),
      "round 1's implementer is not sent to the plan the researcher wrote, so the round did not take the planned brief");
  } else if (mode === 'w25') {
    // An increment the state shows as having already closed an attempt: the
    // session-local counter cannot see it, but the archived attempt count the
    // index carries can, and it is what keeps a hand-back full across a
    // restart.
    assertEqualArrays(labels,
      ['load-state', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'an increment whose earlier attempt the state archived was worked direct again after the restart');
    const researchCall = calls.find((c) => c.label === 'research:i1.0');
    assertTrue(!!researchCall && researchCall.prompt.includes('git checkout -b issue-branch--i1-take2'),
      "the restarted attempt's researcher is not sent to a fresh take2 branch, so the run did not know it was a later attempt while it classified");
    assertTrue(!!result && Array.isArray(result.increments) && !!result.increments[0] && result.increments[0].depth === 'full',
      "the run's result does not carry the restarted increment's chain depth as full");
  } else if (mode === 'w26') {
    // Criteria 2 and 4: every ruling any step of the run recorded reaches the
    // result, each traceable to its step, and reaches the publish prompt under
    // its own heading.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'the fresh one-increment run does not dispatch its plain sequence');
    assertEqualArrays((result && result.rulings || []).map((r) => r.step + ': ' + r.ruling),
      ['decompose: MARKER-RULING-CUT', 'research:i1.0: MARKER-RULING-PLAN', 'tests:i1.0: MARKER-RULING-TESTS',
       'implement:i1.0: MARKER-RULING-BUILD', 'review:i1.0: MARKER-RULING-VERDICT', 'replan:i1: MARKER-RULING-CLOSE'],
      "the run's result does not carry every step's ruling, traceable to its step, in dispatch order");
    const publishCall = calls.find((c) => c.label === 'publish');
    assertTrue(!!publishCall, 'publish was never dispatched');
    for (const pair of ['decompose: MARKER-RULING-CUT', 'research:i1.0: MARKER-RULING-PLAN', 'tests:i1.0: MARKER-RULING-TESTS',
       'implement:i1.0: MARKER-RULING-BUILD', 'review:i1.0: MARKER-RULING-VERDICT', 'replan:i1: MARKER-RULING-CLOSE']) {
      assertTrue(!!publishCall && publishCall.prompt.includes(pair),
        'the publish prompt does not carry the ruling ' + JSON.stringify(pair));
    }
    assertTrue(!!publishCall && publishCall.prompt.includes('## Rulings'),
      'the publish prompt does not ask for a heading of its own for the rulings');
    assertTrue(logs.some((l) => l.includes('MARKER-RULING-PLAN')),
      "a step's ruling never reached the chat");
  } else if (mode === 'w27') {
    // Criterion 3: a resumed run recovers the rulings of the steps it skips,
    // so the result of a resumed run is not poorer than an uninterrupted one's.
    assertEqualArrays(labels, ['load-state', 'implement:i1.0', 'review:i1.0', 'replan:i1', 'publish'],
      'the resumed run did not skip the recorded decompose, researcher and test-author steps');
    const rulingPairs = (result && result.rulings || []).map((r) => r.step + ': ' + r.ruling);
    assertTrue(rulingPairs.includes('decompose: MARKER-RULING-CUT'),
      "the resumed run's result does not carry the recorded decompose step's ruling");
    assertTrue(rulingPairs.includes('research:i1.0: MARKER-RULING-RESUMED'),
      "the resumed run's result does not carry the skipped researcher step's ruling");
    assertTrue(rulingPairs.includes('tests:i1.0: MARKER-RULING-TESTS'),
      "the resumed run's result does not carry the skipped test-author step's ruling");
    const publishCall = calls.find((c) => c.label === 'publish');
    assertTrue(!!publishCall && publishCall.prompt.includes('research:i1.0: MARKER-RULING-RESUMED'),
      "the resumed run's publish prompt is poorer than an uninterrupted run's — it does not carry the skipped researcher step's ruling");
  } else if (mode === 'w28') {
    // Criterion 3, the closed-increment half: a resumed run recovers the
    // rulings of an increment an earlier session closed, not only those of a
    // step it skips mid-increment.
    assertEqualArrays(labels,
      ['load-state', 'research:i2.0', 'tests:i2.0', 'implement:i2.0', 'review:i2.0', 'replan:i2', 'publish'],
      'the resumed run did not skip the closed increment i1 and pick up i2');
    const rulingPairs = (result && result.rulings || []).map((r) => r.step + ': ' + r.ruling);
    assertTrue(rulingPairs.includes('research:i1.0: MARKER-RULING-ARCHIVED'),
      "the resumed run's result does not carry the closed increment's archived researcher ruling");
    assertTrue(rulingPairs.includes('replan:i1: MARKER-RULING-CLOSE'),
      "the resumed run's result does not carry the closed increment's archived close ruling");
    const publishCall = calls.find((c) => c.label === 'publish');
    assertTrue(!!publishCall && publishCall.prompt.includes('research:i1.0: MARKER-RULING-ARCHIVED'),
      "the resumed run's publish prompt does not carry the closed increment's archived ruling");
  } else if (mode === 'w29') {
    // A correction round's review is scoped to the previous verdict's findings
    // and the fix's diff range — it judges the fix, not the increment again.
    assertEqualArrays(labels,
      ['load-state', 'decompose', 'research:i1.0', 'tests:i1.0', 'implement:i1.0', 'review:i1.0',
       'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a review with findings does not open exactly one correction round');
    const round1Review = calls.find((c) => c.label === 'review:i1.1');
    assertTrue(!!round1Review && round1Review.prompt.includes('MARKER-FINDING-CLAIM') && round1Review.prompt.includes('MARKER-FINDING-REPRO'),
      "the correction round's review prompt does not name the previous verdict's findings");
    assertTrue(!!round1Review && round1Review.prompt.includes('git diff MARKER-REVIEW-HEAD..HEAD'),
      "the correction round's review prompt does not name the fix's diff range");
    assertTrue(!!round1Review && !round1Review.prompt.includes('git diff issue-branch...HEAD'),
      "the correction round's review prompt names the increment's diff range instead of the fix's — it judges the increment again, not the fix");
    assertTrue(!!round1Review && /correction round/i.test(round1Review.prompt),
      "the correction round's review prompt does not say a correction round is what it is judging");
    assertTrue(!!round1Review && !/\bsteps docs\/issues\/x\/backlog\.json/.test(round1Review.prompt) && /read nothing out of/i.test(round1Review.prompt),
      'the correction round review is sent to read a step of the run state instead of carrying its brief in the prompt');
    assertTrue(!!round1Review && round1Review.prompt.includes('CHECK-MARKER'),
      "the correction round's review prompt does not carry the closed list of commands");

    const round0Review = calls.find((c) => c.label === 'review:i1.0');
    assertTrue(!!round0Review && round0Review.prompt.includes('git diff issue-branch...HEAD'),
      "the first round's review prompt does not name the increment's diff range against the issue branch");
    assertTrue(!!round0Review && !round0Review.prompt.includes('MARKER-FINDING-CLAIM') && !/correction round/i.test(round0Review.prompt),
      'the first round of an increment is dispatched as though it were a correction round');
    assertTrue(!!round0Review && round0Review.prompt.includes('- `findings`') && round0Review.prompt.includes('- `head`'),
      "the review prompt does not tell the reviewer to record findings and head, so a correction round could never be scoped to them");

    const verdictSchema = /const VERDICT = \{[\s\S]*?\n\}/.exec(src);
    assertTrue(!!verdictSchema, 'the workflow source names no const VERDICT schema block');
    if (verdictSchema) {
      const block = verdictSchema[0];
      assertTrue(/\bfindings\b/.test(block) && /\bhead\b/.test(block),
        'the VERDICT schema does not name findings and head, so the reviewer is never asked for either');
      const required = (block.match(/required:\s*\[[^\]]*\]/) || [''])[0];
      assertTrue(/\bfindings\b/.test(required) && /\bhead\b/.test(required),
        "the VERDICT schema's required: line does not list findings and head");
    }
  } else if (mode === 'w30') {
    // A correction round resumed from the state has no findings and no head in
    // hand — idxStep drops both — so it falls back to the first round's form
    // instead of rendering a git command built from values a restart dropped.
    assertEqualArrays(labels,
      ['load-state', 'research:i1.1', 'tests:i1.1', 'implement:i1.1', 'review:i1.1', 'replan:i1', 'publish'],
      'a correction round resumed from the state is not dispatched as a first round');
    const round1Review = calls.find((c) => c.label === 'review:i1.1');
    assertTrue(!!round1Review && round1Review.prompt.includes('git diff issue-branch...HEAD'),
      "the resumed correction round's review prompt does not fall back to the increment's diff range");
    assertTrue(!!round1Review && !round1Review.prompt.includes('undefined') && !round1Review.prompt.includes('git diff ..HEAD'),
      "the resumed correction round's review prompt renders a git command built from values the restart dropped");
    assertTrue(!!round1Review && !/correction round/i.test(round1Review.prompt),
      "the resumed correction round's review prompt announces a correction round while naming no finding it corrects");
  } else if (mode === 'w31') {
    // Criterion 1: the structured return demands both lists, per criterion —
    // whether the plan named a break, and the break itself where it did.
    const researchCall = byLabel('research:i1.0');
    assertTrue(!!researchCall && !!researchCall.schema && !!researchCall.schema.properties &&
      !!researchCall.schema.properties.breaks && researchCall.schema.properties.breaks.type === 'array',
      "research:i1.0's schema does not declare `breaks` as an array property");
    assertTrue(!!researchCall && !!researchCall.schema && !!researchCall.schema.properties &&
      !!researchCall.schema.properties.unbreakable && researchCall.schema.properties.unbreakable.type === 'array',
      "research:i1.0's schema does not declare `unbreakable` as an array property");
    assertTrue(!!researchCall && !!researchCall.schema && Array.isArray(researchCall.schema.required) &&
      researchCall.schema.required.includes('breaks'),
      "research:i1.0's schema does not require `breaks`");
    assertTrue(!!researchCall && !!researchCall.schema && Array.isArray(researchCall.schema.required) &&
      researchCall.schema.required.includes('unbreakable'),
      "research:i1.0's schema does not require `unbreakable`");

    // Criterion 1: the researcher is told to record both lists.
    assertTrue(!!researchCall && researchCall.prompt.includes('- `breaks`'),
      "research:i1.0's prompt does not tell the researcher to record `breaks`");
    assertTrue(!!researchCall && researchCall.prompt.includes('- `unbreakable`'),
      "research:i1.0's prompt does not tell the researcher to record `unbreakable`");

    // Criterion 2: the criterion the plan named no break for reaches the
    // reviewer's prompt, under its own heading, and the breaks heading is
    // absent since this fixture's `breaks` list is empty.
    const reviewCall = byLabel('review:i1.0');
    assertTrue(!!reviewCall && reviewCall.prompt.includes('MARKER-UNBREAKABLE'),
      "review:i1.0's prompt does not carry the criterion the plan declared unbreakable");
    assertTrue(!!reviewCall && reviewCall.prompt.includes('The criteria the plan named no break for, with the reason:'),
      "review:i1.0's prompt does not carry the unbreakable heading");
    assertTrue(!!reviewCall && !reviewCall.prompt.includes('The break the plan named for each criterion it named one for:'),
      "review:i1.0's prompt carries the breaks heading though the plan named no break for any criterion");

    // Criterion 2's resumed-run mechanism: the state loader's schema asks for
    // both lists, on the run-level steps and on an increment's own steps, so a
    // resumed run is actually given them — the fixture-driven case above
    // cannot catch a schema that stopped asking, because the stub returns its
    // fixture whatever the schema says.
    const loaderCall = byLabel('load-state');
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties &&
      !!loaderCall.schema.properties.runSteps && !!loaderCall.schema.properties.runSteps.items &&
      !!loaderCall.schema.properties.runSteps.items.properties &&
      !!loaderCall.schema.properties.runSteps.items.properties.breaks,
      "the state loader's schema does not ask runSteps for `breaks`");
    assertTrue(!!loaderCall && Array.isArray(loaderCall.schema.properties.runSteps.items.required) &&
      loaderCall.schema.properties.runSteps.items.required.includes('breaks'),
      "the state loader's schema does not require `breaks` on runSteps");
    assertTrue(!!loaderCall && !!loaderCall.schema.properties.runSteps.items.properties.unbreakable,
      "the state loader's schema does not ask runSteps for `unbreakable`");
    assertTrue(!!loaderCall && Array.isArray(loaderCall.schema.properties.runSteps.items.required) &&
      loaderCall.schema.properties.runSteps.items.required.includes('unbreakable'),
      "the state loader's schema does not require `unbreakable` on runSteps");
    assertTrue(!!loaderCall && !!loaderCall.schema.properties.increments &&
      !!loaderCall.schema.properties.increments.items && !!loaderCall.schema.properties.increments.items.properties &&
      !!loaderCall.schema.properties.increments.items.properties.steps &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items.properties &&
      !!loaderCall.schema.properties.increments.items.properties.steps.items.properties.breaks,
      "the state loader's schema does not ask an increment's steps for `breaks`");
    assertTrue(!!loaderCall && Array.isArray(loaderCall.schema.properties.increments.items.properties.steps.items.required) &&
      loaderCall.schema.properties.increments.items.properties.steps.items.required.includes('breaks'),
      "the state loader's schema does not require `breaks` on an increment's steps");
    assertTrue(!!loaderCall && !!loaderCall.schema.properties.increments.items.properties.steps.items.properties.unbreakable,
      "the state loader's schema does not ask an increment's steps for `unbreakable`");
    assertTrue(!!loaderCall && Array.isArray(loaderCall.schema.properties.increments.items.properties.steps.items.required) &&
      loaderCall.schema.properties.increments.items.properties.steps.items.required.includes('unbreakable'),
      "the state loader's schema does not require `unbreakable` on an increment's steps");
  } else if (mode === 'w32') {
    // Criterion: "The run result carries, per increment, every criterion
    // accepted without an executable check." A criterion the plan declared
    // unbreakable is exactly that.
    // Break: remove the `unchecked` field from the `worked.push` object in
    // workflows/agile-loop.js.
    assertTrue(!!result && Array.isArray(result.increments) && result.increments.length === 1,
      'w32: the run result does not carry exactly one worked increment');
    assertEqualArrays(result.increments[0] && result.increments[0].unchecked, ['does i1 — MARKER-UNBREAKABLE'],
      "w32: the run result's unchecked list does not carry the criterion the plan declared unbreakable");
  } else if (mode === 'w33') {
    // Criterion 1's edge: a criterion the plan named a break for is not
    // carried as unchecked.
    // Break: make `uncheckedCriteria` return the increment's criteria
    // whenever `unbreakable` is empty, so an increment whose every criterion
    // has a break is reported as unchecked.
    assertTrue(!!result && Array.isArray(result.increments) && result.increments.length === 1,
      'w33: the run result does not carry exactly one worked increment');
    assertEqualArrays(result.increments[0] && result.increments[0].unchecked, [],
      "w33: the run result's unchecked list carries a criterion the plan named a break for");
  } else if (mode === 'w34') {
    // Criterion: "An increment worked `direct` names no break for any of its
    // criteria, and the run result carries all of them as accepted without
    // an executable check."
    // Break: delete the both-lists-empty branch of `uncheckedCriteria` so it
    // returns the empty `unbreakable` list for a direct increment.
    assertTrue(!!result && Array.isArray(result.increments) && result.increments.length === 1,
      'w34: the run result does not carry exactly one worked increment');
    assertTrue(!!result.increments[0] && result.increments[0].depth === 'direct',
      'w34: the direct increment is not reported with depth "direct"');
    assertEqualArrays(result.increments[0] && result.increments[0].unchecked, ['does i1'],
      'w34: a direct increment does not carry all its criteria as unchecked');
  } else if (mode === 'w35') {
    // Criterion: "A run resumed from `backlog.json` reports the same
    // criteria as one that never restarted."
    // Break: in the restore loop of workflows/agile-loop.js, call
    // `uncheckedCriteria` with two empty lists instead of the archived pair,
    // so the restored increment reports all its criteria instead of the one
    // its plan declared unbreakable.
    assertTrue(!!result && Array.isArray(result.increments) && result.increments.length >= 1,
      'w35: the run result does not carry the restored increment');
    const restored = result.increments.find((w) => w.id === 'i1');
    assertTrue(!!restored, 'w35: the run result does not carry the restored increment i1');
    assertEqualArrays(restored && restored.unchecked, ['does i1 — MARKER-UNBREAKABLE'],
      'w35: a run resumed behind a closed increment does not report the same unchecked list as one that never restarted');

    // Criterion 3's schema half: the state loader has to ask an increment
    // for `attemptBreaks` or a resumed run has nothing to recover it from.
    // Break: remove `attemptBreaks` from the STATE schema's increment item.
    const loaderCall = byLabel('load-state');
    assertTrue(!!loaderCall && !!loaderCall.schema && !!loaderCall.schema.properties &&
      !!loaderCall.schema.properties.increments && !!loaderCall.schema.properties.increments.items &&
      !!loaderCall.schema.properties.increments.items.properties &&
      !!loaderCall.schema.properties.increments.items.properties.attemptBreaks,
      "w35: the state loader's schema does not ask an increment for `attemptBreaks`");
    assertTrue(!!loaderCall && Array.isArray(loaderCall.schema.properties.increments.items.required) &&
      loaderCall.schema.properties.increments.items.required.includes('attemptBreaks'),
      "w35: the state loader's schema does not require `attemptBreaks` on an increment");
  } else {
    throw new Error('unknown mode ' + mode);
  }

  if (failures.length) {
    process.stderr.write(failures.join('\n') + '\n');
    process.exit(1);
  }
}

main().catch((e) => {
  process.stderr.write(String((e && e.stack) || e) + '\n');
  process.exit(1);
});
JS

run_driver() {
  # $1 = workflow file, $2 = mode, $3 = human-readable case description
  if node "$driver_tmp/driver.js" "$1" "$2" 2>"$driver_tmp/err"; then
    ok "$3"
  else
    no "$3:"
    sed 's/^/       /' "$driver_tmp/err"
  fi
}

for wf in "$root/workflows/agile-loop.js"; do
  wf_name="$(basename "$wf")"
  run_driver "$wf" w1 "$wf_name: a fresh run dispatches load-state, decompose, the chain, the close and publish, in order"
  run_driver "$wf" w2 "$wf_name: a resumed run skips the recorded researcher and test-author and starts at the implementer"
  run_driver "$wf" w3 "$wf_name: a backlog whose increments are all closed dispatches only the state loader and publish"
  run_driver "$wf" w4 "$wf_name: the test-author's prompt carries the test plan and not the implementation plan"
  run_driver "$wf" w5 "$wf_name: the implementer's prompt carries the plan and the checks and not the test plan"
  run_driver "$wf" w6 "$wf_name: the reviewer's prompt carries the checks and the break the plan named for a criterion"
  run_driver "$wf" w7 "$wf_name: a question from the researcher ends the run at publish"
  run_driver "$wf" w8 "$wf_name: every step's prompt tells the agent to record its return, name \`rulings\` among the fields it records, and push the commit — and every dispatched schema, including the state loader's, carries \`rulings\` as well as the prompt"
  run_driver "$wf" w9 "$wf_name: a run resumed after a question for the human works that step again with the question in its prompt"
  run_driver "$wf" w10 "$wf_name: a correction round carries the reviewer's findings to the researcher and the reason to the human"
  run_driver "$wf" w11 "$wf_name: a question from the closing planner ends the run and reaches the human"
  run_driver "$wf" w13 "$wf_name: a Decompose worked again after the human's answer has its new cut worked, not the one the state file still held"
  run_driver "$wf" w14 "$wf_name: a Decompose worked again after a session died before recording it has its new cut worked"
  run_driver "$wf" w16 "$wf_name: a correction round whose findings are all direct fixes skips the researcher and the test-author, and is still reviewed"
  run_driver "$wf" w17 "$wf_name: a blocked increment's branch is closed unmerged and named to the closing planner"
  run_driver "$wf" w18 "$wf_name: the publish prompt carries the run's outcome and sends the agent to read nothing — and a run with no rulings adds no rulings line, heading or log"
  run_driver "$wf" w19 "$wf_name: a resumed run hands the step that asked the human the answer in its prompt"
  run_driver "$wf" w20 "$wf_name: an increment the planner cut direct is worked by the implementer and the reviewer alone"
  run_driver "$wf" w21 "$wf_name: a full increment and a direct increment each take their own path, the direct one judged by the run's last researcher step"
  run_driver "$wf" w22 "$wf_name: a direct increment whose review files a finding leaves the direct path for the rest of its attempt"
  run_driver "$wf" w23 "$wf_name: an increment the planner cut direct and handed back after a failed attempt is full on its next attempt"
  run_driver "$wf" w24 "$wf_name: a direct increment whose review files only direct fixes still runs the full chain in its correction round"
  run_driver "$wf" w25 "$wf_name: an increment the state shows as having already closed an attempt is full again after a restart"
  run_driver "$wf" w26 "$wf_name: the rulings every step recorded reach the run's result and the publish prompt"
  run_driver "$wf" w27 "$wf_name: a resumed run recovers the rulings of the steps it skips"
  run_driver "$wf" w28 "$wf_name: a resumed run recovers the rulings of an increment an earlier session closed"
  run_driver "$wf" w29 "$wf_name: a correction round's review is dispatched against the findings and the fix's diff"
  run_driver "$wf" w30 "$wf_name: a correction round resumed from the state is dispatched as a first round, not as a broken one"
  run_driver "$wf" w31 "$wf_name: the structured return names both lists, the state loader asks for both, and a criterion the plan named no break for reaches the reviewer under its own heading"
  run_driver "$wf" w32 "$wf_name: a criterion the plan declared unbreakable reaches the run result as unchecked"
  run_driver "$wf" w33 "$wf_name: a criterion the plan named a break for is not carried as unchecked"
  run_driver "$wf" w34 "$wf_name: an increment worked direct carries all its criteria as unchecked"
  run_driver "$wf" w35 "$wf_name: a run resumed behind a closed increment reports the same unchecked list as one that never restarted, and the state loader's schema asks for the archive that carries it"
done

# Round 3, finding 2: only the incremental loop re-cuts, so an increment
# handed back is agile-loop.js's case alone.
run_driver "$root/workflows/agile-loop.js" w12 "agile-loop.js: an increment the planner hands back is worked a second time, not skipped as recorded"
run_driver "$root/workflows/agile-loop.js" w15 "agile-loop.js: a run resumed behind a closed increment counts it and hands the reviewer its baseline"

rm -rf "$driver_tmp"

echo
echo "=== no page under tools/argus describes an argus-ui view that does not exist"

# docs/issues/2026-08-07-timeline-focus-and-context-filter removed argus-ui's
# six technical tabs, so a session's detail pane is now only the session list,
# the timeline and the context panel. tools/argus/README.md still promised the
# old shape: "tabs" plural, a "waterfall" figure, the wrapped enumeration
# "sessions, overview, tasks, traces, events, metrics, attributes", a "tools
# table", content shown "under \"Attributes\"", and a sentence that "writes
# the source under" every figure. Nothing compared the collector's own docs to
# the interface it describes, so this drifted for a whole increment before a
# reviewer caught it. Whitespace is collapsed before matching because the
# offending enumeration is line-wrapped in the source — "sessions, overview,"
# ends one line and "tasks, traces, …" begins the next — and a per-line grep
# would miss it.
declare -a argus_view_patterns=(
  '\btabs?\b'
  '\bwaterfall\b'
  'overview, *tasks'
  'tools table'
  'under "Attributes"'
  'writes the source under'
)
argus_view_hits=""
for file in "$root"/tools/argus/*.md; do
  [ -e "$file" ] || continue
  collapsed="$(tr '\n' ' ' <"$file" | tr -s ' ')"
  for pattern in "${argus_view_patterns[@]}"; do
    if echo "$collapsed" | grep -qiE "$pattern"; then
      argus_view_hits="${argus_view_hits}$(basename "$file") matches $pattern
"
    fi
  done
done
if [ -z "$argus_view_hits" ]; then
  ok "no page under tools/argus describes an argus-ui view that does not exist"
else
  no "these pages under tools/argus still describe a removed argus-ui view:"
  echo "$argus_view_hits" | sed 's/^/       /'
fi

echo
echo "=== the workflow registers"

# The plugin ships the `workflows/` directory, so a script there is live the
# moment it is written — including one that does not parse. A workflow script is only ever compiled at
# dispatch, minutes into a run, so nothing else in this repository would catch
# a syntax error before an agent chain had already been paid for. Compiling
# them here is that check: `new AsyncFunction` parses the body without running
# a line of it.
node -e '
  const fs = require("fs"), path = require("path");
  const root = process.argv[1];
  const dir = path.join(root, "workflows");
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const problems = [];
  const names = new Map();
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".js")).sort();
  for (const file of files) {
    const src = fs.readFileSync(path.join(dir, file), "utf8");
    // Top-level `return` and `await` are what the workflow runtime gives a
    // script, so the body only parses inside an async function — and `export`
    // only parses outside one. Trading the keyword away leaves the syntax the
    // check is for.
    try { new AsyncFunction(src.replace(/^export const meta =/m, "const meta =")); }
    catch (e) { problems.push(file + " does not parse: " + e.message); continue; }
    const meta = /export const meta = \{[\s\S]*?\bname:\s*.([\w-]+)./.exec(src);
    if (!meta) { problems.push(file + ": no meta.name"); continue; }
    // Parsing is not enough. The harness reads `meta` before it runs a line of
    // the script and rejects any value it would have to evaluate — a
    // concatenated string, a variable, a template, a spread. A workflow that
    // trips that rule is valid JavaScript, compiles here, and is still never
    // listed and never dispatchable, which is how agile-loop shipped unusable.
    // Strings go first and comments after them, so a brace inside either is not
    // read as structure; then the keys go, and what is left is the values.
    const from = src.indexOf("{", src.indexOf("export const meta ="));
    // The apostrophe is spelled \u0027 below, and named nowhere in this
    // comment, because the whole program is one single-quoted argument to
    // `node -e`: a bare apostrophe anywhere in it ends the argument.
    const bare = src.slice(from)
      .replace(/\u0027(?:[^\u0027\\]|\\.)*\u0027/g, "0")
      .replace(/"(?:[^"\\]|\\.)*"/g, "0")
      .replace(/\/\/.*$/gm, "");
    let depth = 0, end = -1;
    for (let i = 0; i < bare.length; i++) {
      if (bare[i] === "{") depth++;
      else if (bare[i] === "}" && --depth === 0) { end = i; break; }
    }
    const values = bare.slice(0, end + 1).replace(/[A-Za-z_$][\w$]*\s*:/g, ":");
    const bad = [];
    if (end < 0) bad.push("it is never closed");
    if (/`/.test(values)) bad.push("a template literal");
    if (/\+/.test(values)) bad.push("a concatenation");
    if (/\.\.\./.test(values)) bad.push("a spread");
    for (const id of values.match(/[A-Za-z_$][\w$]*/g) || []) {
      if (id !== "true" && id !== "false" && id !== "null") { bad.push(id); break; }
    }
    if (bad.length) problems.push(file + ": meta is not a pure literal (" + bad.join(", ") + ")");
    if (names.has(meta[1])) problems.push(meta[1] + " is declared by " + names.get(meta[1]) + " and " + file);
    names.set(meta[1], file);
  }
  if (!names.has("agile-loop")) problems.push("no workflow declares the name agile-loop");
  if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
' "$root"
if [ $? -eq 0 ]; then
  ok "every workflow script parses, keeps meta a pure literal, and agile-loop is declared"
else
  no "a workflow script does not parse, its meta is not a pure literal, or two of them claim one name"
fi

# The incremental loop is the one that hands an agent a slice of the issue, and
# the rule that makes that safe — the named increment is the whole of what the
# agent is asked for — has to reach the agent, not just the script. The shared
# brief is the only channel that does so in every project alike.
if grep -q 'increment' "$root/skills/agent-brief/SKILL.md"; then
  ok "the shared brief tells an agent what a prompt naming one increment means"
else
  no "nothing in the shared brief bounds an agent to the increment its prompt names"
fi

echo
echo "=== every agent page is declared"

# Agent discovery for a plugin scans `agents/` recursively, so `plugin.json`
# declares the pages instead — and nothing compares the two. A page missing
# from the list is an agent that is simply not there in any session, which the
# workflow calling it discovers only at dispatch.
node -e '
  const fs = require("fs"), path = require("path");
  const root = process.argv[1];
  const declared = JSON.parse(fs.readFileSync(path.join(root, ".claude-plugin/plugin.json"), "utf8")).agents || [];
  const onDisk = fs.readdirSync(path.join(root, "agents")).filter((f) => f.endsWith(".md")).sort();
  const problems = [];
  for (const page of onDisk) {
    if (!declared.includes("./agents/" + page)) problems.push("agents/" + page + " is not declared in plugin.json");
  }
  for (const entry of declared) {
    if (!fs.existsSync(path.join(root, entry))) problems.push(entry + " is declared but does not exist");
  }
  if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
' "$root"
if [ $? -eq 0 ]; then
  ok "plugin.json declares every page in agents/ and nothing that is not there"
else
  no "plugin.json and agents/ disagree about which agents exist"
fi

echo
echo "=== the reviewer proves a doubt with a probe in the sandbox"

# The reviewer found that the flat pattern table above only proved every word
# appears somewhere on the page — including the frontmatter `description`,
# which already pairs "probe" with "sandbox", "checkout", "diff" and "doubt"
# inside its own sentence. Deleting the rule from the body left the table
# green, and the whole grip on criteria 1, 5 and 6 turned out to be the word
# "commit" landing in a sentence that belongs to criterion 2. This case scopes
# each rule to the section that owns it, then to one paragraph inside that
# section, and pins it with a conjunction of terms chosen so only the
# paragraph carrying that rule can satisfy all of them — so a paragraph
# deleted from the body turns the case red instead of hiding behind a word
# the frontmatter already carries.
reviewer_probe_page="$root/agents/reviewer.md"
declare -a reviewer_probe_rules=(
  '^## .*probe:criterion 1, a probe is written and run in the sandbox and what it returns is the reproduction:probe:sandbox:reproduc|return'
  '^## .*probe:criterion 6, a probe follows a stated doubt that reaches the report:probe:doubt:report'
  '^## .*probe:criterion 2, a probe never reaches the checkout, a commit or the diff:probe:checkout:commit:diff'
  '^## .*probe:criterion 5, the closed list does not bind inside the sandbox:probe:closed:list'
  '^## .*probe:criterion 3, a probe is evidence and the pinning test stays with the test-author:probe:test-author:classif|triag'
  '^## .*reproduction:criterion 3, a reproduction is still a spec:reproduc:spec'
  '^## what you record:criterion 4, the reproduction carries what the probe ran and returned:probe:return'
)
reviewer_probe_misses=""
for rule in "${reviewer_probe_rules[@]}"; do
  IFS=':' read -ra rule_fields <<<"$rule"
  want="${rule_fields[0]}"
  label="${rule_fields[1]}"
  paragraphs="$(awk -v RS='' -v want="$want" '
    /^## / { inside = tolower($0) ~ want; next }
    inside { gsub(/\n/, " "); print }
  ' "$reviewer_probe_page")"
  matched="$paragraphs"
  for ((field_index = 2; field_index < ${#rule_fields[@]}; field_index++)); do
    term="${rule_fields[$field_index]}"
    matched="$(echo "$matched" | grep -iE -- "$term" || true)"
  done
  if [ -z "$matched" ]; then
    reviewer_probe_misses="${reviewer_probe_misses}${label}
"
  fi
done
if [ -z "$reviewer_probe_misses" ]; then
  ok "every rule the probe licence needs stands in its own paragraph of agents/reviewer.md"
else
  no "these rules of the probe licence stand in no paragraph of agents/reviewer.md:"
  echo "$reviewer_probe_misses" | sed 's/^/       /'
fi

# The rule above catches an incomplete licence, not a contradictory one: a
# page that adds the probe section but leaves the old blanket prohibition
# standing would pass every pattern above while still forbidding, in the
# same breath, the thing it just allowed.
reviewer_probe_old_ban="$(grep -inE 'not even a throwaway|never write a test' "$reviewer_probe_page" || true)"
if [ -z "$reviewer_probe_old_ban" ]; then
  ok "the old blanket prohibition on writing a test is gone from agents/reviewer.md"
else
  no "the old blanket prohibition is still on agents/reviewer.md:"
  echo "$reviewer_probe_old_ban" | sed 's/^/       /'
fi

# Criterion 7 asks the review's summary to say how many probes ran and what
# they showed, so a clean review still shows whether it looked. "probe"
# pairing with "summary" anywhere on the page is too loose a test — the two
# words could land in unrelated paragraphs — so this anchors on the
# `summary` bullet itself and its continuation lines.
reviewer_probe_summary_bullet="$(grep -A3 -- '- \*\*`summary`\*\*' "$reviewer_probe_page" || true)"
if echo "$reviewer_probe_summary_bullet" | grep -qi 'probe'; then
  ok "the summary bullet on agents/reviewer.md reports how many probes ran and what they showed"
else
  no "the summary bullet on agents/reviewer.md does not mention a probe:"
  echo "$reviewer_probe_summary_bullet" | sed 's/^/       /'
fi

# The licence belongs on the reviewer's page alone — granting it in the
# shared brief or on another agent's page would hand every agent the same
# write permission the sandbox is meant to bound. Direct mirror of the
# chain_depth_owners case above.
reviewer_probe_owners="$(grep -lie 'probe' "$root"/agents/*.md "$root"/skills/*/SKILL.md 2>/dev/null || true)"
if [ "$reviewer_probe_owners" = "$reviewer_probe_page" ]; then
  ok "agents/reviewer.md is the only agent page or shipped skill naming a probe"
else
  no "the word \"probe\" is owned by more (or fewer) pages than agents/reviewer.md alone:"
  echo "${reviewer_probe_owners:-       (none)}" | sed "s|^$root/|       |"
fi

echo
echo "=== the reviewer executes the break and reads the unbreakable"

reviewer_break_page="$root/agents/reviewer.md"

# Criterion "The reviewer does not file the absence of a test for a criterion
# the researcher declared unbreakable." — check 3 of '## What you check' has
# to carry both the mutation-standard hold and a branch for a criterion the
# prompt names as one the plan named no break for, in the same paragraph.
# Extracted directly rather than through the paragraph-scoped loop below,
# because the numbered checks 1-4 share one blank-line paragraph on this page
# and only the text of check 3 itself decides this criterion.
# Break: delete the branch clause from check 3, leaving "A criterion no test
# would catch is a finding" unqualified.
reviewer_break_check3="$(awk '
  /^3\. \*\*The tests against the intent\.\*\*/ { flag = 1 }
  /^4\. \*\*Beyond the criteria\.\*\*/ { flag = 0 }
  flag { print }
' "$reviewer_break_page" | tr '\n' ' ' | tr -s ' ')"
if echo "$reviewer_break_check3" | grep -qi 'mutation standard' && echo "$reviewer_break_check3" | grep -qi 'no break'; then
  ok "check 3 of agents/reviewer.md's 'What you check' holds the mutation standard and the branch for a criterion the plan named no break for"
else
  no "check 3 of agents/reviewer.md's 'What you check' does not carry both the mutation standard and the no-break branch:"
  echo "$reviewer_break_check3" | sed 's/^/       /'
fi

# Same shape as the probe table above, for the same reason: a flat page-wide
# grep would pass on a word the frontmatter already carries, so each rule
# below is pinned to one paragraph of the new break section that owns it. The
# section-selector pattern requires the "## " heading itself to name "break",
# which also keeps this loop off '## The probe' — that section already pairs
# "probe", "checkout", "commit" and "diff" in one paragraph, and an unscoped
# grep would go green on it for criterion 6 below.
declare -a reviewer_break_rules=(
  '^## .*break:criterion, the prompt hands the reviewer a break or a reason per criterion, and that block plus the closed command list are the only two things about the plan it is given:hands you|prompt hands:only two things'
  '^## .*break:criterion, unbreakable criteria are judged by reading the diff against them:no break:read:diff'
  '^## .*break:criterion, an applied break runs in the sandbox worktree with the commands the prompt already names and verification rests on that run failing:break:sandbox|worktree:command:verif'
  '^## .*break:criterion, a break that leaves every listed command green is a finding against the criterion it was named for:break:turned red|stayed green:finding'
  '^## .*break:criterion, a failure produced by applying a break is never a finding against the change:break:never a finding|not a finding:check 1|unmodified checkout'
  '^## .*break:criterion, an applied break never reaches the checkout and never reaches the diff:break:checkout:diff'
  '^## .*break:criterion, a round handed no break at all applies none and the four checks stand as they otherwise would:no break:apply:four checks|as they stand'
)
reviewer_break_misses=""
for rule in "${reviewer_break_rules[@]}"; do
  IFS=':' read -ra rule_fields <<<"$rule"
  want="${rule_fields[0]}"
  label="${rule_fields[1]}"
  paragraphs="$(awk -v RS='' -v want="$want" '
    /^## / { inside = tolower($0) ~ want; next }
    inside { gsub(/\n/, " "); print }
  ' "$reviewer_break_page")"
  matched="$paragraphs"
  for ((field_index = 2; field_index < ${#rule_fields[@]}; field_index++)); do
    term="${rule_fields[$field_index]}"
    matched="$(echo "$matched" | grep -iE -- "$term" || true)"
  done
  if [ -z "$matched" ]; then
    matched_count=0
  else
    matched_count="$(echo "$matched" | grep -c .)"
  fi
  # A rule counts only when its terms land in exactly one paragraph of the
  # section: two paragraphs matching one entry's terms is the defect this
  # section exists to catch, and treating that as a pass is the break.
  if [ "$matched_count" -ne 1 ]; then
    reviewer_break_misses="${reviewer_break_misses}${label} (matched ${matched_count} paragraphs)
"
  fi
done
if [ -z "$reviewer_break_misses" ]; then
  ok "every rule the break section needs stands in its own paragraph of agents/reviewer.md"
else
  no "these rules of the break section stand in no paragraph of agents/reviewer.md:"
  echo "$reviewer_break_misses" | sed 's/^/       /'
fi

# Criterion "The reviewer judges each unbreakable criterion by reading the
# diff against it, and says in its `summary` what it judged and on what." —
# the summary half. Extracted the way the probe-summary case above extracts
# the bullet. Break: delete the added clause from the `summary` bullet.
reviewer_break_summary_bullet="$(grep -A4 -- '- \*\*`summary`\*\*' "$reviewer_break_page" || true)"
if echo "$reviewer_break_summary_bullet" | grep -qi 'diff' && echo "$reviewer_break_summary_bullet" | grep -qi 'break'; then
  ok "the summary bullet on agents/reviewer.md reports which unbreakable criteria were judged by reading the diff, and which breaks were run"
else
  no "the summary bullet on agents/reviewer.md does not report the unbreakable criteria read against the diff and the breaks run:"
  echo "$reviewer_break_summary_bullet" | sed 's/^/       /'
fi

echo
echo "=== no page or doc still claims the reviewer is given nothing another agent produced"

# Criterion: "No page or doc still claims the reviewer is given nothing
# another agent produced." The reviewer now runs the plan's named breaks and
# reads the diff against an unbreakable criterion, so a bare "given nothing
# any agent/role produced" is stale wherever it stands without naming the
# break that qualifies it. docs/ is deliberately excluded from the file list
# below: the issue files there are the record of earlier runs, not doctrine.
# Break: restore agents/reviewer.md's opening sentence to
# "You are the pair of eyes that has been given nothing the other agents
# produced — only the diff and the issue file." — that sentence names no
# break, so this case goes red.
declare -a nothing_produced_files=(
  "$root"/agents/*.md
  "$root"/skills/*/SKILL.md
  "$root/skills/CLAUDE.md"
  "$root/README.md"
  "$root/rulebook.md"
  "$root"/workflows/*.js
)
nothing_produced_misses=""
for f in "${nothing_produced_files[@]}"; do
  [ -f "$f" ] || continue
  joined="$(tr '\n' ' ' <"$f" | tr -s ' ')"
  matches="$(echo "$joined" | grep -oiE '[^.]*nothing[^.]{0,60}(agent|role)s?[^.]{0,20}produced[^.]*\.' || true)"
  [ -z "$matches" ] && continue
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if ! echo "$m" | grep -qi 'break'; then
      nothing_produced_misses="${nothing_produced_misses}${f}: ${m}
"
    fi
  done <<<"$matches"
done
if [ -z "$nothing_produced_misses" ]; then
  ok "no page or doc claims the reviewer is given nothing another agent produced without naming the break that qualifies it"
else
  no "these passages still claim the reviewer is given nothing produced, without naming a break:"
  echo "$nothing_produced_misses" | sed 's/^/       /'
fi

echo
echo "=== the reviewer's opening paragraph is the one passage naming its own breaks"

# Criterion: "Each rule this increment adds to a page gets a case in
# test-repo.sh that turns red when that rule is removed, and each such case
# matches only the passage carrying its rule." The rewritten opening
# paragraph of agents/reviewer.md is one of the two rules this increment adds
# to a page (the rulebook's new numbered step below is the other), so it is
# pinned to exactly one paragraph below the frontmatter, the same way the
# break-section rules above are each pinned to one paragraph.
# Break: delete the clause naming the plan's breaks from that opening
# paragraph, leaving the old "pair of eyes ... nothing the other agents
# produced" sentence unqualified again.
reviewer_opening_count="$(awk -v RS='' '
  NR > 1 { gsub(/\n/, " "); if (tolower($0) ~ /pair of eyes/ && tolower($0) ~ /break/) c++ }
  END { print c + 0 }
' "$reviewer_break_page")"
if [ "$reviewer_opening_count" -eq 1 ]; then
  ok "exactly one paragraph of agents/reviewer.md below the frontmatter names both the pair of eyes and the breaks it runs"
else
  no "agents/reviewer.md's opening paragraph naming the pair of eyes and its breaks matched $reviewer_opening_count paragraph(s), not exactly 1"
fi

echo
echo "=== the human is told one line naming every criterion accepted without an executable check"

# Criterion: "\`rulebook.md\` requires the session to give the human one line
# naming those criteria, for every increment that has any." Extract each
# numbered step of the \"### Issue Mode\" list and require exactly one of
# them to carry \`unchecked\`, \"executable check\" and \"one line\" together
# — the way the reviewer-break table above counts paragraphs: zero is the
# missing-instruction defect, two is the duplicate-instruction one.
# Break 1: delete that numbered step from rulebook.md — the count goes to 0.
# Break 2: duplicate it as a second numbered item elsewhere in the Issue Mode
# list — the count goes to 2. This is the case that carries the coverage
# criterion's "matches only the passage carrying its rule" half for the
# rulebook's new step.
issue_mode_section="$(awk '
  /^### Issue Mode/ { insection = 1; next }
  /^### / { if (insection) exit }
  insection { print }
' "$root/rulebook.md")"
issue_mode_matches=0
current_step=""
count_step() {
  if [ -n "$current_step" ]; then
    lower="$(echo "$current_step" | tr '[:upper:]' '[:lower:]')"
    if echo "$lower" | grep -q 'unchecked' && echo "$lower" | grep -q 'executable check' && echo "$lower" | grep -q 'one line'; then
      issue_mode_matches=$((issue_mode_matches + 1))
    fi
  fi
}
while IFS= read -r line; do
  if echo "$line" | grep -qE '^[0-9]+\. \*\*'; then
    count_step
    current_step="$line"
  else
    current_step="${current_step}
${line}"
  fi
done <<<"$issue_mode_section"
count_step
if [ "$issue_mode_matches" -eq 1 ]; then
  ok "exactly one numbered step of rulebook.md's Issue Mode list gives the human one line naming every criterion accepted without an executable check"
else
  no "rulebook.md's Issue Mode list carries that instruction in $issue_mode_matches step(s), not exactly 1:"
  echo "$issue_mode_section" | sed 's/^/       /'
fi

echo
echo "=== a correction round judges the fix"

# Same shape as the probe table above, for the same reason: a flat page-wide
# grep would pass on a word the frontmatter already carries, so each rule is
# pinned to one paragraph of the correction-round section that owns it.
reviewer_correction_page="$root/agents/reviewer.md"
declare -a reviewer_correction_rules=(
  'correction round:criterion 2, addressed means the defect is gone, not that a fix was attempted:address:no longer exist:attempt'
  'correction round:criterion 3, new breakage inside the fix diff is a finding:fix:diff:finding:broke|breakage|introduc'
  'correction round:criterion 4, a remark outside the named findings and the fix diff is an observation that neither blocks nor extends the loop:observation:summary:outside:round'
  'correction round:criterion 5, findingCount counts only not-addressed findings and new fix-diff findings:findingcount:not addressed|not-addressed'
  'correction round:criterion 1, the prompt tells the reviewer where the findings and the fix diff are:prompt:finding:diff'
)
reviewer_correction_misses=""
for rule in "${reviewer_correction_rules[@]}"; do
  IFS=':' read -ra rule_fields <<<"$rule"
  want="${rule_fields[0]}"
  label="${rule_fields[1]}"
  paragraphs="$(awk -v RS='' -v want="$want" '
    /^## / { inside = tolower($0) ~ want; next }
    inside { gsub(/\n/, " "); print }
  ' "$reviewer_correction_page")"
  matched="$paragraphs"
  for ((field_index = 2; field_index < ${#rule_fields[@]}; field_index++)); do
    term="${rule_fields[$field_index]}"
    matched="$(echo "$matched" | grep -iE -- "$term" || true)"
  done
  if [ -z "$matched" ]; then
    reviewer_correction_misses="${reviewer_correction_misses}${label}
"
  fi
done
if [ -z "$reviewer_correction_misses" ]; then
  ok "every rule a correction round needs stands in its own paragraph of agents/reviewer.md"
else
  no "these rules of the correction-round scope stand in no paragraph of agents/reviewer.md:"
  echo "$reviewer_correction_misses" | sed 's/^/       /'
fi

# The rules above catch an incomplete section, not a contradictory one: a page
# that adds the correction-round section while leaving the old blanket
# statement standing contradicts itself in the same breath, and the reader
# follows whichever sentence it saw last.
reviewer_correction_old_fresh="$(grep -inE 'every round starts fresh|knows nothing of the earlier ones' "$reviewer_correction_page" || true)"
if [ -z "$reviewer_correction_old_fresh" ]; then
  ok "agents/reviewer.md no longer claims every round starts fresh with no memory of the earlier ones"
else
  no "agents/reviewer.md still claims every round starts fresh:"
  echo "$reviewer_correction_old_fresh" | sed 's/^/       /'
fi

# Collapsed first, the way the mutation-standard case above collapses
# agents/reviewer.md before it greps: this exact sentence wraps across a line
# break in the page's prose, and a plain grep would miss it there.
reviewer_correction_collapsed="$(tr '\n' ' ' <"$reviewer_correction_page" | tr -s ' ')"
if echo "$reviewer_correction_collapsed" | grep -qiE 'the findings themselves it never sees'; then
  reviewer_correction_old_blind="the findings themselves it never sees"
else
  reviewer_correction_old_blind=""
fi
if [ -z "$reviewer_correction_old_blind" ]; then
  ok "agents/reviewer.md no longer claims it never sees the findings themselves"
else
  no "agents/reviewer.md still claims it never sees the findings themselves, though the prompt now carries them:"
  echo "$reviewer_correction_old_blind" | sed 's/^/       /'
fi

echo
echo "=== every test suite carries its doc"

# The suite doc is what spares the test-author reading a suite whole to find
# its conventions (docs/issues/2026-08-08-suite-docs-own-the-test-conventions).
# The test-author keeps it current; this pins only that a directory holding
# tests carries one at all, so a new suite cannot ship undocumented and a
# bootstrapped doc cannot be deleted silently.
undocumented=""
while IFS= read -r dir; do
  [ -f "$dir/CLAUDE.md" ] || undocumented="$undocumented ${dir#"$root"/}"
done < <(find "$root" -name '*.test.mjs' -not -path '*/node_modules/*' -not -path "$root/.git/*" -exec dirname {} \; | sort -u)
if [ -z "$undocumented" ]; then
  ok "every directory holding a *.test.mjs carries a CLAUDE.md suite doc"
else
  no "these test directories carry no CLAUDE.md:$undocumented"
fi

# The two pages that divide the responsibility have to keep naming it: the
# test-author owns the doc, and the researcher's test plan points at it
# instead of restating conventions.
if grep -q 'CLAUDE.md' "$root/agents/test-author.md"; then
  ok "the test-author's page names the suite doc it keeps"
else
  no "the test-author's page does not mention the suite doc"
fi
if grep -qi 'suite doc' "$root/agents/researcher.md"; then
  ok "the researcher's page sends conventions to the suite doc"
else
  no "the researcher's page does not name the suite doc"
fi

echo
echo "=== remote operation deploys the collector alone"

# Dockerfile, compose.yaml and render.yaml build and run argus. The interface
# is local only: it is never packaged into the image, never named by the
# blueprint, and the collector no longer carries the files it serves.
node -e '
  const fs = require("fs"), path = require("path");
  const root = process.argv[1];
  const problems = [];
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "tools/argus/package.json"), "utf8"));
  if ((pkg.files || []).includes("public")) problems.push("tools/argus/package.json still ships public/");
  if (fs.existsSync(path.join(root, "tools/argus/public"))) problems.push("tools/argus/public still exists");
  for (const file of ["tools/argus/Dockerfile", "tools/argus/compose.yaml", "render.yaml"]) {
    const text = fs.readFileSync(path.join(root, file), "utf8");
    if (/argus-ui/.test(text)) problems.push(file + " deploys the interface");
    if (/public\//.test(text)) problems.push(file + " still references public/");
  }
  if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
' "$root"
if [ $? -eq 0 ]; then
  ok "the image, the compose file and the blueprint carry the collector and no interface"
else
  no "the deployment still carries the interface"
fi

echo
echo "=== a rule's form is picked by the failure it prevents"

# The four-row table and the exemption-clause ban both live in
# .claude/rules/authoring.md. table.js reads the table once per case below: it
# splits the page into pipe-delimited rows, drops the header separator (a row
# that is only pipes, dashes, colons and spaces), and treats row 1 as the
# header and the rest as body rows. Its "row" mode additionally selects the
# one body row whose failure-class cell matches a regex and asserts every
# marker is in the "works" cell and none is in the "fails" cell — case-
# insensitively throughout — which is what catches a row whose two forms have
# been swapped.
form_tmp="$(mktemp -d)"
cat >"$form_tmp/table.js" <<'JS'
const fs = require("fs");
const root = process.argv[2];
const mode = process.argv[3];

function fail(msg) { console.error(msg); process.exit(1); }

const text = fs.readFileSync(root + "/.claude/rules/authoring.md", "utf8");
const lines = text.split("\n").filter((l) => l.trim().startsWith("|"));
const rows = lines.map((l) => {
  const cells = l.trim().split("|");
  cells.shift();
  cells.pop();
  return cells.map((c) => c.trim());
});
if (rows.length < 2) fail("no table found in .claude/rules/authoring.md");
const header = rows[0];
const body = rows.slice(1).filter((r) => !r.every((c) => /^[-:\s]*$/.test(c)));

if (mode === "shape") {
  if (body.length !== 4) fail("expected exactly 4 body rows, found " + body.length);
  body.forEach((r, i) => {
    if (r.length !== 4) fail("row " + i + " has " + r.length + " cells, expected 4");
    r.forEach((c, j) => { if (!c) fail("row " + i + " cell " + j + " is empty"); });
  });
  process.exit(0);
}

if (mode === "header") {
  if (!/failure/i.test(header[0] || "")) fail("header cell 1 does not name the failure class: " + JSON.stringify(header[0]));
  if (!/works/i.test(header[1] || "")) fail("header cell 2 does not name the form that works: " + JSON.stringify(header[1]));
  if (!/fails/i.test(header[2] || "")) fail("header cell 3 does not name the form that fails: " + JSON.stringify(header[2]));
  if (!/reason|why/i.test(header[3] || "")) fail("header cell 4 does not name the reason: " + JSON.stringify(header[3]));
  process.exit(0);
}

if (mode === "reason") {
  const oneSentence = /^[^.]+\.$/;
  body.forEach((r, i) => {
    if (!oneSentence.test(r[3] || "")) fail("row " + i + " reason cell is not exactly one sentence: " + JSON.stringify(r[3]));
  });
  process.exit(0);
}

if (mode === "row") {
  const failureRx = new RegExp(process.argv[4], "i");
  const markers = JSON.parse(process.argv[5]);
  const matches = body.filter((r) => failureRx.test(r[0] || ""));
  if (matches.length !== 1) fail("expected exactly one row matching " + process.argv[4] + ", found " + matches.length);
  const row = matches[0];
  const works = row[1] || "";
  const fails = row[2] || "";
  const problems = [];
  for (const m of markers) {
    const rx = new RegExp(m, "i");
    if (!rx.test(works)) problems.push("marker " + m + " missing from the works cell: " + JSON.stringify(works));
    if (rx.test(fails)) problems.push("marker " + m + " found in the fails cell: " + JSON.stringify(fails));
  }
  if (problems.length) fail(problems.join("; "));
  process.exit(0);
}

if (mode === "ban") {
  const paragraphs = text.split(/\n\s*\n/).map((p) =>
    p.split("\n").filter((l) => !l.trim().startsWith("|")).join(" ").replace(/\s+/g, " ").trim()
  );
  const mentioning = paragraphs.filter((p) => /exemption clause/i.test(p));
  if (mentioning.length === 0) fail('no paragraph mentions "exemption clause"');
  const guarded = mentioning.some((p) => /never/i.test(p) && /re-cut/i.test(p) && /observable predicate/i.test(p));
  if (!guarded) fail('no paragraph mentioning "exemption clause" also carries never, re-cut and observable predicate');
  process.exit(0);
}

fail("unknown mode " + mode);
JS

# Criterion 1: a table of exactly four rows, four named parts each.
# Break: add a fifth row, delete one, or blank any cell — in particular the
# "form that fails" cell of any row.
if node "$form_tmp/table.js" "$root" shape >/dev/null 2>&1; then
  ok "the form table has exactly four body rows, each with four non-empty cells"
else
  no "the form table's shape is wrong: $(node "$form_tmp/table.js" "$root" shape 2>&1)"
fi

# Criterion 1: column order. Break: swap the "Form that works" and "Form that
# fails" headers — which inverts all four rows at once while every cell keeps
# its text, and is why this case is separate from the shape case above.
if node "$form_tmp/table.js" "$root" header >/dev/null 2>&1; then
  ok "the form table's header names failure, works, fails and the reason, in order"
else
  no "the form table's header is wrong: $(node "$form_tmp/table.js" "$root" header 2>&1)"
fi

# Criterion 1: one-sentence reason. Break: split any reason cell into two
# sentences, or empty it.
if node "$form_tmp/table.js" "$root" reason >/dev/null 2>&1; then
  ok "every form-table row states its reason in exactly one sentence"
else
  no "a form-table reason cell is not one sentence: $(node "$form_tmp/table.js" "$root" reason 2>&1)"
fi

# Criterion 2 and criterion 5, row 1 — a rule skipped under pressure.
# Breaks, each independently red: swap cells 2 and 3 of the row (the failing
# form names no prohibition); replace "A prohibition" in cell 2 with
# "A reminder"; delete "carries its price and " from cell 2 (criterion 6, the
# price); delete ", verbatim," from cell 2, or replace "quotes, verbatim, the
# rationalisation it counters" with "names the rationalisation it counters"
# (criterion 6, the verbatim rationalisation); move any marker's wording into
# cell 3.
if node "$form_tmp/table.js" "$root" row 'skipped under pressure' '["prohibition","\\bprice\\b","verbatim","rationalisation"]' >/dev/null 2>&1; then
  ok "row 1 (skipped under pressure) pairs the prohibition, its price and the verbatim rationalisation with the winning form"
else
  no "row 1 (skipped under pressure) is wrong: $(node "$form_tmp/table.js" "$root" row 'skipped under pressure' '["prohibition","\\bprice\\b","verbatim","rationalisation"]' 2>&1)"
fi

# Criterion 2 and criterion 5, row 2 — a wrong output shape.
# Breaks: swap cells 2 and 3, so the wrong output shape is paired with a list
# of prohibitions — the form measured to lose against it (criterion 5);
# replace cell 2 with "A list of prohibitions"; drop "what the output is"
# from cell 2.
if node "$form_tmp/table.js" "$root" row 'output shape' '["recipe","output"]' >/dev/null 2>&1; then
  ok "row 2 (wrong output shape) pairs the recipe with the winning form"
else
  no "row 2 (wrong output shape) is wrong: $(node "$form_tmp/table.js" "$root" row 'output shape' '["recipe","output"]' 2>&1)"
fi

# Criterion 2 and criterion 5, row 3 — an omitted required element.
# Breaks: swap cells 2 and 3, so the omission is paired with prose in the body
# (criterion 5); replace cell 2 with "Prose in the body asking for the
# element"; drop "in the schema or the template" from cell 2.
if node "$form_tmp/table.js" "$root" row 'omitted required element' '["\\bslot\\b","schema|template"]' >/dev/null 2>&1; then
  ok "row 3 (omitted required element) pairs the required slot with the winning form"
else
  no "row 3 (omitted required element) is wrong: $(node "$form_tmp/table.js" "$root" row 'omitted required element' '["\\bslot\\b","schema|template"]' 2>&1)"
fi

# Criterion 2 and criterion 5, row 4 — behaviour that depends on a condition.
# Breaks: swap cells 2 and 3, so the conditional behaviour is paired with a
# judgement call or a bolted-on exemption (criterion 5); replace "keyed to an
# observable predicate" in cell 2 with "left to the agent's judgement".
if node "$form_tmp/table.js" "$root" row 'depends on a condition' '["observable predicate"]' >/dev/null 2>&1; then
  ok "row 4 (depends on a condition) pairs the observable predicate with the winning form"
else
  no "row 4 (depends on a condition) is wrong: $(node "$form_tmp/table.js" "$root" row 'depends on a condition' '["observable predicate"]' 2>&1)"
fi

# Criterion 3 and criterion 6 — the exemption-clause ban. Stripping the table
# lines before collapsing paragraphs is load-bearing: without it, row 4's
# cells satisfy the assertion and the ban paragraph can be gutted while the
# case stays green — that is exactly the hole INC-1's second review round
# found. Breaks: delete the ban paragraph; replace "Never patch a working
# rule" with "Consider avoiding patching a working rule"; delete "Re-cut the
# rule" from it; replace "Re-cut the rule on an observable predicate instead"
# with "Re-cut the rule on your best judgement instead" (criterion 6, the
# observable predicate).
if node "$form_tmp/table.js" "$root" ban >/dev/null 2>&1; then
  ok "the authoring rules ban patching a working rule with an exemption clause and require re-cutting on an observable predicate"
else
  no "the exemption-clause ban is missing or gutted: $(node "$form_tmp/table.js" "$root" ban 2>&1)"
fi

rm -rf "$form_tmp"

# Criterion 4: the home exists and is scoped to both audiences. Break: delete
# the file, or drop either pattern from paths:. (The pre-existing scoping
# cases above add, for free, that the page is path-scoped at all and that both
# patterns match tracked files.)
if [ -f "$root/.claude/rules/authoring.md" ] &&
  sed -n '2,/^---$/p' "$root/.claude/rules/authoring.md" | grep -q 'skills/\*\*' &&
  sed -n '2,/^---$/p' "$root/.claude/rules/authoring.md" | grep -q 'agents/\*\*'; then
  ok ".claude/rules/authoring.md exists and is scoped to skills/** and agents/** alike"
else
  no ".claude/rules/authoring.md is missing, or its paths: frontmatter does not cover skills/** and agents/**"
fi

# Criterion 4: the skill-page author is pointed at it. Break: delete the
# pointer sentence.
if grep -q '\.claude/rules/authoring\.md' "$root/skills/CLAUDE.md"; then
  ok "skills/CLAUDE.md points whoever authors a skill page at .claude/rules/authoring.md"
else
  no "skills/CLAUDE.md does not point at .claude/rules/authoring.md"
fi

# Criterion 4: the agent-page author is pointed at it. Break: delete the
# pointer sentence.
if grep -q '\.claude/rules/authoring\.md' "$root/.claude/rules/agents.md"; then
  ok ".claude/rules/agents.md points whoever authors an agent page at .claude/rules/authoring.md"
else
  no ".claude/rules/agents.md does not point at .claude/rules/authoring.md"
fi

# Criterion 4: one home for the ban. Mirrors mutation_standard_owners above.
# Break, either direction: restate the ban on a second page (two paths
# match), or delete it from the owner (none match).
exemption_ban_owners="$(grep -lie 'exemption clause' "$root"/agents/*.md "$root"/skills/*/SKILL.md "$root/skills/CLAUDE.md" "$root"/.claude/rules/*.md "$root/rulebook.md" "$root/README.md" "$root/GEMINI.md" 2>/dev/null || true)"
if [ "$exemption_ban_owners" = "$root/.claude/rules/authoring.md" ]; then
  ok ".claude/rules/authoring.md is the only page naming an exemption clause"
else
  no "the phrase \"exemption clause\" is owned by more (or fewer) pages than .claude/rules/authoring.md alone:"
  echo "${exemption_ban_owners:-       (none)}" | sed "s|^$root/|       |"
fi

# Criterion 4: one home for the table. Same ownership check keyed on
# "rationalisation", the table's most distinctive word. Break, either
# direction: restate a table row on another page, or delete row 1 from the
# owner.
form_table_owners="$(grep -lie 'rationalisation' "$root"/agents/*.md "$root"/skills/*/SKILL.md "$root/skills/CLAUDE.md" "$root"/.claude/rules/*.md "$root/rulebook.md" "$root/README.md" "$root/GEMINI.md" 2>/dev/null || true)"
if [ "$form_table_owners" = "$root/.claude/rules/authoring.md" ]; then
  ok ".claude/rules/authoring.md is the only page naming a rationalisation"
else
  no "the phrase \"rationalisation\" is owned by more (or fewer) pages than .claude/rules/authoring.md alone:"
  echo "${form_table_owners:-       (none)}" | sed "s|^$root/|       |"
fi

echo
echo "=== a description names the occasion, not the steps"

# desc.js reads .claude/rules/authoring.md the same way table.js above reads
# it — table lines stripped, paragraphs collapsed to one line each, filtered
# to the ones mentioning "description" — and reads a skill's frontmatter
# description the way the plan spells out: line 1 "---" to the next "---",
# the single "description:" line inside it, key and surrounding quotes
# stripped, whitespace collapsed. A description folded over several YAML
# lines, or missing, or empty, fails loudly rather than passing silently.
desc_tmp="$(mktemp -d)"
cat >"$desc_tmp/desc.js" <<'JS'
const fs = require("fs");
const root = process.argv[2];
const mode = process.argv[3];

function fail(msg) { console.error(msg); process.exit(1); }

function paragraphsOf(file) {
  const text = fs.readFileSync(file, "utf8");
  return text
    .split(/\n\s*\n/)
    .map((p) => p.split("\n").filter((l) => !l.trim().startsWith("|")).join(" ").replace(/\s+/g, " ").trim())
    .filter((p) => p.length > 0);
}

function descriptionParagraphs() {
  const paras = paragraphsOf(root + "/.claude/rules/authoring.md").filter((p) => /description/i.test(p));
  if (paras.length === 0) fail('no paragraph in .claude/rules/authoring.md mentions "description"');
  return paras;
}

function readSkillDescription(file) {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split("\n");
  if ((lines[0] || "").trim() !== "---") fail(file + ": frontmatter does not start with ---");
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") { end = i; break; }
  }
  if (end === -1) fail(file + ": frontmatter has no closing ---");
  const fm = lines.slice(1, end);
  const descLine = fm.find((l) => /^description:/i.test(l.trim()));
  if (!descLine) fail(file + ": no description: line in frontmatter (folded onto several lines?)");
  let value = descLine.trim().replace(/^description:\s*/i, "");
  value = value.replace(/^["']|["']$/g, "");
  value = value.replace(/\s+/g, " ").trim();
  if (!value) fail(file + ": description value is empty");
  return value;
}

if (mode === "occasion") {
  const paras = descriptionParagraphs();
  if (!paras.some((p) => /occasion/i.test(p))) fail('no description paragraph mentions "occasion": ' + JSON.stringify(paras));
  process.exit(0);
}

if (mode === "steps-ban") {
  const paras = descriptionParagraphs();
  if (!paras.some((p) => /\bnever\b[^.]*\bsteps\b/i.test(p))) fail('no description paragraph bans steps with "never ... steps": ' + JSON.stringify(paras));
  process.exit(0);
}

if (mode === "reason") {
  const paras = descriptionParagraphs();
  if (!paras.some((p) => /shortcut/i.test(p) && /body/i.test(p))) fail('no description paragraph carries both "shortcut" and "body": ' + JSON.stringify(paras));
  process.exit(0);
}

if (mode === "skill-occasion") {
  const file = process.argv[4];
  const desc = readSkillDescription(file);
  if (!/reach for it|\bwhenever\b|\bwhen\b/i.test(desc)) fail("description names no occasion: " + JSON.stringify(desc));
  process.exit(0);
}

if (mode === "skill-nosteps") {
  const file = process.argv[4];
  const desc = readSkillDescription(file);
  const markers = [
    ["\\bhow it [a-z]+s\\b", "how it ...s"],
    ["\\bfirst\\b[^.]*\\bthen\\b", "first ... then"],
    ["\\bstep [0-9]", "step N"],
  ];
  for (const [rx, label] of markers) {
    if (new RegExp(rx, "i").test(desc)) fail("description walks the steps (matched " + label + "): " + JSON.stringify(desc));
  }
  process.exit(0);
}

if (mode === "carry-bullet") {
  const file = process.argv[4];
  const requiredRx = new RegExp(process.argv[5], "i");
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split("\n");
  const headingIdx = lines.findIndex((l) => /^## What a page has to carry/.test(l));
  if (headingIdx === -1) fail(file + ": no \"## What a page has to carry\" heading");
  let sectionEnd = lines.length;
  for (let i = headingIdx + 1; i < lines.length; i++) {
    if (/^## /.test(lines[i])) { sectionEnd = i; break; }
  }
  const section = lines.slice(headingIdx + 1, sectionEnd);
  const bulletStart = section.findIndex((l) => /^- \*\*Frontmatter\*\*/.test(l));
  if (bulletStart === -1) fail(file + ": no \"- **Frontmatter**\" bullet in its carry section");
  let bulletEnd = section.length;
  for (let i = bulletStart + 1; i < section.length; i++) {
    if (/^- \*\*/.test(section[i])) { bulletEnd = i; break; }
  }
  const block = section.slice(bulletStart, bulletEnd).join(" ").replace(/\s+/g, " ").trim();
  if (!requiredRx.test(block)) fail(file + ": Frontmatter bullet does not match required regex " + process.argv[5] + ": " + JSON.stringify(block));
  const forbidden = [/\btriggers?\b/i, /when to dispatch/i, /\boccasion\b/i];
  for (const rx of forbidden) {
    if (rx.test(block)) fail(file + ": Frontmatter bullet restates the occasion rule (matched " + rx + "): " + JSON.stringify(block));
  }
  process.exit(0);
}

if (mode === "skill-lead") {
  const file = process.argv[4];
  const m1 = new RegExp(process.argv[5], "i");
  const m2 = new RegExp(process.argv[6], "i");
  const desc = readSkillDescription(file);
  const firstSentenceMatch = desc.match(/^[^.]*\./);
  const lead = firstSentenceMatch ? firstSentenceMatch[0] : desc;
  if (!m1.test(lead)) fail("lead sentence missing " + process.argv[5] + ": " + JSON.stringify(lead));
  if (!m2.test(lead)) fail("lead sentence missing " + process.argv[6] + ": " + JSON.stringify(lead));
  process.exit(0);
}

fail("unknown mode " + mode);
JS

# Case 1: the rule requires the occasion. Break: delete "names the occasion
# to reach for the thing it fronts" from the description paragraph, or delete
# the section.
if node "$desc_tmp/desc.js" "$root" occasion >/dev/null 2>&1; then
  ok "the authoring rules require a description to name the occasion"
else
  no "the authoring rules do not require a description to name the occasion: $(node "$desc_tmp/desc.js" "$root" occasion 2>&1)"
fi

# Case 2: the rule forbids the steps. Break: delete "and never walks through
# the steps inside it", or soften "never" to "try not to".
if node "$desc_tmp/desc.js" "$root" steps-ban >/dev/null 2>&1; then
  ok "the authoring rules forbid a description from walking through the steps"
else
  no "the authoring rules do not forbid a description from walking through the steps: $(node "$desc_tmp/desc.js" "$root" steps-ban 2>&1)"
fi

# Case 3: the rule carries its reason. Break: delete the sentence beginning
# "A description that summarises a workflow becomes the shortcut agents take
# instead of reading the body."
if node "$desc_tmp/desc.js" "$root" reason >/dev/null 2>&1; then
  ok "the authoring rules carry the reason: a summarised workflow becomes a shortcut past the body"
else
  no "the authoring rules do not carry the shortcut-past-the-body reason: $(node "$desc_tmp/desc.js" "$root" reason 2>&1)"
fi

# Cases 4-7: every shipped skill description names an occasion. One case per
# skills/*/SKILL.md, sorted, naming the skill. Break: strip the occasion
# clause from any of the four.
for f in "$root"/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$f")")"
  if node "$desc_tmp/desc.js" "$root" skill-occasion "$f" >/dev/null 2>&1; then
    ok "$skill's description names an occasion for using it"
  else
    no "$skill's description names no occasion: $(node "$desc_tmp/desc.js" "$root" skill-occasion "$f" 2>&1)"
  fi
done

# Cases 8-11: no shipped skill description walks the body's steps. One case
# per skills/*/SKILL.md, sorted, naming the skill and the marker that
# matched. Break: restore a description carrying "how it ...s", "first ...
# then", or "step N".
for f in "$root"/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$f")")"
  if node "$desc_tmp/desc.js" "$root" skill-nosteps "$f" >/dev/null 2>&1; then
    ok "$skill's description does not walk through the steps"
  else
    no "$skill's description walks through the steps: $(node "$desc_tmp/desc.js" "$root" skill-nosteps "$f" 2>&1)"
  fi
done

# Case 12: the rule has one home. Mirrors exemption_ban_owners and
# form_table_owners above. Break, either direction: restate the description
# rule on skills/CLAUDE.md or .claude/rules/agents.md (two paths match), or
# delete it from the authoring page (none match).
description_rule_owners="$(grep -lie 'occasion' "$root"/agents/*.md "$root"/skills/*/SKILL.md "$root/skills/CLAUDE.md" "$root"/.claude/rules/*.md "$root/rulebook.md" "$root/README.md" "$root/GEMINI.md" 2>/dev/null || true)"
if [ "$description_rule_owners" = "$root/.claude/rules/authoring.md" ]; then
  ok ".claude/rules/authoring.md is the only page naming the occasion"
else
  no "the word \"occasion\" is owned by more (or fewer) pages than .claude/rules/authoring.md alone:"
  echo "${description_rule_owners:-       (none)}" | sed "s|^$root/|       |"
fi

# Cases 13-15: a rewritten description still leads with the words a request
# for that skill would actually contain. Break: rewrite the lead into words a
# request would not carry, e.g. "Elicitation protocol for underspecified
# intents" for grill, "Post-run process analysis" for retro, "Cross-role
# conventions" for agent-brief.
if node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/agent-brief/SKILL.md" 'rules' 'uroboros subagent' >/dev/null 2>&1; then
  ok "agent-brief's description leads with the words a request for it would contain"
else
  no "agent-brief's description does not lead with the words a request for it would contain: $(node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/agent-brief/SKILL.md" 'rules' 'uroboros subagent' 2>&1)"
fi

if node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/grill/SKILL.md" 'vague idea' 'acceptance criteria' >/dev/null 2>&1; then
  ok "grill's description leads with the words a request for it would contain"
else
  no "grill's description does not lead with the words a request for it would contain: $(node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/grill/SKILL.md" 'vague idea' 'acceptance criteria' 2>&1)"
fi

if node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/retro/SKILL.md" 'retrospective' 'log' >/dev/null 2>&1; then
  ok "retro's description leads with the words a request for it would contain"
else
  no "retro's description does not lead with the words a request for it would contain: $(node "$desc_tmp/desc.js" "$root" skill-lead "$root/skills/retro/SKILL.md" 'retrospective' 'log' 2>&1)"
fi

# Case 16: the skill-page rules do not restate the occasion rule (criterion 2,
# "no page restates it"). Break: restore "and names the triggers" to the
# Frontmatter bullet of skills/CLAUDE.md, or delete "leads with the words a
# request would actually contain" from it (which fails the required regex
# instead, so the case cannot be satisfied by gutting the bullet).
if node "$desc_tmp/desc.js" "$root" carry-bullet "$root/skills/CLAUDE.md" 'leads with the words a request' >/dev/null 2>&1; then
  ok "skills/CLAUDE.md keeps the discovery rule and restates no occasion rule"
else
  no "skills/CLAUDE.md's carry rule restates the occasion rule or dropped the discovery clause: $(node "$desc_tmp/desc.js" "$root" carry-bullet "$root/skills/CLAUDE.md" 'leads with the words a request' 2>&1)"
fi

# Case 17: the agent-page rules do not restate the occasion rule (criterion 2,
# "no page restates it"). Break: restore "when to dispatch it," to the
# Frontmatter bullet of .claude/rules/agents.md, or delete "what a caller
# reads while deciding" from it (which fails the required regex instead).
if node "$desc_tmp/desc.js" "$root" carry-bullet "$root/.claude/rules/agents.md" 'what a caller reads while deciding' >/dev/null 2>&1; then
  ok ".claude/rules/agents.md says what the description is read for and restates no occasion rule"
else
  no ".claude/rules/agents.md's carry rule restates the occasion rule or dropped the reading clause: $(node "$desc_tmp/desc.js" "$root" carry-bullet "$root/.claude/rules/agents.md" 'what a caller reads while deciding' 2>&1)"
fi

rm -rf "$desc_tmp"

echo
echo "=== every rule in the shared brief is written in its winning form"

# One collapsed copy of the page for the whole section — every marker below
# wraps across lines in the page's prose, so a case tests the collapsed copy,
# never a bare grep on the file. This is the section's own variable: it is not
# brief_collapsed from "a decidable question gets a ruling" above, which that
# section owns.
brief_form="$(tr '\n' ' ' <"$root/skills/agent-brief/SKILL.md" | tr -s ' ')"

# Case 1: the push rule is a priced prohibition quoting the excuses it
# counters (failure class: a rule skipped under pressure). Break: restore "You
# commit your work where your page says to, and you push that commit straight
# away — an unpushed commit dies with the container that made it, and the run
# state it carries dies with it." — the prohibition and both quoted excuses
# vanish and the first two markers fail.
if echo "$brief_form" | grep -q 'Never keep a commit local' &&
  echo "$brief_form" | grep -q '"one push at the end will do"' &&
  echo "$brief_form" | grep -q 'an unpushed commit dies with the container'; then
  ok "the shared brief's push rule is a priced prohibition quoting its excuses"
else
  no "the shared brief's push rule is missing its price or its quoted excuses"
fi

# Case 2: the default-branch rule is a priced prohibition (failure class: a
# rule skipped under pressure). Break: restore "The default branch moves only
# through a pull request a human merges, and opening that pull request is your
# caller's, never yours." — all three markers vanish.
if echo "$brief_form" | grep -q 'Never push to the default branch' &&
  echo "$brief_form" | grep -q '"the work is done and the branch is green"' &&
  echo "$brief_form" | grep -q 'a change no human approved'; then
  ok "the shared brief closes the default branch with a priced prohibition"
else
  no "the shared brief's default-branch rule is missing its price or its quoted excuse"
fi

# Case 3: reading outside your prompt is a priced prohibition quoting the
# excuse it counters. Break: restore "and take nothing else out of them:".
if echo "$brief_form" | grep -q 'never read a step or a field it did not name' &&
  echo "$brief_form" | grep -q '"it is in the same file anyway"'; then
  ok "the shared brief prohibits reading outside your prompt, with the excuse quoted"
else
  no "the shared brief's read-scope rule is missing its prohibition or its quoted excuse"
fi

# Case 4: the Bash rule is keyed to an observable predicate, not a judgement
# call, and the old judgement-call wording is gone even if bolted back on
# beside the new bullet. Break, either direction: restore "Prefer a dedicated
# tool over Bash when one fits — reserve Bash for shell-only operations."
# (fails the presence markers), or append that sentence to the new bullet
# (fails the absence assertion).
if echo "$brief_form" | grep -q 'use Bash where the thing needs a shell' &&
  echo "$brief_form" | grep -q 'Use the tools above where one of them does the thing' &&
  ! echo "$brief_form" | grep -q 'Prefer a dedicated tool'; then
  ok "the shared brief keys the Bash choice to an observable predicate"
else
  no "the shared brief's Bash rule still reads as a judgement call, present or bolted on"
fi

# Case 5: the closed command list is a priced prohibition quoting the excuses
# it counters. Break: restore "run exactly those and nothing else — a suite, a
# linter or a formatter it does not name is not yours to run, however obvious
# it looks, and you never go looking for a runner yourself." — all three
# markers vanish.
if echo "$brief_form" | grep -q 'Never run a suite, a linter or a formatter the list does not name' &&
  echo "$brief_form" | grep -q '"the whole suite is right there"' &&
  echo "$brief_form" | grep -q 'a failure someone else owns'; then
  ok "the shared brief closes the command list with a priced prohibition"
else
  no "the shared brief's command-list rule is missing its price or its quoted excuses"
fi

# Case 6: a ruling is a required slot in a template, not three elements asked
# for in prose. Break: restore "— short enough to survive the steering
# projection that carries it." directly after "...if the default is wrong",
# which deletes the template. The older case above pinning "one string naming
# the decision, the reason, and what it costs if the default is wrong" must
# stay green here too — that clause is kept word for word in the rewrite.
if echo "$brief_form" | grep -q 'wrong costs <cost>' &&
  echo "$brief_form" | grep -q 'in that order'; then
  ok "the shared brief states a ruling's shape as a template, not prose"
else
  no "the shared brief no longer gives a ruling's shape as a template"
fi

# Case 7: hand-writing the run state is a priced prohibition quoting the
# excuse it counters. Not keyed to "never edit that file by hand" — the
# replaced wording contains that phrase too, so a case built on it would stay
# green after a restore. Break: restore "That helper is the only writer of
# `backlog.json`, so you never edit that file by hand." — all three markers
# vanish.
if echo "$brief_form" | grep -q 'never write it with anything else' &&
  echo "$brief_form" | grep -q '"the helper rejected my argument"' &&
  echo "$brief_form" | grep -q 'starts over from the beginning'; then
  ok "the shared brief prohibits hand-writing the run state, with its price and its quoted excuse"
else
  no "the shared brief's run-state rule is missing its price or its quoted excuse"
fi

# Case 8: the announce timing is two branches on a predicate, not an exemption
# bolted onto the general rule. Break, either direction: restore "Announce
# before any other work — after only the branch steps your prompt names, so
# the announcement lands on the branch your step commits to — with the
# increment id and the label your prompt gives you." (fails the presence
# markers and the absence assertion at once), or re-append the bolted clause
# beside the new branches (fails the absence assertion alone).
if echo "$brief_form" | grep -q 'Where your prompt names branch steps' &&
  echo "$brief_form" | grep -q 'Where it names none' &&
  ! echo "$brief_form" | grep -q 'after only the branch steps'; then
  ok "the shared brief's announce timing is two stated branches on a predicate"
else
  no "the shared brief's announce timing still reads as an exemption bolted on"
fi

# Case 9: not dispatching is a priced prohibition quoting the excuse it
# counters. Break: restore "You do not dispatch subagents and you do not call
# the next agent in the chain." — all three markers vanish.
if echo "$brief_form" | grep -q 'Never dispatch a subagent' &&
  echo "$brief_form" | grep -q '"one dispatch would finish this"' &&
  echo "$brief_form" | grep -q 'the run state never records'; then
  ok "the shared brief prohibits dispatching, with its price and its quoted excuse"
else
  no "the shared brief's no-dispatch rule is missing its price or its quoted excuse"
fi

echo
echo "=== every rule on the planner and reviewer pages is written in its winning form"

# Two collapsed copies of the pages for the whole section — every marker below
# wraps across lines in the pages' prose, so a case tests the collapsed copy,
# never a bare grep on the file. These are this section's own variables: not
# reviewer_collapsed or reviewer_correction_collapsed, which belong to the
# sections that own them.
planner_form="$(tr '\n' ' ' <"$root/agents/planner.md" | tr -s ' ')"
reviewer_form="$(tr '\n' ' ' <"$root/agents/reviewer.md" | tr -s ' ')"

# Case 1: the cut-or-not rule is two branches on a predicate plus a priced
# prohibition (row 4, with row 1 underneath; failure class: an exemption
# clause and a judgement call). Break, either direction: restore "Whether to
# cut at all is yours: do not split an issue that is one change" (presence
# markers and the absence assertion fail at once), or bolt that sentence back
# beside the new branches (the absence assertion alone fails).
if echo "$planner_form" | grep -q "Where the issue's criteria describe one change" &&
  echo "$planner_form" | grep -q 'Where they describe more than one' &&
  echo "$planner_form" | grep -q 'Never split an increment to make the backlog look thorough' &&
  echo "$planner_form" | grep -q '"smaller slices are safer"' &&
  ! echo "$planner_form" | grep -q 'Whether to cut at all is yours'; then
  ok "the planner's cut-or-not rule is two branches on a predicate plus a priced prohibition"
else
  no "the planner's cut-or-not rule still reads as a judgement call, present or bolted on"
fi

# Case 2: the codemap's shape is a recipe, not prose (row 2; failure class: a
# required element asked for in prose). Break: restore "Beside the cut you
# keep the codemap: every file the issue has to change, path and why, one
# line per file."
if echo "$planner_form" | grep -q '<path> — <why the issue has to change it>' &&
  ! echo "$planner_form" | grep -q 'every file the issue has to change, path'; then
  ok "the planner's codemap shape is a recipe, not prose"
else
  no "the planner's codemap shape still reads as prose"
fi

# Case 3: the criterion-to-increment mapping is a template slot (row 3;
# failure class: a required element asked for in prose). Break: restore "Say
# in your \`summary\` which criterion went where."
if echo "$planner_form" | grep -q '<criterion> → <increment id>' &&
  ! echo "$planner_form" | grep -q 'which criterion went where'; then
  ok "the planner's criterion-to-increment mapping is a template slot"
else
  no "the planner's criterion-to-increment mapping still reads as prose"
fi

# Case 4: landing the branch states each branch on its own (row 4; failure
# class: conditional behaviour left to a judgement call). Break, either
# direction: restore the run-on sentence "an accepted increment's branch you
# merge into the issue branch and push", or leave it standing beside the new
# bullets.
if echo "$planner_form" | grep -q '\*\*Where the review accepted it\*\*' &&
  echo "$planner_form" | grep -q '\*\*Where the review did not accept it\*\*' &&
  echo "$planner_form" | grep -q '\*\*Where the merge conflicts\*\*' &&
  ! echo "$planner_form" | grep -q "an accepted increment's branch you merge"; then
  ok "the planner states each branch of landing a branch on its own"
else
  no "the planner's landing-the-branch rule still runs its branches together"
fi

# Case 5: churn is a priced prohibition quoting its excuse (row 1; failure
# class: a rule skipped under pressure). Break: restore "Change nothing you
# have no reason to change." — both markers vanish.
if echo "$planner_form" | grep -q 'Never touch an increment this run gave you no reason to touch' &&
  echo "$planner_form" | grep -q '"while I am in the file anyway"'; then
  ok "the planner's churn rule is a priced prohibition quoting its excuse"
else
  no "the planner's churn rule is missing its price or its quoted excuse"
fi

# Case 6: the search-only boundary is a priced prohibition quoting its
# excuses (row 1; failure class: a rule skipped under pressure). Break:
# restore that bullet lead — the three presence markers vanish and the
# absence assertion fails.
if echo "$planner_form" | grep -q 'Never open a file to decide how the change should work' &&
  echo "$planner_form" | grep -q '"one look at the module and the cut writes itself"' &&
  echo "$planner_form" | grep -q 'takes the decision from the agent that owns it' &&
  ! echo "$planner_form" | grep -q 'You search the codebase for the codemap, and for nothing else'; then
  ok "the planner's search-only boundary is a priced prohibition quoting its excuses"
else
  no "the planner's search-only boundary is missing its price, its quoted excuses, or its absence assertion"
fi

# Case 7: what an increment carries is a template, not prose (row 3; failure
# class: a required element asked for in prose). Break: restore "Every
# increment carries its id, title, what it delivers, its own acceptance
# criteria, its chain depth and its status".
if echo "$planner_form" | grep -q 'goal what it delivers' &&
  echo "$planner_form" | grep -q 'criteria its own acceptance criteria, one string each' &&
  echo "$planner_form" | grep -q 'depth its chain depth' &&
  ! echo "$planner_form" | grep -q 'Every increment carries its id, title'; then
  ok "the planner's increment-carries rule is a template, not prose"
else
  no "the planner's increment-carries rule still reads as prose"
fi

# Case 8: judging only what you verified is a priced prohibition quoting its
# excuses (row 1; failure class: a rule skipped under pressure). Break:
# restore "Guard it by judging only what you can verify yourself".
if echo "$reviewer_form" | grep -q 'never file a finding you have not verified' &&
  echo "$reviewer_form" | grep -q '"the plan surely meant this"' &&
  echo "$reviewer_form" | grep -q 'sends four agents into a correction round that fixes nothing' &&
  ! echo "$reviewer_form" | grep -q 'Guard it by judging only what you can verify yourself'; then
  ok "the reviewer's verify-only rule is a priced prohibition quoting its excuses"
else
  no "the reviewer's verify-only rule is missing its price, its quoted excuses, or its absence assertion"
fi

# Case 9: a red run is one predicate with each branch stated, and the
# exemption clause is gone (row 4; failure class: an exemption clause).
# Two earlier wordings have to be rejected: the merge-base wording at
# commit 67ee04d ("a finding only when this change caused it ... unless
# the change was supposed to fix it") drops the three presence markers
# and fails the first absence assertion; the round-0 wording ("Where the
# diff touched the code that failed, it is a finding, your first one ...
# Where you cannot tell which of these you are in") drops all three
# presence markers and fails the last two absence assertions; putting back
# only the unreachable escape sentence fails the last absence assertion
# alone.
if echo "$reviewer_form" | grep -q 'Where an acceptance criterion asked this increment to fix that red' &&
  echo "$reviewer_form" | grep -q 'Where the diff never touched the code that failed' &&
  echo "$reviewer_form" | grep -q 'Where the diff touched that code, run the same listed command at the merge base in a sandbox' &&
  ! echo "$reviewer_form" | grep -q 'unless the change was supposed to fix it' &&
  ! echo "$reviewer_form" | grep -q 'Where the diff touched the code that failed, it is a finding' &&
  ! echo "$reviewer_form" | grep -q 'Where you cannot tell which of these you are in'; then
  ok "the reviewer's red-run rule keys each branch on an observable predicate and still turns on whether this change caused the red"
else
  no "the reviewer's red-run rule carries an exemption clause, or decides on the diff alone"
fi

# Case 10: the run state is a branch on a predicate, not an exception to
# check 2 (row 4; failure class: an exemption clause). Break, either
# direction: restore "Judge every changed file that way, except
# \`backlog.json\`", or bolt the exception back on.
if echo "$reviewer_form" | grep -q 'Where a changed file is `backlog.json`' &&
  ! echo "$reviewer_form" | grep -q 'except `backlog.json`'; then
  ok "the reviewer's run-state rule is a branch on a predicate, not an exception"
else
  no "the reviewer's run-state rule still carries an exception bolted onto check 2"
fi

# Case 11: the blast-radius check is a priced prohibition quoting its
# excuses (row 1; failure class: a rule skipped under pressure). Break:
# restore "and answer every time, even when the answer is \"nothing found\"".
if echo "$reviewer_form" | grep -q 'Never close a review with this check unanswered' &&
  echo "$reviewer_form" | grep -q '"every criterion is met"' &&
  echo "$reviewer_form" | grep -q 'leaving it out is not' &&
  ! echo "$reviewer_form" | grep -q 'answer every time, even when the answer'; then
  ok "the reviewer's blast-radius check is a priced prohibition quoting its excuses"
else
  no "the reviewer's blast-radius check is missing its price, its quoted excuses, or its absence assertion"
fi

# Case 12: the per-finding verdict is a template slot (row 3; failure class:
# a required element asked for in prose). Break: restore "Say in your
# \`summary\`, per named finding, whether it is addressed or not."
if echo "$reviewer_form" | grep -q 'one line per named finding: `<finding> — addressed`' &&
  ! echo "$reviewer_form" | grep -q 'per named finding, whether it is addressed or not'; then
  ok "the reviewer's per-finding verdict is a template slot"
else
  no "the reviewer's per-finding verdict still reads as prose"
fi

# Case 13: a reproduction's shape is a template, not four elements in prose
# (row 3; failure class: a required element asked for in prose). Break:
# restore "A finding exists only if you can state it concretely: these
# inputs or this state, this wrong result, at this file and line — or this
# criterion, unmet, shown by this gap."
if echo "$reviewer_form" | grep -q '<these inputs or this state> → <this wrong result>, at <file>:<line>' &&
  echo "$reviewer_form" | grep -q '<this criterion>, unmet, shown by <this gap>' &&
  ! echo "$reviewer_form" | grep -q 'state it concretely: these inputs or this state'; then
  ok "the reviewer's reproduction shape is a template, not prose"
else
  no "the reviewer's reproduction shape still reads as prose"
fi

# Case 14: never opening the run state is a priced prohibition quoting its
# excuses (row 1; failure class: a rule skipped under pressure). Not keyed to
# "never read" — the heading carries that phrase and would keep the case
# green after a restore. Break: restore "You record your own step into
# \`backlog.json\`, and you never read it: it holds every other agent's
# return".
if echo "$reviewer_form" | grep -q 'and never open it' &&
  echo "$reviewer_form" | grep -q '"only my own step"' &&
  echo "$reviewer_form" | grep -q 'no longer a check on it' &&
  ! echo "$reviewer_form" | grep -q 'and you never read it: it holds'; then
  ok "the reviewer prohibits opening the run state, with its price and its quoted excuses"
else
  no "the reviewer's run-state rule is missing its price, its quoted excuses, or its absence assertion"
fi

# Case 15: writing nothing in the checkout is a priced prohibition quoting
# its excuses (row 1; failure class: a rule skipped under pressure). Break:
# restore "You write nothing in the checkout — no production code, no test,
# no fix — and nothing you run may change it."
if echo "$reviewer_form" | grep -q 'Never write in the checkout' &&
  echo "$reviewer_form" | grep -q '"it is a one-line fix"' &&
  echo "$reviewer_form" | grep -q 'reviewing its own work' &&
  ! echo "$reviewer_form" | grep -q 'You write nothing in the checkout'; then
  ok "the reviewer prohibits writing in the checkout, with its price and its quoted excuses"
else
  no "the reviewer's checkout rule is missing its price, its quoted excuses, or its absence assertion"
fi

# Case 16: the probe's stated doubt carries its quoted excuse in the same
# sentence as the prohibition (row 1; failure class: a rule skipped under
# pressure). Break: restore "Probe from a stated doubt, never to explore.
# Name the criterion" — the prohibition survives, the excuse does not, and
# the marker fails.
if echo "$reviewer_form" | grep -q 'Probe from a stated doubt, never to explore — not "while the sandbox is up"'; then
  ok "the reviewer's probe rule carries its quoted excuse in the same sentence as the prohibition"
else
  no "the reviewer's probe rule dropped its quoted excuse or split it from the prohibition"
fi

# Case 17: the probe staying in the sandbox is a priced prohibition quoting
# its excuse (row 1; failure class: a rule skipped under pressure). Break:
# restore "A probe exists in the sandbox alone: never write one into the
# checkout, never commit one, and never let one reach the diff under review."
# ending there — both markers vanish.
if echo "$reviewer_form" | grep -q '"it is only a scratch file"' &&
  echo "$reviewer_form" | grep -q 'the next round files it against the increment'; then
  ok "the reviewer's sandbox rule is a priced prohibition quoting its excuse"
else
  no "the reviewer's sandbox rule is missing its price or its quoted excuse"
fi

echo
echo "=== every rule on the researcher, test-author and implementer pages is written in its winning form"

# Three collapsed copies of the pages for the whole section — every marker
# below wraps across lines in the pages' prose, so a case tests the collapsed
# copy, never a bare grep on the file. These are this section's own
# variables: not implementer_collapsed, which "a decidable question gets a
# ruling" owns.
researcher_form="$(tr '\n' ' ' <"$root/agents/researcher.md" | tr -s ' ')"
testauthor_form="$(tr '\n' ' ' <"$root/agents/test-author.md" | tr -s ' ')"
implementer_form="$(tr '\n' ' ' <"$root/agents/implementer.md" | tr -s ' ')"

# Case 1: researcher, R-1, row 1 — the read-before-question rule is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "opening files before you have the question is
# how a one-file change costs an afternoon." — the first two markers vanish
# and the absence assertion fails; bolting it back beside the new prohibition
# fails the absence assertion alone.
if echo "$researcher_form" | grep -q 'Never open a file before you have named the question it answers' &&
  echo "$researcher_form" | grep -q '"one pass over the module first"' &&
  echo "$researcher_form" | grep -q 'costs an afternoon' &&
  ! echo "$researcher_form" | grep -q 'opening files before you have the question'; then
  ok "the researcher's read-before-question rule is a priced prohibition quoting its excuse"
else
  no "the researcher's read-before-question rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 2: researcher, R-2, row 1 — trusting the map for design is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "trust the map for where and never for design.",
# or append it beside the new prohibition.
if echo "$researcher_form" | grep -q 'Never take a design decision from the map' &&
  echo "$researcher_form" | grep -q '"the map already says how"' &&
  echo "$researcher_form" | grep -q 'the one agent that could have checked it was you' &&
  ! echo "$researcher_form" | grep -q 'trust the map for where and never for design'; then
  ok "the researcher's map-for-design rule is a priced prohibition quoting its excuse"
else
  no "the researcher's map-for-design rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 3: researcher, R-3, row 3 — the moduleMap shape is a recipe, not prose
# (failure class: an omitted required element asked for in prose). Break:
# restore "path, what each holds, the entry points."
if echo "$researcher_form" | grep -q '<path> — <what it holds> — <the entry points>' &&
  ! echo "$researcher_form" | grep -q 'path, what each holds, the entry points'; then
  ok "the researcher's moduleMap shape is a recipe, not prose"
else
  no "the researcher's moduleMap shape still reads as prose"
fi

# Case 4: researcher, R-4, row 1 — the environment list's closing rule is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "List nothing else — a command you mention for
# completeness reads downstream as a command to run."
if echo "$researcher_form" | grep -q 'Never list a command your test plan does not ask for' &&
  echo "$researcher_form" | grep -q '"for completeness"' &&
  echo "$researcher_form" | grep -q 'the run pays for it' &&
  ! echo "$researcher_form" | grep -q 'List nothing else'; then
  ok "the researcher's environment-list rule is a priced prohibition quoting its excuse"
else
  no "the researcher's environment-list rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 5: researcher, R-5, row 3 — a case's shape is a template, not four
# elements asked for in prose (failure class: an omitted required element).
# Break: restore the prose sentence and the "each case states, as part of the
# case, the break" clause. The four older cases on this bullet (lines 481,
# 490, 518, 544 of this file) must stay green — a run of the whole file is
# what shows it.
if echo "$researcher_form" | grep -q '<criterion> — <input and state> → <expected result> — break: <the production change that would make it fail>' &&
  ! echo "$researcher_form" | grep -q 'input, state, expected result, and the edges'; then
  ok "the researcher's case shape is a template, not prose"
else
  no "the researcher's case shape still reads as prose"
fi

# Case 6: researcher, R-6, row 3 — the "How" per-case shape is a template,
# not prose (failure class: an omitted required element). Break: restore
# "Per case: the level (unit, integration, end-to-end), the test file by
# path, the framework, and the command that runs just that file." The
# existing "suite doc" case (line 2179) must stay green.
if echo "$researcher_form" | grep -q '<level: unit, integration or end-to-end> — <test file by path> — <framework> — <the command that runs just that file>' &&
  ! echo "$researcher_form" | grep -q 'Per case: the level'; then
  ok "the researcher's per-case How shape is a template, not prose"
else
  no "the researcher's per-case How shape still reads as prose"
fi

# Case 7: researcher, R-7, row 1 — weighing what counts as done is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "Weigh what each entry buys against what it
# costs.", or append it beside the new prohibition.
if echo "$researcher_form" | grep -q 'Never list a command you have not weighed' &&
  echo "$researcher_form" | grep -q '"the whole suite is safer"' &&
  echo "$researcher_form" | grep -q 'by the implementer and the reviewer both' &&
  ! echo "$researcher_form" | grep -q 'Weigh what each entry buys against what it costs'; then
  ok "the researcher's what-counts-as-done rule is a priced prohibition quoting its excuse"
else
  no "the researcher's what-counts-as-done rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 8: researcher, R-8, row 4 — the exemption clause on "What is already
# red" is re-cut into a rule keyed to an observable predicate, with each
# branch stated on its own (failure class: an exemption clause). Break,
# either direction: restore the old bullet body (all four presence markers
# vanish and both absence assertions fail), or re-append the exception
# sentence beside the new branches (the first absence assertion alone
# fails).
if echo "$researcher_form" | grep -q 'does a decision in your plan turn on a fact only a run can settle' &&
  echo "$researcher_form" | grep -q 'Where none does, run nothing' &&
  echo "$researcher_form" | grep -q 'Where one does, run what settles that fact' &&
  echo "$researcher_form" | grep -q 'Wanting to know where the list stands is not such a fact' &&
  ! echo "$researcher_form" | grep -q 'that is the exception, not a habit' &&
  ! echo "$researcher_form" | grep -q 'You do not run the list yourself'; then
  ok "the researcher's what-is-already-red rule is keyed to an observable predicate, not an exemption clause"
else
  no "the researcher's what-is-already-red rule still carries an exemption clause, present or bolted on"
fi

# Case 9: researcher, R-9 and R-10, row 1, and the tail of the R-8 re-cut —
# the boundaries are priced prohibitions quoting their excuses, and the run
# boundary is scoped to test runs so the announce, record, commit and push
# commands the shared brief requires stay allowed (failure class: a rule
# skipped under pressure). Break, three directions: restore "You do not write
# production code or tests." or "You do not run tests.", each caught by its
# own absence assertion; or restore round 0's "You run nothing except what
# **What is already red** sends you to run.", which forbade those commands —
# the last absence assertion fails and the three new presence markers vanish.
if echo "$researcher_form" | grep -q 'Never write production code or a test' &&
  echo "$researcher_form" | grep -q '"the fix is three lines"' &&
  echo "$researcher_form" | grep -q 'a plan whose author already built it' &&
  echo "$researcher_form" | grep -q 'Never run a test where no decision in your plan turns on a fact only that run can settle' &&
  echo "$researcher_form" | grep -q '"a baseline first"' &&
  echo "$researcher_form" | grep -q 'plans around what it saw instead of around what the issue asked for' &&
  ! echo "$researcher_form" | grep -q 'You do not write production code or tests' &&
  ! echo "$researcher_form" | grep -q 'You do not run tests' &&
  ! echo "$researcher_form" | grep -q 'You run nothing except'; then
  ok "the researcher's boundaries are priced prohibitions quoting their excuses, and its run boundary is scoped to test runs"
else
  no "the researcher's boundaries still read as unpriced reminders, or forbid the runs the shared brief requires"
fi

# Case 10: test-author, T-1, row 1 — never opening production code is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "so you do not open production code at all."
if echo "$testauthor_form" | grep -q 'Never open production code' &&
  echo "$testauthor_form" | grep -q '"just to see what it is called"' &&
  echo "$testauthor_form" | grep -q 'nobody downstream can tell the difference' &&
  ! echo "$testauthor_form" | grep -q 'so you do not open production code at all'; then
  ok "the test-author's no-production-code rule is a priced prohibition quoting its excuse"
else
  no "the test-author's no-production-code rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 11: test-author, T-2, row 1 — adding no unasked coverage is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "Add no coverage the plan did not ask for.", or
# append it beside the new prohibition.
if echo "$testauthor_form" | grep -q 'Never add a case the plan did not ask for' &&
  echo "$testauthor_form" | grep -q '"this edge obviously needs a test"' &&
  echo "$testauthor_form" | grep -q 'nobody to settle it' &&
  ! echo "$testauthor_form" | grep -q 'Add no coverage the plan did not ask for'; then
  ok "the test-author's no-unasked-coverage rule is a priced prohibition quoting its excuse"
else
  no "the test-author's no-unasked-coverage rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 12: test-author, T-3, row 1 — the failure a case is left with has to be
# the missing behaviour, in a priced prohibition quoting its excuse (failure
# class: a rule skipped under pressure). Break, two directions: restore
# "confirm each fails because the behaviour is missing", caught by the first
# absence assertion; or restore round 0's "Never record a case as failing
# without that reason in hand", which asked only that the reason be known and
# let an import error be recorded as the failure — the second absence
# assertion fails and the first presence marker vanishes.
if echo "$testauthor_form" | grep -q 'Never leave a case failing on anything but the missing behaviour' &&
  echo "$testauthor_form" | grep -q '"red is red"' &&
  echo "$testauthor_form" | grep -q 'makes it pass by fixing the typo' &&
  ! echo "$testauthor_form" | grep -q 'confirm each fails because the behaviour is missing' &&
  ! echo "$testauthor_form" | grep -q 'Never record a case as failing without that reason in hand'; then
  ok "the test-author's prove-the-failure rule demands the failure be the missing behaviour, priced and quoting its excuse"
else
  no "the test-author's prove-the-failure rule asks only for a reason, or still reads as an unpriced reminder"
fi

# Case 13: test-author, T-4, row 3 — the suite doc's contents are required
# slots, one section each (failure class: an omitted required element), and
# not the one-line em-dash template round 0 wrote, which imposed a shape on
# the doc that the rule never asked for. Break, two directions: restore the
# prose list, whose join "worked in: what the suite covers" the first absence
# assertion catches; or restore round 0's em-dash template, caught by the
# second. The existing "CLAUDE.md" case (line 2174) must stay green.
if echo "$testauthor_form" | grep -q 'a section per slot and no slot empty: what the suite covers' &&
  echo "$testauthor_form" | grep -q 'the command that runs just this suite' &&
  ! echo "$testauthor_form" | grep -q 'worked in: what the suite covers' &&
  ! echo "$testauthor_form" | grep -q '<what the suite covers> — <the helpers and fixtures a new case reuses>'; then
  ok "the test-author's suite-doc contents are required slots, one section each"
else
  no "the test-author's suite-doc contents read as prose, or as a one-line template"
fi

# Case 14: test-author, T-5 first bullet, row 1 — the production-code
# boundary is a priced prohibition quoting its excuse (failure class: a rule
# skipped under pressure). Break: restore that bullet ("Production code is
# off limits, even a one-line stub.").
if echo "$testauthor_form" | grep -q 'Never write outside the test files and the suite doc beside them' &&
  echo "$testauthor_form" | grep -q '"it is a one-line stub"' &&
  echo "$testauthor_form" | grep -q 'built the thing its own test was meant to judge' &&
  ! echo "$testauthor_form" | grep -q 'Production code is off limits'; then
  ok "the test-author's production-code boundary is a priced prohibition quoting its excuse"
else
  no "the test-author's production-code boundary still reads as an unpriced reminder, present or bolted on"
fi

# Case 15: test-author, T-5 second bullet, row 1 — never making a test pass
# is a priced prohibition quoting its excuse (failure class: a rule skipped
# under pressure). Break: restore that bullet — note the third presence
# marker is the interface declaration the rewrite keeps, so it alone would
# not catch the restore, which is why the absence assertion carries the
# case.
if echo "$testauthor_form" | grep -q 'Never make a test pass — not "it was one line from green"' &&
  echo "$testauthor_form" | grep -q 'inherits a suite that proves nothing' &&
  echo "$testauthor_form" | grep -q 'may not edit what you wrote' &&
  ! echo "$testauthor_form" | grep -q 'You never make a test pass'; then
  ok "the test-author's never-make-it-pass rule is a priced prohibition quoting its excuse"
else
  no "the test-author's never-make-it-pass rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 16: test-author, T-6, row 3 — the `cases` field's shape is a template,
# not prose (failure class: an omitted required element). Break: restore the
# prose bullet ("the test file by path, the test's name, ...").
if echo "$testauthor_form" | grep -q 'one entry per planned case, every slot filled' &&
  echo "$testauthor_form" | grep -q '`want` what the case demands' &&
  echo "$testauthor_form" | grep -q '`got` the failure it produced' &&
  ! echo "$testauthor_form" | grep -q 'the test file by path, the test'; then
  ok "the test-author's cases-field shape is a template, not prose"
else
  no "the test-author's cases-field shape still reads as prose"
fi

# Case 17: implementer, I-1, row 1 — never reading issue.md is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "You do not read \`issue.md\`.", or append it
# beside the new prohibition.
if echo "$implementer_form" | grep -q 'Never open `issue.md`' &&
  echo "$implementer_form" | grep -q '"the criteria are right there"' &&
  echo "$implementer_form" | grep -q 'builds what the plan never asked for' &&
  ! echo "$implementer_form" | grep -q 'You do not read `issue.md`'; then
  ok "the implementer's never-read-issue rule is a priced prohibition quoting its excuse"
else
  no "the implementer's never-read-issue rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 18: implementer, I-3, row 1 — the research ban, priced once and
# removed from step 1, is a priced prohibition quoting its excuse (failure
# class: a rule skipped under pressure). Break: restore either wording ("you
# do no research in the codebase" from step 1, or "You never research the
# codebase yourself." from the boundaries).
if echo "$implementer_form" | grep -q 'Never research the codebase' &&
  echo "$implementer_form" | grep -q '"a quick look at the caller settles it"' &&
  echo "$implementer_form" | grep -q 'the work rests on it anyway' &&
  ! echo "$implementer_form" | grep -q 'You never research the codebase yourself' &&
  ! echo "$implementer_form" | grep -q 'and you do no research in the codebase'; then
  ok "the implementer's research ban is a single priced prohibition quoting its excuse"
else
  no "the implementer's research ban still reads as an unpriced reminder, present or bolted on, in either place it used to live"
fi

# Case 19: implementer, I-2 and I-4 — one rule, the test ban, priced once and
# removed from step 3, is a priced prohibition quoting its excuse (failure
# class: a rule skipped under pressure). Break: restore either wording ("You
# may not edit a test and you may not write one." from step 3, or "You never
# write or edit a test, and you never decide whether one is needed." from
# the boundaries). The existing case pinning "need a material decision" and
# "leave a material decision open" (lines 674-686) must stay green.
if echo "$implementer_form" | grep -q 'Never write or edit a test' &&
  echo "$implementer_form" | grep -q '"the assertion is obviously wrong"' &&
  echo "$implementer_form" | grep -q 'no longer pins what was asked for' &&
  echo "$implementer_form" | grep -q 'which the test plan settled' &&
  ! echo "$implementer_form" | grep -q 'You never write or edit a test, and you never decide whether one is needed' &&
  ! echo "$implementer_form" | grep -q 'You may not edit a test'; then
  ok "the implementer's test ban is a single priced prohibition quoting its excuse"
else
  no "the implementer's test ban still reads as an unpriced reminder, present or bolted on, in either place it used to live"
fi

# Case 20: implementer, I-5, row 1 — never accepting your own work is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore that bullet ("You never review or accept your
# own work.").
if echo "$implementer_form" | grep -q 'Never accept your own work' &&
  echo "$implementer_form" | grep -q '"it is obviously right"' &&
  echo "$implementer_form" | grep -q 'a fresh one is the whole point of the review' &&
  ! echo "$implementer_form" | grep -q 'You never review or accept your own work'; then
  ok "the implementer's never-accept-own-work rule is a priced prohibition quoting its excuse"
else
  no "the implementer's never-accept-own-work rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 21: implementer, I-6, row 1 — scope being the brief is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore that bullet ("Scope is the brief."). The fourth
# presence marker is the clause the rewrite keeps; the absence assertion is
# what catches the restore.
if echo "$implementer_form" | grep -q 'Never build what the brief did not ask for' &&
  echo "$implementer_form" | grep -q '"it is two lines while I am in the file"' &&
  echo "$implementer_form" | grep -q 'the review has no criterion to judge it by' &&
  echo "$implementer_form" | grep -q 'goes in your return as a note' &&
  ! echo "$implementer_form" | grep -q 'Scope is the brief'; then
  ok "the implementer's scope-is-the-brief rule is a priced prohibition quoting its excuse"
else
  no "the implementer's scope-is-the-brief rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 22: implementer, I-7, row 3 — a deviation's shape is a template, not
# prose (failure class: an omitted required element). Break: restore the
# prose bullet ("what it said, what you did, why").
if echo "$implementer_form" | grep -q '<what the plan said> → <what you built> — <why>' &&
  ! echo "$implementer_form" | grep -q 'what it said, what you did, why'; then
  ok "the implementer's deviation shape is a template, not prose"
else
  no "the implementer's deviation shape still reads as prose"
fi

# Case 23: the stale citation — this pins that the rewrite of I-1 moves the
# sentence hooks/read-barrier.mjs quotes, which hooks/CLAUDE.md requires
# ("every entry in its table cites the page it comes from"). Not an
# acceptance criterion of this increment. Read the file directly, no
# collapsing needed — the comment is one line. Break: leave the comment as it
# stands while the page changes, or change the comment without changing the
# page.
if grep -q 'Never open `issue.md`' "$root/hooks/read-barrier.mjs" &&
  ! grep -q 'You do not read' "$root/hooks/read-barrier.mjs"; then
  ok "hooks/read-barrier.mjs cites the implementer.md sentence the rewrite of I-1 leaves current"
else
  no "hooks/read-barrier.mjs still cites the pre-rewrite implementer.md wording"
fi

echo
echo "=== every rule on the argus, grill and retro skill pages is written in its winning form"

# Three collapsed copies of the pages for the whole section — every marker
# below wraps across lines in the pages' prose, so a case tests the collapsed
# copy, never a bare grep on the file. These three names are new; nothing
# else in the file uses them.
argus_form="$(tr '\n' ' ' <"$root/skills/argus/SKILL.md" | tr -s ' ')"
grill_form="$(tr '\n' ' ' <"$root/skills/grill/SKILL.md" | tr -s ' ')"
retro_form="$(tr '\n' ' ' <"$root/skills/retro/SKILL.md" | tr -s ' ')"

# Case 1: argus, A-4, row 1 — never handing the setup over silently is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "Say that out loud when you hand this over; it is
# the one step that silently produces no data." — the three presence markers
# vanish and the absence assertion fails; bolting the old sentence back
# beside the new prohibition fails the absence assertion alone.
if echo "$argus_form" | grep -q 'Never hand the setup over without saying that out loud' &&
  echo "$argus_form" | grep -q '"they will start a new session anyway"' &&
  echo "$argus_form" | grep -q 'reads as a broken collector' &&
  ! echo "$argus_form" | grep -q 'Say that out loud when you hand this over'; then
  ok "argus's hand-over rule is a priced prohibition quoting its excuse"
else
  no "argus's hand-over rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 2: argus, A-5, row 1 — running the probe in the agent's own
# environment is a priced prohibition quoting its excuse (failure class: a
# rule skipped under pressure). Break: restore "Run it inside the
# environment the agent runs in.", alone or appended beside the new
# prohibition.
if echo "$argus_form" | grep -q 'Never run it outside the environment the agent runs in' &&
  echo "$argus_form" | grep -q '"my shell is close enough"' &&
  echo "$argus_form" | grep -q 'passes on variables nothing is exporting with' &&
  ! echo "$argus_form" | grep -q 'Run it inside the environment the agent runs in'; then
  ok "argus's probe-environment rule is a priced prohibition quoting its excuse"
else
  no "argus's probe-environment rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 3: argus, A-6, row 1 — never offering to recover unexported telemetry
# is a priced prohibition quoting its excuse (failure class: a rule skipped
# under pressure). Break: restore the old paragraph, caught by the absence
# assertion and by the first three markers. The fourth marker is the
# requirement the rewrite keeps, and it is asserted so that a later edit
# cannot drop the "offer a new session" half while the prohibition alone
# keeps the case green.
if echo "$argus_form" | grep -q 'Never offer to recover it' &&
  echo "$argus_form" | grep -q '"there may be a log somewhere"' &&
  echo "$argus_form" | grep -q 'the search ends empty however long it runs' &&
  echo "$argus_form" | grep -q 'offer the measurable thing: a new session doing the same work' &&
  ! echo "$argus_form" | grep -q 'There is nothing to recover. Telemetry not exported at the time was never produced'; then
  ok "argus's nothing-to-recover rule is a priced prohibition quoting its excuse"
else
  no "argus's nothing-to-recover rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 4: grill, G-2, row 1 — never opening the interview before the sweep
# returns is a priced prohibition quoting its excuse (failure class: a rule
# skipped under pressure). Break: restore "Ask them last, though." The third
# marker is the price the rewrite keeps verbatim, so the absence assertion is
# what catches a restore that appends the old opening.
if echo "$grill_form" | grep -q 'Never open the interview before the sweep has come back' &&
  echo "$grill_form" | grep -q '"the idea is clear enough to just ask"' &&
  echo "$grill_form" | grep -q 'the vagueness that made grilling necessary survives untouched' &&
  ! echo "$grill_form" | grep -q 'Ask them last, though'; then
  ok "grill's sweep-before-interview rule is a priced prohibition quoting its excuse"
else
  no "grill's sweep-before-interview rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 5: grill, G-3a, row 3 — the sweep's return shape is a recipe, not
# prose (failure class: an omitted required element asked for in prose).
# Break: restore the prose sentence "What comes back is the ground the
# interview stands on — what already exists, what the idea would touch, and
# which questions the repository cannot answer."
if echo "$grill_form" | grep -q 'every slot filled' &&
  echo "$grill_form" | grep -q '<what already exists> — <what the idea would touch> — <the questions the repository cannot answer>' &&
  ! echo "$grill_form" | grep -q 'what already exists, what the idea would touch, and which questions the repository cannot answer'; then
  ok "grill's sweep-return shape is a recipe, not prose"
else
  no "grill's sweep-return shape still reads as prose"
fi

# Case 6: grill, G-3b, row 1 — never reading the swept material yourself is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "You read none of that yourself", alone or
# beside the new prohibition.
if echo "$grill_form" | grep -q 'Never read the swept material yourself' &&
  echo "$grill_form" | grep -q '"one file will be quicker than briefing a subagent"' &&
  echo "$grill_form" | grep -q 'the sweep exists to keep it clean' &&
  ! echo "$grill_form" | grep -q 'You read none of that yourself'; then
  ok "grill's do-not-read-the-sweep rule is a priced prohibition quoting its excuse"
else
  no "grill's do-not-read-the-sweep rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 7: grill, G-5, row 1 — never bundling questions is a priced
# prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "Never bundle questions; bundled questions get
# half-answers." Note the absence marker carries the semicolon: the new
# wording opens with the same three words, so only the semicolon form
# distinguishes the replaced rule.
if echo "$grill_form" | grep -q 'Never bundle questions — not "these two go together"' &&
  echo "$grill_form" | grep -q 'the turn that asked both is spent' &&
  ! echo "$grill_form" | grep -q 'Never bundle questions; bundled questions get half-answers'; then
  ok "grill's never-bundle-questions rule is a priced prohibition quoting its excuse"
else
  no "grill's never-bundle-questions rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 8: grill, G-6, row 1, both halves of step 3 — never letting a vague
# answer stand and never leaving an edge undecided are priced prohibitions
# quoting their excuses (failure class: a rule skipped under pressure).
# Break, two directions: restore the first sentence of the old bullet,
# caught by the first absence assertion; or restore the second, caught by
# the second. The second presence marker is the "politely" the rewrite
# keeps in the rule, so a rewrite that drops it while keeping the
# prohibition also goes red.
if echo "$grill_form" | grep -q 'Never let "it should be better" stand as an answer' &&
  echo "$grill_form" | grep -q '"we can pin it down later"' &&
  echo "$grill_form" | grep -q 'press politely for the one that can land as an acceptance criterion' &&
  echo "$grill_form" | grep -q 'an answer nobody can fail is a criterion nobody can test' &&
  echo "$grill_form" | grep -q 'Never leave an edge the sweep turned up undecided' &&
  echo "$grill_form" | grep -q '"the centre is what matters"' &&
  echo "$grill_form" | grep -q 'one role too late' &&
  ! echo "$grill_form" | grep -q 'Push politely past' &&
  ! echo "$grill_form" | grep -q 'Close the edges the sweep turned up as well as the centre'; then
  ok "grill's vague-answer and undecided-edge rules are priced prohibitions quoting their excuses"
else
  no "grill's vague-answer and undecided-edge rules still read as unpriced reminders, present or bolted on"
fi

# Case 9: grill, G-8, row 3 — the criteria document's shape is a recipe, not
# prose (failure class: an omitted required element). Break: restore the
# prose list "the problem, the acceptance criteria, and **a decision
# recorded for every answer the human gave**".
if echo "$grill_form" | grep -q 'a section per slot and no slot empty: the problem; the acceptance criteria; a decision for every answer the human gave' &&
  ! echo "$grill_form" | grep -q 'the problem, the acceptance criteria, and'; then
  ok "grill's criteria-document shape is a recipe, not prose"
else
  no "grill's criteria-document shape still reads as prose"
fi

# Case 10: grill, G-9, row 1 — never starting the loop on unapproved criteria
# is a priced prohibition quoting its excuse (failure class: a rule skipped
# under pressure). Break: restore "Then show the criteria to the human for
# approval:". The fourth presence marker is the requirement the rewrite
# keeps, asserted so a later edit cannot leave the prohibition without the
# act it demands.
if echo "$grill_form" | grep -q 'Never start the loop on criteria the human has not approved' &&
  echo "$grill_form" | grep -q '"they told me what they want already"' &&
  echo "$grill_form" | grep -q 'spends every later role on criteria nobody agreed to' &&
  echo "$grill_form" | grep -q 'Show the criteria and wait for the approval' &&
  ! echo "$grill_form" | grep -q 'Then show the criteria to the human for approval'; then
  ok "grill's approve-before-loop rule is a priced prohibition quoting its excuse"
else
  no "grill's approve-before-loop rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 11: retro, R-2, row 4 — identifying the log file is a rule keyed to an
# observable predicate, with each branch stated on its own (failure class:
# behaviour that depends on a condition, folded into one sentence). Break:
# restore "Identify the log file to parse (either via an explicit path
# parameter or by running `bin/parse-agent-log --latest`)." Both branches are
# asserted separately, so folding the two back into one sentence goes red
# even if the words survive.
if echo "$retro_form" | grep -q 'Where the caller named a log file, parse that one' &&
  echo "$retro_form" | grep -q 'Where the caller named none, run `bin/parse-agent-log --latest`' &&
  ! echo "$retro_form" | grep -q 'either via an explicit path parameter or by running'; then
  ok "retro's log-file rule is keyed to an observable predicate, with each branch stated on its own"
else
  no "retro's log-file rule still folds both branches into one sentence"
fi

# Case 12: retro, R-3, row 1 — never going looking for a prose report is a
# priced prohibition quoting its excuse (failure class: a rule skipped under
# pressure). Break: restore "no agent writes a prose report of its own, so
# do not go looking for one." The fourth marker is the fact the rewrite
# keeps, so gutting it while the prohibition stands also goes red.
if echo "$retro_form" | grep -q 'Never go looking for a prose report of the run' &&
  echo "$retro_form" | grep -q '"there must be a summary somewhere"' &&
  echo "$retro_form" | grep -q 'the search spends the retro' &&
  echo "$retro_form" | grep -q 'those are the whole record' &&
  ! echo "$retro_form" | grep -q 'so do not go looking for one'; then
  ok "retro's no-prose-report rule is a priced prohibition quoting its excuse"
else
  no "retro's no-prose-report rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 13: retro, R-5, row 3 — the retrospective document's tables are a
# recipe, not prose (failure class: an omitted required element). Break:
# restore "Include a **Session Metrics Summary** table, a **Per-Agent
# Breakdown** table (main agent vs each subagent), and a **Mermaid Sequence
# Diagram** illustrating the interaction flow between User, Main Agent,
# Subagents, and Tools/System."
if echo "$retro_form" | grep -q 'The retrospective carries these three as well, a section per slot and no slot empty' &&
  echo "$retro_form" | grep -q 'a table, the main agent against each subagent' &&
  echo "$retro_form" | grep -q 'the interaction flow between User, Main Agent, Subagents and Tools' &&
  ! echo "$retro_form" | grep -q 'table (main agent vs each subagent)'; then
  ok "retro's retrospective-tables shape is a recipe, not prose"
else
  no "retro's retrospective-tables shape still reads as prose"
fi

# Case 14: the three pages carry no vocabulary another page owns — the fast,
# named signal for a failure the pre-existing ownership cases (lines 185,
# 455, 508, 666, 2077, 2419, 2431, 2626 and the handoff cases at 327 and 343
# of this file) would otherwise report as an unexplained ownership drift.
# Break: reword any of the fourteen replacements with a word another page
# owns — for instance pricing grill's G-2 with "the rationalisation it
# counters", or writing A-5's excuse as "the shell it probes is close
# enough". Read the three pages directly, no collapsing needed.
case14_words='occasion|exemption clause|rationalisation|chain depth|counts as tested|dependency footprint|probe|hand-off|handoff'
case14_ok=true
case14_report=""
for case14_file in skills/argus/SKILL.md skills/grill/SKILL.md skills/retro/SKILL.md; do
  case14_ci="$(grep -inE "$case14_words" "$root/$case14_file" || true)"
  case14_cs="$(grep -n 'rulebook' "$root/$case14_file" || true)"
  if [ -n "$case14_ci" ]; then
    case14_ok=false
    case14_report="${case14_report}${case14_file} (case-insensitive):
$case14_ci
"
  fi
  if [ -n "$case14_cs" ]; then
    case14_ok=false
    case14_report="${case14_report}${case14_file} (rulebook, case-sensitive):
$case14_cs
"
  fi
done
if $case14_ok; then
  ok "argus, grill and retro carry no vocabulary another page owns"
else
  no "argus, grill or retro carries vocabulary another page owns:"
  echo "$case14_report" | sed 's/^/       /'
fi

echo
echo "=== every rule on the two pages carrying the authoring rules is written in its winning form"

# Two collapsed copies of the pages for the whole section — every marker
# below wraps across lines in the pages' prose, so a case tests the collapsed
# copy, never a bare grep on the file. These two names are new; nothing else
# in the file uses them.
skills_doc_form="$(tr '\n' ' ' <"$root/skills/CLAUDE.md" | tr -s ' ')"
agent_rules_form="$(tr '\n' ' ' <"$root/.claude/rules/agents.md" | tr -s ' ')"

# Case 1: skills/CLAUDE.md, S-3/R-1, row 1 — leaving a location in use out of
# plugin.json is a priced prohibition quoting its excuse (failure class: a
# rule skipped under pressure). Break: restore "Every location in use is
# listed in `plugin.json`'s `skills` field", alone or beside the new
# prohibition.
if echo "$skills_doc_form" | grep -q 'Never leave a location in use out of `plugin.json`' &&
  echo "$skills_doc_form" | grep -q '"discovery will find it"' &&
  echo "$skills_doc_form" | grep -q 'a skill in the tree that no session ever reaches' &&
  ! echo "$skills_doc_form" | grep -q 'Every location in use is listed in'; then
  ok "the skill-page rules price leaving a location out of plugin.json and quote the excuse"
else
  no "the skill-page location-listing rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 2: skills/CLAUDE.md, S-5/R-2, row 3 — the skill page's body is a
# recipe, not prose (failure class: an omitted required element asked for in
# prose). Break: restore "not an essay: how to run it, what it produces, and
# a closing" (the pre-branch prose) or "not an essay: a section per slot and
# no slot empty" (the round-0 wording this round replaces).
if echo "$skills_doc_form" | grep -q 'is the procedure, not an essay: every slot filled' &&
  echo "$skills_doc_form" | grep -q 'a closing "what it is not"' &&
  ! echo "$skills_doc_form" | grep -q 'not an essay: how to run it' &&
  ! echo "$skills_doc_form" | grep -q 'a section per slot'; then
  ok "the skill-page body is a slot recipe, not prose"
else
  no "the skill-page body still reads as prose"
fi

# Case 3: skills/CLAUDE.md, S-6/R-3, row 1 — putting a path, filename or
# heading on the interface side is a priced prohibition quoting its excuse
# (failure class: a rule skipped under pressure). Break: restore "keep paths,
# filenames and headings on the inside". The fourth marker is the
# requirement the rewrite keeps, asserted so gutting it while the
# prohibition stands also goes red.
if echo "$skills_doc_form" | grep -q 'Never put a path, a filename or a heading on the interface side' &&
  echo "$skills_doc_form" | grep -q '"the caller needs to know where it lands"' &&
  echo "$skills_doc_form" | grep -q 'the inside stops being free to change' &&
  echo "$skills_doc_form" | grep -q 'Say which is which on the page' &&
  ! echo "$skills_doc_form" | grep -q 'keep paths, filenames and headings on the inside'; then
  ok "the interface rule is a priced prohibition quoting its excuse"
else
  no "the interface rule still reads as an unpriced reminder, present or bolted on, or has dropped the which-is-which requirement"
fi

# Case 4: skills/CLAUDE.md, S-7/R-4, row 1 — restating a rule another page
# owns is a priced prohibition quoting its excuse (failure class: a rule
# skipped under pressure). Break: restore "point at the owner instead of
# restating it". The fourth marker is the requirement kept in the rule.
if echo "$skills_doc_form" | grep -q 'Never restate a rule another page owns' &&
  echo "$skills_doc_form" | grep -q '"one sentence here saves the reader a jump"' &&
  echo "$skills_doc_form" | grep -q 'the two copies drift apart' &&
  echo "$skills_doc_form" | grep -q 'point at the owner where another page owns a rule' &&
  ! echo "$skills_doc_form" | grep -q 'point at the owner instead of restating it'; then
  ok "the describe-once rule is a priced prohibition quoting its excuse"
else
  no "the describe-once rule still reads as an unpriced reminder, present or bolted on, or has dropped the point-at-the-owner requirement"
fi

# Case 5: skills/CLAUDE.md, S-11a/R-5, row 1 — hard-coding a path inside this
# repository is a priced prohibition quoting its excuse (failure class: a
# rule skipped under pressure). Break: restore "so nothing in it may
# hard-code a path".
if echo "$skills_doc_form" | grep -q 'Never hard-code a path inside this repository' &&
  echo "$skills_doc_form" | grep -q '"it resolves here"' &&
  echo "$skills_doc_form" | grep -q 'resolves nowhere else' &&
  ! echo "$skills_doc_form" | grep -q 'so nothing in it may hard-code a path'; then
  ok "the hard-coded-path rule is a priced prohibition quoting its excuse"
else
  no "the hard-coded-path rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 6: .claude/rules/agents.md, A-3/R-6, row 1 — adding an agent without
# adding its line is a priced prohibition quoting its excuse (failure class:
# a rule skipped under pressure). Break: restore "Add an agent, add its
# line".
if echo "$agent_rules_form" | grep -q 'Never add an agent without adding its line' &&
  echo "$agent_rules_form" | grep -q '"discovery scans the directory anyway"' &&
  echo "$agent_rules_form" | grep -q 'a missing line is an agent that is simply not there in any session' &&
  ! echo "$agent_rules_form" | grep -q 'Add an agent, add its line'; then
  ok "the declare-every-agent rule is a priced prohibition quoting its excuse"
else
  no "the declare-every-agent rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 7: .claude/rules/agents.md, A-7/R-7, row 1 — making a page here the
# only home of a rule that binds a run is a priced prohibition quoting its
# excuse (failure class: a rule skipped under pressure). Break: restore "It
# may never be the only home of a rule that binds a run".
if echo "$agent_rules_form" | grep -q 'Never make a page here the only home of a rule that binds a run' &&
  echo "$agent_rules_form" | grep -q '"whoever works here will read it"' &&
  echo "$agent_rules_form" | grep -q 'binds nobody in the one place it had to' &&
  ! echo "$agent_rules_form" | grep -q 'It may never be the only home of a rule that binds a run'; then
  ok "the only-home rule is a priced prohibition quoting its excuse"
else
  no "the only-home rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 8: .claude/rules/agents.md, A-8/R-8, row 1 — editing one copy without
# editing the other is a priced prohibition quoting its excuse (failure
# class: a rule skipped under pressure). Break: restore "Edit one, edit the
# other."
if echo "$agent_rules_form" | grep -q 'Never edit one copy without editing the other' &&
  echo "$agent_rules_form" | grep -q '"the other one can follow later"' &&
  echo "$agent_rules_form" | grep -q 'runs the session and the agents on different rules' &&
  ! echo "$agent_rules_form" | grep -q 'Edit one, edit the other'; then
  ok "the edit-both-copies rule is a priced prohibition quoting its excuse"
else
  no "the edit-both-copies rule still reads as an unpriced reminder, present or bolted on"
fi

# Case 9: .claude/rules/agents.md, A-9 + A-11/R-9, row 4 — the page's one
# exemption clause, re-cut on an observable predicate with each branch
# stated on its own (failure class: an exemption clause). Break, two
# directions: restore "restates nothing the shared brief already says",
# caught by the first absence assertion; or restore "The one exception opens
# every page", caught by the second. Each branch is asserted separately, so
# folding the two back into a general rule plus an exception goes red even
# if the words survive.
if echo "$agent_rules_form" | grep -q 'whether that sentence still has to work when the brief did not load' &&
  echo "$agent_rules_form" | grep -q 'stands in the brief alone' &&
  echo "$agent_rules_form" | grep -q 'stands on the page, and one sentence meets that' &&
  echo "$agent_rules_form" | grep -q 'report the shared brief as missing and stop' &&
  ! echo "$agent_rules_form" | grep -q 'restates nothing the shared brief already says' &&
  ! echo "$agent_rules_form" | grep -q 'The one exception opens every page'; then
  ok "the brief-restating rule is keyed to an observable predicate, with each branch stated on its own"
else
  no "the brief-restating rule still reads as a general rule plus an exception, present or bolted on"
fi

# Case 10: .claude/rules/agents.md, A-12/R-10, row 4 — the model-tier rule
# states each branch on its own; the true branch is a permission, not an
# obligation (failure class: an exemption clause). Break: restore "name a
# tier only for an agent whose work is mechanical enough that a smaller one
# cannot get it wrong" (the pre-branch exemption) or "`model` names that
# tier and the page says why" (the round-0 wording this round replaces,
# which turned the permission into an obligation). Both branches are
# asserted separately, so folding them back onto one semicolon goes red, and
# the second absence marker alone pins the modality.
if echo "$agent_rules_form" | grep -q '`model` is left out, so the agent runs on the session' &&
  echo "$agent_rules_form" | grep -q 'is mechanical enough that a smaller model cannot get it wrong, its page may name that tier' &&
  echo "$agent_rules_form" | grep -q 'a page that names one says why' &&
  ! echo "$agent_rules_form" | grep -q 'name a tier only for an agent whose work' &&
  ! echo "$agent_rules_form" | grep -q '`model` names that tier and the page says why'; then
  ok "the model-tier rule states each branch on its own"
else
  no "the model-tier rule still folds both branches onto one semicolon, present or bolted on"
fi

# Case 11: .claude/rules/agents.md, A-13/R-11, row 3 — the agent page's body
# is a recipe, not prose (failure class: an omitted required element asked
# for in prose). Break: restore "does not already cover: the role, how it
# works" (the pre-branch prose) or "does not already cover, a section per
# slot and no slot empty" (the round-0 wording this round replaces).
if echo "$agent_rules_form" | grep -q 'does not already cover, every slot filled' &&
  echo "$agent_rules_form" | grep -q 'the boundaries that belong to it alone; the shape of its report' &&
  ! echo "$agent_rules_form" | grep -q 'does not already cover: the role, how it works' &&
  ! echo "$agent_rules_form" | grep -q 'does not already cover, a section per slot'; then
  ok "the agent-page body is a slot recipe, not prose"
else
  no "the agent-page body still reads as prose"
fi

# Case 12: .claude/rules/agents.md, A-14/R-12, row 3 — the two boundaries are
# slots, not prose (failure class: an omitted required element asked for in
# prose). Break: restore "So state both explicitly". The third marker is the
# price the rewrite keeps.
if echo "$agent_rules_form" | grep -q 'The boundaries slot carries both and leaves neither empty' &&
  echo "$agent_rules_form" | grep -q 'what the agent does not get; what it may not do' &&
  echo "$agent_rules_form" | grep -q 'An omission here becomes a leak in every run' &&
  ! echo "$agent_rules_form" | grep -q 'So state both explicitly'; then
  ok "the two boundaries are slots, not prose"
else
  no "the two boundaries still read as prose, or have dropped the price"
fi

# Case 13: .claude/rules/agents.md, A-15a/R-13, row 1 — handing a role a tool
# its work does not need is a priced prohibition quoting its excuse (failure
# class: a rule skipped under pressure). Break: restore "a read-only role
# gets no writing tools" as the whole rule. The second presence marker is
# the requirement carried into the new rule word for word, asserted so a
# rewrite that leaves it only in the price goes red.
if echo "$agent_rules_form" | grep -q 'Never hand a role a tool its work does not need' &&
  echo "$agent_rules_form" | grep -q 'never hand a read-only role a writing tool' &&
  echo "$agent_rules_form" | grep -q '"it may as well have it in case"' &&
  echo "$agent_rules_form" | grep -q 'the boundary the page declared is gone from that run on' &&
  ! echo "$agent_rules_form" | grep -q 'a read-only role gets no writing tools'; then
  ok "the narrow-tool-list rule is a priced prohibition quoting its excuse"
else
  no "the narrow-tool-list rule still reads as an unpriced reminder, present or bolted on, or has dropped the read-only requirement"
fi

# Case 14: .claude/rules/agents.md, A-15b/R-14, row 1 — handing an agent a
# path beyond its directory is a priced prohibition quoting its excuse
# (failure class: a rule skipped under pressure). Break: restore "and hand
# it no path beyond that directory". The fourth marker is the requirement
# the rewrite keeps.
if echo "$agent_rules_form" | grep -q 'Never hand it a path beyond that directory' &&
  echo "$agent_rules_form" | grep -q '"one path saves it a search"' &&
  echo "$agent_rules_form" | grep -q 'reads what its role was never given' &&
  echo "$agent_rules_form" | grep -q 'finds what it needs in the run state, `backlog.json`' &&
  ! echo "$agent_rules_form" | grep -q 'and hand it no path beyond that directory'; then
  ok "the no-path-beyond-the-issue-directory rule is a priced prohibition quoting its excuse"
else
  no "the no-path-beyond-the-issue-directory rule still reads as an unpriced reminder, present or bolted on, or has dropped the backlog.json requirement"
fi

# Case 15: neither page carries vocabulary another page owns — the fast,
# named signal for a failure that the pre-existing ownership cases at lines
# 2419, 2431 and 2626 would otherwise report as an unexplained ownership
# drift, since all three include these two pages in their file sets. Break:
# word any of the fourteen replacements with a word another page owns — for
# instance pricing R-4 with "the rationalisation it counters", or writing
# R-2 as "the description names the occasion". Read the two pages directly,
# no collapsing needed. "probe" and "rulebook" are deliberately NOT in the
# alternation, because .claude/rules/agents.md already carries both.
case15_words='occasion|exemption clause|rationalisation|chain depth|counts as tested|dependency footprint'
case15_ok=true
case15_report=""
for case15_file in skills/CLAUDE.md .claude/rules/agents.md; do
  case15_hits="$(grep -inE "$case15_words" "$root/$case15_file" || true)"
  if [ -n "$case15_hits" ]; then
    case15_ok=false
    case15_report="${case15_report}${case15_file}:
$case15_hits
"
  fi
done
if $case15_ok; then
  ok "the two pages carrying the authoring rules carry no vocabulary another page owns"
else
  no "the two pages carrying the authoring rules carry vocabulary another page owns:"
  echo "$case15_report" | sed 's/^/       /'
fi

# Case 16: no comment or document elsewhere in the repository still quotes a
# sentence these rewrites replaced. Break: leave one of the replaced
# sentences quoted in hooks/read-barrier.mjs's RULES table, in a CLAUDE.md,
# or on any page. Nothing quotes them today, so the case starts green and
# catches a re-introduction. The two rewritten pages are deliberately inside
# the search: after the rewrite they must not carry the old wording either.
# test-repo.sh is excluded because its own absence markers above quote those
# fragments, and docs/issues is excluded because the plan and the backlog
# quote them too.
case16_fragments='Add an agent, add its line|a read-only role gets no writing tools|The one exception opens every page|nothing in it may hard-code a path|point at the owner instead of restating it'
case16_hits="$(grep -rnE "$case16_fragments" "$root" \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=issues \
  --exclude=test-repo.sh 2>/dev/null || true)"
if [ -z "$case16_hits" ]; then
  ok "no comment or document still quotes a sentence these rewrites replaced"
else
  no "these files still quote a sentence these rewrites replaced:"
  echo "$case16_hits" | sed "s|^$root/|       |"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "PASS: $passed cases"
else
  echo "FAIL: $failed of $((passed + failed)) cases"
  exit 1
fi
