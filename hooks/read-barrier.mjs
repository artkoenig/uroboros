#!/usr/bin/env node
// ---------------------------------------------------------------------------
// The plugin's PreToolUse hook, and the mechanically visible shadow of three
// rules the agent pages already own: the implementer does not read `issue.md`,
// the reviewer does not read `backlog.json`, and no agent reads a field of a
// step that its own page does not grant it.
//
// It exists because those rules were honour-system. A page can say "you do not
// read this file" and be obeyed every time but the one that matters; a run
// where a role reads a document written for someone else is a run whose result
// nobody can trust, because the fresh context that was the whole point of the
// role was not fresh. So the pages keep the rules, and this refuses the call.
// Nothing here restates a rule — every entry in the table below cites the page
// it comes from, and moves when that page moves.
//
// It decides from the event payload alone: the `agent_type` and the tool
// input, nothing else. It opens no file, opens no connection and reads no
// environment variable. That is what makes it cheap enough to sit in front of
// every Read, every Bash call and every Grep of every agent, and it is also the
// honest position for a guard: a hook that read the state it guards would be
// guarding it by opening it.
//
// Every path exits 0. A refusal is the documented PreToolUse decision object
// on stdout — which is what lets the refusal reach the agent as a reason with a
// page to go and read, where a non-zero exit would only hand it a stderr blob
// and lose the reason. The exit code is therefore constant, and "if the hook
// itself breaks, every call goes through" is a property anyone can check.
//
// It fails open, deliberately and everywhere. A wrong refusal blocks an agent
// mid-run over a call its page allows, and costs a human the run; a wrong pass
// costs nothing that the pages did not already cost before this file existed.
// So only a positive identification refuses, and everything else is silent:
// an unparseable payload, an unknown agent, an ungated tool, a command this
// cannot classify, and the single catch around the whole of `main`.
//
// What it deliberately does not catch: `node -e` and `python -c`, because
// closing those means guessing at the content of arbitrary code; a `cd` into
// an issue directory before a `cat`, because tracking a shell's working
// directory across segments is guesswork; and any reader outside the list
// below. Those gaps are the price of never refusing wrongly.
//
// Zero dependencies, no build step: it runs from a checkout and from a plugin
// cache alike, so it hard-codes no path.
// ---------------------------------------------------------------------------
import path from 'node:path'

// The three gated roles, keyed on the exact `agent_type` the workflow
// dispatches with. The `uroboros:` prefix is load-bearing: a project that
// installs this plugin may have its own agent called `reviewer`, and gating
// that one would be a wrong refusal in somebody else's run.
//
// Every other agent type — the researcher, the planner, the state loader's
// `general-purpose`, the main conversation, anything foreign — is absent from
// this table on purpose, and an absent key is a silent pass.
const RULES = {
  // agents/implementer.md, "How you work" step 1: "Never open `issue.md`".
  // agents/researcher.md, on `testPlan`: "the implementer never sees it".
  'uroboros:implementer': {
    role: 'the implementer',
    page: 'agents/implementer.md',
    file: 'issue.md',
    fields: ['testPlan'],
    instead: 'Take what you need from the reads your prompt names.',
  },
  // agents/reviewer.md, "You never read `backlog.json`": "the helper's reading
  // subcommands are not yours".
  'uroboros:reviewer': {
    role: 'the reviewer',
    page: 'agents/reviewer.md',
    file: 'backlog.json',
    fields: [],
    instead:
      "Your prompt is your whole brief; recording your own step with the helper's start and record still works.",
  },
  // agents/test-author.md, "How you work" step 1: "take no other field of it —
  // the implementation plan is not yours".
  'uroboros:test-author': {
    role: 'the test-author',
    page: 'agents/test-author.md',
    file: null,
    fields: ['plan'],
    instead: 'Take what you need from the reads your prompt names.',
  },
}

// The tools a read can arrive through. Glob returns paths rather than content,
// and writes are somebody else's problem: this hook is about reading.
const GATED_TOOLS = new Set(['Read', 'Bash', 'Grep'])

// The two documents any of the rules above is about. A candidate path has to
// end in one of these *and* live under a `docs/issues/` directory before it
// counts — the basename alone would refuse an installing project's own
// unrelated `issue.md`, and `backlog.json.tmp`, the half-written file the
// recorder renames away, is not either of them.
const GATED_BASENAMES = new Set(['issue.md', 'backlog.json'])

// The backlog helper, found by the basename of whatever token names it: the
// plugin cache path it is really invoked under varies by installation, so the
// prefix is never worth matching.
const HELPER = 'backlog.mjs'
const HELPER_READS = new Set(['index', 'steps', 'codemap', 'read'])

// Commands that put a file's content in front of whoever ran them. A blunter
// rule — "any command that mentions the path" — would refuse the reviewer's own
// `git add <dir>/backlog.json` before its commit, which is the wrong refusal
// this whole file is arranged to avoid.
const READERS = new Set([
  'cat', 'head', 'tail', 'less', 'more', 'bat', 'nl', 'tac', 'od', 'xxd',
  'hexdump', 'strings', 'wc', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'sed',
  'awk', 'jq', 'cut', 'sort', 'uniq', 'diff', 'column',
])

