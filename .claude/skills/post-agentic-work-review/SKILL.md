---
name: post-agentic-work-review
description: Self-review pass over your own uncommitted Trajan changes before reporting done or committing — adversarial senior-dev critique for bugs and missing edge cases, plus pruning non-critical comments and checking tick-graph view/access patterns and naming. Use after finishing any C++ code change, when asked to "review my changes", "find edge cases", "clean up comments", or before a commit.
---

# Post-Agentic Work Review

Run this on your own diff before saying "done". Scope = the uncommitted change:

```
git diff                       # full review
git diff -U0 | grep '^\+' | grep -E '//|/\*|###'   # just the comments you added
```

Review each changed hunk against the passes below, then fix in place. Do not widen scope to untouched code.

## Pass 0 — Adversarial review (do this first)

Read the full `git diff` and play a senior dev who **hates this implementation**. Be specific and hostile, not polite. Force yourself to answer:

- What would you tear apart in review? Wrong abstraction, hidden coupling, a command/helper doing too much, state that can desync, a simpler approach you ignored?
- **What edge cases are missing?** Empty/zero/one, max/overflow, null or unset ids, self-referencing input (transfer to same base), duplicates, concurrent/partial failure, item destroyed mid-operation, command posted but `IsValid` false, save/load round-trip, multiplayer desync.
- Does it actually do what was asked, or just compile? What breaks the moment a user does something unintended?
- Did you verify the claims you're about to make ("works", "tested"), or are you assuming?

Write the criticisms down as a short list, then fix the real ones before continuing. If a criticism is a genuine gap you won't fix now, surface it to the user — don't bury it.

## Pass 1 — Comments: keep only the critical why

Project rule: **default to no comment.** A comment earns its place only when the *why* is non-obvious. One line.

Delete a comment if it:
- restates what well-named code already says (`// Holds every selected wing` over `HoldSelectedWings`)
- describes *what* a function does when the name already does (`// True if X` over `IsX` / `CanX`)
- is multi-line elaboration, a tutorial, or a banner
- cites the bug/task/feature/doctrine that motivated it (that belongs in the commit message)

Keep (and trim to one line) a comment that captures:
- a non-obvious rationale or invariant (`// Clears other wings but keeps the airbase, so its panel stays open`)
- a deferred-execution / control-flow surprise (`// the clicked Region commits per wing, so nothing is posted here`)
- why a guard or early-return exists (`// already based here; nothing to transfer`)
- system-entry-point overviews (heartbeats) — these are the documented exception, keep them.

`.gui` `### Section` markers that match the file's existing style are fine; verbose inline descriptions are not.

## Pass 2 — Tick-graph access patterns

- **Reads → `CDataView`, writes → `CDataAccess`.** Never take a `CDataAccess`/`CUniversalAccess` param for a function that only reads.
- **Narrowest scope.** A helper must declare the *smallest* view covering what it touches: list only the read types in `CDataView<A, B>`, only the mutated types in `CDataAccess<C>`. Do **not** take `CUniversalView`/`CUniversalAccess` just because the caller has one — a broad view downcasts to a narrow one for free, so a narrow signature costs the caller nothing and gives the scheduler more parallelism.
- A broad view in a signature hides the real dependency surface — flag any new `CUniversalView`/`CUniversalAccess` parameter on a logic helper and narrow it.
- Interface data-system bindings reading via `NGameState::MakeUniversalViewI()` are the accepted exception (they genuinely span types).

## Pass 3 — Naming

- `CUniversalView` variable → `AllReads`. `CUniversalAccess` → `AllWrites`. Narrow ones → plain `Reads` / `Writes`.
- Member/getter naming (standard N9): `Get` = returns const value/ref, `Access` = returns mutable, `Calc` = computed/derived. No passthrough getters that just return a member.
- Booleans: `Is`/`Has`/`Can`/`Should`, no `b` prefix. No hungarian (`p` for pointers only).

## Report

State what you changed (e.g. "removed 5 comments, narrowed 1 view param, renamed AllReads") so the user sees the pass ran. If a build is warranted (only naming/signature changes affect it — comment removal does not), say so.
