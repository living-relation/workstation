---
name: pr-closeout
description: >-
  Use after a pull request opens, or when the user says "close out": put the PR effect in the repo state file on that branch, save any new preference or cross-project fact, run gates, and report.
---

# PR close-out

**In one line:** after a PR opens, put what that PR changed into the repo's state file.
Memory gets a new preference, rule or cross-project fact only, each fact once. Then check, push and report.

## When to use
Right after a pull request is opened (the local pr-closeout hook says so when it is wired), or
when the user says "update state and memory" / "close out" / "run pr-closeout". Puts the PR's
effect on project state into the repo's one state file on the **same PR branch**. Shared memory
gets only preferences, rules and cross-project facts (signed, each fact once), never status,
progress, next steps, PR or branch state, TODOs or handoffs. Then runs the repo's gates and doc
hygiene, and reports in a few lines. Any repo.

## Hard rules
- **State goes on the PR's own branch.** Add a commit to the branch you just opened. Never open
  a second PR for the state update (stacked-PR rule, [[feedback-stacked-prs]]).
- **Read the repo's rules first.** `AGENTS.md` names the state file (e.g. `STATE.md`,
  `docs/OPEN-ITEMS.md` "Current state"). Follow its format, freeze rules and PR-body rules
  (e.g. a `Rows:` line).
- **Repo facts go in the repo; memory holds only what the repo can't.** Memory gets preferences,
  corrections, cross-project facts and external pointers, never project progress. Each fact is
  written once.
- **Sign every memory note and index line** `-- <agent>, YYYY-MM-DD` (ET dates).
- **Never force-push, never skip hooks, never merge.** The user merges.
- **Skip what doesn't apply.** A PR that changes no state (a typo fix, a bot regen) needs no
  state edit. Say "state: no change" and move on.

## Steps
1. **What changed.** Read the PR's diff and body (`gh pr view <n> --json title,body,files`, or
   the GitHub tools if there is no `gh`).
   List each effect on project state: a revision bump, a closed or opened row, a removed tool,
   a changed required check, a new rule.
2. **State file.** On the PR branch, edit only the lines those effects make stale (status
   block, a row's status, a "Next" line). Don't rewrite the rest. Commit with the repo's
   attribution and push. If the repo has no state file, say "no state file" and skip.
3. **Memory.** Store path: `<Projects>\_claude\Claude Projects\Working Memory\memory\`
   (Claude Code also reaches it through the `autoMemoryDirectory` junction). Write in the
   project's `<project>\INDEX.md` folder or the general `MEMORY.md`. Do not use
   `~\.claude\working-memory`; a leftover junction there is not the store.
   - **Where you run decides how you reach it.** On the PC (Claude Code, Cursor): write
     the files directly. In a cloud session or the Grok Bot: use Desktop Commander or Remote
     Control to reach the PC folder. If no route works, don't create a memory anywhere else.
     Put the facts in the report under "memory to save" so the user or the next PC session
     saves them. Claude desktop online Memory is not this store and is not synced.
   - Save new durable things the user said or that turned up this session: preferences,
     corrections, machine or tool gotchas, external links. One note per fact, with frontmatter
     (name, description, type) and the **Why:** / **How to apply:** lines.
   - Update a note that is now wrong; don't add a duplicate.
   - Add a signed index line for every new note.
   - If a memory note holds project progress (status, next steps, PR or branch state, TODOs,
     a handoff), put that content in the repo state file on this branch. Tell the user the
     memory copy is stale. Do not delete it without a yes. Do not write the PR's effect into memory.
4. **Hygiene.** Run the repo's gates from `AGENTS.md` "Commands" (example: `python tools/check_all.py`,
   `python .github/scripts/test_docs_gates.py`, `python bench/check_parity.py`), plus its
   warn-only doc checks if it has them. Report new warnings only, not old ones.
5. **Report**, in at most 6 lines:
   - state: what you changed (or "no change"), with the commit
   - memory: the notes added or updated (or "none")
   - checks: pass/fail
   - the full PR link
   - anything left for the user (a conflict between rules, a decision)

## Where it runs
One skill file for every agent. Workstation `install.ps1` copies `handoff/claude/pr-closeout-nudge.ps1`
into `~\.claude\hooks` and wires it in `~\.claude\settings.json` PostToolUse (merge; other hook
entries stay). Cursor on the PC also runs those user Claude hooks, so the same script fires there.
The Grok Bot reads this same skill from `~\.claude\skills`. Claude Code cloud sessions and Cowork
get it as a skill uploaded to claude.ai. Where no hook runs (Grok, cloud, Cowork), the description
above is the trigger: run it as soon as you open a PR, or when the user says "run pr-closeout" /
"close out".

## Not this skill's job
Merging, deleting branches before the merge, CI babysitting (the app's Auto-fix does that), and
new docs, scripts or gates in a frozen repo.