// `git` alone is no reader — most of what an agent does with it is a write or
// a diff. These two subcommands print a file.
const GIT_READS = new Set(['show', 'cat-file'])

// Wrappers that stand in front of the real command without changing what it
// does.
const PREFIXES = new Set(['sudo', 'command', 'time'])

const SEPARATORS = new Set([';', '&&', '||', '|', '&'])

function readStdin() {
  return new Promise((resolve) => {
    let text = ''
    process.stdin.setEncoding('utf8')
    process.stdin.on('data', (chunk) => {
      text += chunk
    })
    process.stdin.on('end', () => resolve(text))
    process.stdin.on('error', () => resolve(text))
  })
}

// Waits for the decision to actually leave the process, so the `process.exit`
// at the end of the file cannot cut a refusal in half on its way down a pipe.
function emit(text) {
  return new Promise((resolve) => process.stdout.write(text, resolve))
}

// Splits a command line into words and shell operators, dropping the quotes
// that only bound a word. Enough of a shell to find a path in an argument
// list; not a shell, and not trying to be one — anything it misreads ends up
// unclassified, which is the passing side.
function tokenize(command) {
  const tokens = []
  let current = ''
  let open = false
  let quote = ''
  const flush = () => {
    if (open) tokens.push(current)
    current = ''
    open = false
  }
  for (let i = 0; i < command.length; i += 1) {
    const ch = command[i]
    if (quote) {
      if (ch === quote) quote = ''
      else current += ch
      open = true
      continue
    }
    if (ch === '"' || ch === "'") {
      quote = ch
      open = true
      continue
    }
    if (ch === '\\' && i + 1 < command.length) {
      current += command[i + 1]
      i += 1
      open = true
      continue
    }
    if (ch === ' ' || ch === '\t' || ch === '\r') {
      flush()
      continue
    }
    if (ch === '\n' || ch === ';') {
      flush()
      tokens.push(';')
      continue
    }
    if (ch === '&' || ch === '|') {
      flush()
      if (command[i + 1] === ch) {
        tokens.push(ch + ch)
        i += 1
      } else {
        tokens.push(ch)
      }
      continue
    }
    if (ch === '<' || ch === '>') {
      flush()
      tokens.push(ch)
      continue
    }
    current += ch
    open = true
  }
  flush()
  return tokens
}

// One command line becomes the list of commands the shell would actually run,
// each classified on its own. `a && b`, `a | b` and a two-line heredoc-free
// script all reach here as separate segments.
function segmentsOf(tokens) {
  const segments = []
  let current = []
  for (const token of tokens) {
    if (SEPARATORS.has(token)) {
      if (current.length) segments.push(current)
      current = []
      continue
    }
    current.push(token)
  }
  if (current.length) segments.push(current)
  return segments
}

// Pulls the redirects out of a segment: `< path` is a read of `path`, `> path`
// is a write and its operand is not a candidate for anything.
function splitRedirects(segment) {
  const words = []
  const redirected = []
  for (let i = 0; i < segment.length; i += 1) {
    const token = segment[i]
    if (token === '<' || token === '>') {
      const operand = segment[i + 1]
      if (token === '<' && operand) redirected.push(operand)
      i += 1
      continue
    }
    words.push(token)
  }
  return { words, redirected }
}

// Drops the `VAR=value` assignments and the wrappers that can stand in front of
// the command that matters.
function stripPrefixes(words) {
  let start = 0
  while (start < words.length) {
    const word = words[start]
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(word) || PREFIXES.has(path.basename(word))) {
      start += 1
      continue
    }
    break
  }
  return words.slice(start)
}

// The value of `--fields`, in either shape the helper accepts, or null when the
// call names none at all — which asks for the whole step, the closed field
// with it.
function fieldsOf(words) {
  for (let i = 0; i < words.length; i += 1) {
    if (words[i] === '--fields') return (words[i + 1] || '').split(',').map((f) => f.trim()).filter(Boolean)
    if (words[i].startsWith('--fields=')) {
      return words[i].slice('--fields='.length).split(',').map((f) => f.trim()).filter(Boolean)
    }
  }
  return null
}

