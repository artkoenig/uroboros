---
name: retro
description: Session retrospective from a Claude Code or Gemini/Antigravity session log. Reach for it when a run is finished and someone asks what to learn from it — which rules created friction, where the tokens and the context went, what to automate next. What it hands back is a retrospective in the run's own issue document; measuring a session while it is still running is `argus`'s instead.
user-invocable: true
---

# Retro Skill

Generate a structured English session retrospective for an issue based on Claude Code or Gemini/Antigravity session logs.

## Instructions

When invoked to run a retro for an issue, follow these steps:

1. **Locate the session log file:**
   Where the caller named a log file, parse that one. Where the caller named none, run `bin/parse-agent-log --latest` and parse the file it names.

2. **Extract data:**
   Execute `bin/parse-agent-log <path> --format all` to extract quantitative metrics (tokens, tool calls, errors, thinking blocks) and the transcript markdown.

   Never go looking for a prose report of the run — not "there must be a
   summary somewhere": no agent writes one, and the search spends the retro's
   context before it has read a single metric. A run leaves the session log,
   the issue directory's `backlog.json` and the git history, and those are the
   whole record.

3. **Synthesize the English Retro:**
   Analyze the parsed data and transcript to synthesize a retrospective answering these 10 core workflow questions across 5 categories in English:

   - **Rulebook & Process Friction**
     - Which process rule or automated hook created disproportionate friction?
     - Where did the agent apply rules too rigidly or incorrectly, causing unnecessary overhead?

   - **Subagent Efficiency & Delegation**
     - Did delegating to subagents conserve context, or was the briefing overhead larger than the gain?
     - Were there redundancies or repeated research between the main conversation and subagent runs?

   - **Specification & Planning Quality**
     - Were all critical requirement gaps uncovered upfront during grilling/specifying, or did ambiguities surface late during implementation?
     - Was the architecture plan strictly followed, or were there unauthorized deviations?

   - **Token & Latency Optimization**
     - Where did token spikes, redundant tool loops, or uncompacted outputs occur?
     - How efficient was context cache utilization across steps?

   - **Tooling & Automation Opportunities**
     - Which recurring manual steps should be encapsulated into dedicated CLI tools or scripts?
     - Which errors were caused by missing environment pre-requisites before test execution?

   The retrospective carries these three as well, a section per slot and no slot empty:

   - **Session Metrics Summary** — a table.
   - **Per-Agent Breakdown** — a table, the main agent against each subagent.
   - **Mermaid Sequence Diagram** — the interaction flow between User, Main Agent, Subagents and Tools/System.

4. **Append the formatted section:**
   Append the formatted Retrospective section directly under the `## Retro` heading in the active issue document (e.g. at `docs/issues/<timestamp>-<slug>/issue.md`). Where the document has no such heading yet, add it at the end of the file first.

## What it is not

Not a live measurement: it reads logs after the fact, and what a session costs
while it runs is the `argus` skill's. Not a review of the change either — it
judges the process that produced the change, never the change itself.

