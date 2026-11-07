---
name: workflow-execute
description: The execution stage of a piece of work, carrying refined issues to commits one task at a time, up to a merge ready for human review. Use once an item is broken down and its tracker exists, to work on it.
argument-hint: <item name>
user-invocable: true
---

# Skill: Workflow Execute

Carry a broken-down item forward by executing its issues, coordinated one task at a time. A task is the unit of a run: its issues are dispatched, in parallel where they are independent and in order where they are not, until the task is ready for a merge that a person reviews.

**Assumed input:** An item folder in the active-work location holding a progress tracker. If there is no tracker, the item has not been broken down; stop and report that, pointing at the breakdown stage.

**Produces:** Commits for the issues executed, a tracker kept true as they land, and one or more tasks brought to merge-ready. It never merges and never writes to `main`.

The tracker is the only source of what to do next. State is never reconstructed by reading the documents beneath an entry; that is the cost the tracker exists to remove.

---

## Parameters

Resolve these before doing anything else.

- **`WORKFLOW_POLICY`** — the project's work policy: the magnitude scale, the ladder, the artifact model, the naming scheme and the progress model. Follow its links. If unset, ask for it.
- **Active-work location**, **level definitions**, **tracker format**, **naming scheme** — all resolve from the policy.
- **The item folder path** — the active-work location plus the item name this skill was invoked on. Resolve it once, as an absolute path, and pass it to every subagent.
- **`WORKFLOW_FANOUT`** — whether issues may be executed by subagents. If unset, ask once. Anything short of an explicit refusal is permission. Without it, issues run one at a time in the main conversation.
- **Model and effort criteria** — the project or user context that says which model tier and effort a kind of change warrants. It governs how an issue's suggested model and effort is read and adjusted.
- **Isolation capability** — whether the environment can give a subagent its own worktree. This decides how independent issues may run concurrently. Determine it once.

---

## Phase 1 — Select the task

Open the tracker and nothing else. Walk it in numeric order and take the first **task** that is not blocked, is refined or in progress, and has at least one issue that is refined and blocked by nothing. That task is this run's unit.

If no such task exists, do not descend into documents to find work. Resolve why instead:

- The earliest open entry is a stub with nothing refined beneath it: the work is not broken down that far. Stop and defer to the breakdown stage.
- Every remaining entry is blocked: report the blockers, backward-pointing as the tracker records them, and stop.
- A story has all its tasks done and is pending review: stop. Story review is a human gate.
- Everything at the top level is done: report the item as complete and leave its disposal, which removes the folder, to a person.

---

## Phase 2 — Read the task

Read the task document. Its concurrency section is the authority on which issues may run together and which wait on a sibling; take it as given and never re-derive dependency from the issue bodies. That question was settled at breakdown by the one level that sees all the issues at once.

From the tracker, take the state of each issue under this task. The runnable set is the issues that are refined, blocked by nothing, and not waiting on a sibling still open. Read each runnable issue's suggested model and effort, and no more of it; the full body is read by whoever executes the issue, not by the coordinator, whose context stays lean.

---

## Phase 3 — Plan the wave

A wave is the runnable set that can start together right now.

For each issue in it, take its suggested model and effort as the starting point. Lower it on your own where the change is plainly cheaper than the recommendation, with a stated reason. Raise it only with the developer's decision, carrying the justification for the raise. State the model and effort chosen for each issue when presenting the wave.

Choose how the wave runs:

- Independent issues with isolation available run concurrently, each in its own worktree.
- Independent issues without isolation run concurrently only where their changes land on disjoint files; where they overlap, they run in order instead.
- Dependent issues run in order, each after its predecessor's commit is in.

Present the wave, its models and efforts, and its mode, and wait for authorization. Authorize per wave, not once for the task. A proposed raise is confirmed here or it does not happen.

---

## Phase 4 — Execute the wave

Mark each issue in progress in the tracker at the moment it is dispatched. The mark is the claim, and it precedes the work. The coordinator edits the tracker at every point; no subagent touches it.

One subagent per issue, clean context, at the chosen model and effort, in its worktree where the wave is isolated. Give it the item folder path, the issue document, its parent task document, and the naming scheme, and let it resolve the standing instructions the issue names, the build, run and instrumentation skills that govern the change. It executes that one issue and produces the commit its "what finishing means" defines: the clean build, the run and its output, the acceptance shown. It writes nothing outside its issue.

Each subagent returns whether finishing was met, the commit, and anything that blocked it.

- On success, mark the issue done. Then run the close sweep the progress model requires: remove the issue's name from every blocker list that cites it, and return each entry so freed to the state it held before it blocked.
- On a blocker, mark the issue blocked from in progress, record the cause backward-pointing on its entry, land or discard whatever is coherent, and carry on with the rest of the wave. A blocker is discovered by attempting the work; finding one is normal.

Where the wave was isolated, reconcile each returned commit onto the task branch as it lands.

**Promotion halts execution.** If an issue will not fit one commit, or the task will not fit one merge a reviewer can evaluate, stop. Land or discard what is coherent, report what does not fit, and defer to the magnitude and breakdown stages. Do not push through to a change nobody can review, and do not rename or amend anything already written.

---

## Phase 5 — Close the task or continue

Re-read the tracker after the wave. If the task now has a further runnable wave, a set that the just-landed commits unblocked, return to Phase 3 for it within the same task.

When every issue of the task is done, the task is merge-ready but not done: its merge is its review, and that merge is a person's. Present the task as merge-ready. A preparation pass over the branch, a cleanup or a simplification, may be offered here before review; it is a suggestion, not a step taken unasked.

Then stop. Taking up the next task is a fresh selection the developer authorizes, not a continuation assumed. Story review and item completion are human gates this skill does not cross.

---

## Boundaries

- Execution does not design, does not break down, and does not revise magnitude. It reports a stub, a blocker or an overflow, and stops.
- It never writes to `main`, by merge or by direct commit. It readies the branch and hands off.
- The coordinator owns every tracker edit, at claim, close, block and unblock. No subagent touches the tracker.
- State is read from the tracker, never reconstructed from the documents beneath it. Concurrency is read from the task, never re-derived.
- No wave runs past a gate the developer has not given.
