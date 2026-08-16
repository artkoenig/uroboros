# Increment branches never reach the remote

## Problem

The environment the loop runs in refuses remote branch deletions. A push that
creates a branch succeeds; `git push origin --delete <branch>` and its
`git push origin :<branch>` form both fail with

```
error: RPC failed; HTTP 403 curl 22 The requested URL returned error: 403
send-pack: unexpected disconnect while reading sideband packet
```

The 403 comes from the session's egress proxy, not from git and not from the
credentials, and a 403 there is an organisation policy denial that no retry
resolves. The GitHub MCP server offers no second route: it has `create_branch`
and no counterpart to it.

Today the loop pushes every increment branch as the increment is worked, merges
an accepted one into the issue branch, and then tries to delete it from the
remote — `workflows/agile-loop.js:1356` in the replan prompt, and
`agents/planner.md:110` on the planner's own page. That delete can never
succeed here. The workflow prompt at least softens it ("A failed delete is a
line in your summary, not a blocker"), so the loop does not break; the planner's
page carries the same instruction with no such escape, so a planner working from
its page can spend a round on a call that is refused by policy. Either way every
accepted increment leaves a dead branch on the remote and an error in the log.

The delete only exists because the branch was pushed. Nothing needs it there:
the increment branch is a working surface between the agents of one increment,
the issue branch is what the pull request is opened for, and the run state is
what a resume reads. So the fix is to stop pushing the increment branch at all
and to push the issue branch after each increment the planner lands — that keeps
the resume point on the remote and leaves exactly one branch per issue, which is
what the delete was trying to achieve.

One thing the research must settle first: the agents of an increment must be
able to see each other's local commits for this to work at all. If they share a
git directory — one checkout, or worktrees of it — a local branch is visible to
all of them and nothing has to be pushed. If instead each agent works from its
own clone, the pushes are load-bearing and this issue is a blocker to raise, not
something to route around by pushing anyway.

## Acceptance criteria

- [ ] No agent pushes an increment branch to the remote. Every agent working an
      increment commits to it locally and pushes nothing.
- [ ] The planner pushes the issue branch to the remote after each increment it
      lands, so the remote always holds every accepted increment up to that
      point.
- [ ] No agent and no workflow prompt asks for a remote branch deletion. The
      `git push origin --delete` instruction is gone from
      `workflows/agile-loop.js` and from `agents/planner.md`, and no other page
      asks for one.
- [ ] The run state a resume reads reaches the remote with the issue branch, so
      a run whose container dies resumes from every step recorded up to the last
      landed increment.
- [ ] A resumed run works the increments still open and does not redo an
      increment the run state records as closed.
- [ ] The reviewer still receives the increment's diff range and can read that
      diff, with the increment branch present only locally.
- [ ] An increment the review does not accept stays unmerged, exactly as it does
      today, and the note the planner closes with still names its branch. Its
      commits stay local and do not reach the remote.
- [ ] The run opens one pull request, for the issue branch, as it does today.

## Non-goals

- The delete is not replaced by another way of removing remote branches. There
  is none in this environment, and the change removes the need rather than the
  obstacle.
- Increment branches themselves stay. This changes where they live, not whether
  the loop cuts them.
- Branches already left on the remote by earlier runs are not cleaned up here.
