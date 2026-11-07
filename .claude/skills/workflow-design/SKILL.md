---
name: workflow-design
description: The design stage of a piece of work, shaping the desired state and what has to change to reach it. Use once the current state and the intent of a piece of work have been established and before the work is broken down.
argument-hint: <item name>
user-invocable: true
---

# Skill: Workflow Design

Turn a researched starting position into a settled design: what should be true when the work is done, what has to change to get there, and what accepting the work means. Or conclude that the work will not be executed.

**Assumed input:** An item folder in the active-work location holding an item document and an evidenced account of the current state, as the artifact model names them. If either is missing, say so and ask whether to proceed on the developer's own account or have it established first; their account then substitutes for the evidence throughout, and its claims enter Phase 3 to verify rather than as fact. Do not survey the project to replace it.

**Produces:** A design document in the item folder and a confirmed magnitude on the item document, or a no-op resolution.

---

## Parameters

Resolve before doing anything else.

- **`WORKFLOW_POLICY`** — the project's work policy document, defining the magnitude scale, the artifact model, the naming scheme and the progress model. Follow its links; it may be a set. If unset, ask for it.
- **Interrogation model** — the project's question families for design interrogation, and the required content of a design document. Resolve from the policy. If the policy does not establish the families, ask for them and do not substitute an improvised set.
- **Active-work location** and **proposed-work location** — resolve from the policy.
- **Design intent location** and **technical debt register** — resolve from project context.
- **The findings** — whatever the artifact model calls the evidenced account of the current state an item carries out of conception. Resolve its name from the model; it is referred to throughout as the findings.
- **Documentation writing standard** — resolve from project context, and follow it when writing the design document.
- **`WORKFLOW_FANOUT`** — whether research may be delegated to subagents. If unset, ask once and store it alongside `WORKFLOW_POLICY`, wherever that resolves from. Treat any value other than an explicit refusal as permission.

Choose every subagent's model by what it costs to be wrong, not by how much text it produces. Work whose errors surface at the next gate takes the cheapest model that can do it. Work whose errors propagate into everything derived from it takes a stronger one. State the model chosen when dispatching, so the choice is reviewable.

---

## Phase 1 — Orient

Read the item document and the findings. Do not re-establish what they already record.

Before asking anything, identify privately: parts of the intent that state a wish rather than a checkable state, scope boundaries never stated, decisions presented as obvious, and claims the findings do not cover.

Open a working notes file in the item folder, under the name the artifact model gives working material of this kind, asking once if the model names none. Lay it out in two parts: one section per family in the interrogation model, and a flat list of the required parts of the design document with the status of each. It is deleted when the design document is written.

---

## Phase 2 — Interrogation

Cover every family the interrogation model defines, in the order it gives them. Depth within a family is judgement; visiting it is not. A family with nothing to settle is recorded in the notes as visited with that outcome, never passed over silently.

Stop at the later of two points: every required part of the design document can be written without inventing anything, and a round has passed that only restated answers already given.

Park a question the developer cannot answer, as a deliberately open question recorded with what it holds up; treat that part as written. State every parking at the checkpoint, and never use parking to close a family that was not pressed.

Where the same family has been through three rounds without settling, stop and put the remaining gaps to the developer as a decision to press further or to park them.

- Ask 2 to 4 questions per round, drawn from the family in hand. Prioritise questions whose answer changes the shape of the work over questions that add detail to a shape already agreed.
- Where the findings already answer part of a family, state the answer and ask for confirmation instead of asking open.
- Where a family holds no question whose answer could change the design, do not invent one. State the conclusion and what it was drawn from, specific enough that the developer can disagree with it, and ask for agreement. Disagreement reopens the family as an ordinary round.
- Open questions while the shape is still moving, closed confirmations once it has settled.
- When an answer contradicts an earlier one, or contradicts the findings, state the contradiction and ask which side holds.
- Challenge the magnitude recorded on the item as the boundary and impact families move it.
- Rewrite the notes at the end of every round: per family, what is settled and what is open; then the parts list, marking each part settled, short, or parked.

Do not decompose the work, order it, or name files and symbols.

---

## Phase 3 — Verification

Verify the factual claims interrogation raises that the findings do not cover. Do not accept them.

- A claim a single lookup settles is checked in the main conversation. Anything wider is delegated, with related claims batched into one subagent rather than one each, and nothing else is read in the main conversation.
- A locate-and-report check takes the cheapest model. A claim about how something behaves, or about whether existing behaviour satisfies a need, takes a stronger one. Where a claim is load-bearing enough that the design collapses if it is wrong, two cheap independent checks outweigh one expensive check: two can disagree, one model cannot disagree with itself.
- Where the batch exceeds a handful of subagents, say what will run and what it costs, and wait.
- Where delegation is not permitted, name the claim to the developer and ask them to confirm it or to authorise the check. Do not proceed on an unverified claim.
- Report contradictions between the claim and the code as they are found, and return to Phase 2 on anything they reopen.
- A contradiction that invalidates the recorded current state itself is not repaired here. Name the gap, stop, and report that the item's account of the current state has to be re-established before the design can continue.

---

## Phase 4 — Converge

Restate, in the conversation and not yet on disk, every part the artifact model requires of a design document, in the order it requires them, plus the magnitude the work now warrants with the reason if it moved. Do not restate a subset.

State which phase follows. Where interrogation concluded the work should not proceed, on whichever no-op condition the policy names, Phase 5b follows; otherwise Phase 5a.

Wait for confirmation. A correction returns to Phase 2 or Phase 3, and is not patched into a draft.

---

## Phase 5a — The work proceeds

Write the design document into the item folder, under the name and with the content the artifact model requires, following the project's documentation writing standard, to be read cold by someone who was not present for the interrogation.

Fill every required part from what interrogation settled or from the findings, inventing nothing. A part that cannot be written from interrogation is a family that was not covered deeply enough and returns to Phase 2; a part that cannot be written from the findings is Phase 3's case of a current state that has to be re-established.

Describe changes as systems, layers and interfaces and the nature of the change to each. Record the relations between them in the kinds the artifact model distinguishes, keeping apart a change that must merely exist before another and a change whose design holds only while an earlier one turns out as intended. No ordering of the work, no slicing, no file or symbol inventory, no code.

Then:

- Record the confirmed magnitude on the item document, replacing whatever it held.
- Delete the working notes.
- Leave the findings in place.
- If the design intent is of a kind that outlives the work producing it, say so and recommend moving it to the design intent location. The move is the developer's decision.

Write nothing else. Not any level of the breakdown, not the tracker, and not the workspace implementation would happen in.

---

## Phase 5b — The work is a no-op

Resolve against the no-op condition named at Phase 4, producing every artifact the policy prescribes for it and no others.

Two rules govern how those artifacts are produced, whatever the condition:

- Where the resolution is a new entry in the technical debt register, it follows the fan-out preference, delegated where permitted to a subagent on a stronger model, since it outlives the item and is read by people without this context.
- Where the resolution is an account for the developer to carry to their team, make it evidenced rather than impressionistic.

Where the policy stages the resolution rather than writing it into place, put it in the proposed-work location. Then tell the developer the item folder is no longer needed and leave its removal, and the decision to stage or escalate, to them.

---

## Boundaries

- Design never moves work between the proposed and active locations, and never decides that work is or is not being taken up.
- Design does not survey the project. It verifies specific claims raised in interrogation.
