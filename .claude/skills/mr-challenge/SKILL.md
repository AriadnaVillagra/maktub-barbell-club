---
name: mr-challenge
description: Challenge or give feedback on a PR or MR description. Use when the owner asks for feedback on their PR/MR description, says "challenge my MR" or "challenge my PR". Also intercepts requests to ghostwrite one, which RULES.md rule 14 forbids.
---

# PR Description Challenge

A clean-context adversarial review of a PR description against the diff and the item's artifacts. Checks developer understanding, diff completeness, and reviewer actionability. Outputs questions, never rewrites.

## Ghostwriting redirect

If this skill is triggered because someone asked you to **write** a PR description, do not write it. RULES.md rule 14: the owner writes it, because writing it is how they review what was built — a description handed to them is one they read instead of the diff. Do not draft one, offer to draft one, or leave one ready to paste. Instead, push back and offer to review their draft once they write it. You can help them get started by summarizing the diff and the item's artifacts so they have context, but the description itself must come from them.

## Process

1. **Collect inputs.** Gather three things:

   - The MR description — accept it however it arrives:
     - If the developer already provided it in the conversation (e.g. after a checkpoint prompt), use it directly, do not ask again.
     - If they point to a file, read it.
     - If the `gh` CLI is available and a PR exists for the current branch, offer to pull it from there.
     - Otherwise, ask the developer to provide it.
   - The diff — run `git diff main...HEAD` (or the appropriate target branch)
   - The item's artifacts — from the active work root (`ACTIVE_WORK_ROOT`, `.plans/`), read the item's `design.md` and the documents for the levels this work sits at, using `progress.md` to find them. Work built under the older model has `PRD.md`, `STATUS.md`, `briefs/` and `issues/` in `docs/backup/plans/` instead.

2. **Launch a clean-context agent.** The reviewer receives only the inputs above — no conversation history from the current session. Give it the review brief below.

3. **Present the agent's questions to the developer.** Each question should reference the specific part of the description or diff it concerns. Never rewrite or suggest replacement text — only ask questions.

4. **Iterate.** The developer may update their description and run the challenge again.

## Review brief (for the clean-context agent)

You are reviewing a PR description written by the owner. You have the description, the diff, and the item's artifacts (its design, and the story, task or issue it belongs to). Your job is to challenge the developer's understanding — output questions, never rewrites.

**Shape first.** RULES.md rule 14 fixes the sections, so that every PR can be
scanned and compared: `## Summary` (what and why, a short paragraph), `## Changes`
(a bullet per meaningful change, grouped by workspace where it spans more than
one), `## Testing` (what was run and its result, or "not tested" and why). A
missing or renamed section is the first thing to raise. Summary should link the
item's issue where there is one.

Then check three dimensions:

**Understanding** — does the developer explain *why* these changes exist, not just *what* changed? Can you tell from the description what problem was being solved and what approach was taken? If the description reads like a changelog ("added X, modified Y"), ask why those changes were needed.

**Completeness** — does the description account for every significant change in the diff? Flag:
- Changes in the diff not mentioned in the description (the developer may not realize they're there)
- Claims in the description that don't appear in the diff (leftover from an earlier draft?)
- Artifacts that describe work not reflected in either the diff or the description

**Actionability** — could a reviewer who hasn't seen this code act on this description?
- Would they know what to test?
- Would they know what to watch for in review (tricky parts, known limitations)?
- Would they know what changed from the user's perspective?

Additional checks:
- If the description restates what's already in the item's artifacts, suggest pointing to those instead
- If the changes are client- or owner-facing, ask for screenshots — a screen nobody has looked at is not evidence, and both apps are looked at on a device

Output format: a numbered list of questions, each referencing the specific concern. Group by dimension (understanding, completeness, actionability). If a dimension has no concerns, say so — don't invent questions.
