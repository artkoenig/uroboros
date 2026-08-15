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
  'MARKER-RULING-CUT',
  'MARKER-RULING-PLAN',
  'MARKER-RULING-TESTS',
  'MARKER-RULING-BUILD',
  'MARKER-RULING-VERDICT',
  'MARKER-RULING-CLOSE',
  'MARKER-RULING-RESUMED',
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
  questions: [],
  summary: 'plan summary',
};
const planReturnWithQuestion = Object.assign({}, planReturn, { questions: ['ask the human'] });
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
  } else if (mode === 'w3') {
    assertEqualArrays(labels, ['load-state', 'publish'], 'a fully-closed backlog dispatches more than the state loader and publish');
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
  run_driver "$wf" w6 "$wf_name: the reviewer's prompt carries the checks alone"
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
if [ "$failed" -eq 0 ]; then
  echo "PASS: $passed cases"
else
  echo "FAIL: $failed of $((passed + failed)) cases"
  exit 1
fi
