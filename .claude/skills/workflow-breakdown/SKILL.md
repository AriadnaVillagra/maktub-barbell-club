---
name: workflow-breakdown
description: The breakdown stage of a piece of work, deriving the executable levels beneath a settled design and the tracker that carries them. Use once a design document exists and before any implementation begins.
argument-hint: <item name>
user-invocable: true
---

# Skill: Workflow Breakdown

Break a designed item into the levels beneath it, one layer at a time, with the developer confirming each layer before the next is started.

**Assumed input:** An item folder in the active-work location holding an item document with a confirmed magnitude, a design document, and the findings. If the design document is absent, stop and report that the work is not designed.

**Produces:** The item's progress tracker, the documents of its top layer, and the documents of any layer refined beneath them this session. Layers left unrefined are a valid end state.

Everything written here traces back to the design or to the layer above it. Anything that cannot be traced goes back to design rather than being invented here.

---

## Parameters

Resolve these before doing anything else.

- **`WORKFLOW_POLICY`** — the project's work policy: the magnitude scale, the ladder of levels, the artifact model, the naming scheme and the progress model. Follow its links, since it is usually a set of documents rather than one. If unset, ask for it.
- **Active-work location**, **level definitions**, **tracker format**, **naming scheme** — all resolve from the policy. Never improvise a definition of a level the policy already gives.
- **The item folder path** — the active-work location plus the item name this skill was invoked on. Resolve it once, as an absolute path, and pass it to every subagent that writes a document. A subagent cannot find where its work goes and must not be left to guess.
- **The findings** — the evidenced account of the current state that the item carried out of conception. The artifact model gives its real name; it is called the findings throughout.
- **Documentation writing standard** — resolve from project context, and follow it in every document written here.
- **Level templates** — one per level, resolved from the artifact model. A template fixes which sections a document at that level has and in what order. Write to the template, and where it is more specific than this skill, it wins. If a level has no template, write it from "What each level document holds" below.
- **`WORKFLOW_FANOUT`** — whether work may be delegated to subagents. If unset, ask once and store it wherever `WORKFLOW_POLICY` lives. Anything short of an explicit refusal is permission.
- **Model and effort criteria** — the project or user context that says which model tier and effort a kind of change warrants. Resolve it from project and user context. It feeds the suggested model and effort recorded on each issue; if the context supplies none, omit that recommendation rather than inventing a scale.

Pick each subagent's model by what a mistake would cost, not by how much text the job produces. If an error would surface at the next gate, use the cheapest model that can do the job. If an error would propagate into everything derived from it, use a stronger one. Say which model was chosen when dispatching, so the choice can be questioned.

---

## Phase 1 — Orient

Look for an existing tracker first. If there is one, the item has been broken down before and its entries and names are already settled, so skip Phases 2 to 4 and enter Phase 5 at the shallowest layer whose entries have nothing beneath them.

Read the item document, the design and the findings in full.

Work out, without writing anything yet:

- Which levels of the ladder this magnitude occupies.
- What kinds of deliverable the design implies. Read the consequential impact too, not only the account of what has to change; the policy's scale does not privilege one kind of deliverable over another.
- Which changes have to come before others, keeping two things apart. **Ordering** means one change simply has to be in place first. **Contingency** means a later change is shaped by an earlier one and holds only if that one turns out as intended.
- Which questions the design left open, and what each one holds up. These are blockers that exist before any work starts.

If the design is missing a part the artifact model requires, or has one that cannot be used, name it and stop.

---

## Phase 2 — Name the top layer

The **top layer** is the set of documents at the highest level the item's magnitude occupies, as the ladder gives it. Nothing sits above that layer except the design, which is therefore what each of its members narrows.

This phase settles the members of that layer and their order. It does not write them, and it does not touch anything below them.

Judge each candidate against the policy's definition of its level, and against one further question: what is true after this alone that is not true now. No answer means the candidate sits at the wrong level.

Where the top layer sits at the level the policy marks as the point the design may be re-evaluated rather than merely continued, two further conditions have to hold together and a candidate fails on either alone:

- It satisfies the policy's own definition of that level.
- It discharges a contingency the design records, rather than merely sitting at an ordering boundary.

A boundary drawn where the design records ordering alone belongs at the level below. At every other level the policy's definition governs and this extra test does not apply.

Where the layer has one member, that member carries the whole design and narrows nothing away from it, and this phase is a confirmation that the magnitude is right rather than a decomposition.

Name the members, which fixes their order, before writing anything. Order follows the design's ordering relations first, then the earliest discharge of contingency.

Present the layer with the reason for each boundary and the order. Wait for confirmation.

---

## Phase 3 — Open the tracker

Only reached when Phase 1 found no tracker. An existing one is never rewritten here.

Write it in the form the progress model defines, under the name the artifact model gives it. If the model names none, ask once.

An entry with nothing beneath it yet is a stub, carrying whatever the progress model says an unrefined entry carries. The tracker opened here is a list of stubs, written before descending rather than assembled at the end.

The main agent writes the tracker, at every phase. No subagent touches it.

---

## Phase 4 — Write the top layer

The layer named in Phase 2 has no documents yet. Write them now, before descending.

The design is their parent. There is no level document above the top layer, so what each member narrows is the design itself, and where the layer has one member it narrows nothing: that document carries the whole design and says so plainly rather than inventing a narrower framing.

One subagent per document, clean context, including where the layer has one member.

Give each subagent the item folder path, the name of the document it is to write, the level's template, only the parts of the design bearing on it, the level definition, the writing standard, and the boundary and order settled at Phase 2. It writes that one document and nothing else, and does not touch the tracker, the design or the findings.

