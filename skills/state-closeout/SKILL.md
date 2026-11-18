---
name: state-closeout
description: >-
  Use when context nears 80%, on a pivot, blocker, milestone or PR: tag live notes, move each to its home, rewrite STATE to 30 lines. Mode handoff prints a paste-ready resume block.
---
# State closeout

**In one line:** empty the live notes into their permanent homes, then leave a STATE file of 30 lines or less.

Two modes: `closeout` (the default) and `handoff`. The project's own rules win over this skill.

## When to use
- **Context near 80%** (the one shared threshold). Do not `/compact` again and again. Close out, print the handoff block, and tell the user to start a new chat.
- **Pivot or interruption.** Before doing the new ask, write the new goal and next step to your STATE file. Move the old unfinished steps to `TASK.md` (still this branch) or `BACKLOG.md` (dropped).
- **Blocker.** Write the exact failing command and error under Active Blocker. Stop after 2 guesses at a fix.
- **Milestone or finished deliverable.** Close out, then run deliverable-lock.
- **PR.** pr-closeout runs this skill.
- **Mode `handoff`:** the user asks for a handoff, or another chat or agent takes over.

## Where things live
The store is resolved by `python <workstation>/scripts/state/state_paths.py`. It prints the store, the project folder (`<store>/<project>/`) and your slug.

| File | Where | Who writes it |
|---|---|---|
| `STATE.md` | project folder | the coordinator, or the only agent |
| `STATE-<slug>.md` | project folder | the agent on that branch or job |
| `BACKLOG.md` | project folder | anyone; append only |
| `archives/` | project folder | `state_manager.py archive-branch` |
| `TASK.md` | worktree root, git-ignored | the branch |
| DECISIONS, `.claude/rules/`, SPEC, data | the repo, where the router's role table says | the repo, by PR |

Write only your own STATE file. The root STATE's `Branch_States` line is generated from the `STATE-*.md` files (by `state_manager.py`); never edit it by hand. A worker never edits the root STATE, the router, SPEC or DECISIONS unless its brief says so. It appends findings to BACKLOG and reports.

## The seven tags
| Tag | Means | Goes to |
|---|---|---|
| `[DONE]` | finished and committed | dropped; git history is the record |
| `[NEXT]` | the one next action | stays in STATE under Next Single Step (1, at most 2) |
| `[TASK]` | later work on this branch | `TASK.md`; STATE may name the step number |
| `[ADR]` | why a choice was made | appended to DECISIONS (ID, Status, Context, Decision, Rejected, Supersedes, Reopen if); STATE keeps only the ID in `Latest_ADR` |
| `[RULE]` | how files must be made, named, ordered or checked | `.claude/rules/<domain>.md`, naming its enforcer (a check, a hook, or "none yet"); then `python <workstation>/scripts/state/rules_sync.py`. Never hand-edit `.cursor/rules/` |
| `[SOT]` | raw values: numbers, pins, IDs, sizes, tolerances | the data file or SPEC the router names, **only after the owner's yes**. Until then: a BACKLOG line marked `needs owner yes` |
| `[BKLG]` | out of scope now | appended to `BACKLOG.md` with the date and where it came from |

Only `[NEXT]` may stay in a STATE file.

## Sorting an untagged line (ask in order; the first yes wins)
1. Is it already committed and passing the repo's checks? Then `[DONE]`.
2. Does it hold raw values (numbers, pins, IDs, sizes, tolerances)? Then `[SOT]`.
3. Would a future session break the project if it forgot this?
   - It explains **why** a choice was made: `[ADR]`.
   - It says **how** files must be made, named, ordered or checked: `[RULE]`.
4. Is it work still to do?
   - Needed for the current SPEC milestone, and the very next action: `[NEXT]`.
   - Needed for the milestone, but later on this branch: `[TASK]`.
   - Not needed for the current milestone: `[BKLG]`.

If nothing fits, ask the user. Do not guess.

**2-run rule.** A line kept in STATE through a closeout gets `(carried 1)`. It may not be carried again: `(carried 2)` fails the lint. Graduate it now, as `[ADR]`, `[RULE]`, `[TASK]` or `[BKLG]`.

## Mode `closeout` (default)
1. **Find your file.** Run `state_paths.py`. Coordinator or single agent on main: `STATE.md`. Otherwise `STATE-<slug>.md`. Read it, `TASK.md`, and this session's notes in chat.
2. **Tag every line.** Sort untagged lines with the 4 questions. If the project asks for a proposal first, show the tag list and wait for the yes.
3. **Graduate** in this order: `[SOT]` (ask first), `[ADR]`, `[RULE]` (then rules_sync), `[TASK]`, `[BKLG]`, then drop `[DONE]`.
4. **Check nothing was lost.** Every line that is not `[DONE]` now lives in exactly one home. For a big move, run `python <workstation>/scripts/state/move_integrity.py --before <copy> --after <files>`.
5. **Rewrite STATE** (overwrite, never append) to the schema below. Add `(carried 1)` to a `[NEXT]` line kept from the last run.
6. **Lint:** `python <workstation>/scripts/state/state_lint.py <file>`. Exit 2: fix it and run it again. Exit 0 with a note that the store is unreachable: see "Store unreachable".
7. **Commit the repo homes** (DECISIONS, rules, SPEC, data) on the branch, following the repo's rules. Store files are not in git.
8. **Report** in a few lines: what moved where (counts per home), the STATE line count, and the lint result.

## Mode `handoff`
1. If the STATE file has untagged lines or fails the lint, run `closeout` first.
2. Print one fenced `text` block, filled from the STATE file (no placeholders):
```text
RESUME: paste this as the first message in a new chat.
Repo: <repo>   Branch/worktree: <branch> <path>
State file: <store>/<project>/STATE-<slug>.md
Last_Verified_SHA: <sha or none>
Goal: <objective>
Blocker: <NONE, or the exact failing command>
Next: [NEXT] <one action, with file path>
Task list: TASK.md step <n>, or none
Run session-start, then confirm goal, last good commit and next step in 3 lines before acting.
```
3. Change no file in this mode. The block is a copy; the STATE file is the record. No handoff files and no handoff folder in the repo.

## STATE schema v1
```
# STATE (max 30 lines, overwrite only)
Repo: <repo>
Branch: <branch>
Last_Verified_SHA: <sha or none>
Updated: <YYYY-MM-DD> -- <agent>

## Current Goal
- Objective: <one sentence>
- Spec_Ref: <path#anchor or none>

## Active Blocker
- Status: NONE | BLOCKED
- Detail: <exact failing command / question, or none>

## Next Single Step
- [NEXT] <one action, with file path>

## Pointers
- Branch_States: <STATE-<slug>.md list or none>
- Backlog: BACKLOG.md
- Latest_ADR: <id or none>
```

## Store unreachable (PC offline, cloud session)
Work from committed docs. Put the STATE text you would write in the final reply under "state to save"; the next session on the PC writes it. Never create a store anywhere else.

## Hard rules
- STATE: 30 lines max, the headers above, only `[NEXT]` tags, overwritten each time.
- BACKLOG is append only. Close an item with a new `[closed <date>] <item>` line.
- DECISIONS is append only. A change is a new entry that names the one it supersedes.
- SPEC and data change only after the owner's yes.
- No secrets in any of these files.
