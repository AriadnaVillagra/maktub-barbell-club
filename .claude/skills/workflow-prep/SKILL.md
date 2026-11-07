---
name: workflow-prep
description: The conception stage of a piece of work, establishing what is true today, what is being asked for, and whether the work should proceed at all. Use when a feature, problem, metric or improvement is first raised, before any design or planning begins.
argument-hint: <what you want to change>
user-invocable: true
---

# Skill: Workflow Prep

Establish the gap between the current state of the project and the state the request describes, size it roughly, and either leave a researched starting position on record or resolve the request as work that will not be executed.

**Assumed input:** A statement of intent. It says what someone wants to be true and nothing reliable about what has to change.

**Produces:** An item folder holding the item document and a findings document, a no-op resolution, or an account of what blocked the research where a gate question could not be answered.

---

## Parameters

Resolve before doing anything else. Resolve silently from project context where it establishes them, and ask only on genuine absence.

- **`WORKFLOW_POLICY`** — the project's work policy document, defining the magnitude scale, the artifact model, the naming scheme and the progress model. Follow its links; it may be a set. If unset, ask for it. If the project has no such model, say so and stop.
- **Proposed-work location** and **active-work location** — resolve from the policy. Ask if it does not establish them.
- **Technical debt register** — resolve from project context. If the project has none, blocking debt is reported as prose instead.
- **Documentation root** and **design intent location** — resolve from project context.
- **Item naming convention** — how a unit of work is named in this project. Resolve from the policy's naming scheme. If the scheme names only the documents inside an item and not the item itself, ask once.
- **`WORKFLOW_FANOUT`** — whether research and authoring may be delegated to subagents. If unset, ask once and store it alongside `WORKFLOW_POLICY`, wherever that resolves from. Treat any value other than an explicit refusal as permission.

Choose every subagent's model by what it costs to be wrong, not by how much text it produces. Work whose errors surface at the next gate takes the cheapest model that can do it. Work whose errors propagate into everything derived from it takes a stronger one. State the model chosen when dispatching, so the choice is reviewable.

---

## Phase 1 — Intake

Gather only what is needed to know what to search for.

1. Record the stated intent close to as given. Do not refine it, do not improve it, do not propose a solution shape.
2. Ask whether existing material is being worked from: a proposed item, a debt entry, a design document, a prior discussion.
3. Ask at most what is needed to make the request searchable, for example which application or system it concerns when the phrasing does not say.

Existing material is a starting point, never a resumption, and is re-checked in Phase 2 like anything else.

---

## Phase 2 — Research

Read until the gate questions below are answered with file-level evidence, then stop. Answering them from three files is a complete Phase 2.

**The gate questions:**

1. **Does this already exist?** Search for what was described. If found, is it the right shape, and does it satisfy the stated need? A yes is a no-op candidate.
2. **What does this depend on that the project does not have?** Name the missing foundation, if any, in terms of what exists today.
3. **Is there a clear starting point?** A change with no identifiable first point of contact with the material it changes is not ready. Material is whatever the work delivers in; the policy's scale does not privilege code over content, documentation or a prototype.
4. **Can this work be named confidently?** Produce a name under the item naming convention. If the name will not come, research is not finished.

**Sweeps, in parallel with the above:**

- The proposed-work location and the active-work location, for work that touches this. Report every kind of relation found, not only an exact match: the same work already proposed, partial overlap, a prerequisite that must land first, something this would block. There may be several.
- The technical debt register, for entries that obstruct the change.
- The documentation root and design intent location, for stated intent this change would contradict or fulfil.

**Fan-out.** Run the sweeps directly; they are a search over known locations, not delegated. Where fan-out is permitted, delegate the code research as two separate dispatches: locating what exists and where it lives on the cheapest model, judging whether it is the right shape and satisfies the need on a stronger one. Where fan-out is not permitted, run the research in the main conversation and keep reading narrow.

Do not begin designing a solution.

---

## Phase 3 — Checkpoint

Present, in the conversation and not yet on disk:

1. **Current state**, with the evidence behind it. Cite files.
2. **The gap** between that and what was asked for.
3. **Whatever was found** in the sweeps, by relation.
4. **A preliminary magnitude**, stated as preliminary and taken as the smallest that fits.
5. **The proposed name.** Check it first against what the sweeps already returned from the two work locations, and against anything else the project uses to name work in progress.

Where Phase 2 found a missing foundation, ask the question that decides the outcome: **is closing that gap part of this work?** A yes usually raises the magnitude. A no makes this a no-op blocked on the foundation.

If a gate question could not be answered, say which and stop. Produce a short account for the developer to take to whoever can resolve it, carrying the evidence the research did establish, not only the obstruction's name. Create no folder.

State which phase follows and why. A preliminary magnitude of no-op goes to Phase 4b, naming which of the policy's no-op conditions was reached; any other magnitude goes to Phase 4a. Where the research supports a no-op but the developer's account does not, say so and let them decide.

Wait for the developer to confirm or correct before Phase 4.

---

## Phase 4a — The work proceeds

Create the item folder in the active-work location, under the confirmed name, and write the two artifacts the artifact model assigns to conception, under the names it gives them:

- **The item document** — the name, the preliminary magnitude, and what the work is for. Nothing that will change while the work is carried out.
- **The findings document** — the evidenced current state, the stated intent as given, the gap, everything the sweeps returned, and known blockers named the way the progress model names causes outside an item. Written to be read cold by someone who was not present for the research.

Write nothing else. Not the design, not any level of the breakdown, not the tracker, and not the workspace implementation would happen in.

---

## Phase 4b — The work is a no-op

Nothing has been written to disk at this point.

Resolve against the no-op condition named at the checkpoint, producing every artifact the policy prescribes for that condition and no others. A condition may call for more than one.

Whatever the condition:

- A resolution that references something already existing, whether proposed work, a debt entry or a dependency, names it by its identifier rather than restating it.
- A new technical debt register entry follows the fan-out preference: delegate to a subagent on a stronger model, since the entry outlives the item and is read by people without this context, or write it in place. Either way it is the last thing Prep does.
- An account for the developer to carry to their team is evidenced, not impressionistic.

Where the policy's resolution is work that needs no further sizing, write it against the location that kind of material belongs in. Otherwise produce a brief summary for the developer to stage in the proposed-work location, and do not move it there.

Where an item folder already exists from earlier work on this request, tell the developer it is no longer needed once the material has been distilled into the resolution, and leave its removal to them.

---

## Boundaries

- Prep establishes what is true now and whether to proceed. Do not interrogate the desired change.
- Prep never moves work between the proposed and active locations, and never decides that work is or is not being taken up.
- When an item comes back with a specific gap named in its findings, re-enter at Phase 2 against that gap alone. Do not restart intake.
