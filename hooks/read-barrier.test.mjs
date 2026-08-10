import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The hook under test. Resolved relative to this file so the suite runs the
// same way from a checkout and from a plugin cache.
const hook = fileURLToPath(new URL('./read-barrier.mjs', import.meta.url));

// A fixed issue directory, used by every case that needs a gated file. The
// event's cwd is '/repo', so a case can hand either the absolute path below
// or the path relative to it and mean the same file.
const ISSUE = '/repo/docs/issues/2026-01-01-a-thing/issue.md';
const STATE = '/repo/docs/issues/2026-01-01-a-thing/backlog.json';

// Spawns the hook the way Claude Code does — the event as JSON on stdin — and
// resolves to { code, stdout, stderr }. `input` goes in verbatim when it is a
// string, so a case can hand it something that is not JSON at all. No `env`
// argument: the hook reads no environment.
function runHook(input) {
  const child = spawn(hook, [], { stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  child.stdin.end(typeof input === 'string' ? input : JSON.stringify(input));
  return new Promise((resolve) => {
    child.on('exit', (code) => resolve({ code, stdout, stderr }));
  });
}

// A well-formed PreToolUse payload, common fields included. Defaults to the
// implementer running a Bash call with an empty command, so a case that only
// needs to change one field can spread a single override.
function event(extra = {}) {
  return {
    session_id: 'session-1',
    transcript_path: '/dev/null',
    cwd: '/repo',
    permission_mode: 'default',
    agent_id: 'agent-7',
    agent_type: 'uroboros:implementer',
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: {},
    tool_use_id: 'toolu_1',
    ...extra,
  };
}

const readOf = (agentType, filePath) =>
  event({ agent_type: agentType, tool_name: 'Read', tool_input: { file_path: filePath } });

const bashOf = (agentType, command) =>
  event({ agent_type: agentType, tool_name: 'Bash', tool_input: { command } });

const grepOf = (agentType, targetPath) =>
  event({ agent_type: agentType, tool_name: 'Grep', tool_input: { path: targetPath } });

// The command line the helper is really invoked with. The plugin cache path
// varies in reality, which is exactly why the hook must find the helper by
// basename rather than by this exact prefix.
const helper = (args) => `node "/plugins/uroboros/skills/agent-brief/assets/backlog.mjs" ${args}`;

function allows(result, context) {
  const prefix = context ? `${context}: ` : '';
  assert.equal(result.code, 0, `${prefix}a pass exits 0`);
  assert.equal(result.stdout, '', `${prefix}a pass prints nothing on stdout`);
}

function denies(result, ...substrings) {
  assert.equal(result.code, 0, 'a refusal is still an exit 0 — the JSON on stdout carries the deny, not the exit code');
  let decision;
  assert.doesNotThrow(() => { decision = JSON.parse(result.stdout); }, `a deny must be JSON on stdout, got: ${result.stdout}`);
  assert.equal(decision.hookSpecificOutput.hookEventName, 'PreToolUse');
  assert.equal(decision.hookSpecificOutput.permissionDecision, 'deny');
  for (const s of substrings) {
    assert.ok(
      decision.hookSpecificOutput.permissionDecisionReason.includes(s),
      `the reason "${decision.hookSpecificOutput.permissionDecisionReason}" must name "${s}"`,
    );
  }
}

// The cases below run in the order the hook's own gates do: the roles and
// their files first, then the fields, then everything that passes, then the
// shape of the refusal and the exit code.

test('a Read of the issue file by the implementer is refused, and the reason names the file and the page', async () => {
  const result = await runHook(readOf('uroboros:implementer', ISSUE));
  denies(result, ISSUE, 'agents/implementer.md');
});

test('a cat of the issue file is refused like the Read, with the relative path resolved against the event cwd', async () => {
  const result = await runHook(bashOf('uroboros:implementer', 'cat docs/issues/2026-01-01-a-thing/issue.md'));
  denies(result, 'issue.md');
});

test('the researcher reading the same issue file passes', async () => {
  const result = await runHook(readOf('uroboros:researcher', ISSUE));
  allows(result);
});

test('the test-author reading the same issue file passes', async () => {
  const result = await runHook(readOf('uroboros:test-author', ISSUE));
  allows(result, "its page sends it there");
});

test('the reviewer is refused every reading subcommand of the helper on the run state', async () => {
  const subcommands = [
    { sub: 'index', args: `index ${STATE}` },
    { sub: 'steps', args: `steps ${STATE} i1 research:i1.0 --fields findings` },
    { sub: 'codemap', args: `codemap ${STATE}` },
    { sub: 'read', args: `read ${STATE}` },
  ];
  for (const { sub, args } of subcommands) {
    const result = await runHook(bashOf('uroboros:reviewer', helper(args)));
    try {
      denies(result, STATE, 'agents/reviewer.md');
    } catch (err) {
      err.message = `subcommand "${sub}": ${err.message}`;
      throw err;
    }
  }
});

test("the reviewer's own start and record on the run state pass — the gate is on reads, not writes", async () => {
  const start = await runHook(bashOf('uroboros:reviewer', helper(`start ${STATE} i1 review:i1.0 /tmp/p.txt`)));
  allows(start, 'start');
  const record = await runHook(bashOf('uroboros:reviewer', helper(`record ${STATE} i1 review:i1.0 /tmp/r.json /tmp/p.txt`)));
  allows(record, 'record');
});

test('a cat of the run state by the reviewer is refused', async () => {
  const result = await runHook(bashOf('uroboros:reviewer', `cat ${STATE}`));
  denies(result, STATE, 'agents/reviewer.md');
});

test('a git show of the run state at a revision by the reviewer is refused', async () => {
  const result = await runHook(bashOf('uroboros:reviewer', `git show origin/main:docs/issues/2026-01-01-a-thing/backlog.json`));
  denies(result, 'backlog.json', 'agents/reviewer.md');
});

test('staging and committing the run state by the reviewer passes', async () => {
  const result = await runHook(bashOf('uroboros:reviewer', `git add ${STATE} && git commit -m "record the review"`));
  allows(result);
});

test('a Grep whose path is the run state is refused for the reviewer, and one on a source file passes', async () => {
  const denied = await runHook(grepOf('uroboros:reviewer', STATE));
  denies(denied, STATE, 'agents/reviewer.md');
  const allowed = await runHook(grepOf('uroboros:reviewer', '/repo/hooks/read-barrier.mjs'));
  allows(allowed, 'a grep of an unrelated source file');
});

test("the implementer running the helper's index on the run state passes — only the reviewer's page closes that file", async () => {
  const result = await runHook(bashOf('uroboros:implementer', helper(`index ${STATE}`)));
  allows(result);
});

test("the test-author asking for the researcher's plan field is refused, and the reason names the field and the page", async () => {
  const result = await runHook(bashOf('uroboros:test-author', helper(`steps ${STATE} i1 research:i1.0 --fields plan`)));
  denies(result, 'plan', 'agents/test-author.md');
});

test('the test-author asking for the test plan alone passes', async () => {
  const result = await runHook(bashOf('uroboros:test-author', helper(`steps ${STATE} i1 research:i1.0 --fields testPlan`)));
  allows(result);
});

test('a forbidden field anywhere in the list is refused', async () => {
  const result = await runHook(bashOf('uroboros:test-author', helper(`steps ${STATE} i1 research:i1.0 --fields testPlan,plan`)));
  denies(result, 'plan', 'agents/test-author.md');
});

test('the implementer asking for the test plan is refused, and the three fields its page names pass', async () => {
  const denied = await runHook(bashOf('uroboros:implementer', helper(`steps ${STATE} i1 research:i1.0 --fields testPlan`)));
  denies(denied, 'agents/implementer.md');
  const allowed = await runHook(bashOf('uroboros:implementer', helper(`steps ${STATE} i1 research:i1.0 --fields plan,moduleMap,environment`)));
  allows(allowed, 'the three fields the implementer\'s page names');
});

test('a steps call with no --fields by a role with a closed field is refused, and the reason names --fields', async () => {
  const result = await runHook(bashOf('uroboros:test-author', helper(`steps ${STATE} i1 research:i1.0`)));
  denies(result, '--fields', 'agents/test-author.md');
});

test('a steps call with no --fields by the planner passes — no field is closed to it', async () => {
  const result = await runHook(bashOf('uroboros:planner', helper(`steps ${STATE} i1`)));
  allows(result);
});

test('which step a prompt named is not in the payload, so the label never decides', async () => {
  const first = await runHook(bashOf('uroboros:implementer', helper(`steps ${STATE} i1 research:i1.0 --fields plan,moduleMap,environment`)));
  allows(first, 'research:i1.0 with the implementer\'s own fields');
  const second = await runHook(bashOf('uroboros:implementer', helper(`steps ${STATE} i1 review:i1.0 --fields findings`)));
  allows(second, 'review:i1.0 with a field on no list');
});

test("a field on no page's list passes for every gated role", async () => {
  const implementer = await runHook(bashOf('uroboros:implementer', helper(`steps ${STATE} i1 research:i1.0 --fields cases`)));
  allows(implementer, 'implementer, --fields cases');
  const testAuthor = await runHook(bashOf('uroboros:test-author', helper(`steps ${STATE} i1 research:i1.0 --fields openQuestions`)));
  allows(testAuthor, 'test-author, --fields openQuestions');
});

test('an event with no agent_type passes without a word', async () => {
  const input = readOf('uroboros:implementer', ISSUE);
  delete input.agent_type;
  const result = await runHook(input);
  allows(result);
  assert.equal(result.stderr, '', 'an event with no agent_type is not a uroboros agent, so nothing is worth saying about it');
});

test("the state loader's general-purpose read of the index passes without a word", async () => {
  const result = await runHook(bashOf('general-purpose', helper(`index ${STATE}`)));
  allows(result);
  assert.equal(result.stderr, '', 'general-purpose is not one of the three gated agent_type values');
});

test("an agent type that is not uroboros's passes without a word", async () => {
  const foreign = await runHook(readOf('Explore', ISSUE));
  allows(foreign, 'Explore');
  assert.equal(foreign.stderr, '', 'Explore is a foreign agent_type');
  const bareRole = await runHook(readOf('reviewer', STATE));
  allows(bareRole, 'bare role name "reviewer"');
  assert.equal(bareRole.stderr, '', 'the bare role name is not the uroboros:-prefixed agent_type the workflow dispatches with');
});

test('a tool the hook does not gate passes', async () => {
  const write = await runHook(event({ agent_type: 'uroboros:implementer', tool_name: 'Write', tool_input: { file_path: ISSUE } }));
  allows(write, 'Write');
  assert.equal(write.stderr, '', 'writes are not gated');
  const edit = await runHook(event({ agent_type: 'uroboros:implementer', tool_name: 'Edit', tool_input: { file_path: ISSUE } }));
  allows(edit, 'Edit');
  assert.equal(edit.stderr, '', 'writes are not gated');
});

test('a Bash call the hook cannot positively identify as a read passes', async () => {
  const nodeEval = await runHook(bashOf(
    'uroboros:implementer',
    `node -e "console.log(require('fs').readFileSync('docs/issues/2026-01-01-a-thing/issue.md','utf8'))"`,
  ));
  allows(nodeEval, 'node -e');
  const bashScript = await runHook(bashOf('uroboros:implementer', 'bash test.sh'));
  allows(bashScript, 'bash test.sh');
});

test('an input the hook cannot use passes and still exits 0', async () => {
  const withoutToolInput = event({ agent_type: 'uroboros:implementer' });
  delete withoutToolInput.tool_input;

  const table = [
    { name: 'empty stdin', input: '' },
    { name: 'not json at all', input: 'not json at all' },
    { name: '{} an empty object', input: '{}' },
    { name: '[] a JSON array, not an object', input: '[]' },
    { name: 'tool_input missing', input: withoutToolInput },
    { name: 'tool_input: null', input: event({ agent_type: 'uroboros:implementer', tool_input: null }) },
    {
      name: 'tool_input.command a number, not a string',
      input: event({ agent_type: 'uroboros:implementer', tool_name: 'Bash', tool_input: { command: 12345 } }),
    },
    {
      name: 'tool_input.file_path an array, not a string',
      input: event({ agent_type: 'uroboros:implementer', tool_name: 'Read', tool_input: { file_path: ['a', 'b'] } }),
    },
  ];

  for (const { name, input } of table) {
    const result = await runHook(input);
    try {
      allows(result);
    } catch (err) {
      err.message = `entry "${name}": ${err.message}`;
      throw err;
    }
  }
});

test('a refusal is a PreToolUse deny decision on stdout and nothing else, and the process still exits 0', async () => {
  const result = await runHook(readOf('uroboros:implementer', ISSUE));
  assert.equal(result.code, 0, 'the exit code stays 0 whether the hook allows or denies');
  const decision = JSON.parse(result.stdout);
  assert.deepEqual(Object.keys(decision), ['hookSpecificOutput'], 'nothing besides the documented envelope is on stdout');
  const out = decision.hookSpecificOutput;
  assert.deepEqual(
    Object.keys(out).sort(),
    ['hookEventName', 'permissionDecision', 'permissionDecisionReason'].sort(),
    'exactly the three documented fields, nothing more',
  );
  assert.equal(out.hookEventName, 'PreToolUse');
  assert.equal(out.permissionDecision, 'deny');
  assert.equal(typeof out.permissionDecisionReason, 'string');
  assert.ok(out.permissionDecisionReason.length > 0, 'a deny with no reason gives the agent nothing to correct');
});