// What one command reads: the paths it puts in front of the agent, and — when
// it is the helper's `steps` — the fields it asks for. `fields: undefined`
// means this was no `steps` call at all; `fields: null` means it was one that
// named none.
function readsOfSegment(segment) {
  const { words, redirected } = splitRedirects(segment)
  const reads = { paths: [...redirected], fields: undefined }
  const command = stripPrefixes(words)
  if (!command.length) return reads

  const head = path.basename(command[0])

  // 1. The helper. Its reading subcommands hand back the run state; its writing
  //    ones are how an agent records its own step, and are no read at all.
  const helperAt = command.findIndex((word) => path.basename(word) === HELPER)
  if (head === 'node' && helperAt >= 0) {
    const subcommand = command[helperAt + 1]
    if (!HELPER_READS.has(subcommand)) return reads // a write, or nothing this knows
    const statePath = command[helperAt + 2]
    if (statePath && !statePath.startsWith('-')) reads.paths.push(statePath)
    if (subcommand === 'steps') reads.fields = fieldsOf(command.slice(helperAt + 2))
    return reads
  }

  // 2. A reader command. Every argument that is not a flag is a candidate path;
  //    `git show` takes its path after a revision and a colon.
  const isGit = head === 'git' && GIT_READS.has(command[1])
  if (!isGit && !READERS.has(head)) return reads // unclassified, and so allowed

  for (const word of command.slice(isGit ? 2 : 1)) {
    if (!word || word.startsWith('-')) continue
    reads.paths.push(isGit && word.includes(':') ? word.slice(word.lastIndexOf(':') + 1) : word)
  }
  return reads
}

// A candidate names the role's forbidden document when its basename is that
// document *and* it sits under a `docs/issues/` directory. Both halves are
// required: the basename alone would refuse an installing project's own
// unrelated `issue.md`, and resolving against the event's `cwd` — not this
// process's — is what makes a relative path mean what the agent meant.
function namesGatedFile(candidate, cwd, wanted) {
  if (!wanted || typeof candidate !== 'string' || !candidate) return false
  const resolved = path.resolve(cwd, candidate)
  if (path.basename(resolved) !== wanted || !GATED_BASENAMES.has(wanted)) return false
  const parts = resolved.split(path.sep)
  return parts.some((part, i) => part === 'docs' && parts[i + 1] === 'issues')
}

function denyReason(rule, subject, instead) {
  return `${rule.role} may not read ${subject} — ${rule.page} says so. ${instead}`
}

// The paths a tool input puts in front of the agent, as they appeared in it.
function candidatesFrom(toolName, toolInput) {
  if (toolName === 'Read') {
    return typeof toolInput.file_path === 'string' ? [{ paths: [toolInput.file_path] }] : []
  }
  if (toolName === 'Grep') {
    // A `path` that names a directory, or none at all, is not a positive
    // identification of anything — and the basename test below is what tells
    // the two apart without opening either.
    return typeof toolInput.path === 'string' ? [{ paths: [toolInput.path] }] : []
  }
  if (typeof toolInput.command !== 'string') return []
  return segmentsOf(tokenize(toolInput.command)).map(readsOfSegment)
}

async function main() {
  // Read before anything else: a hook that leaves its stdin unread can leave
  // the writer on the other end blocked on a full pipe.
  const raw = await readStdin()

  let event
  try {
    event = JSON.parse(raw)
  } catch {
    return // not JSON, and a guard that cannot read the call does not judge it
  }
  if (!event || typeof event !== 'object' || Array.isArray(event)) return

  // The gate that keeps this hook off almost everything: every call of the
  // main conversation, of the planner, of the researcher and of the state
  // loader ends here, before a tool name is even looked at.
  const rule = RULES[event.agent_type]
  if (!rule) return

  // The matcher in `hooks.json` already narrows this; this is the guarantee.
  if (!GATED_TOOLS.has(event.tool_name)) return

  const toolInput = event.tool_input
  if (!toolInput || typeof toolInput !== 'object' || Array.isArray(toolInput)) return

  const cwd = typeof event.cwd === 'string' && event.cwd ? event.cwd : process.cwd()

  for (const reads of candidatesFrom(event.tool_name, toolInput)) {
    for (const candidate of reads.paths || []) {
      if (namesGatedFile(candidate, cwd, rule.file)) {
        return emit(decision(denyReason(rule, candidate, rule.instead)))
      }
    }

    if (reads.fields === undefined || !rule.fields.length) continue

    // A label is never looked at: which steps and which fields a prompt named
    // is not in this payload, so the only thing worth asking is whether the
    // call would hand back a field the role's own page closes.
    if (reads.fields === null) {
      return emit(decision(denyReason(
        rule,
        'a step whole',
        'Name the fields your prompt gave you with --fields.',
      )))
    }
    const forbidden = reads.fields.find((field) => rule.fields.includes(field))
    if (forbidden) {
      return emit(decision(denyReason(
        rule,
        `the "${forbidden}" field of a step`,
        'Ask for only the fields your prompt named with --fields.',
      )))
    }
  }
}

// The documented PreToolUse decision object, and the only thing this hook ever
// prints. Silence is the pass.
function decision(reason) {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  })
}

// One catch for the whole of it, and it exits 0 like every other path: a hook
// that broke has to let the call through, not stop the run on its way out.
try {
  await main()
} catch {
  // Silent on purpose: stderr in front of an agent is something it has to
  // reason about, and there is nothing here worth reasoning about.
}
process.exit(0)