These documents are what every layer beneath them inherits, so they take a stronger model than the leaves do.

A section describing how a document's children relate to one another cannot be written yet. Leave it for the pass that derives them, as the template says.

Each subagent returns the title it settled on, what finishing means, and anything it could not derive. Run the conformance check over what it wrote, then present the layer and wait.

---

## Phase 5 — Refine one layer down

Repeat this per layer until reaching the lowest level the ladder defines, or until the developer stops. Where the item occupies more than two levels, ask how far to go rather than assuming the leaves.

Where a layer has a single parent there is no cross-parent reconciliation to do, and it is skipped. The dispatch is not skipped: one parent is still refined by a subagent. Neither is the sibling-dependency derivation, since one parent still has children that stand in relation to each other.

Judge each child against the policy's definition of the level it sits at, and by what its delivery reads as to whoever receives it. Splitting a unit to keep it small, at the cost of making it unreadable alone, is a boundary drawn in the wrong place.

Per layer:

1. State how many parents will be dispatched and what that costs, then wait for authorization. Authorize per layer, not once for the whole item. A layer too wide to review in one sitting is dispatched and gated in batches.
2. One subagent per parent, clean context. Give it the item folder path, the parent document, only the parts of the design bearing on that parent, the level definition, the level's template, the test above for judging a child, the naming scheme, the writing standard, and its parent's name. The path is where it writes, not an invitation to read the folder. When the children are issues, also give it the model and effort criteria, so each issue records a suggested model and effort per its template. This is a starting recommendation for the executor, not a binding assignment.
   Pick the model by depth. Deriving the lowest level takes the cheapest model that can hold the level definition; a thin parent document is a reason to fix the parent, not to raise the model.
3. Each subagent numbers its own children under its parent's name in the order it decides, following the naming scheme. Two parents cannot collide, and the order of the layer as a whole is already fixed by the order of the parents.
4. A subagent writes its own children and nothing else: not the tracker, not the design, not the findings, not another parent's documents.
5. Where fan-out is not permitted, refine parents one at a time in the main conversation and keep the reading narrow.

Each subagent returns one entry per child and no more: its name, the one-line change it delivers, what finishing it means, its blockers, its suggested model and effort where the child is an issue, and anything it could not derive. Plus, for the parent, anything it could not decompose at all. The drafts are not read back, beyond the conformance check.

A subagent that cannot derive part of its layer stops at the gap instead of inventing across it. Its parent stays a stub, the gap is recorded as a blocker on that entry, pointing backwards as the progress model requires, and the rest of the layer carries on. Gaps are reported together at the gate as a return to design, not repaired here.

Run the conformance check over every document written this layer. Then, in the main conversation, check the returns for:

- Two children under different parents describing the same change.
- A change the design named that no child claims.
- A boundary two children both cross.
- A blocker recorded under one parent that another parent does not know about.
- Which children depend on a sibling and which are free of each other. Work this out from what each child needs in place before it can be started, not from the order they came back in, and do not assume a chain.

Resolve all of that before the gate. Present the layer and wait.

Then record what the layer established, on the level the artifact model gives the question to, in the terms its template sets.

It does not go on the tracker. A child waiting on a sibling not yet done is not blocked, it is next; blocked is what the progress model defines it as.

Then update the tracker: entries that now have children take their state, entries still without children stay bare names, and blockers found during the layer are recorded on the entries they block.

---

## The conformance check

Run over every document a subagent writes, at the top layer and at every layer below. It is mechanical and needs none of the prose read: the document conforms to its level's template, on every rule the template states about frontmatter, identity, and which sections are mandatory or conditional. Check additionally that `parent` names the document it was dispatched under, or the item folder for the top layer, which the template cannot know.

Where a level has no template, check it against "What each level document holds" instead.

A document that fails goes back to the subagent that wrote it. It is not corrected in the main conversation.

---

## What each level document holds

**A level's template governs its documents entirely.** These rules apply only where the artifact model supplies no template for a level, and are the shape to write from in that case. Where a template exists, do not check a document against these as well; the template has already settled it.

- A document states only what its parent does not. Refer upward, never restate, never anticipate the level below, and never summarise the level beneath.
- Every document says what finishing it means, in the terms the policy says that level delivers in.
- A level that carries a review says what that review judges. A level that decomposes says what it excludes, and, once its children exist, which of them may be taken at the same time. That question belongs to the last level that can see all of its children at once.
- The lowest level points at the material it changes and never reproduces it. Carry only what cannot be read off that material: where the change lands, what must be true afterwards, the constraints bearing on it, and decisions already closed.
- Write on top of what the project loads into every session, rather than repeating it, and name the standing instructions that govern the change by the identifier that resolves each, not by describing what it covers. A document short because it assumed knowledge that floor does not supply is not minimal, it is incomplete.

---

## Promotion halts breakdown

If a level will not fit inside its parent, the breakdown stops. Name what does not fit, and stop there. The policy owns what happens next.

Do not correct the magnitude, do not amend the design, do not rename anything already written, and do not absorb the overflow by letting a level grow past its definition.

---

## Boundaries

- Breakdown does not design. It does not reopen decisions the design closed, and it does not settle questions the design left open.
- Breakdown does not assign or revise magnitude. It reports one that no longer fits, and stops.
- Breakdown never moves work between the proposed and active locations, never creates the workspace the implementation would happen in, and never carries out any part of the work it describes.
- The findings are retained and disposed of as the artifact model requires.
- No layer is refined past a gate the developer has not given.
